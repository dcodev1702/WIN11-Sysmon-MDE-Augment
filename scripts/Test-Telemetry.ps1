#Requires -Version 5.1
#Requires -PSEdition Desktop

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-OptionalRegistryValue {
    param(
        [string] $Path,
        [string] $Name
    )

    $item = Get-ItemProperty -LiteralPath $Path -ErrorAction SilentlyContinue
    if (-not $item) {
        return $null
    }
    $property = $item.PSObject.Properties[$Name]
    if (-not $property) {
        return $null
    }
    $property.Value
}

if (-not (Test-IsAdministrator)) {
    throw 'Run this script from an elevated Windows PowerShell session.'
}

$auditPolicyPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit'
$commandLineEnabled = Get-OptionalRegistryValue `
    -Path $auditPolicyPath `
    -Name ProcessCreationIncludeCmdLine_Enabled
$advancedAuditPrecedence = Get-OptionalRegistryValue `
    -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' `
    -Name SCENoApplyLegacyAuditPolicy
$processCreationPolicy = (& auditpol.exe /get /subcategory:'Process Creation') -join "`n"
$registryPolicy = (& auditpol.exe /get /subcategory:'Registry') -join "`n"

if ($commandLineEnabled -ne 1) {
    throw 'ProcessCreationIncludeCmdLine_Enabled is not set to 1.'
}
if ($advancedAuditPrecedence -ne 1) {
    throw 'SCENoApplyLegacyAuditPolicy is not set to 1.'
}
if ($processCreationPolicy -notmatch 'Success' -or $processCreationPolicy -notmatch 'Failure') {
    throw 'Advanced Audit Policy Process Creation success/failure auditing is not enabled.'
}
if ($registryPolicy -notmatch 'Success' -or $registryPolicy -notmatch 'Failure') {
    throw 'Advanced Audit Policy Registry success/failure auditing is not enabled.'
}

$expectedAuditRights = [Security.AccessControl.RegistryRights]::SetValue -bor
    [Security.AccessControl.RegistryRights]::CreateSubKey -bor
    [Security.AccessControl.RegistryRights]::Delete -bor
    [Security.AccessControl.RegistryRights]::ChangePermissions -bor
    [Security.AccessControl.RegistryRights]::TakeOwnership
$expectedAuditFlags = [Security.AccessControl.AuditFlags]::Success -bor
    [Security.AccessControl.AuditFlags]::Failure
$worldSid = [Security.Principal.SecurityIdentifier]::new(
    [Security.Principal.WellKnownSidType]::WorldSid,
    $null
)
$policyRoots = @(
    [pscustomobject]@{
        ProviderPath = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Mozilla\Firefox'
        SubKeyPath = 'SOFTWARE\Policies\Mozilla\Firefox'
    },
    [pscustomobject]@{
        ProviderPath = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Policies\Mozilla\Firefox'
        SubKeyPath = 'SOFTWARE\WOW6432Node\Policies\Mozilla\Firefox'
    }
)

$saclResults = foreach ($root in $policyRoots) {
    $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        [Microsoft.Win32.RegistryHive]::LocalMachine,
        [Microsoft.Win32.RegistryView]::Registry64
    )
    try {
        $registryKey = $baseKey.OpenSubKey(
            $root.SubKeyPath,
            [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,
            [Security.AccessControl.RegistryRights]::ReadPermissions -bor
                [Security.AccessControl.RegistryRights]::ChangePermissions
        )
        if (-not $registryKey) {
            throw "Unable to open Firefox policy root: $($root.ProviderPath)"
        }
        try {
            $accessSecurity = $registryKey.GetAccessControl(
                [Security.AccessControl.AccessControlSections]::Access
            )
            $accessRules = @($accessSecurity.GetAccessRules(
                $true,
                $true,
                [Security.Principal.SecurityIdentifier]
            ))
            $auditSecurity = $registryKey.GetAccessControl(
                [Security.AccessControl.AccessControlSections]::Audit
            )
            $auditRules = @($auditSecurity.GetAuditRules(
                $true,
                $false,
                [Security.Principal.SecurityIdentifier]
            ))
            $matchingRules = @($auditRules | Where-Object {
                $_.IdentityReference -eq $worldSid -and
                [int]$_.RegistryRights -eq [int]$expectedAuditRights -and
                $_.AuditFlags -eq $expectedAuditFlags -and
                $_.InheritanceFlags -eq [Security.AccessControl.InheritanceFlags]::ContainerInherit -and
                $_.PropagationFlags -eq [Security.AccessControl.PropagationFlags]::None
            })
            if ($matchingRules.Count -ne 1) {
                throw "Expected one Firefox policy audit rule: $($root.ProviderPath)"
            }
            if (
                @($accessRules | Where-Object IsInherited).Count -ne 10 -or
                @($accessRules | Where-Object { -not $_.IsInherited }).Count -ne 0 -or
                $accessSecurity.AreAccessRulesProtected
            ) {
                throw "The Firefox policy DACL has changed: $($root.ProviderPath)"
            }

            [pscustomobject]@{
                Path = $root.ProviderPath
                AuditRuleVerified = $true
                DaclVerified = $true
            }
        } finally {
            $registryKey.Dispose()
        }
    } finally {
        $baseKey.Dispose()
    }
}

$marker = 'ProcessCommandLineAudit_{0}' -f [guid]::NewGuid().ToString('N')
$probeStartLocal = Get-Date
$probeProcess = Start-Process `
    -FilePath $env:ComSpec `
    -ArgumentList @('/d', '/c', "echo $marker > nul") `
    -Wait `
    -PassThru
if ($probeProcess.ExitCode -ne 0) {
    throw "The command-line audit probe exited with code $($probeProcess.ExitCode)."
}

$deadline = [datetime]::UtcNow.AddSeconds(10)
$probeEvent = $null
do {
    $events = @(Get-WinEvent -FilterHashtable @{
        LogName = 'Security'
        Id = 4688
        StartTime = $probeStartLocal
    } -ErrorAction SilentlyContinue)
    $probeEvent = $events | Where-Object {
        $_.ToXml() -like "*$marker*"
    } | Select-Object -First 1
} while (-not $probeEvent -and [datetime]::UtcNow -lt $deadline)

if (-not $probeEvent) {
    throw 'Security Event 4688 did not contain the command-line audit marker.'
}

$probeXml = [xml]$probeEvent.ToXml()
$probeCommandLineNode = $probeXml.SelectSingleNode(
    "//*[local-name()='EventData']/*[local-name()='Data' and @Name='CommandLine']"
)
$probeCommandLine = [string]$probeCommandLineNode.InnerText

[pscustomobject]@{
    ProcessCreationAudit = 'Verified'
    CommandLinePolicy = $commandLineEnabled
    AdvancedAuditPolicyPrecedence = $advancedAuditPrecedence
    Security4688RecordId = $probeEvent.RecordId
    Security4688TimeUtc = $probeEvent.TimeCreated.ToUniversalTime().ToString('o')
    Security4688CommandLine = $probeCommandLine
    FirefoxPolicyAuditRoots = @($saclResults)
    Status = 'Valid'
}