#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $FirefoxPath = 'C:\Program Files\Mozilla Firefox\firefox.exe',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $ProfilePath,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $AddonUrl = 'https://addons.mozilla.org/en-US/firefox/addon/grammarly-1/',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $AddonId = '87677a2c52b84ad3a151a4a72f5bd3c4@jetpack',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $OutputDirectory,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $XdrCsvPath,

    [Parameter()]
    [switch] $ValidateOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$firefoxRoot = Join-Path -Path $env:APPDATA -ChildPath 'Mozilla\Firefox'
$profilesIni = Join-Path -Path $firefoxRoot -ChildPath 'profiles.ini'
$installsIni = Join-Path -Path $firefoxRoot -ChildPath 'installs.ini'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$sysmonLogName = 'Microsoft-Windows-Sysmon/Operational'

function Resolve-DefaultFirefoxProfile {
    if (-not (Test-Path -LiteralPath $installsIni)) {
        throw "Firefox installs.ini was not found: $installsIni"
    }

    $defaultLine = Get-Content -LiteralPath $installsIni | Where-Object {
        $_ -match '^Default=(.+)$'
    } | Select-Object -First 1

    if (-not $defaultLine) {
        throw "No default Firefox profile is defined in $installsIni."
    }

    $relativePath = ($defaultLine -replace '^Default=', '').Replace('/', '\')
    $candidate = Join-Path -Path $firefoxRoot -ChildPath $relativePath
    (Resolve-Path -LiteralPath $candidate).ProviderPath
}

function Test-FirefoxAddonLoggingEnabled {
    param([string] $ResolvedProfilePath)

    $preferencePattern = 'user_pref\("extensions\.logging\.enabled",\s*true\s*\);'
    foreach ($fileName in @('user.js', 'prefs.js')) {
        $preferenceFile = Join-Path -Path $ResolvedProfilePath -ChildPath $fileName
        if (Test-Path -LiteralPath $preferenceFile) {
            $content = [System.IO.File]::ReadAllText($preferenceFile)
            if ([regex]::IsMatch($content, $preferencePattern)) {
                return $true
            }
        }
    }
    return $false
}

function Get-OptionalPropertyValue {
    param(
        [object] $InputObject,
        [string] $Name,
        [object] $DefaultValue = $null
    )

    if ($null -eq $InputObject) {
        return $DefaultValue
    }

    $property = $InputObject.PSObject.Properties[$Name]
    if ($property) {
        return $property.Value
    }
    return $DefaultValue
}

function Get-FirefoxExtensionSnapshot {
    param([string] $ResolvedProfilePath)

    $extensionsPath = Join-Path -Path $ResolvedProfilePath -ChildPath 'extensions.json'
    if (-not (Test-Path -LiteralPath $extensionsPath)) {
        return @()
    }

    $extensions = Get-Content -LiteralPath $extensionsPath -Raw | ConvertFrom-Json
    @($extensions.addons | ForEach-Object {
        $defaultLocale = Get-OptionalPropertyValue -InputObject $_ -Name 'defaultLocale'
        [pscustomobject]@{
            Id = Get-OptionalPropertyValue -InputObject $_ -Name 'id'
            Name = Get-OptionalPropertyValue -InputObject $defaultLocale -Name 'name'
            Version = Get-OptionalPropertyValue -InputObject $_ -Name 'version'
            Type = Get-OptionalPropertyValue -InputObject $_ -Name 'type'
            Location = Get-OptionalPropertyValue -InputObject $_ -Name 'location'
            Active = Get-OptionalPropertyValue -InputObject $_ -Name 'active' -DefaultValue $false
            Visible = Get-OptionalPropertyValue -InputObject $_ -Name 'visible' -DefaultValue $false
            UserDisabled = Get-OptionalPropertyValue -InputObject $_ -Name 'userDisabled' -DefaultValue $false
            AppDisabled = Get-OptionalPropertyValue -InputObject $_ -Name 'appDisabled' -DefaultValue $false
            PendingUninstall = Get-OptionalPropertyValue -InputObject $_ -Name 'pendingUninstall' -DefaultValue $false
            SignedState = Get-OptionalPropertyValue -InputObject $_ -Name 'signedState'
            SourceUri = Get-OptionalPropertyValue -InputObject $_ -Name 'sourceURI'
            Path = Get-OptionalPropertyValue -InputObject $_ -Name 'path'
        }
    })
}

function Get-FirefoxPolicySnapshot {
    $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey(
        'SOFTWARE\Policies\Mozilla\Firefox',
        $false
    )
    if (-not $key) {
        return [pscustomobject]@{
            Exists = $false
            ValueKind = $null
            Elements = @()
        }
    }

    try {
        $valueNames = @($key.GetValueNames())
        if ($valueNames -notcontains 'ExtensionSettings') {
            return [pscustomobject]@{
                Exists = $true
                ValueKind = $null
                Elements = @()
            }
        }

        [pscustomobject]@{
            Exists = $true
            ValueKind = $key.GetValueKind('ExtensionSettings').ToString()
            Elements = @($key.GetValue(
                'ExtensionSettings',
                $null,
                [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames
            ))
        }
    } finally {
        $key.Dispose()
    }
}

function Convert-SysmonEvent {
    param([System.Diagnostics.Eventing.Reader.EventRecord] $Event)

    $xml = [xml]$Event.ToXml()
    $eventData = @{}
    foreach ($node in $xml.Event.EventData.Data) {
        $eventData[[string]$node.Name] = [string]$node.'#text'
    }

    [pscustomobject]@{
        TimeCreatedUtc = $Event.TimeCreated.ToUniversalTime().ToString('o')
        RecordId = $Event.RecordId
        EventId = $Event.Id
        RuleName = $eventData.RuleName
        UtcTime = $eventData.UtcTime
        ProcessGuid = $eventData.ProcessGuid
        ProcessId = $eventData.ProcessId
        Image = $eventData.Image
        User = $eventData.User
        EventType = $eventData.EventType
        TargetFilename = $eventData.TargetFilename
        TargetObject = $eventData.TargetObject
        Details = $eventData.Details
        DestinationHostname = $eventData.DestinationHostname
        DestinationIp = $eventData.DestinationIp
        DestinationPort = $eventData.DestinationPort
        QueryName = $eventData.QueryName
        Hashes = $eventData.Hashes
        Contents = $eventData.Contents
        RawXml = $Event.ToXml()
    }
}

if (-not (Test-Path -LiteralPath $FirefoxPath -PathType Leaf)) {
    throw "Firefox executable was not found: $FirefoxPath"
}

$runningFirefox = @(Get-Process -Name 'firefox' -ErrorAction SilentlyContinue)
if ($runningFirefox.Count -gt 0) {
    throw 'Close every Firefox process before starting a capture.'
}

if ([string]::IsNullOrWhiteSpace($ProfilePath)) {
    $ProfilePath = Resolve-DefaultFirefoxProfile
} else {
    $ProfilePath = (Resolve-Path -LiteralPath $ProfilePath).ProviderPath
}

if (-not (Test-FirefoxAddonLoggingEnabled -ResolvedProfilePath $ProfilePath)) {
    throw "Enable extensions.logging.enabled=true in $ProfilePath before capturing."
}

if ($XdrCsvPath) {
    $XdrCsvPath = (Resolve-Path -LiteralPath $XdrCsvPath).ProviderPath
}

if ($ValidateOnly) {
    return [pscustomobject]@{
        Firefox = $FirefoxPath
        Profile = $ProfilePath
        AddonId = $AddonId
        AddonUrl = $AddonUrl
        AddonLoggingEnabled = $true
        XdrCsv = $XdrCsvPath
        Status = 'Ready'
    }
}

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $captureName = 'firefox-extension-capture-{0}' -f [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')
    $OutputDirectory = Join-Path -Path (Join-Path -Path $repositoryRoot -ChildPath 'output') -ChildPath $captureName
}

$outputPath = [System.IO.Directory]::CreateDirectory($OutputDirectory).FullName
$debugLogPath = Join-Path -Path $outputPath -ChildPath 'firefox_addon_manager_debug.log'
$beforeSnapshotPath = Join-Path -Path $outputPath -ChildPath 'firefox_extensions_before.csv'
$afterSnapshotPath = Join-Path -Path $outputPath -ChildPath 'firefox_extensions_after.csv'
$policyPath = Join-Path -Path $outputPath -ChildPath 'firefox_extension_policy.json'
$sysmonCsvPath = Join-Path -Path $outputPath -ChildPath 'sysmon_firefox_events_UTC.csv'
$sysmonXmlPath = Join-Path -Path $outputPath -ChildPath 'sysmon_firefox_events_raw.clixml'
$metadataPath = Join-Path -Path $outputPath -ChildPath 'capture_metadata.json'

Get-FirefoxExtensionSnapshot -ResolvedProfilePath $ProfilePath |
    Export-Csv -LiteralPath $beforeSnapshotPath -NoTypeInformation -Encoding UTF8
Get-FirefoxPolicySnapshot | ConvertTo-Json -Depth 8 |
    Set-Content -LiteralPath $policyPath -Encoding UTF8

if ($XdrCsvPath) {
    Copy-Item -LiteralPath $XdrCsvPath -Destination (Join-Path -Path $outputPath -ChildPath 'xdr_results.csv')
}

$startUtc = [DateTime]::UtcNow
$previousMozLog = [Environment]::GetEnvironmentVariable('MOZ_LOG', 'Process')
[Environment]::SetEnvironmentVariable('MOZ_LOG', 'timestamp,sync', 'Process')

Write-Host "Capture start (UTC): $($startUtc.ToString('o'))"
Write-Host "Firefox debug log: $debugLogPath"
Write-Host 'Install the approved extension, complete the Firefox prompt, then close every Firefox window.'

$escapedFirefox = $FirefoxPath.Replace('"', '""')
$escapedProfile = $ProfilePath.Replace('"', '""')
$escapedUrl = $AddonUrl.Replace('"', '""')
$escapedLog = $debugLogPath.Replace('"', '""')
$commandLine = '""{0}" -no-remote -profile "{1}" "{2}" > "{3}" 2>&1"' -f `
    $escapedFirefox, $escapedProfile, $escapedUrl, $escapedLog

try {
    & $env:ComSpec /d /s /c $commandLine
    $firefoxExitCode = $LASTEXITCODE
} finally {
    [Environment]::SetEnvironmentVariable('MOZ_LOG', $previousMozLog, 'Process')
}

$endUtc = [DateTime]::UtcNow
Get-FirefoxExtensionSnapshot -ResolvedProfilePath $ProfilePath |
    Export-Csv -LiteralPath $afterSnapshotPath -NoTypeInformation -Encoding UTF8

$eventIds = 1, 3, 7, 10, 11, 12, 13, 14, 15, 22, 23, 26, 255
$events = @(Get-WinEvent -FilterHashtable @{
    LogName = $sysmonLogName
    Id = $eventIds
    StartTime = $startUtc
    EndTime = $endUtc
} -ErrorAction SilentlyContinue)

$convertedEvents = @($events | ForEach-Object { Convert-SysmonEvent -Event $_ })
$addonIdPattern = [regex]::Escape($AddonId)
$firefoxEventPattern = '(?i)firefox|mozilla|{0}|\.xpi|extensions\.json' -f $addonIdPattern
$firefoxEvents = @($convertedEvents | Where-Object {
    $searchable = @(
        $_.Image,
        $_.TargetFilename,
        $_.TargetObject,
        $_.Details,
        $_.DestinationHostname,
        $_.QueryName,
        $_.Contents
    ) -join '|'

    $searchable -match $firefoxEventPattern
})

$firefoxEvents | Select-Object -Property * -ExcludeProperty RawXml |
    Export-Csv -LiteralPath $sysmonCsvPath -NoTypeInformation -Encoding UTF8
$events | Export-Clixml -LiteralPath $sysmonXmlPath -Depth 5

$metadata = [ordered]@{
    CaptureStartUtc = $startUtc.ToString('o')
    CaptureEndUtc = $endUtc.ToString('o')
    DurationSeconds = [math]::Round(($endUtc - $startUtc).TotalSeconds, 3)
    FirefoxPath = $FirefoxPath
    FirefoxVersion = (Get-Item -LiteralPath $FirefoxPath).VersionInfo.ProductVersion
    FirefoxExitCode = $firefoxExitCode
    ProfilePath = $ProfilePath
    AddonId = $AddonId
    AddonUrl = $AddonUrl
    AddonLoggingPreference = 'extensions.logging.enabled=true'
    DebugLog = $debugLogPath
    SysmonCsv = $sysmonCsvPath
    SysmonRaw = $sysmonXmlPath
    SysmonMatchingEvents = $firefoxEvents.Count
    SysmonErrors255 = @($convertedEvents | Where-Object EventId -eq 255).Count
    XdrCsv = if ($XdrCsvPath) { Join-Path -Path $outputPath -ChildPath 'xdr_results.csv' } else { $null }
}
$metadata | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $metadataPath -Encoding UTF8

if ($firefoxExitCode -ne 0) {
    throw "Firefox exited with code $firefoxExitCode. Review $debugLogPath."
}

[pscustomobject]@{
    OutputDirectory = $outputPath
    CaptureStartUtc = $startUtc
    CaptureEndUtc = $endUtc
    FirefoxExitCode = $firefoxExitCode
    DebugLog = $debugLogPath
    SysmonEvents = $firefoxEvents.Count
    SysmonErrors255 = $metadata.SysmonErrors255
    XdrCsvIncluded = [bool]$XdrCsvPath
    Status = 'Captured'
}
