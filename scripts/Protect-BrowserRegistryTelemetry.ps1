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
    $ConfigPath = Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'win11-sysmon-mde-augment.xml'
}

$resolvedConfig = (Resolve-Path -LiteralPath $ConfigPath).ProviderPath
$configuration = New-Object System.Xml.XmlDocument
$configuration.PreserveWhitespace = $true
$configuration.Load($resolvedConfig)
$approvedRuleName = 'Local noise tuning: MDE service key probes'
$browserRuleName = 'technique_id=T1176,technique_name=Browser Extensions'
$browserPatterns = @(
    '\SOFTWARE\Policies\Microsoft\Edge',
    '\SOFTWARE\WOW6432Node\Policies\Microsoft\Edge',
    '\SOFTWARE\Policies\Google\Chrome',
    '\SOFTWARE\WOW6432Node\Policies\Google\Chrome',
    '\SOFTWARE\Policies\Mozilla\Firefox',
    '\SOFTWARE\WOW6432Node\Policies\Mozilla\Firefox',
    '\SOFTWARE\Microsoft\Edge\Extensions',
    '\SOFTWARE\WOW6432Node\Microsoft\Edge\Extensions',
    '\SOFTWARE\Google\Chrome\Extensions',
    '\SOFTWARE\WOW6432Node\Google\Chrome\Extensions',
    '\SOFTWARE\Mozilla\Firefox\Extensions',
    '\SOFTWARE\WOW6432Node\Mozilla\Firefox\Extensions'
)
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
$registryExclusions = @($configuration.SelectNodes("//RegistryEvent[@onmatch='exclude']"))
$registryIncludes = @($configuration.SelectNodes("//RegistryEvent[@onmatch='include']"))
$fileCreateIncludes = @($configuration.SelectNodes("//FileCreate[@onmatch='include']"))

if ($registryIncludes.Count -ne 1) {
    throw "Expected one RegistryEvent include block, found $($registryIncludes.Count)."
}
if ($fileCreateIncludes.Count -ne 1) {
    throw "Expected one FileCreate include block, found $($fileCreateIncludes.Count)."
}

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

function Test-BrowserRegistryRules {
    $rules = @($configuration.SelectNodes("//RegistryEvent[@onmatch='include']/TargetObject[@name='$browserRuleName']"))
    if ($rules.Count -ne $browserPatterns.Count) {
        return $false
    }

    foreach ($pattern in $browserPatterns) {
        $matches = @($rules | Where-Object {
            $_.condition -eq 'contains' -and $_.InnerText -ceq $pattern
        })
        if ($matches.Count -ne 1) {
            return $false
        }
    }
    return $true
}

function Test-FirefoxFileCreateRules {
    foreach ($definition in $firefoxFileRuleDefinitions) {
        $matchingRules = @($fileCreateIncludes[0].ChildNodes | Where-Object {
            $_.NodeType -eq [System.Xml.XmlNodeType]::Element -and
            $_.LocalName -eq 'Rule' -and
            $_.GetAttribute('name') -ceq $definition.Name
        })
        if ($matchingRules.Count -ne 1 -or $matchingRules[0].GetAttribute('groupRelation') -ne 'and') {
            return $false
        }

        $conditions = @($matchingRules[0].ChildNodes | Where-Object {
            $_.NodeType -eq [System.Xml.XmlNodeType]::Element
        })
        if ($conditions.Count -ne $definition.Conditions.Count) {
            return $false
        }

        foreach ($conditionDefinition in $definition.Conditions) {
            $matches = @($conditions | Where-Object {
                $_.LocalName -ceq $conditionDefinition[0] -and
                $_.GetAttribute('condition') -ceq $conditionDefinition[1] -and
                $_.InnerText -ceq $conditionDefinition[2]
            })
            if ($matches.Count -ne 1) {
                return $false
            }
        }
    }
    return $true
}

$approvedExclusionValid = $registryExclusions.Count -eq 1 -and
    (Test-ApprovedRegistryExclusion -RegistryExclusion $registryExclusions[0])
$browserRulesValid = Test-BrowserRegistryRules
$firefoxFileRulesValid = Test-FirefoxFileCreateRules

if ($approvedExclusionValid -and $browserRulesValid -and $firefoxFileRulesValid) {
    return [pscustomobject]@{
        Configuration = $resolvedConfig
        RemovedExclusionGroups = 0
        ApprovedNoiseTuningRule = $approvedRuleName
        BrowserRegistryRules = $browserPatterns.Count
        FirefoxFileCreateRules = $firefoxFileRuleDefinitions.Count
        Status = 'AlreadyProtected'
    }
}

if (-not $browserRulesValid) {
    foreach ($browserRule in @($configuration.SelectNodes("//RegistryEvent[@onmatch='include']/TargetObject[@name='$browserRuleName']"))) {
        $null = $browserRule.ParentNode.RemoveChild($browserRule)
    }
    foreach ($pattern in $browserPatterns) {
        $browserRule = $configuration.CreateElement('TargetObject')
        $browserRule.SetAttribute('name', $browserRuleName)
        $browserRule.SetAttribute('condition', 'contains')
        $browserRule.InnerText = $pattern
        $null = $registryIncludes[0].AppendChild($browserRule)
    }
}

if (-not $firefoxFileRulesValid) {
    foreach ($definition in $firefoxFileRuleDefinitions) {
        foreach ($existingRule in @($fileCreateIncludes[0].SelectNodes('Rule') | Where-Object {
            $_.GetAttribute('name') -ceq $definition.Name
        })) {
            $null = $existingRule.ParentNode.RemoveChild($existingRule)
        }

        $rule = $configuration.CreateElement('Rule')
        $rule.SetAttribute('name', $definition.Name)
        $rule.SetAttribute('groupRelation', 'and')
        foreach ($conditionDefinition in $definition.Conditions) {
            $condition = $configuration.CreateElement($conditionDefinition[0])
            $condition.SetAttribute('condition', $conditionDefinition[1])
            $condition.InnerText = $conditionDefinition[2]
            $null = $rule.AppendChild($condition)
        }
        $null = $fileCreateIncludes[0].AppendChild($rule)
    }
}

if (-not $approvedExclusionValid) {
    foreach ($registryExclusion in $registryExclusions) {
        $ruleGroup = $registryExclusion.ParentNode
        if ($ruleGroup.LocalName -ne 'RuleGroup' -or $ruleGroup.SelectNodes('RegistryEvent').Count -ne 1) {
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
    RemovedExclusionGroups = if ($approvedExclusionValid) { 0 } else { $registryExclusions.Count }
    ApprovedNoiseTuningRule = $approvedRuleName
    BrowserRegistryRules = $browserPatterns.Count
    FirefoxFileCreateRules = $firefoxFileRuleDefinitions.Count
    Status = 'Protected'
}