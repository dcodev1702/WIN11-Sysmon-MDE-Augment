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
$approvedRuleName = 'Local noise tuning: MDE service key probes'
$registryExclusions = @($configuration.SelectNodes("//RegistryEvent[@onmatch='exclude']"))

function Test-ApprovedRegistryExclusion {
    param([System.Xml.XmlElement] $RegistryExclusion)

    $elements = @($RegistryExclusion.ChildNodes | Where-Object {
        $_.NodeType -eq [System.Xml.XmlNodeType]::Element
    })
    if ($elements.Count -ne 1) {
        return $false
    }

    $rule = $elements[0]
    if ($rule.LocalName -ne 'Rule' -or $rule.GetAttribute('name') -ne $approvedRuleName -or $rule.groupRelation -ne 'and') {
        return $false
    }

    $conditions = @($rule.ChildNodes | Where-Object {
        $_.NodeType -eq [System.Xml.XmlNodeType]::Element
    })
    if ($conditions.Count -ne 3) {
        return $false
    }

    return (
        $rule.SelectNodes("Image[@condition='is' and text()='C:\Program Files\Windows Defender Advanced Threat Protection\MsSense.exe']").Count -eq 1 -and
        $rule.SelectNodes("EventType[@condition='is' and text()='CreateKey']").Count -eq 1 -and
        $rule.SelectNodes("TargetObject[@condition='begin with' and text()='HKLM\System\CurrentControlSet\Services\']").Count -eq 1
    )
}

if ($registryExclusions.Count -eq 1 -and (Test-ApprovedRegistryExclusion -RegistryExclusion $registryExclusions[0])) {
    return [pscustomobject]@{
        Configuration = $resolvedConfig
        RemovedExclusionGroups = 0
        ApprovedNoiseTuningRule = $approvedRuleName
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

$eventFiltering = $configuration.SelectSingleNode('/Sysmon/EventFiltering')
$ruleGroup = $configuration.CreateElement('RuleGroup')
$ruleGroup.SetAttribute('groupRelation', 'or')
$registryExclusion = $configuration.CreateElement('RegistryEvent')
$registryExclusion.SetAttribute('onmatch', 'exclude')
$rule = $configuration.CreateElement('Rule')
$rule.SetAttribute('name', $approvedRuleName)
$rule.SetAttribute('groupRelation', 'and')

foreach ($conditionDefinition in @(
    @('Image', 'is', 'C:\Program Files\Windows Defender Advanced Threat Protection\MsSense.exe'),
    @('EventType', 'is', 'CreateKey'),
    @('TargetObject', 'begin with', 'HKLM\System\CurrentControlSet\Services\')
)) {
    $condition = $configuration.CreateElement($conditionDefinition[0])
    $condition.SetAttribute('condition', $conditionDefinition[1])
    $condition.InnerText = $conditionDefinition[2]
    $null = $rule.AppendChild($condition)
}

$null = $registryExclusion.AppendChild($rule)
$null = $ruleGroup.AppendChild($registryExclusion)
$null = $eventFiltering.AppendChild($ruleGroup)

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
    ApprovedNoiseTuningRule = $approvedRuleName
    Status = 'Protected'
}