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

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

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

function Start-FirefoxRedirected {
    param(
        [string] $ResolvedFirefoxPath,
        [string[]] $Arguments,
        [string] $StandardOutputPath,
        [string] $StandardErrorPath
    )

    Start-Process `
        -FilePath $ResolvedFirefoxPath `
        -ArgumentList $Arguments `
        -RedirectStandardOutput $StandardOutputPath `
        -RedirectStandardError $StandardErrorPath `
        -Wait `
        -PassThru
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

$isAdministrator = Test-IsAdministrator
if ($ValidateOnly) {
    return [pscustomobject]@{
        Firefox = $FirefoxPath
        Profile = $ProfilePath
        AddonId = $AddonId
        AddonUrl = $AddonUrl
        AddonLoggingEnabled = $true
        Launcher = 'Start-Process'
        ShellElevated = $isAdministrator
        XdrCsv = $XdrCsvPath
        Status = if ($isAdministrator) { 'Blocked' } else { 'Ready' }
    }
}

if ($isAdministrator) {
    throw 'Run this capture from a non-administrator Windows PowerShell window. Firefox de-elevates administrator launches and detaches redirected logging.'
}

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $captureName = 'firefox-extension-capture-{0}' -f [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')
    $OutputDirectory = Join-Path -Path (Join-Path -Path $repositoryRoot -ChildPath 'output') -ChildPath $captureName
}

$outputPath = [System.IO.Directory]::CreateDirectory($OutputDirectory).FullName
$debugLogPath = Join-Path -Path $outputPath -ChildPath 'firefox_addon_manager_debug.log'
$standardOutputPath = Join-Path -Path $outputPath -ChildPath 'firefox_stdout.log'
$beforeSnapshotPath = Join-Path -Path $outputPath -ChildPath 'firefox_extensions_before.csv'
$afterSnapshotPath = Join-Path -Path $outputPath -ChildPath 'firefox_extensions_after.csv'
$policyPath = Join-Path -Path $outputPath -ChildPath 'firefox_extension_policy.json'
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

$firefoxArguments = @(
    '-no-remote',
    '-profile',
    ('"{0}"' -f $ProfilePath),
    ('"{0}"' -f $AddonUrl)
)

try {
    $firefoxProcess = Start-FirefoxRedirected `
        -ResolvedFirefoxPath $FirefoxPath `
        -Arguments $firefoxArguments `
        -StandardOutputPath $standardOutputPath `
        -StandardErrorPath $debugLogPath
    $firefoxExitCode = $firefoxProcess.ExitCode
} finally {
    [Environment]::SetEnvironmentVariable('MOZ_LOG', $previousMozLog, 'Process')
}

$endUtc = [DateTime]::UtcNow
Get-FirefoxExtensionSnapshot -ResolvedProfilePath $ProfilePath |
    Export-Csv -LiteralPath $afterSnapshotPath -NoTypeInformation -Encoding UTF8

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
    StandardOutputLog = $standardOutputPath
    SysmonSourceLog = $sysmonLogName
    SysmonQueryStartUtc = $startUtc.ToString('o')
    SysmonQueryEndUtc = $endUtc.ToString('o')
    XdrCsv = if ($XdrCsvPath) { Join-Path -Path $outputPath -ChildPath 'xdr_results.csv' } else { $null }
}
$metadata | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $metadataPath -Encoding UTF8

if ($firefoxExitCode -ne 0) {
    $diagnosticPaths = @($debugLogPath, $standardOutputPath) | Where-Object {
        Test-Path -LiteralPath $_
    }
    if ($diagnosticPaths.Count -gt 0) {
        throw "Firefox exited with code $firefoxExitCode. Review $($diagnosticPaths -join ', ')."
    }
    throw "Firefox exited with code $firefoxExitCode before redirected log files were created."
}

[pscustomobject]@{
    OutputDirectory = $outputPath
    CaptureStartUtc = $startUtc
    CaptureEndUtc = $endUtc
    FirefoxExitCode = $firefoxExitCode
    DebugLog = $debugLogPath
    StandardOutputLog = $standardOutputPath
    SysmonSourceLog = $sysmonLogName
    XdrCsvIncluded = [bool]$XdrCsvPath
    Status = 'Captured'
}
