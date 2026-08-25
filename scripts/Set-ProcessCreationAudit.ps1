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
$lsaPolicyPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'
$commandLineValueName = 'ProcessCreationIncludeCmdLine_Enabled'
$advancedAuditValueName = 'SCENoApplyLegacyAuditPolicy'

$commandLineBefore = Get-OptionalRegistryValue -Path $auditPolicyPath -Name $commandLineValueName
$advancedAuditBefore = Get-OptionalRegistryValue -Path $lsaPolicyPath -Name $advancedAuditValueName
$remediated = $commandLineBefore -ne 1 -or $advancedAuditBefore -ne 1

if ($PSCmdlet.ShouldProcess('Detailed Tracking > Process Creation', 'Enable Success and Failure auditing')) {
    & auditpol.exe /set /subcategory:'Process Creation' /success:enable /failure:enable | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "auditpol.exe exited with code $LASTEXITCODE while enabling Process Creation auditing."
    }
}

if ($PSCmdlet.ShouldProcess($auditPolicyPath, "Set $commandLineValueName to 1")) {
    $null = New-Item -Path $auditPolicyPath -Force
    $null = New-ItemProperty `
        -LiteralPath $auditPolicyPath `
        -Name $commandLineValueName `
        -PropertyType DWord `
        -Value 1 `
        -Force
}

if ($PSCmdlet.ShouldProcess($lsaPolicyPath, "Set $advancedAuditValueName to 1")) {
    $null = New-ItemProperty `
        -LiteralPath $lsaPolicyPath `
        -Name $advancedAuditValueName `
        -PropertyType DWord `
        -Value 1 `
        -Force
}

if ($remediated -and $PSCmdlet.ShouldProcess('Computer policy', 'Apply with gpupdate')) {
    & gpupdate.exe /target:computer /force | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "gpupdate.exe exited with code $LASTEXITCODE while applying computer policy."
    }
}

$processCreationPolicy = & auditpol.exe /get /subcategory:'Process Creation'
$commandLineAfter = Get-OptionalRegistryValue -Path $auditPolicyPath -Name $commandLineValueName
$advancedAuditAfter = Get-OptionalRegistryValue -Path $lsaPolicyPath -Name $advancedAuditValueName
$processCreationPolicyText = $processCreationPolicy -join "`n"
$processCreationEnabled = $processCreationPolicyText -match 'Success' -and
    $processCreationPolicyText -match 'Failure'

if (
    -not $WhatIfPreference -and
    (
        -not $processCreationEnabled -or
        $commandLineAfter -ne 1 -or
        $advancedAuditAfter -ne 1
    )
) {
    throw 'Process creation command-line auditing was not verified after policy application.'
}

[pscustomobject]@{
    ProcessCreationAudit = if ($processCreationEnabled) { 'Success and Failure' } else { 'Not verified' }
    ProcessCreationIncludeCmdLineEnabled = $commandLineAfter
    AdvancedAuditPolicyPrecedence = $advancedAuditAfter
    PolicyRemediated = $remediated
    Status = if ($WhatIfPreference) { 'WhatIf' } else { 'Protected' }
}