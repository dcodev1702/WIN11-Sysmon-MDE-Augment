<p align="center">
  <img alt="Windows 11" src="https://img.shields.io/badge/Windows_11-0078D4?style=for-the-badge&logo=windows11&logoColor=white">
  <img alt="Built-in Sysmon" src="https://img.shields.io/badge/Built--in_Sysmon-F25022?style=for-the-badge&logo=microsoft&logoColor=white">
  <img alt="MDE augment" src="https://img.shields.io/badge/MDE_Augment-7FBA00?style=for-the-badge&logo=microsoftdefender&logoColor=white">
  <img alt="Schema 4.90" src="https://img.shields.io/badge/XML_4.90-FFB900?style=for-the-badge&logoColor=black">
</p>

# Windows 11 Sysmon: MDE Augment

> 🛡️ A deployment-ready configuration for **Windows 11 built-in Sysmon**, based on Olaf Hartong's **MDE augment** profile and extended to monitor Microsoft Edge, Google Chrome, and Mozilla Firefox extension activity.

This project enables high-fidelity Sysmon telemetry that complements Microsoft Defender for Endpoint (MDE). Sysmon records activity; it does **not** analyze, alert on, or block that activity. Forward the resulting events to Microsoft Sentinel, Windows Event Collection, or another SIEM for detection and response.

## 📦 Project contents

| File | Purpose |
| --- | --- |
| [`win11-sysmon-mde-augment.xml`](win11-sysmon-mde-augment.xml) | Olaf's MDE augment configuration plus browser extension registry and Firefox profile-artifact monitoring. |
| [`scripts/Enable-Sysmon.ps1`](scripts/Enable-Sysmon.ps1) | Validates the XML, enables built-in Sysmon, and installs or updates the configuration. |
| [`scripts/Test-Configuration.ps1`](scripts/Test-Configuration.ps1) | Verifies XML parsing and all browser registry, Firefox file, and noise-tuning rule boundaries. |
| [`scripts/Protect-BrowserRegistryTelemetry.ps1`](scripts/Protect-BrowserRegistryTelemetry.ps1) | Reconstructs browser registry rules, Firefox file rules, and the approved MDE noise rule after an upstream refresh. |
| [`CHANGELOG.md`](CHANGELOG.md) | Chronological record of telemetry and tuning changes. |
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
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Configuration.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Enable-Sysmon.ps1
```

The `-ExecutionPolicy Bypass` setting applies only to the new PowerShell process used for that command; it does not change the machine or user execution-policy setting. Both scripts require Windows PowerShell 5.1 (`powershell.exe`) because the inbox DISM feature cmdlets can fail under PowerShell 7 (`pwsh.exe`) on some Windows builds.

The installer:

1. Requires elevation and parses the configuration before changing Windows.
2. Refuses to proceed when a standalone Sysmon service may conflict.
3. Enables the `Sysmon` Windows optional feature.
4. Uses `sysmon -i` for a new installation or `sysmon -c` for an existing built-in installation.
5. Confirms the service and `Microsoft-Windows-Sysmon/Operational` event log exist.
6. Sets the Sysmon Operational channel maximum size to **4 GiB** and reports the effective size.

If Windows reports that a restart is required, restart the device and run the script again. Preview the planned action without changing Windows with:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Enable-Sysmon.ps1 -WhatIf
```

## 🪟 Manual Microsoft procedure

The following is the equivalent manual flow from Microsoft Learn. Run it in an elevated Windows PowerShell session:

```powershell
Get-Service sysmon*
Enable-WindowsOptionalFeature -Online -FeatureName Sysmon

New-Item -ItemType Directory -Path C:\Sysmon -Force
Copy-Item .\win11-sysmon-mde-augment.xml C:\Sysmon\win11-sysmon-mde-augment.xml
sysmon -i C:\Sysmon\win11-sysmon-mde-augment.xml
wevtutil sl Microsoft-Windows-Sysmon/Operational /ms:4294967296
```

Restart Windows after enabling the optional feature if requested, then continue with `sysmon -i`. Configuration changes take effect immediately and do not otherwise require a restart.

To update an existing installation:

```powershell
sysmon -c C:\Sysmon\win11-sysmon-mde-augment.xml
```

## 🔎 Browser extension registry coverage

Sysmon Registry Events **12, 13, and 14** cover key/value creation, modification, deletion, and rename activity. Twelve case-insensitive `contains` patterns cover managed policy trees for Microsoft Edge, Google Chrome, and Mozilla Firefox; native external-registration trees for Edge and Chrome; and defensive direct-registration coverage for Firefox. The patterns match each watched root and all descendant keys and values under HKLM or any HKU user SID; separate patterns cover WOW6432Node views.

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
HKLM\SOFTWARE\Policies\Mozilla\Firefox
HKLM\SOFTWARE\WOW6432Node\Policies\Mozilla\Firefox
```

Equivalent `HKU\<SID>\SOFTWARE\...` policy paths are covered for per-user settings.

### Watched extension policy locations

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
| Firefox | Native | `HKLM\SOFTWARE\Policies\Mozilla\Firefox\ExtensionSettings` |
| Firefox | Native | `HKLM\SOFTWARE\Policies\Mozilla\Firefox\Extensions\Install` |
| Firefox | Native | `HKLM\SOFTWARE\Policies\Mozilla\Firefox\Extensions\Uninstall` |
| Firefox | Native | `HKLM\SOFTWARE\Policies\Mozilla\Firefox\Extensions\Locked` |

Mozilla documents the native Firefox policy root. The WOW6432Node Firefox pattern is defensive visibility for redirected, misplaced, or suspicious writes; it is not the recommended policy location.

### Watched native external-registration roots

| Browser | Registry view | Machine path | Per-user equivalent |
| --- | --- | --- | --- |
| Edge | Native | `HKLM\SOFTWARE\Microsoft\Edge\Extensions` | `HKU\<SID>\SOFTWARE\Microsoft\Edge\Extensions` |
| Edge | 32-bit | `HKLM\SOFTWARE\WOW6432Node\Microsoft\Edge\Extensions` | `HKU\<SID>\SOFTWARE\WOW6432Node\Microsoft\Edge\Extensions` |
| Chrome | Native | `HKLM\SOFTWARE\Google\Chrome\Extensions` | `HKU\<SID>\SOFTWARE\Google\Chrome\Extensions` |
| Chrome | 32-bit | `HKLM\SOFTWARE\WOW6432Node\Google\Chrome\Extensions` | `HKU\<SID>\SOFTWARE\WOW6432Node\Google\Chrome\Extensions` |
| Firefox | Native | `HKLM\SOFTWARE\Mozilla\Firefox\Extensions` | `HKU\<SID>\SOFTWARE\Mozilla\Firefox\Extensions` |
| Firefox | 32-bit | `HKLM\SOFTWARE\WOW6432Node\Mozilla\Firefox\Extensions` | `HKU\<SID>\SOFTWARE\WOW6432Node\Mozilla\Firefox\Extensions` |

Each Chromium extension ID appears as a child key under these native roots. Chrome commonly stores `update_url` or `update_URL` in that child key. The root-fragment rules capture the root itself, every extension-ID subkey, and settings below each ID, including the screenshot pattern `HKLM\SOFTWARE\Google\Chrome\Extensions\<extension-id>\update_URL`.

Mozilla recommends `ExtensionSettings` enterprise policy for current Firefox deployments. The two non-policy Firefox `Extensions` roots are monitored defensively to surface direct, legacy, nonstandard, or suspicious registration attempts even when those keys do not already exist. Creating, changing, renaming, or deleting a watched root, descendant key, or value generates Sysmon registry telemetry regardless of the writing process.

The XML maps these additions to MITRE ATT&CK **T1176: Browser Extensions**. Values beneath the watched policy roots contain extension identifiers, install URLs, or policy JSON, so changes are useful for detecting unauthorized allowlisting, blocking, or silent force-installation.

Because Sysmon exclusion rules take precedence over include rules, this configuration replaces the upstream `RegistryEvent onmatch="exclude"` group with one approved rule that can match only `MsSense.exe` `CreateKey` probes under `HKLM\System\CurrentControlSet\Services\`. It cannot match any Edge, Chrome, or Firefox extension root, so create, modify, delete, and rename telemetry remains unconditional for the requested browser paths. Other event-family exclusions from the MDE augment profile remain unchanged.

### Firefox profile artifacts

Sysmon Event ID **11** adds two Firefox-specific artifact signals under `%APPDATA%\Mozilla\Firefox\Profiles`:

| Artifact | Meaning |
| --- | --- |
| `extensions\*.xpi` written by `firefox.exe` | High-confidence extension install or update artifact. |
| `extensions.json` written by `firefox.exe` | Extension state changed; correlate it with registry and XPI events because enable, disable, update, and removal can all rewrite this file. |

These are file-write artifacts, not semantic "installation succeeded" audit records.

## Configure Firefox extensions in Registry Editor

Firefox does not use the Edge/Chrome external-extension registry layout. Use Mozilla's `ExtensionSettings` enterprise policy at the documented native policy root. The steps below create a machine-wide policy by hand.

1. On the extension's [addons.mozilla.org](https://addons.mozilla.org/) listing, open **More information** and select **Copy add-on ID**. For an extension already installed locally, find its ID under **Add-ons** in `about:support`. Preserve braces when the ID is a UUID.
2. Build the AMO install URL as `https://addons.mozilla.org/firefox/downloads/latest/ADDON_ID/latest.xpi`, replacing `ADDON_ID` with the copied ID. An explicit URL remains clear and compatible with Firefox versions before 153, where AMO `install_url` became optional.
3. Close every Firefox window so the policy is read on the next browser start.
4. Open Registry Editor as Administrator and navigate to `HKEY_LOCAL_MACHINE\SOFTWARE\Policies`.
5. Create missing keys in this order: `Mozilla`, then `Firefox`. The final key must be `HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Mozilla\Firefox`.
6. Select the `Firefox` key, choose **New > Multi-String Value**, and name the value `ExtensionSettings`. Its registry type must be `REG_MULTI_SZ`.
7. Edit `ExtensionSettings` and enter valid JSON as a single line. Replace both `ADDON_ID` placeholders before saving:

```json
{"ADDON_ID":{"installation_mode":"force_installed","install_url":"https://addons.mozilla.org/firefox/downloads/latest/ADDON_ID/latest.xpi"}}
```

For multiple extensions, add each ID as another property in the same JSON object:

```json
{"FIRST_ADDON_ID":{"installation_mode":"force_installed","install_url":"https://addons.mozilla.org/firefox/downloads/latest/FIRST_ADDON_ID/latest.xpi"},"SECOND_ADDON_ID":{"installation_mode":"normal_installed","install_url":"https://addons.mozilla.org/firefox/downloads/latest/SECOND_ADDON_ID/latest.xpi"}}
```

`force_installed` installs the extension and prevents user removal. `normal_installed` installs it but allows the user to disable it. Do not add comments or trailing commas to the JSON. For a private XPI, use an approved HTTPS URL or a `file:///` URL instead of the AMO URL.

8. Start Firefox and open `about:policies`. Confirm that **Active** shows `ExtensionSettings` and that the **Errors** tab is empty.
9. Open `about:addons` and confirm the expected extension and management state.
10. Confirm Sysmon captured the registry write and Firefox profile artifacts:

```powershell
$started = (Get-Date).AddMinutes(-15)
Get-WinEvent -FilterHashtable @{
  LogName = 'Microsoft-Windows-Sysmon/Operational'
  Id = 11, 12, 13, 14
  StartTime = $started
} | Where-Object Message -Match 'Mozilla\\Firefox|extensions\.json|\.xpi' |
  Select-Object TimeCreated, Id, Message
```

Expect Event IDs 12-14 for policy key/value lifecycle activity. Event ID 11 appears when Firefox writes a matching XPI or `extensions.json` artifact. To remove a managed extension, change its `installation_mode` to `blocked`, restart Firefox, verify removal, and then remove its property from the policy JSON if the block no longer needs to be enforced.

Mozilla's older numbered policy is also monitored: string values named `1`, `2`, and so on can be placed below `...\Firefox\Extensions\Install` for XPI URLs or native paths, below `...\Locked` for IDs that users cannot disable or remove, and below `...\Uninstall` for IDs to remove. Mozilla recommends `ExtensionSettings` for new deployments because future improvements are made there.

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
- Preserve all twelve browser registry patterns and both Firefox Event ID 11 rules when refreshing the upstream MDE augment file.
- After replacing the XML from upstream, run `scripts\Protect-BrowserRegistryTelemetry.ps1` and then `scripts\Test-Configuration.ps1` before deployment.
- Keep one controlled configuration version per endpoint role where practical.
- Treat Sysmon events as evidence, not alerts; correlate them with MDE and identity/network telemetry.

The MDE augment profile has intentional blind spots. Use Olaf's balanced or excludes-only profiles when the endpoint does not have MDE or when incident-response collection requires broader telemetry.

## 🔇 Local noise tuning

A retained-log baseline on **2026-08-24** measured **23,074 events in 267.5 seconds** (about **86.26 events/second**):

| Source | Baseline share | Adjustment | Preserved security behavior |
| --- | ---: | --- | --- |
| Process Access ID 10 from per-user VS Code | 93.54% | Exempt VS Code only from the broad `AppData` masquerading include rule. | Separate LSASS, credential-dumping, injection, suspicious call-trace, and dangerous-access rules still apply. |
| Registry ID 12 from `MsSense.exe` service-key probes | 4.36% | Exclude only `CreateKey` under `HKLM\System\CurrentControlSet\Services\` by the exact MDE image path. | Value changes, deletes, other images, and all Edge/Chrome/Firefox policy telemetry remain included. |

These are environment-observed suppressions, not general endorsements to ignore VS Code or MDE activity. Reassess them when executable paths, endpoint roles, or threat models change. The Chrome extension installation itself was not noisy: Sysmon retained four Event ID 15 records for the CRX download, SHA-256, Internet Zone marker, and Chrome Web Store referrer.

After loading the tuned configuration, a 125.3-second sample retained 247 events at **1.97 events/second**, a **97.7% reduction** from baseline. Neither suppressed pattern appeared, Event ID 255 remained at zero, and other ProcessAccess and registry activity continued to surface. Treat this as a local preliminary measurement and continue monitoring over normal business cycles.

## 🙏 Credits

This project is inspired by and derived from [Olaf Hartong's sysmon-modular project](https://github.com/olafhartong/sysmon-modular). Olaf created the modular Sysmon framework, the MDE augmentation strategy, and the upstream `sysmonconfig-mde-augment.xml` that serves as this project's foundation. This repository adapts that work for Windows 11 built-in Sysmon and adds targeted Microsoft Edge, Google Chrome, and Mozilla Firefox extension telemetry. Full upstream licensing is preserved in [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

## 📚 Sources and provenance

- [Enable and configure Sysmon in Windows](https://learn.microsoft.com/en-us/windows/security/operating-system-security/sysmon/how-to-enable-sysmon)
- [Sysmon events](https://learn.microsoft.com/en-us/windows/security/operating-system-security/sysmon/sysmon-events)
- [Olaf Hartong: sysmon-modular](https://github.com/olafhartong/sysmon-modular)
- [Upstream MDE augment configuration](https://raw.githubusercontent.com/olafhartong/sysmon-modular/master/sysmonconfig-mde-augment.xml)
- [Microsoft Edge extension policies](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies#extensions)
- [Chrome Enterprise extension policies](https://chromeenterprise.google/policies/#ExtensionInstallAllowlist)
- [Chrome alternative installation methods: Windows registry](https://developer.chrome.com/docs/extensions/how-to/distribute/install-extensions#registry)
- [Firefox administrator reference: ExtensionSettings](https://firefox-admin-docs.mozilla.org/reference/policies/extensionsettings/)
- [Firefox administrator reference: Extensions](https://firefox-admin-docs.mozilla.org/reference/policies/extensions/)

The upstream XML was retrieved on **2026-08-24** with SHA-256 `B0BAFCEC2BE753772E36E4BF891336DF558A4CEC53DD8C9BC716613B92F98943`, then extended with the documented managed/native browser registry rules and replacement of the competing `RegistryEvent` exclusion group. Review the [third-party notice](THIRD-PARTY-NOTICES.md) before redistribution.

*Disclaimer: GitHub Copilot (w/ChatGPT 5.6 Sol) was employed in the creation of this project.*