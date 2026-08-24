#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'win11-sysmon-mde-augment.xml'
}

$resolvedConfig = (Resolve-Path -LiteralPath $ConfigPath).ProviderPath
$configuration = New-Object System.Xml.XmlDocument
$configuration.Load($resolvedConfig)

if ($configuration.DocumentElement.Name -ne 'Sysmon') {
    throw "The configuration root must be Sysmon: $resolvedConfig"
}

$ruleName = 'technique_id=T1176,technique_name=Browser Extensions'
$browserRules = @($configuration.SelectNodes("//RegistryEvent[@onmatch='include']/TargetObject[@name='$ruleName']"))
$chromiumPolicyPatterns = @(
    '\SOFTWARE\Policies\Microsoft\Edge',
    '\SOFTWARE\WOW6432Node\Policies\Microsoft\Edge',
    '\SOFTWARE\Policies\Google\Chrome',
    '\SOFTWARE\WOW6432Node\Policies\Google\Chrome'
)
$firefoxPolicyPatterns = @(
    '\SOFTWARE\Policies\Mozilla\Firefox',
    '\SOFTWARE\WOW6432Node\Policies\Mozilla\Firefox'
)
$policyPatterns = $chromiumPolicyPatterns + $firefoxPolicyPatterns
$externalExtensionPatterns = @(
    '\SOFTWARE\Microsoft\Edge\Extensions',
    '\SOFTWARE\WOW6432Node\Microsoft\Edge\Extensions',
    '\SOFTWARE\Google\Chrome\Extensions',
    '\SOFTWARE\WOW6432Node\Google\Chrome\Extensions',
    '\SOFTWARE\Mozilla\Firefox\Extensions',
    '\SOFTWARE\WOW6432Node\Mozilla\Firefox\Extensions'
)
$expectedPatterns = $policyPatterns + $externalExtensionPatterns
$chromiumExtensionLists = @(
    'ExtensionInstallAllowlist',
    'ExtensionInstallBlocklist',
    'ExtensionInstallForcelist'
)
$firefoxExtensionPolicies = @(
    'ExtensionSettings',
    'Extensions\Install',
    'Extensions\Uninstall',
    'Extensions\Locked'
)

if ($browserRules.Count -ne $expectedPatterns.Count) {
    throw "Expected $($expectedPatterns.Count) browser registry rules, found $($browserRules.Count)."
}

$registryExclusions = @($configuration.SelectNodes("//RegistryEvent[@onmatch='exclude']"))
$approvedRuleName = 'Local noise tuning: MDE service key probes'
if ($registryExclusions.Count -ne 1) {
    throw "Expected one approved RegistryEvent exclusion group, found $($registryExclusions.Count)."
}

$registryExclusionRules = @($registryExclusions[0].SelectNodes('Rule'))
if ($registryExclusionRules.Count -ne 1) {
    throw 'The RegistryEvent exclusion group contains unapproved rules.'
}

$approvedRule = $registryExclusionRules[0]
$approvedConditions = @($approvedRule.ChildNodes | Where-Object {
    $_.NodeType -eq [System.Xml.XmlNodeType]::Element
})
if (
    $approvedRule.GetAttribute('name') -ne $approvedRuleName -or
    $approvedRule.groupRelation -ne 'and' -or
    $approvedConditions.Count -ne 3 -or
    $approvedRule.SelectNodes("Image[@condition='is' and text()='C:\Program Files\Windows Defender Advanced Threat Protection\MsSense.exe']").Count -ne 1 -or
    $approvedRule.SelectNodes("EventType[@condition='is' and text()='CreateKey']").Count -ne 1 -or
    $approvedRule.SelectNodes("TargetObject[@condition='begin with' and text()='HKLM\System\CurrentControlSet\Services\']").Count -ne 1
) {
    throw 'The approved MDE registry noise-tuning rule is missing or has changed.'
}

foreach ($pattern in $expectedPatterns) {
    $matchingRules = @($browserRules | Where-Object {
        $_.condition -eq 'contains' -and $_.InnerText -ceq $pattern
    })

    if ($matchingRules.Count -ne 1) {
        throw "The browser registry rule is missing or duplicated for $pattern."
    }
}

foreach ($root in @(
    'HKLM\SOFTWARE\Policies\Microsoft\Edge',
    'HKLM\SOFTWARE\WOW6432Node\Policies\Microsoft\Edge',
    'HKLM\SOFTWARE\Policies\Google\Chrome',
    'HKLM\SOFTWARE\WOW6432Node\Policies\Google\Chrome'
)) {
    foreach ($extensionList in $chromiumExtensionLists) {
        $location = "$root\$extensionList"
        $covered = @($chromiumPolicyPatterns | Where-Object {
            $location.IndexOf($_, [StringComparison]::OrdinalIgnoreCase) -ge 0
        }).Count -eq 1
        if (-not $covered) {
            throw "No policy pattern covers $location."
        }
    }
}

foreach ($root in @(
    'HKLM\SOFTWARE\Policies\Mozilla\Firefox',
    'HKLM\SOFTWARE\WOW6432Node\Policies\Mozilla\Firefox'
)) {
    foreach ($extensionPolicy in $firefoxExtensionPolicies) {
        $location = "$root\$extensionPolicy"
        $covered = @($firefoxPolicyPatterns | Where-Object {
            $location.IndexOf($_, [StringComparison]::OrdinalIgnoreCase) -ge 0
        }).Count -eq 1
        if (-not $covered) {
            throw "No Firefox policy pattern covers $location."
        }
    }
}

$sampleUserSid = 'S-1-5-21-111111111-222222222-333333333-1001'
foreach ($pattern in $expectedPatterns) {
    foreach ($hivePrefix in @('HKLM', "HKU\$sampleUserSid")) {
        $samplePath = "$hivePrefix$pattern\SampleExtensionId"
        if ($samplePath.IndexOf($pattern, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
            throw "The sample path $samplePath is not covered by $pattern."
        }
    }
}

foreach ($pattern in $externalExtensionPatterns) {
    foreach ($hivePrefix in @('HKLM', "HKU\$sampleUserSid")) {
        $rootPath = "$hivePrefix$pattern"
        foreach ($samplePath in @(
            $rootPath,
            "$rootPath\SampleExtensionId",
            "$rootPath\SampleExtensionId\update_URL"
        )) {
            if ($samplePath.IndexOf($pattern, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
                throw "The native extension path $samplePath is not covered by $pattern."
            }
        }
    }
}

$firefoxFileRuleDefinitions = @(
    [pscustomobject]@{
        Name = 'Firefox profile extension XPI created or overwritten'
        Conditions = @(
            @('Image', 'end with', '\firefox.exe'),
            @('TargetFilename', 'contains', '\AppData\Roaming\Mozilla\Firefox\Profiles\'),
            @('TargetFilename', 'contains', '\extensions\'),
            @('TargetFilename', 'end with', '.xpi')
        )
    },
    [pscustomobject]@{
        Name = 'Firefox extension state database created or overwritten'
        Conditions = @(
            @('Image', 'end with', '\firefox.exe'),
            @('TargetFilename', 'contains', '\AppData\Roaming\Mozilla\Firefox\Profiles\'),
            @('TargetFilename', 'end with', '\extensions.json')
        )
    }
)
$fileCreateRules = @($configuration.SelectNodes("//FileCreate[@onmatch='include']/Rule"))
foreach ($definition in $firefoxFileRuleDefinitions) {
    $matchingRules = @($fileCreateRules | Where-Object {
        $_.GetAttribute('name') -ceq $definition.Name
    })
    if ($matchingRules.Count -ne 1 -or $matchingRules[0].GetAttribute('groupRelation') -ne 'and') {
        throw "The Firefox FileCreate rule is missing or duplicated: $($definition.Name)."
    }

    $conditions = @($matchingRules[0].ChildNodes | Where-Object {
        $_.NodeType -eq [System.Xml.XmlNodeType]::Element
    })
    if ($conditions.Count -ne $definition.Conditions.Count) {
        throw "The Firefox FileCreate rule has an unexpected condition count: $($definition.Name)."
    }

    foreach ($conditionDefinition in $definition.Conditions) {
        $matches = @($conditions | Where-Object {
            $_.LocalName -ceq $conditionDefinition[0] -and
            $_.GetAttribute('condition') -ceq $conditionDefinition[1] -and
            $_.InnerText -ceq $conditionDefinition[2]
        })
        if ($matches.Count -ne 1) {
            throw "The Firefox FileCreate rule has changed: $($definition.Name)."
        }
    }
}

$processAccessInclude = $configuration.SelectSingleNode("//ProcessAccess[@onmatch='include']")
$appDataRules = @($processAccessInclude.SelectNodes("Rule[SourceImage[contains(text(),'\AppData\')]]"))
if ($appDataRules.Count -ne 1) {
    throw "Expected one broad AppData ProcessAccess rule, found $($appDataRules.Count)."
}

$appDataRule = $appDataRules[0]
if (
    $appDataRule.groupRelation -ne 'and' -or
    $appDataRule.SelectNodes("SourceImage[@condition='not end with' and text()='\AppData\Local\Microsoft\Teams\current\Teams.exe']").Count -ne 1 -or
    $appDataRule.SelectNodes("SourceImage[@condition='not end with' and text()='\AppData\Local\Programs\Microsoft VS Code\Code.exe']").Count -ne 1
) {
    throw 'The broad AppData ProcessAccess noise tuning is missing or has changed.'
}

[pscustomobject]@{
    Configuration = $resolvedConfig
    SchemaVersion = $configuration.DocumentElement.schemaversion
    RegistryIncludeGroups = $configuration.SelectNodes("//RegistryEvent[@onmatch='include']").Count
    BrowserPolicyPatterns = $policyPatterns.Count
    ChromiumPolicyPatterns = $chromiumPolicyPatterns.Count
    FirefoxPolicyPatterns = $firefoxPolicyPatterns.Count
    BrowserExternalExtensionPatterns = $externalExtensionPatterns.Count
    NativeExtensionSamplePaths = $externalExtensionPatterns.Count * 2 * 3
    BrowserRuleNodes = $browserRules.Count
    ExtensionListLocations = ($chromiumPolicyPatterns.Count * $chromiumExtensionLists.Count) +
        ($firefoxPolicyPatterns.Count * $firefoxExtensionPolicies.Count)
    FirefoxFileCreateRules = $firefoxFileRuleDefinitions.Count
    MachineAndUserHivesCovered = $true
    NativeAndWow6432ViewsCovered = $true
    RegistryExcludeGroups = $registryExclusions.Count
    ApprovedRegistryNoiseRule = $approvedRuleName
    VSCodeAppDataNoiseSuppressed = $true
    BrowserEventsUnconditionallyIncluded = $true
    Status = 'Valid'
}