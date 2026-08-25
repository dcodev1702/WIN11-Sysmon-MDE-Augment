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
| [`scripts/Enable-Sysmon.ps1`](scripts/Enable-Sysmon.ps1) | Deploys Sysmon, enforces DNS Client Operational, and applies Firefox policy SACLs. |
| [`scripts/Test-Configuration.ps1`](scripts/Test-Configuration.ps1) | Verifies XML parsing, browser telemetry boundaries, noise tuning, and the Sysmon DNS-off invariant. |
| [`scripts/Protect-BrowserRegistryTelemetry.ps1`](scripts/Protect-BrowserRegistryTelemetry.ps1) | Reconstructs local browser/noise rules and the DNS-off invariant after an upstream refresh. |
| [`scripts/Set-FirefoxPolicyAudit.ps1`](scripts/Set-FirefoxPolicyAudit.ps1) | Enables Registry auditing and protects native/WOW6432Node Firefox policy roots with persistent SACLs. |
| [`scripts/Set-ProcessCreationAudit.ps1`](scripts/Set-ProcessCreationAudit.ps1) | Enables Advanced Audit Policy Process Creation and GPO-backed command-line inclusion. |
| [`scripts/Test-Telemetry.ps1`](scripts/Test-Telemetry.ps1) | Validates process command lines, audit precedence, Firefox SACLs, and a live marker-bearing Security 4688. |
| [`FIREFOX-EXTENSION-POLICY-GUIDE.md`](FIREFOX-EXTENSION-POLICY-GUIDE.md) | Documents the Firefox default-deny policy, approved-ID exceptions, manual deployment, verification, capture, and rollback. |
| [`CHANGELOG.md`](CHANGELOG.md) | Chronological record of telemetry and tuning changes. |
| [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md) | Attribution and license notice for the upstream configuration. |

## Firefox correlation report

The latest locally generated Firefox product is `output\firefox_grammarly_five_source_correlated_timeline_UTC.html`. Generated reports remain ignored by Git.

The current report uses this unified UTC window:

| Milestone | UTC |
| --- | --- |
| Report date | `2026-08-25` |
| Manual Firefox policy activity | `09:22:16.868–09:23:22.312` |
| Firefox capture | `09:24:22.312–09:25:12.772` |
| Report envelope | `09:22:16.868–09:25:12.772` |

All timeline rows, summaries, source cards, and report queries use UTC. The product correlates Security 4657/4688, DNS Client Operational, Sysmon, Defender XDR `DeviceFileEvents`, and Firefox capture artifacts. Its policy prelude uses the live manual Registry Editor chain from Security and Sysmon: process creation, temporary value creation, `ExtensionSettings` creation, and the final Grammarly policy write. XDR process telemetry and the intermediate delete operation are intentionally excluded from that timeline.

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
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Telemetry.ps1
```

The `-ExecutionPolicy Bypass` setting applies only to the new PowerShell process used for that command; it does not change the machine or user execution-policy setting. Both scripts require Windows PowerShell 5.1 (`powershell.exe`) because the inbox DISM feature cmdlets can fail under PowerShell 7 (`pwsh.exe`) on some Windows builds.

The installer:

1. Requires elevation and parses the configuration before changing Windows.
2. Refuses to proceed when a standalone Sysmon service may conflict.
3. Enables the `Sysmon` Windows optional feature.
4. Uses `sysmon -i` for a new installation or `sysmon -c` for an existing built-in installation.
5. Confirms the service and `Microsoft-Windows-Sysmon/Operational` event log exist.
6. Sets the Sysmon Operational channel maximum size to **4 GiB** and reports the effective size.
7. Tests whether `Microsoft-Windows-DNS-Client/Operational` is enabled at exactly **2 GiB**; if either condition is false, it enables the channel, sets the size, and verifies both conditions again.
8. Enables Security Registry success/failure auditing and verifies persistent, inheritable Firefox policy SACLs on native and WOW6432Node roots.
9. Enables Advanced Audit Policy Process Creation success/failure auditing, advanced subcategory precedence, and command-line inclusion in Security Event 4688.

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
wevtutil sl Microsoft-Windows-DNS-Client/Operational /e:true /ms:2147483648
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Set-FirefoxPolicyAudit.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Set-ProcessCreationAudit.ps1
```

Restart Windows after enabling the optional feature if requested, then continue with `sysmon -i`. Configuration changes take effect immediately and do not otherwise require a restart.

To update an existing installation:

```powershell
sysmon -c C:\Sysmon\win11-sysmon-mde-augment.xml
```

## 🔎 Browser extension registry coverage

Sysmon Registry Events **12, 13, and 14** cover registry key lifecycle, value set/delete, and object rename activity. A newly created value is recorded as Event 13 `SetValue`, the same event type used for later modifications. Twelve case-insensitive `contains` patterns cover managed policy trees for Microsoft Edge, Google Chrome, and Mozilla Firefox; native external-registration trees for Edge and Chrome; and defensive direct-registration coverage for Firefox. The patterns match each watched root and all descendant keys and values under HKLM or any HKU user SID; separate patterns cover WOW6432Node views.

| Activity | Sysmon event | Captured for watched trees |
| --- | --- | --- |
| Key create or delete | 12 | Yes |
| Value delete | 12 | Yes |
| Value create or modify (`SetValue`) | 13 | Yes |
| Registry object rename | 14 | Yes |

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
| Firefox | Native | `HKLM\SOFTWARE\Policies\Mozilla\Firefox\ExtensionSettings` (`REG_MULTI_SZ` value) |
| Firefox | Defensive 32-bit | `HKLM\SOFTWARE\WOW6432Node\Policies\Mozilla\Firefox\ExtensionSettings` (`REG_MULTI_SZ` mirror) |

Mozilla documents the native Firefox policy root. `ExtensionSettings` is the Firefox extension-management value used by this project; its single JSON element defines the wildcard default and any extension-specific exceptions. Nested `Extensions` policy subkeys are not treated as supported Firefox settings. The WOW6432Node Firefox pattern is defensive visibility for redirected, misplaced, or suspicious writes; it is not the recommended policy location.

### `ExtensionSettings.json` example

The following compact JSON is the validated example used for the Grammarly policy:

```json
{"*":{"installation_mode":"blocked","blocked_install_message":"Only approved extensions may be installed."},"87677a2c52b84ad3a151a4a72f5bd3c4@jetpack":{"installation_mode":"allowed"}}
```

| JSON entry | Effect |
| --- | --- |
| `"*"` | Applies a default rule to every extension without a more specific add-on-ID entry. |
| `"installation_mode":"blocked"` | Blocks installation of unapproved extensions and causes Firefox to remove an already-installed user extension that has no explicit exception. Firefox-managed system add-ons are handled separately. |
| `"blocked_install_message"` | Shows the administrator-supplied explanation when Firefox blocks an installation. |
| `"87677a2c52b84ad3a151a4a72f5bd3c4@jetpack"` | Matches Grammarly by its exact Firefox add-on ID. |
| `"installation_mode":"allowed"` | Permits the user to install Grammarly normally from Mozilla Add-ons. It does not install, force-enable, or lock the extension. |

An `ExtensionSettings.json` file is useful as a readable example, review artifact, backup, or deployment input. Firefox does **not** automatically read a standalone file with that name as the Windows enterprise policy. For this deployment, store the policy at the native Firefox location and mirror the same value under WOW6432Node for defensive 32-bit visibility:

```text
Native key:          HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Mozilla\Firefox
Defensive WOW key:  HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Policies\Mozilla\Firefox
Value:               ExtensionSettings
Type:                REG_MULTI_SZ
Data:                the complete JSON above as one string element
```

The native key is Mozilla's supported policy location. The WOW6432Node key is this project's defensive mirror for redirected, misplaced, or suspicious 32-bit writes; keep its `ExtensionSettings` value identical to the native value rather than treating it as a separate policy. To apply the configuration manually, fully exit Firefox, back up and review any existing Firefox policy, create or edit `ExtensionSettings` at both roots, and paste the compact JSON as one line. Merge required approved IDs into the same JSON object instead of overwriting an existing policy blindly. Fully restart Firefox; Windows sign-out is not required.

Verify the result at `about:policies`: the **Active** view must show `ExtensionSettings`, the wildcard entry must be `blocked`, the Grammarly ID must be `allowed`, and the **Errors** view must be empty. Then confirm an unlisted extension is blocked and Grammarly remains available for user installation. See the [complete Firefox extension policy guide](FIREFOX-EXTENSION-POLICY-GUIDE.md) and Mozilla's [ExtensionSettings reference](https://firefox-admin-docs.mozilla.org/reference/policies/extensionsettings/) for additional installation modes, backup, capture, troubleshooting, and rollback guidance.

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

Firefox extension management in this project uses only the supported `ExtensionSettings` policy value. The two non-policy Firefox `Extensions` roots are unrelated to that policy and are monitored only to surface direct, legacy, nonstandard, or suspicious registration attempts, even when those keys do not already exist. Creating, changing, renaming, or deleting a watched root, descendant key, or value generates Sysmon registry telemetry regardless of the writing process.

The XML maps these additions to MITRE ATT&CK **T1176: Browser Extensions**. Values beneath the watched policy roots contain extension identifiers, install URLs, or policy JSON, so changes are useful for detecting unauthorized allowlisting, blocking, or silent force-installation.

Because Sysmon exclusion rules take precedence over include rules, this configuration replaces the upstream `RegistryEvent onmatch="exclude"` group with one closed allowlist containing four exact AND rules: one for `MsSense.exe` `CreateKey` probes under `HKLM\System\CurrentControlSet\Services\` and three for periodic Windows Time health-state operations. None can match an Edge, Chrome, or Firefox extension root, so create, modify, delete, and rename telemetry remains unconditional for the requested browser paths. Other event-family exclusions from the MDE augment profile remain unchanged.

The four exclusion rules intentionally omit XML `name` attributes. Live testing showed that Sysmon can stamp the name of a partially matched exclusion rule onto an unrelated event that remains included. Comments and validator metadata retain readable labels without corrupting the `RuleName` field used by downstream detections.

### Firefox policy change detection

Firefox policy changes can be covered by three independent endpoint sources:

| Source | Primary evidence |
| --- | --- |
| Security | Event 4657 records the policy value name plus old/new JSON; Event 4688 records the modifying process. |
| Sysmon | Event 1 records the full writer command line; Events 12–14 identify policy key/value lifecycle under RuleName T1176. |
| Defender XDR | `DeviceProcessEvents` can provide registry-writer lineage, command line, integrity, token elevation, signature, and hashes when a qualifying process event is retained. It does not expose the policy JSON written by a GUI Registry Editor session. |

The current correlation report attributes the hand-entered policy change with Security and Sysmon only. Security records `regedit.exe` process creation and the actual `REG_MULTI_SZ` JSON; Sysmon independently records the same process and T1176 `SetValue` operations. No XDR process row is used for that manual policy prelude.

`Set-FirefoxPolicyAudit.ps1` enables the Security **Registry** audit subcategory for success and failure and applies one explicit, inheritable `Everyone` audit rule to each root:

```text
HKLM\SOFTWARE\Policies\Mozilla\Firefox
HKLM\SOFTWARE\WOW6432Node\Policies\Mozilla\Firefox
```

The SACL audits successful and failed `SetValue`, `CreateSubKey`, `Delete`, permission-change, and ownership-change operations on each root and its descendants. Existing DACLs are verified unchanged. The native path is Mozilla's supported policy location; WOW6432Node remains defensive monitoring for redirected, misplaced, or suspicious writes.

Query Defender XDR process telemetry for policy writers:

```kusto
DeviceProcessEvents
| where TimeGenerated > ago(1h)
| where DeviceName contains "win11-wsl2"
| where FileName in~ ("reg.exe", "regedit.exe")
| project TimeGenerated, ReportId, DeviceName, FileName,
          ProcessId, ProcessCommandLine, ProcessIntegrityLevel,
          ProcessTokenElevation, SHA256, InitiatingProcessId,
          InitiatingProcessFileName, InitiatingProcessCommandLine
| order by TimeGenerated asc
```

For Firefox installation correlation, use Security and Sysmon for manual policy provenance. Use `DeviceProcessEvents` for writer or browser lineage only when a qualifying process event exists, and use `DeviceFileEvents` for temporary XPI creation, staging, final rename, package hashes, and profile artifacts.

### Security process command lines

Security Event 4688 command-line capture is enforced to preserve registry-writer launch context and distinguish command-line operations. It does not prove which value a GUI `regedit.exe` session changed; correlate it with Security Event 4657 and Sysmon Events 12–14 for the actual registry operation. Deployment configures all three required controls:

| Control | Enforced state |
| --- | --- |
| Advanced Audit Policy → Detailed Tracking → Process Creation | Success and Failure |
| Include command line in process creation events | Enabled (`ProcessCreationIncludeCmdLine_Enabled=1`) |
| Force audit policy subcategory settings | Enabled (`SCENoApplyLegacyAuditPolicy=1`) |

The command-line setting is represented by this GPO-backed registry value:

```text
HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit
  ProcessCreationIncludeCmdLine_Enabled = 1 (REG_DWORD)
```

`Set-ProcessCreationAudit.ps1` applies the settings and runs `gpupdate /target:computer /force` when remediation is required. `Test-Telemetry.ps1` launches a harmless uniquely marked `cmd.exe` process and fails unless the resulting Security Event 4688 contains the marker in its `CommandLine` field. It also validates both Firefox policy SACLs and Security Registry auditing.

Domain or OU Group Policy takes precedence over local configuration. If enterprise policy disables or replaces these controls, the scripts verify the post-`gpupdate` state and fail rather than report protection incorrectly. Configure the equivalent domain GPO for managed fleets.

Process command lines can contain sensitive arguments. Restrict Security log access and forwarding destinations, apply appropriate retention/access controls, and avoid placing secrets directly on command lines.

### Firefox profile artifacts

Sysmon Event ID **11** adds two Firefox-specific artifact signals under `%APPDATA%\Mozilla\Firefox\Profiles`:

| Artifact | Meaning |
| --- | --- |
| `extensions\*.xpi` written by `firefox.exe` | High-confidence extension install or update artifact. |
| `extensions.json` written by `firefox.exe` | Extension state changed; correlate it with registry and XPI events because enable, disable, update, and removal can all rewrite this file. |

These are file-write artifacts, not semantic "installation succeeded" audit records.

## DNS correlation source

Sysmon Event ID **22** is explicitly disabled in this profile. Endpoint DNS detection and correlation use `Microsoft-Windows-DNS-Client/Operational`, which the installer keeps enabled with a **2 GiB** circular log. Relevant records include:

| DNS Client event | Correlation value |
| --- | --- |
| 3006 | Query start with requesting process ID, name, type, and options. |
| 3008 | Query completion with requesting process ID, name, type, status, and results. |
| 3009–3011 | Network path, DNS server, response, and `ClientPID` details from the DNS Client service. |
| 3016–3020 | Cache/wire-query stages, status, answers, and `ClientPID`. |

A controlled Edge test resolved a unique name through Edge's `network.mojom.NetworkService` PID `13636`. DNS Client Event 3008 retained the name and status, while Sysmon ProcessCreate mapped that PID to ProcessGuid `{825293f1-a8f9-6a8c-d245-000000002600}`. MDE's `MsSense.exe` independently queried the same name 23 times shortly afterward, providing a second detection-pipeline correlation point. No Sysmon Event 22 records were retained during either the Edge or PowerShell tests.

The DNS Client channel observes requests that use the Windows resolver. Browser DNS-over-HTTPS can bypass it; correlate browser debug telemetry, network security controls, or XDR network events when complete secure-DNS visibility is required. The controlled NXDOMAIN test caused unusually high Defender follow-up volume and must not be treated as a normal retention baseline.

## 🧪 Verify telemetry

Confirm the service and inspect recent events:

```powershell
Get-Service sysmon*

Get-WinEvent -LogName 'Microsoft-Windows-Sysmon/Operational' -MaxEvents 20 |
    Select-Object TimeCreated, Id, ProviderName, Message

Get-WinEvent -FilterHashtable @{
  LogName = 'Security'
  Id = 4657, 4688
  StartTime = (Get-Date).AddMinutes(-15)
} | Where-Object Message -Match 'Mozilla\\Firefox|reg(edit)?\.exe'
```

Run the deployed-state test after policy or audit changes:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Telemetry.ps1
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
- Preserve all twelve browser registry patterns, both Firefox Event ID 11 rules, and the empty Event ID 22 exclusion when refreshing the upstream MDE augment file.
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

### Windows Time follow-up

A follow-up retained-log review on **2026-08-24** covered **8.15 hours** from `08:50:32` through `16:59:37` UTC. It found **5,418** events from three Windows Time health-state operations: 1,806 occurrences of each operation, all from `C:\Windows\System32\svchost.exe`, with a median interval of **16.0045 seconds** and a 95th-percentile interval no greater than **16.0141 seconds**. `LastGoodSampleInfo` identified the `VM IC Time Synchronization Provider`; no other image or event-type combination touched the three exact targets.

| Operation | Exact exclusion boundary | Preserved security behavior |
| --- | --- | --- |
| ID 12 `CreateKey` on `HKLM\System\CurrentControlSet\Services\W32Time\Config\Status` | Exact `svchost.exe` image, `CreateKey` event type, and exact target. | Other images, descendants, deletes, renames, and all other W32Time keys remain visible. |
| ID 13 `SetValue` on `...\W32Time\Config\LastKnownGoodTime` | Exact `svchost.exe` image, `SetValue` event type, and exact target. | W32Time configuration and provider changes remain visible. |
| ID 13 `SetValue` on `...\W32Time\Config\Status\LastGoodSampleInfo` | Exact `svchost.exe` image, `SetValue` event type, and exact target. | Non-health state changes and writes by any other image remain visible. |

The three rules remove about **665 events/hour** on this Hyper-V guest without using a W32Time prefix exclusion. A pre-change sample under the current browser configuration retained **1,408 events over 763.87 seconds** (**1.84 events/second**) with zero Event ID 255 errors.

Post-load verification over **115.79 seconds** retained **176 events** at **1.52 events/second**, including 66 non-W32Time registry events, while all three exact W32Time tuple counts and Event ID 255 remained at zero. One event already queued under an interim named configuration arrived 0.623 seconds after the configuration-change event; after that in-flight record, the next 198 retained registry events contained zero local-noise RuleName labels and zero excluded W32Time targets.

No additional exclusion was approved for the other high-volume observations:

- BAM `State\UserSettings` writes remain because they provide forensic execution history.
- TCP/IP service-key probes remain because network-configuration tampering is security relevant.
- `MsSense.exe` TelLib writes remain because they map to defense-health and impairment telemetry outside the existing service-key probe boundary.
- VS Code ProcessAccess remains because the retained events match independent full-access, credential, or injection conditions rather than the broad AppData path rule.
- VS Code `\uv\` named pipes remain because they were process-start bursts from an extensible editor, not sustained background volume.

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

The upstream XML was retrieved on **2026-08-24** with SHA-256 `B0BAFCEC2BE753772E36E4BF891336DF558A4CEC53DD8C9BC716613B92F98943`, then extended with the documented managed/native browser registry rules and replacement of the competing `RegistryEvent` exclusion group. Review the [third-party notice](THIRD-PARTY-NOTICES.md) before redistribution.

*Disclaimer: GitHub Copilot (w/ChatGPT 5.6 Sol) was employed in the creation of this project.*