#Requires -Version 5.1
#Requires -PSEdition Desktop

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
$configuration.PreserveWhitespace = $true
$configuration.Load($resolvedConfig)
$registryExclusions = @($configuration.SelectNodes("//RegistryEvent[@onmatch='exclude']"))

if ($registryExclusions.Count -eq 0) {
    return [pscustomobject]@{
        Configuration = $resolvedConfig
        RemovedExclusionGroups = 0
        Status = 'AlreadyProtected'
    }
}

foreach ($registryExclusion in $registryExclusions) {
    $ruleGroup = $registryExclusion.ParentNode
    if ($ruleGroup.Name -ne 'RuleGroup' -or $ruleGroup.SelectNodes('RegistryEvent').Count -ne 1) {
        throw 'A RegistryEvent exclusion is not contained in a dedicated RuleGroup.'
    }

    $eventFiltering = $ruleGroup.ParentNode
    $precedingWhitespace = $ruleGroup.PreviousSibling
    $null = $eventFiltering.RemoveChild($ruleGroup)
    if ($precedingWhitespace -and $precedingWhitespace.NodeType -eq [System.Xml.XmlNodeType]::Whitespace) {
        $null = $eventFiltering.RemoveChild($precedingWhitespace)
    }
}

$temporaryPath = "$resolvedConfig.tmp"
try {
    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Encoding = New-Object System.Text.UTF8Encoding($false)
    $settings.Indent = $false
    $settings.OmitXmlDeclaration = $true
    $writer = [System.Xml.XmlWriter]::Create($temporaryPath, $settings)
    try {
        $configuration.Save($writer)
    } finally {
        $writer.Dispose()
    }
    Move-Item -LiteralPath $temporaryPath -Destination $resolvedConfig -Force
} finally {
    if (Test-Path -LiteralPath $temporaryPath) {
        Remove-Item -LiteralPath $temporaryPath -Force
    }
}

[pscustomobject]@{
    Configuration = $resolvedConfig
    RemovedExclusionGroups = $registryExclusions.Count
    Status = 'Protected'
}