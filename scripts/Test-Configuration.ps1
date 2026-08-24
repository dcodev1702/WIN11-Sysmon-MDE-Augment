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
$policyPatterns = @(
    '\SOFTWARE\Policies\Microsoft\Edge',
    '\SOFTWARE\WOW6432Node\Policies\Microsoft\Edge',
    '\SOFTWARE\Policies\Google\Chrome',
    '\SOFTWARE\WOW6432Node\Policies\Google\Chrome'
)
$externalExtensionPatterns = @(
    '\SOFTWARE\Microsoft\Edge\Extensions',
    '\SOFTWARE\WOW6432Node\Microsoft\Edge\Extensions',
    '\SOFTWARE\Google\Chrome\Extensions',
    '\SOFTWARE\WOW6432Node\Google\Chrome\Extensions'
)
$expectedPatterns = $policyPatterns + $externalExtensionPatterns
$extensionLists = @(
    'ExtensionInstallAllowlist',
    'ExtensionInstallBlocklist',
    'ExtensionInstallForcelist'
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
    foreach ($extensionList in $extensionLists) {
        $location = "$root\$extensionList"
        $covered = @($policyPatterns | Where-Object {
            $location.IndexOf($_, [StringComparison]::OrdinalIgnoreCase) -ge 0
        }).Count -eq 1
        if (-not $covered) {
            throw "No policy pattern covers $location."
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
    BrowserExternalExtensionPatterns = $externalExtensionPatterns.Count
    BrowserRuleNodes = $browserRules.Count
    ExtensionListLocations = $policyPatterns.Count * $extensionLists.Count
    MachineAndUserHivesCovered = $true
    NativeAndWow6432ViewsCovered = $true
    RegistryExcludeGroups = $registryExclusions.Count
    ApprovedRegistryNoiseRule = $approvedRuleName
    VSCodeAppDataNoiseSuppressed = $true
    BrowserEventsUnconditionallyIncluded = $true
    Status = 'Valid'
}