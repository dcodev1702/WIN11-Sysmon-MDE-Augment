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
if ($registryExclusions.Count -ne 0) {
    throw 'RegistryEvent exclusions override browser includes and must be removed.'
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

[pscustomobject]@{
    Configuration = $resolvedConfig
    SchemaVersion = $configuration.DocumentElement.schemaversion
    RegistryIncludeGroups = $configuration.SelectNodes("//RegistryEvent[@onmatch='include']").Count
    BrowserPolicyRoots = $expectedRoots.Count
    BrowserRuleNodes = $browserRules.Count
    ExtensionListLocations = $expectedRoots.Count * $extensionLists.Count
    RegistryExcludeGroups = $registryExclusions.Count
    BrowserEventsUnconditionallyIncluded = $true
    Status = 'Valid'
}