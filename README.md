<p align="center">
  <img alt="Windows 11" src="https://img.shields.io/badge/Windows_11-0078D4?style=for-the-badge&logo=windows11&logoColor=white">
  <img alt="Built-in Sysmon" src="https://img.shields.io/badge/Built--in_Sysmon-F25022?style=for-the-badge&logo=microsoft&logoColor=white">
  <img alt="MDE augment" src="https://img.shields.io/badge/MDE_Augment-7FBA00?style=for-the-badge&logo=microsoftdefender&logoColor=white">
  <img alt="Schema 4.90" src="https://img.shields.io/badge/XML_4.90-FFB900?style=for-the-badge&logoColor=black">
</p>

# Windows 11 Sysmon: MDE Augment

> 🛡️ A deployment-ready configuration for **Windows 11 built-in Sysmon**, based on Olaf Hartong's **MDE augment** profile and extended to monitor Microsoft Edge and Google Chrome machine policy changes.

This project enables high-fidelity Sysmon telemetry that complements Microsoft Defender for Endpoint (MDE). Sysmon records activity; it does **not** analyze, alert on, or block that activity. Forward the resulting events to Microsoft Sentinel, Windows Event Collection, or another SIEM for detection and response.

## 📦 Project contents

| File | Purpose |
| --- | --- |
| [`win11-sysmon-mde-augment.xml`](win11-sysmon-mde-augment.xml) | Olaf's MDE augment configuration plus browser policy monitoring. |
| [`Enable-Sysmon.ps1`](Enable-Sysmon.ps1) | Validates the XML, enables built-in Sysmon, and installs or updates the configuration. |
| [`Test-Configuration.ps1`](Test-Configuration.ps1) | Verifies XML parsing and all browser policy rule boundaries. |
| [`Protect-BrowserRegistryTelemetry.ps1`](Protect-BrowserRegistryTelemetry.ps1) | Removes competing registry exclusions after an upstream refresh so browser events cannot be suppressed. |
| [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md) | Attribution and license notice for the upstream configuration. |

## ✅ Prerequisites

- A supported Windows 11 release with the built-in Sysmon optional feature.
- Windows PowerShell 5.1 or later, opened **as Administrator**.
- Microsoft Defender for Endpoint, because this profile intentionally minimizes overlap with MDE.
- No standalone Sysinternals Sysmon installation. Built-in and standalone Sysmon cannot coexist.
- Sysmon 15 or later. The upstream project warns that older versions are not fully compatible.

Check for an existing service before enabling the feature:

```powershell
Get-Service sysmon*
```

If this returns a service while the Windows optional feature is disabled, remove the standalone installation before continuing.

## 🚀 Recommended installation

Open Windows PowerShell as Administrator, move to this repository, and run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-Configuration.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Enable-Sysmon.ps1
```

The `-ExecutionPolicy Bypass` setting applies only to the new PowerShell process used for that command; it does not change the machine or user execution-policy setting. Both scripts require Windows PowerShell 5.1 (`powershell.exe`) because the inbox DISM feature cmdlets can fail under PowerShell 7 (`pwsh.exe`) on some Windows builds.

The installer:

1. Requires elevation and parses the configuration before changing Windows.
2. Refuses to proceed when a standalone Sysmon service may conflict.
3. Enables the `Sysmon` Windows optional feature.
4. Uses `sysmon -i` for a new installation or `sysmon -c` for an existing built-in installation.
5. Confirms the service and `Microsoft-Windows-Sysmon/Operational` event log exist.

If Windows reports that a restart is required, restart the device and run the script again. Preview the planned action without changing Windows with:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Enable-Sysmon.ps1 -WhatIf
```

## 🪟 Manual Microsoft procedure

The following is the equivalent manual flow from Microsoft Learn. Run it in an elevated Windows PowerShell session:

```powershell
Get-Service sysmon*
Enable-WindowsOptionalFeature -Online -FeatureName Sysmon

New-Item -ItemType Directory -Path C:\Sysmon -Force
Copy-Item .\win11-sysmon-mde-augment.xml C:\Sysmon\win11-sysmon-mde-augment.xml
sysmon -i C:\Sysmon\win11-sysmon-mde-augment.xml
```

Restart Windows after enabling the optional feature if requested, then continue with `sysmon -i`. Configuration changes take effect immediately and do not otherwise require a restart.

To update an existing installation:

```powershell
sysmon -c C:\Sysmon\win11-sysmon-mde-augment.xml
```

## 🔎 Browser extension policy coverage

Sysmon Registry Events **12, 13, and 14** cover key/value creation, modification, deletion, and rename activity. The custom rules use an exact match for each policy root and a trailing-backslash descendant match. This covers the root and every child while avoiding unrelated, similarly prefixed keys.

| Activity | Sysmon event | Captured for watched trees |
| --- | --- | --- |
| Key or value create | 12 | Yes |
| Key or value delete | 12 | Yes |
| Value modify/set | 13 | Yes |
| Key or value rename | 14 | Yes |

### Watched policy roots

```text
HKLM\SOFTWARE\Policies\Microsoft\Edge
HKLM\SOFTWARE\WOW6432Node\Policies\Microsoft\Edge
HKLM\SOFTWARE\Policies\Google\Chrome
HKLM\SOFTWARE\WOW6432Node\Policies\Google\Chrome
```

### Watched extension list locations

| Browser | Registry view | Extension policy path |
| --- | --- | --- |
| Edge | Native | `HKLM\SOFTWARE\Policies\Microsoft\Edge\ExtensionInstallAllowlist` |
| Edge | Native | `HKLM\SOFTWARE\Policies\Microsoft\Edge\ExtensionInstallBlocklist` |
| Edge | Native | `HKLM\SOFTWARE\Policies\Microsoft\Edge\ExtensionInstallForcelist` |
| Edge | 32-bit | `HKLM\SOFTWARE\WOW6432Node\Policies\Microsoft\Edge\ExtensionInstallAllowlist` |
| Edge | 32-bit | `HKLM\SOFTWARE\WOW6432Node\Policies\Microsoft\Edge\ExtensionInstallBlocklist` |
| Edge | 32-bit | `HKLM\SOFTWARE\WOW6432Node\Policies\Microsoft\Edge\ExtensionInstallForcelist` |
| Chrome | Native | `HKLM\SOFTWARE\Policies\Google\Chrome\ExtensionInstallAllowlist` |
| Chrome | Native | `HKLM\SOFTWARE\Policies\Google\Chrome\ExtensionInstallBlocklist` |
| Chrome | Native | `HKLM\SOFTWARE\Policies\Google\Chrome\ExtensionInstallForcelist` |
| Chrome | 32-bit | `HKLM\SOFTWARE\WOW6432Node\Policies\Google\Chrome\ExtensionInstallAllowlist` |
| Chrome | 32-bit | `HKLM\SOFTWARE\WOW6432Node\Policies\Google\Chrome\ExtensionInstallBlocklist` |
| Chrome | 32-bit | `HKLM\SOFTWARE\WOW6432Node\Policies\Google\Chrome\ExtensionInstallForcelist` |

The XML maps these additions to MITRE ATT&CK **T1176: Browser Extensions**. The policy values beneath each list typically contain extension identifiers, so changes are useful for detecting unauthorized allowlisting, blocking, or silent force-installation.

Because Sysmon exclusion rules take precedence over include rules, this configuration removes the upstream `RegistryEvent onmatch="exclude"` group. This guarantees create, modify, delete, and rename telemetry for the requested paths regardless of which process makes the change. Other event-family exclusions from the MDE augment profile remain unchanged.

## 🧪 Verify telemetry

Confirm the service and inspect recent events:

```powershell
Get-Service sysmon*

Get-WinEvent -LogName 'Microsoft-Windows-Sysmon/Operational' -MaxEvents 20 |
    Select-Object TimeCreated, Id, ProviderName, Message
```

In Event Viewer, use:

```text
Applications and Services Logs > Microsoft > Windows > Sysmon > Operational
```

For a controlled lab test, create and remove a temporary policy value, then query Events 12–14:

```powershell
$started = Get-Date
$path = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge\ExtensionInstallAllowlist'
New-Item -Path $path -Force
New-ItemProperty -Path $path -Name 'SysmonValidation' -Value 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' -PropertyType String -Force
Remove-ItemProperty -Path $path -Name 'SysmonValidation'

Get-WinEvent -FilterHashtable @{
    LogName = 'Microsoft-Windows-Sysmon/Operational'
    Id = 12, 13, 14
    StartTime = $started
} | Where-Object Message -Like '*ExtensionInstallAllowlist*'
```

Use this test only on a lab device or in an approved maintenance window. Remove the empty test key afterward if it did not exist before testing.

## ⚠️ Deployment guidance

- Pilot on representative Windows 11 devices before broad deployment.
- Baseline event volume and tune noisy rules for your software estate.
- Monitor Sysmon Event ID 4 for service state changes, ID 16 for configuration changes, and ID 255 for errors.
- Preserve the four browser policy rules when refreshing the upstream MDE augment file.
- After replacing the XML from upstream, run `Protect-BrowserRegistryTelemetry.ps1` and then `Test-Configuration.ps1` before deployment.
- Keep one controlled configuration version per endpoint role where practical.
- Treat Sysmon events as evidence, not alerts; correlate them with MDE and identity/network telemetry.

The MDE augment profile has intentional blind spots. Use Olaf's balanced or excludes-only profiles when the endpoint does not have MDE or when incident-response collection requires broader telemetry.

## 🙏 Credits

This project is inspired by and derived from [Olaf Hartong's sysmon-modular project](https://github.com/olafhartong/sysmon-modular). Olaf created the modular Sysmon framework, the MDE augmentation strategy, and the upstream `sysmonconfig-mde-augment.xml` that serves as this project's foundation. This repository adapts that work for Windows 11 built-in Sysmon and adds targeted Microsoft Edge and Google Chrome extension-policy telemetry. Full upstream licensing is preserved in [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

## 📚 Sources and provenance

- [Enable and configure Sysmon in Windows](https://learn.microsoft.com/en-us/windows/security/operating-system-security/sysmon/how-to-enable-sysmon)
- [Sysmon events](https://learn.microsoft.com/en-us/windows/security/operating-system-security/sysmon/sysmon-events)
- [Olaf Hartong: sysmon-modular](https://github.com/olafhartong/sysmon-modular)
- [Upstream MDE augment configuration](https://raw.githubusercontent.com/olafhartong/sysmon-modular/master/sysmonconfig-mde-augment.xml)
- [Microsoft Edge extension policies](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies#extensions)
- [Chrome Enterprise extension policies](https://chromeenterprise.google/policies/#ExtensionInstallAllowlist)

The upstream XML was retrieved on **2026-08-24** with SHA-256 `B0BAFCEC2BE753772E36E4BF891336DF558A4CEC53DD8C9BC716613B92F98943`, then extended with the documented browser registry rules and removal of the competing `RegistryEvent` exclusion group. Review the [third-party notice](THIRD-PARTY-NOTICES.md) before redistribution.

*Disclaimer: GitHub Copilot (w/ChatGPT 5.6 Sol) was employed in the creation of this project.*