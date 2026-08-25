#Requires -Version 5.1
#Requires -PSEdition Desktop

[CmdletBinding(SupportsShouldProcess)]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdministrator)) {
    throw 'Run this script from an elevated Windows PowerShell session.'
}

$policyRoots = @(
    [pscustomobject]@{
        Name = 'Native'
        ProviderPath = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Mozilla\Firefox'
        SubKeyPath = 'SOFTWARE\Policies\Mozilla\Firefox'
    },
    [pscustomobject]@{
        Name = 'WOW6432Node'
        ProviderPath = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Policies\Mozilla\Firefox'
        SubKeyPath = 'SOFTWARE\WOW6432Node\Policies\Mozilla\Firefox'
    }
)

$auditIdentity = [Security.Principal.SecurityIdentifier]::new(
    [Security.Principal.WellKnownSidType]::WorldSid,
    $null
)
$auditRights = [Security.AccessControl.RegistryRights]::SetValue -bor
    [Security.AccessControl.RegistryRights]::CreateSubKey -bor
    [Security.AccessControl.RegistryRights]::Delete -bor
    [Security.AccessControl.RegistryRights]::ChangePermissions -bor
    [Security.AccessControl.RegistryRights]::TakeOwnership
$auditFlags = [Security.AccessControl.AuditFlags]::Success -bor
    [Security.AccessControl.AuditFlags]::Failure
$inheritanceFlags = [Security.AccessControl.InheritanceFlags]::ContainerInherit
$propagationFlags = [Security.AccessControl.PropagationFlags]::None

function Test-TargetAuditRule {
    param([Security.AccessControl.RegistryAuditRule] $Rule)

    $Rule.IdentityReference -eq $auditIdentity -and
    -not $Rule.IsInherited -and
    [int]$Rule.RegistryRights -eq [int]$auditRights -and
    $Rule.AuditFlags -eq $auditFlags -and
    $Rule.InheritanceFlags -eq $inheritanceFlags -and
    $Rule.PropagationFlags -eq $propagationFlags
}

if ($PSCmdlet.ShouldProcess('Object Access > Registry', 'Enable Success and Failure auditing')) {
    & auditpol.exe /set /subcategory:'Registry' /success:enable /failure:enable | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "auditpol.exe exited with code $LASTEXITCODE while enabling Registry auditing."
    }
}

$results = foreach ($root in $policyRoots) {
    if (-not (Test-Path -LiteralPath $root.ProviderPath)) {
        if (-not $PSCmdlet.ShouldProcess($root.ProviderPath, 'Create Firefox policy registry root')) {
            continue
        }
        $null = New-Item -Path $root.ProviderPath -Force
    }

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
            throw "Unable to open registry policy root: $($root.ProviderPath)"
        }

        try {
            $accessSections = [Security.AccessControl.AccessControlSections]::Access -bor
                [Security.AccessControl.AccessControlSections]::Owner -bor
                [Security.AccessControl.AccessControlSections]::Group
            $accessBefore = $registryKey.GetAccessControl($accessSections).
                GetSecurityDescriptorSddlForm($accessSections)
            $auditSecurity = $registryKey.GetAccessControl(
                [Security.AccessControl.AccessControlSections]::Audit
            )
            $existingRules = @($auditSecurity.GetAuditRules(
                $true,
                $true,
                [Security.Principal.SecurityIdentifier]
            ))
            $ruleExists = @($existingRules | Where-Object {
                Test-TargetAuditRule -Rule $_
            }).Count -gt 0

            $ruleAdded = $false
            if (-not $ruleExists) {
                if ($PSCmdlet.ShouldProcess($root.ProviderPath, 'Add persistent Firefox policy audit rule')) {
                    $auditRule = [Security.AccessControl.RegistryAuditRule]::new(
                        $auditIdentity,
                        $auditRights,
                        $inheritanceFlags,
                        $propagationFlags,
                        $auditFlags
                    )
                    $auditSecurity.AddAuditRule($auditRule)
                    $registryKey.SetAccessControl($auditSecurity)
                    $ruleAdded = $true
                }
            }

            $verifiedSecurity = $registryKey.GetAccessControl(
                [Security.AccessControl.AccessControlSections]::Audit
            )
            $verifiedRules = @($verifiedSecurity.GetAuditRules(
                $true,
                $true,
                [Security.Principal.SecurityIdentifier]
            ))
            $verified = @($verifiedRules | Where-Object {
                Test-TargetAuditRule -Rule $_
            }).Count -gt 0
            if (-not $verified -and -not $WhatIfPreference) {
                throw "The Firefox policy audit rule was not verified: $($root.ProviderPath)"
            }

            $accessAfter = $registryKey.GetAccessControl($accessSections).
                GetSecurityDescriptorSddlForm($accessSections)
            if ($accessBefore -ne $accessAfter) {
                throw "The DACL changed while setting the SACL: $($root.ProviderPath)"
            }

            [pscustomobject]@{
                Name = $root.Name
                Path = $root.ProviderPath
                RuleAdded = $ruleAdded
                RuleVerified = $verified
                AuditRuleCount = $verifiedRules.Count
                DaclUnchanged = $accessBefore -eq $accessAfter
            }
        } finally {
            $registryKey.Dispose()
        }
    } finally {
        $baseKey.Dispose()
    }
}

[pscustomobject]@{
    RegistryAuditPolicy = 'Success and Failure'
    AuditPrincipal = $auditIdentity.Value
    AuditRights = $auditRights.ToString()
    AuditFlags = $auditFlags.ToString()
    Inheritance = $inheritanceFlags.ToString()
    PolicyRoots = @($results)
    Status = if ($WhatIfPreference) { 'WhatIf' } else { 'Protected' }
}