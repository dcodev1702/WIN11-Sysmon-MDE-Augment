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
    $ConfigPath = Join-Path -Path $PSScriptRoot -ChildPath 'win11-sysmon-mde-augment.xml'
}

$resolvedConfig = (Resolve-Path -LiteralPath $ConfigPath).ProviderPath
$configuration = New-Object System.Xml.XmlDocument
$configuration.Load($resolvedConfig)

if ($configuration.DocumentElement.Name -ne 'Sysmon') {
    throw "The configuration root must be Sysmon: $resolvedConfig"
}

$ruleName = 'technique_id=T1176,technique_name=Browser Extensions'
$browserRules = @($configuration.SelectNodes("//RegistryEvent[@onmatch='include']/TargetObject[@name='$ruleName']"))
$expectedRoots = @(
    'HKLM\SOFTWARE\Policies\Microsoft\Edge',
    'HKLM\SOFTWARE\WOW6432Node\Policies\Microsoft\Edge',
    'HKLM\SOFTWARE\Policies\Google\Chrome',
    'HKLM\SOFTWARE\WOW6432Node\Policies\Google\Chrome'
)
$extensionLists = @(
    'ExtensionInstallAllowlist',
    'ExtensionInstallBlocklist',
    'ExtensionInstallForcelist'
)

if ($browserRules.Count -ne 8) {
    throw "Expected 8 browser policy rules, found $($browserRules.Count)."
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

foreach ($root in $expectedRoots) {
    $exactRules = @($browserRules | Where-Object {
        $_.condition -eq 'is' -and $_.InnerText -ceq $root
    })
    $descendantPrefix = "$root\"
    $descendantRules = @($browserRules | Where-Object {
        $_.condition -eq 'begin with' -and $_.InnerText -ceq $descendantPrefix
    })

    if ($exactRules.Count -ne 1 -or $descendantRules.Count -ne 1) {
        throw "The exact and descendant rules are incomplete for $root."
    }

    foreach ($extensionList in $extensionLists) {
        $location = "$root\$extensionList"
        if (-not $location.StartsWith($descendantPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "The descendant rule does not cover $location."
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
    BrowserPolicyRoots = $expectedRoots.Count
    BrowserRuleNodes = $browserRules.Count
    ExtensionListLocations = $expectedRoots.Count * $extensionLists.Count
    RegistryExcludeGroups = $registryExclusions.Count
    ApprovedRegistryNoiseRule = $approvedRuleName
    VSCodeAppDataNoiseSuppressed = $true
    BrowserEventsUnconditionallyIncluded = $true
    Status = 'Valid'
}