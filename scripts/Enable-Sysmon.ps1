#Requires -Version 5.1
#Requires -PSEdition Desktop

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $ConfigPath,

    [Parameter()]
    [ValidateRange(1048576, 4294967296)]
    [long] $EventLogMaximumSizeBytes = 4GB
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'win11-sysmon-mde-augment.xml'
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-DnsClientOperationalLog {
    param($EventLog)

    return $null -ne $EventLog -and
        $EventLog.IsEnabled -and
        $EventLog.MaximumSizeInBytes -eq 2GB
}

if (-not (Test-IsAdministrator)) {
    throw 'Run this script from an elevated Windows PowerShell session.'
}

$resolvedConfig = (Resolve-Path -LiteralPath $ConfigPath).ProviderPath
$configuration = New-Object System.Xml.XmlDocument
$configuration.Load($resolvedConfig)

if ($configuration.DocumentElement.Name -ne 'Sysmon') {
    throw "The configuration root must be Sysmon: $resolvedConfig"
}

$feature = Get-WindowsOptionalFeature -Online -FeatureName Sysmon
$services = @(Get-Service -Name 'Sysmon*' -ErrorAction SilentlyContinue)

if ($feature.State -ne 'Enabled') {
    if ($services.Count -gt 0) {
        $names = $services.Name -join ', '
        throw "A Sysmon service already exists while the built-in feature is disabled ($names). Remove the standalone Sysmon installation before continuing."
    }

    if (-not $PSCmdlet.ShouldProcess('Windows optional feature Sysmon', 'Enable')) {
        return
    }

    $enableResult = Enable-WindowsOptionalFeature -Online -FeatureName Sysmon -NoRestart
    if ($enableResult.RestartNeeded) {
        Write-Warning 'Windows must restart before Sysmon can be installed. Restart, then run this script again.'
        return [pscustomobject]@{
            Feature = 'EnabledPendingRestart'
            Configuration = $resolvedConfig
            RestartNeeded = $true
        }
    }
}

$sysmonCommand = Get-Command -Name 'sysmon.exe' -CommandType Application -ErrorAction SilentlyContinue |
    Select-Object -First 1

if (-not $sysmonCommand) {
    $sysmonCommand = Get-Command -Name 'sysmon' -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
}

if (-not $sysmonCommand) {
    throw 'The Sysmon command is unavailable. Restart Windows if the optional feature was just enabled.'
}

$services = @(Get-Service -Name 'Sysmon*' -ErrorAction SilentlyContinue)
$operation = if ($services.Count -gt 0) { 'Update' } else { 'Install' }
$arguments = if ($operation -eq 'Update') {
    @('-c', $resolvedConfig)
} else {
    @('-i', $resolvedConfig)
}

if (-not $PSCmdlet.ShouldProcess($resolvedConfig, "$operation built-in Sysmon configuration")) {
    return
}

& $sysmonCommand.Source @arguments
if ($LASTEXITCODE -ne 0) {
    throw "Sysmon exited with code $LASTEXITCODE while attempting to $($operation.ToLowerInvariant()) the configuration."
}

& wevtutil.exe sl 'Microsoft-Windows-Sysmon/Operational' "/ms:$EventLogMaximumSizeBytes"
if ($LASTEXITCODE -ne 0) {
    throw "wevtutil exited with code $LASTEXITCODE while setting the Sysmon Operational log size."
}

$dnsClientLogName = 'Microsoft-Windows-DNS-Client/Operational'
$dnsClientEventLog = Get-WinEvent -ListLog $dnsClientLogName -ErrorAction Stop
$dnsClientLogRemediated = $false
if (-not (Test-DnsClientOperationalLog -EventLog $dnsClientEventLog)) {
    & wevtutil.exe sl $dnsClientLogName /e:true /ms:2147483648
    if ($LASTEXITCODE -ne 0) {
        throw "wevtutil exited with code $LASTEXITCODE while enabling or sizing the DNS Client Operational log."
    }
    $dnsClientLogRemediated = $true
    $dnsClientEventLog = Get-WinEvent -ListLog $dnsClientLogName -ErrorAction Stop
}
if (-not (Test-DnsClientOperationalLog -EventLog $dnsClientEventLog)) {
    throw 'The DNS Client Operational log is not enabled at the required 2 GiB maximum size.'
}

$firefoxPolicyAuditScript = Join-Path -Path $PSScriptRoot -ChildPath 'Set-FirefoxPolicyAudit.ps1'
$firefoxPolicyAudit = & $firefoxPolicyAuditScript
if (
    $firefoxPolicyAudit.Status -ne 'Protected' -or
    @($firefoxPolicyAudit.PolicyRoots).Count -ne 2 -or
    @($firefoxPolicyAudit.PolicyRoots | Where-Object { -not $_.RuleVerified }).Count -ne 0
) {
    throw 'Firefox policy registry auditing was not verified for both registry views.'
}

$processCreationAuditScript = Join-Path -Path $PSScriptRoot -ChildPath 'Set-ProcessCreationAudit.ps1'
$processCreationAudit = & $processCreationAuditScript
if (
    $processCreationAudit.Status -ne 'Protected' -or
    $processCreationAudit.ProcessCreationIncludeCmdLineEnabled -ne 1 -or
    $processCreationAudit.AdvancedAuditPolicyPrecedence -ne 1
) {
    throw 'Security process creation command-line auditing was not verified.'
}

$services = @(Get-Service -Name 'Sysmon*' -ErrorAction Stop)
$eventLog = Get-WinEvent -ListLog 'Microsoft-Windows-Sysmon/Operational'

[pscustomobject]@{
    Feature = 'Enabled'
    Operation = $operation
    Configuration = $resolvedConfig
    SchemaVersion = $configuration.DocumentElement.schemaversion
    Services = $services.Name -join ', '
    ServiceStatus = ($services.Status | Select-Object -Unique) -join ', '
    EventLogEnabled = $eventLog.IsEnabled
    EventLogMaximumSizeBytes = $eventLog.MaximumSizeInBytes
    EventLogMaximumSizeGiB = [math]::Round($eventLog.MaximumSizeInBytes / 1GB, 2)
    DnsCorrelationSource = $dnsClientLogName
    DnsClientOperationalLogEnabled = $dnsClientEventLog.IsEnabled
    DnsClientOperationalLogMaximumSizeBytes = $dnsClientEventLog.MaximumSizeInBytes
    DnsClientOperationalLogMaximumSizeGiB = [math]::Round($dnsClientEventLog.MaximumSizeInBytes / 1GB, 2)
    DnsClientOperationalLogRemediated = $dnsClientLogRemediated
    FirefoxPolicyAuditStatus = $firefoxPolicyAudit.Status
    FirefoxPolicyAuditRoots = @($firefoxPolicyAudit.PolicyRoots.Path)
    FirefoxPolicyAuditPrincipal = $firefoxPolicyAudit.AuditPrincipal
    FirefoxPolicyAuditRights = $firefoxPolicyAudit.AuditRights
    ProcessCreationAuditStatus = $processCreationAudit.Status
    ProcessCreationIncludeCmdLineEnabled = $processCreationAudit.ProcessCreationIncludeCmdLineEnabled
    AdvancedAuditPolicyPrecedence = $processCreationAudit.AdvancedAuditPolicyPrecedence
    RestartNeeded = $false
}