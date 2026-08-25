# Firefox Extension Default-Deny Registry Guide

This guide configures Mozilla Firefox on Windows to:

- Block user installation of all extensions by default.
- Permit only explicitly approved Firefox add-on IDs.
- Let users install approved extensions from their normal Firefox Add-ons website pages.
- Retain Sysmon telemetry for policy and extension-profile changes.

The procedure uses Registry Editor and applies the policy machine-wide. It does not automatically install an extension unless you deliberately select an automatic installation mode later in this guide.

## Firefox policy model

Firefox does not use separate Chromium-style `ExtensionInstallBlocklist` and `ExtensionInstallAllowlist` registry keys. The closest equivalent is one `ExtensionSettings` policy containing JSON:

| Desired behavior | Firefox `ExtensionSettings` entry |
| --- | --- |
| Block extensions by default | `"*": {"installation_mode":"blocked"}` |
| Allow one extension for user installation | `"ADD_ON_ID": {"installation_mode":"allowed"}` |
| Automatically install and prevent removal | `"ADD_ON_ID": {"installation_mode":"force_installed", ...}` |
| Automatically install but permit disabling | `"ADD_ON_ID": {"installation_mode":"normal_installed", ...}` |

A specific extension ID overrides the `"*"` default. Therefore, a policy with `"*"` blocked and selected IDs allowed provides the Edge/Chrome-style default-deny workflow.

## Important warning

Enabling `"installation_mode":"blocked"` for `"*"` removes installed extensions that do not have an explicit ID override. Before applying the policy:

1. Inventory all existing user-installed Firefox extensions.
2. Decide which extensions must remain approved.
3. Record every approved Firefox add-on ID.
4. Test the complete policy on a lab profile before using it on a daily-use profile.

Built-in Firefox components are managed separately by Firefox.

## Prerequisites

- Mozilla Firefox installed on Windows.
- Local administrator rights to edit `HKEY_LOCAL_MACHINE`.
- Signed Firefox extensions. Standard Firefox requires extensions to be signed.
- The normal AMO listing URL for each approved extension.
- The exact Firefox add-on ID for each approved extension.

## Step 1: Collect each approved add-on ID

For an extension listed on [Firefox Add-ons](https://addons.mozilla.org/):

1. Open the extension's listing page.
2. Find **More information**.
3. Select **Copy add-on ID**.
4. Save the copied ID and the listing-page URL together.

For an extension that is already installed:

1. Enter `about:support` in Firefox.
2. Find the **Add-ons** section.
3. Record the extension's **ID** exactly as displayed.

The add-on ID is not necessarily the extension's display name or the slug in its AMO URL. If the ID is a UUID such as `{12345678-1234-1234-1234-1234567890ab}`, preserve the braces.

An AMO listing URL normally resembles:

```text
https://addons.mozilla.org/firefox/addon/EXTENSION-SLUG/
```

The listing URL is where the user will later select **Add to Firefox**. It is not stored in the registry when the extension uses `installation_mode` `allowed`.

## Step 2: Back up the existing Firefox policy

1. Close every Firefox window.
2. Open Registry Editor as Administrator.
3. If `HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Mozilla\Firefox` already exists, right-click the `Firefox` key and select **Export**.
4. Save the `.reg` backup in an approved administrative location.
5. Review existing Firefox policies before changing them.

Do not overwrite an existing `ExtensionSettings` value until its current JSON has been reviewed and merged with the new policy.

## Step 3: Create the machine-wide policy location

1. In Registry Editor, navigate to `HKEY_LOCAL_MACHINE\SOFTWARE\Policies`.
2. Create the `Mozilla` key if it does not exist.
3. Under `Mozilla`, create the `Firefox` key if it does not exist.
4. Confirm the final path is:

```text
HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Mozilla\Firefox
```

5. Select the `Firefox` key.
6. Select **Edit > New > Multi-String Value**.
7. Name the value `ExtensionSettings`.
8. Confirm its type is `REG_MULTI_SZ`.
9. Mirror the same `ExtensionSettings` value and JSON under the project's defensive 32-bit path:

```text
HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Policies\Mozilla\Firefox
```

The native path remains Mozilla's supported policy location. The WOW6432Node path provides defensive visibility for redirected, misplaced, or suspicious 32-bit writes and must contain the same value, type, and JSON rather than a separate policy.

## Step 4: Block every extension by default

Edit the `ExtensionSettings` value and enter the following JSON as one line:

```json
{"*":{"installation_mode":"blocked","blocked_install_message":"Only approved extensions may be installed."}}
```

This is the default-deny rule. Do not start Firefox with only this entry if currently installed extensions must remain available; add their approved IDs first.

## Step 5: Add explicitly approved IDs

Add each approved add-on ID as another top-level JSON property with `installation_mode` set to `allowed`.

For one approved extension:

```json
{"*":{"installation_mode":"blocked","blocked_install_message":"Only approved extensions may be installed."},"APPROVED_ADDON_ID":{"installation_mode":"allowed"}}
```

### Concrete example: Grammarly allowed

This `ExtensionSettings.json` example blocks unlisted user extensions while allowing the Grammarly Firefox add-on ID:

```json
{"*":{"installation_mode":"blocked","blocked_install_message":"Only approved extensions may be installed."},"87677a2c52b84ad3a151a4a72f5bd3c4@jetpack":{"installation_mode":"allowed"}}
```

The wildcard `"*"` entry establishes default-deny behavior and supplies the message shown for blocked installation attempts. The exact Grammarly ID overrides that default with `allowed`, which permits normal user installation from Mozilla Add-ons. It does not automatically install, force-enable, or lock Grammarly. Firefox-managed system add-ons are handled separately from these user-extension rules.

The filename `ExtensionSettings.json` is useful for a reviewable example, backup, or deployment input, but Firefox does not automatically read a standalone file with that name as the Windows enterprise policy. Registry Editor must store the complete compact JSON as one string element in the `REG_MULTI_SZ` value named `ExtensionSettings` under `HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Mozilla\Firefox`, then mirror the identical value under `HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Policies\Mozilla\Firefox` for this project's defensive 32-bit coverage. If an automation tool consumes the JSON file, that tool must validate the JSON and write the same value and type to both roots. After applying it, fully restart Firefox and verify the policy in the **Active** and **Errors** views at `about:policies`.

For multiple approved extensions:

```json
{"*":{"installation_mode":"blocked","blocked_install_message":"Only approved extensions may be installed."},"FIRST_ADDON_ID":{"installation_mode":"allowed"},"SECOND_ADDON_ID":{"installation_mode":"allowed"}}
```

When editing the JSON:

- Replace every placeholder with an exact Firefox add-on ID.
- Keep the `"*"` blocked entry.
- Separate top-level properties with commas.
- Do not add comments or trailing commas.
- Do not use an AMO slug, display name, or Chrome extension ID in place of a Firefox add-on ID.
- Do not add `install_url` to an `allowed` entry. It is unnecessary for user-driven installation.

## Step 6: Verify Firefox accepted the policy

1. Close Registry Editor.
2. Start Firefox.
3. Enter `about:policies` in the address bar.
4. Open the **Active** tab.
5. Confirm `ExtensionSettings` appears.
6. Confirm the `"*"` entry has `installation_mode` set to `blocked`.
7. Confirm every approved add-on ID has `installation_mode` set to `allowed`.
8. Open the **Errors** tab and confirm it is empty.

If Firefox reports an error, stop before testing installation. Correct the registry value and restart Firefox.

Windows sign-out/sign-in is not required for a registry policy change. Firefox must fully exit and restart so it reads the updated enterprise policy. If a sign-out appeared necessary during testing, it likely terminated a Firefox background process that remained alive after the visible windows closed. Verify that no process remains before restarting:

```powershell
Get-Process firefox -ErrorAction SilentlyContinue
```

No output means Firefox is fully stopped. Start Firefox again and confirm the new value in `about:policies` before attempting installation.

Sysmon Events 12–14 for the monitored Firefox policy path do not require a registry SACL. Windows Security Event 4657 is different: it appears only when the **Registry** audit subcategory is enabled and the policy key has a matching audit entry. `scripts\Set-FirefoxPolicyAudit.ps1` persistently configures success/failure auditing for writes and security changes on both `HKLM\SOFTWARE\Policies\Mozilla\Firefox` and its defensive WOW6432Node equivalent.

Security Event 4688 identifies the policy-writing process. `scripts\Set-ProcessCreationAudit.ps1` enables Advanced Audit Policy Process Creation, forces subcategory precedence, enables GPO-backed command-line inclusion, and applies computer policy. This is critical because a 4688 with an empty command line proves only that `reg.exe` started; with command-line auditing enabled, it also records the policy path, value name, data type, and JSON argument. Validate both controls after deployment:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Telemetry.ps1
```

Correlate Security 4657/4688, Sysmon T1176 records, Defender XDR `DeviceProcessEvents`, and the effective value in `about:policies`. Process command lines can contain sensitive arguments, so restrict Security log access and avoid command-line secrets.

Domain or OU Group Policy can override local audit settings. The deployment and test scripts verify effective state after policy application and fail if command-line auditing or the required audit controls are not active.

## Step 7: Install an approved extension from the web

1. In Firefox, open the saved AMO listing URL for an approved extension.
2. Select **Add to Firefox**.
3. Review the requested permissions.
4. Confirm the Firefox installation prompt.
5. Open `about:addons` and confirm the extension is installed.

Because the extension's exact ID has an `allowed` override, it can be installed despite the `"*"` blocked default. The user can later disable or remove an extension installed through this user-driven flow.

## Step 8: Confirm unapproved extensions are blocked

Perform this only as a controlled policy test:

1. Open the AMO listing for an extension whose ID is not in `ExtensionSettings`.
2. Select **Add to Firefox**.
3. Confirm Firefox rejects the installation and displays the configured block message.
4. Open `about:addons` and confirm the unapproved extension was not installed.

This test validates the default `"*"` block. An approved website origin alone must not bypass the extension-ID restriction.

## Add another approved extension later

1. Collect the new extension's exact Firefox add-on ID and AMO listing URL.
2. Close all Firefox windows.
3. Open the existing `ExtensionSettings` value in Registry Editor.
4. Add a new ID-level property with `"installation_mode":"allowed"`.
5. Preserve the `"*"` blocked entry and all existing approved IDs.
6. Fully restart Firefox; Windows sign-out is not required.
7. Verify the policy in `about:policies`.
8. Visit the new extension's AMO listing and select **Add to Firefox**.

## Revoke an extension

To remove an installed extension and explicitly prohibit its ID:

1. Close all Firefox windows.
2. Change that ID's `installation_mode` from `allowed` to `blocked`.
3. Restart Firefox.
4. Confirm the extension was removed from `about:addons`.
5. Confirm `about:policies` reports no errors.

You may retain the explicit `blocked` entry to document the denial. If you remove the ID property later, the `"*"` blocked default still prevents reinstallation.

## Do not substitute origin policies for the ID allowlist

`InstallAddonsPermission` controls which website origins may initiate extension installation. It does not approve an extension ID and is not equivalent to the Edge or Chrome extension allowlist.

Similarly, `install_sources` controls permitted download/referrer URL patterns. Mozilla documents that it is unnecessary when approval is based on specific extension IDs. It also does not override `"installation_mode":"blocked"`.

For the workflow in this guide, use:

- `"*"` with `installation_mode` `blocked` for default deny.
- Exact add-on IDs with `installation_mode` `allowed` for exceptions.
- The normal AMO listing URL for user-driven installation.

## Optional automatic installation

Use an automatic mode only when user-driven installation is not desired:

- `force_installed` automatically installs the extension and prevents user removal.
- `normal_installed` automatically installs the extension but allows the user to disable it.

For compatibility across Firefox releases, provide an explicit AMO XPI URL:

```json
{"*":{"installation_mode":"blocked"},"APPROVED_ADDON_ID":{"installation_mode":"force_installed","install_url":"https://addons.mozilla.org/firefox/downloads/latest/APPROVED_ADDON_ID/latest.xpi"}}
```

For a private signed XPI, use an approved HTTPS URL or a `file:///` URL. This automatic mode differs from the allow-and-install-from-the-web workflow.

### Verified Grammarly XPI

Mozilla's stable latest-version endpoint for the approved Grammarly ID is:

```text
https://addons.mozilla.org/firefox/downloads/latest/87677a2c52b84ad3a151a4a72f5bd3c4%40jetpack/latest.xpi
```

On 2026-08-24, that endpoint resolved to:

```text
https://addons.mozilla.org/firefox/downloads/file/4774290/grammarly_1-8.937.0.xpi
```

The downloaded artifact was verified against Mozilla's Add-ons API and its manifest:

| Property | Verified value |
| --- | --- |
| Version | `8.937.0` |
| Size | `42,614,714` bytes |
| SHA-256 | `d8f2deca5a0d23d8d072ed24548d3897eef19bc871556b18d7c09e91c07139b7` |
| Manifest ID | `87677a2c52b84ad3a151a4a72f5bd3c4@jetpack` |
| Content type | `application/x-xpinstall` |
| Signature containers | COSE and Mozilla JAR signature entries under `META-INF` |

The stable endpoint is preferable to pinning file ID `4774290` because it follows the current compatible AMO release. Do not add `install_url` to the current `allowed` policy entry: Firefox ignores it for the user-driven workflow. Use the stable XPI URL only with `force_installed` or `normal_installed`, or when downloading an artifact for offline analysis.

## Capture Firefox extension debug telemetry

Firefox does not create a `chrome_debug.log` equivalent by default. Its Add-on Manager uses the JavaScript loggers `addons.manager`, `addons.xpi`, and `addons.xpi-utils`. Setting `extensions.logging.enabled=true` raises the parent `addons` logger from warnings to debug and writes messages to the Browser Console and standard error.

The selected `default-release` profile in this environment enables that preference through:

```javascript
user_pref("extensions.logging.enabled", true);
```

The preference is intentionally profile-scoped. Remove that line from `user.js` after troubleshooting if continuous Add-on Manager debug output is not desired.

## 🧰 Step-by-step: save Firefox logging to a file

A normal Start-menu launch does not preserve Firefox Add-on Manager diagnostics because standard error is not redirected. For a capture, let `Capture-FirefoxExtensionTelemetry.ps1` start Firefox. The script saves the Firefox log, records the UTC capture window, and snapshots extension state. Query Sysmon directly from `Microsoft-Windows-Sysmon/Operational` using the recorded UTC bounds.

### 1. 🪪 Record the approved extension details

Have both the Firefox add-on ID and its AMO page URL ready. Add the ID to the allowed policy before starting. Grammarly is already the script default; another extension must be supplied with `-AddonId` and `-AddonUrl`.

Replace `REAL-ADDON-ID` and `REAL-AMO-SLUG` in the examples below. Do not enter those placeholders literally.

### 2. 🛑 Close Firefox completely

Close every Firefox window, then verify that no Firefox process remains:

```powershell
Get-Process firefox -ErrorAction SilentlyContinue
```

No output means Firefox is stopped. If a process is listed, close Firefox normally before continuing so profile state is flushed cleanly.

### 3. 📂 Open the repository in Windows PowerShell

Open a normal, **non-administrator** Windows PowerShell 5.1 window and move to the repository. Do not run the capture from an elevated terminal: Firefox de-elevates administrator launches through Explorer, which detaches the redirected logging streams.

```powershell
Set-Location C:\Users\Lorenzo\gh_repos\win11-sysmon
```

### 4. ✅ Validate capture prerequisites

For Grammarly, use the defaults:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
    -File .\scripts\Capture-FirefoxExtensionTelemetry.ps1 `
    -ValidateOnly
```

For another approved extension, validate with its real ID and AMO URL:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
    -File .\scripts\Capture-FirefoxExtensionTelemetry.ps1 `
    -ValidateOnly `
    -AddonId 'REAL-ADDON-ID' `
    -AddonUrl 'https://addons.mozilla.org/en-US/firefox/addon/REAL-AMO-SLUG/'
```

Continue only when the result contains:

```text
AddonLoggingEnabled : True
ShellElevated       : False
Status              : Ready
```

If validation reports `ShellElevated: True` and `Status: Blocked`, close that terminal and repeat the command in a normal non-administrator Windows PowerShell window.

### 5. ▶️ Start the capture

For Grammarly, run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
    -File .\scripts\Capture-FirefoxExtensionTelemetry.ps1
```

For another approved extension, run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
    -File .\scripts\Capture-FirefoxExtensionTelemetry.ps1 `
    -AddonId 'REAL-ADDON-ID' `
    -AddonUrl 'https://addons.mozilla.org/en-US/firefox/addon/REAL-AMO-SLUG/'
```

The script creates `output\firefox-extension-capture-<UTC timestamp>\`, prints the exact debug-log path, snapshots current extension/policy state, records the UTC start time, and opens the supplied AMO page in Firefox. Keep this PowerShell window open; it waits for Firefox to exit.

If an XDR CSV covering the same activity already exists, include a copy at capture start:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
    -File .\scripts\Capture-FirefoxExtensionTelemetry.ps1 `
    -AddonId 'REAL-ADDON-ID' `
    -AddonUrl 'https://addons.mozilla.org/en-US/firefox/addon/REAL-AMO-SLUG/' `
    -XdrCsvPath 'C:\Path\To\xdr_results.csv'
```

### 6. 🧪 Install and exercise the extension

1. Select **Add to Firefox** on the AMO page.
2. Accept the Firefox permission prompt.
3. Confirm that the extension appears installed and enabled.
4. Leave Firefox idle for one or two minutes.
5. Perform one controlled, repeatable extension action on a neutral page.
6. Leave Firefox idle again for several minutes.

A five-to-ten-minute controlled window is usually more useful than leaving the browser running indefinitely because it limits unrelated browser noise.

### 7. 👀 Watch the Firefox log live (optional)

Open a second PowerShell window in the repository and run:

```powershell
$latest = Get-ChildItem .\output\firefox-extension-capture-* -Directory |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

Get-Content `
    -LiteralPath (Join-Path $latest.FullName 'firefox_addon_manager_debug.log') `
    -Wait
```

Press `Ctrl+C` in the second window to stop watching. This does not stop Firefox or the capture running in the first window.

### 8. ⏹️ Stop and finalize the capture

Close every Firefox window normally. When Firefox exits, the first PowerShell window records the UTC end time, takes the after-install extension snapshot, and returns `Status: Captured`.

Verify Firefox is no longer running if the first window does not return:

```powershell
Get-Process firefox -ErrorAction SilentlyContinue
```

### 9. 🔎 Inspect the completed evidence

Find the newest capture and review its metadata, Firefox log, and extension snapshot:

```powershell
$latest = Get-ChildItem .\output\firefox-extension-capture-* -Directory |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

Get-Content (Join-Path $latest.FullName 'capture_metadata.json')
Get-Content (Join-Path $latest.FullName 'firefox_addon_manager_debug.log')

Import-Csv (Join-Path $latest.FullName 'firefox_extensions_after.csv') |
    Format-Table
```

Use `CaptureStartUtc` and `CaptureEndUtc` from `capture_metadata.json` to query Sysmon from its authoritative source:

```powershell
$metadata = Get-Content (Join-Path $latest.FullName 'capture_metadata.json') -Raw |
    ConvertFrom-Json

Get-WinEvent -FilterHashtable @{
    LogName = $metadata.SysmonSourceLog
    StartTime = [datetime]$metadata.SysmonQueryStartUtc
    EndTime = [datetime]$metadata.SysmonQueryEndUtc
} | Sort-Object TimeCreated
```

If the XDR export is created after the capture, copy it into the completed evidence directory:

```powershell
Copy-Item `
    -LiteralPath 'C:\Path\To\xdr_results.csv' `
    -Destination (Join-Path $latest.FullName 'xdr_results.csv')
```

### 10. 📦 Capture contents

Each run creates an ignored timestamped directory below `output\` containing:

| Artifact | Purpose |
| --- | --- |
| `firefox_addon_manager_debug.log` | Firefox Add-on Manager/XPI debug output captured from standard error. |
| `firefox_stdout.log` | Separate Firefox standard-output capture for launch diagnostics. |
| `capture_metadata.json` | UTC window, Firefox/profile details, exit code, artifact paths, and authoritative Sysmon source/query bounds. |
| `firefox_extension_policy.json` | Read-only snapshot of the effective `ExtensionSettings` registry value. |
| `firefox_extensions_before.csv` | Extension state immediately before launch. |
| `firefox_extensions_after.csv` | Extension state after Firefox exits. |
| `xdr_results.csv` | Optional copy of the XDR export supplied with `-XdrCsvPath`. |

The script launches Firefox with structured `Start-Process` redirection instead of shell command-line quoting. Standard error and standard output use separate files because `Start-Process` requires distinct redirection targets. The script also sets process-scoped `MOZ_LOG=timestamp,sync` and restores the caller's previous value after Firefox exits.

### Correlate the capture

Use `CaptureStartUtc` and `CaptureEndUtc` from `capture_metadata.json` as the shared time boundary. Pull Sysmon records directly from `Microsoft-Windows-Sysmon/Operational`; do not use copied or previously bundled Sysmon exports. Correlate on:

- Firefox process IDs and process GUIDs.
- Add-on ID `87677a2c52b84ad3a151a4a72f5bd3c4@jetpack`.
- XPI URLs, temporary XPI paths, and the installed profile XPI path.
- `extensions.json` changes.
- Sysmon RuleName `technique_id=T1176,technique_name=Browser Extensions` for registry policy activity.
- Sysmon Event IDs 3, 11-15, 23, and 26 for network, file, registry, and deletion evidence.
- DNS Client Operational Event 3008 for Windows-resolver query name, requester PID, status, and answer correlation; Sysmon Event ID 22 is disabled in this profile.
- Defender XDR `DeviceProcessEvents` for policy-writer and browser process command lines, PID/parent lineage, integrity, elevation, signature, and hashes.
- Defender XDR `DeviceFileEvents` for temporary XPI creation, staging, final rename, package hash continuity, and profile artifacts.
- XDR event timestamps normalized to UTC.

Use this Defender XDR process query for Firefox policy edits:

```kusto
DeviceProcessEvents
| where TimeGenerated > ago(1h)
| where DeviceName contains "win11-wsl2" and FileName contains "reg.exe"
| project TimeGenerated, ReportId, DeviceName, FileName,
          ProcessId, ProcessCommandLine, ProcessIntegrityLevel,
          ProcessTokenElevation, SHA256, InitiatingProcessId,
          InitiatingProcessFileName, InitiatingProcessCommandLine
| order by TimeGenerated asc
```

Treat the Firefox log, Security, Sysmon, DNS Client, and both XDR tables as independent evidence sources. A Firefox install-complete message is application telemetry; profile XPI and `extensions.json` writes are file artifacts; and policy registry/process events show configuration state rather than proving that the add-on installed successfully.

## Verify Sysmon telemetry

The Sysmon configuration monitors the Firefox policy root and Firefox profile artifacts. After changing `ExtensionSettings` or installing an approved extension, run:

```powershell
$started = (Get-Date).AddMinutes(-15)
Get-WinEvent -FilterHashtable @{
    LogName = 'Microsoft-Windows-Sysmon/Operational'
    Id = 11, 12, 13, 14
    StartTime = $started
} | Where-Object Message -Match 'Mozilla\\Firefox|extensions\.json|\.xpi' |
    Select-Object TimeCreated, Id, Message
```

Expected evidence:

- Event ID 12 for policy key or value creation/deletion activity.
- Event ID 13 for setting or modifying `ExtensionSettings`.
- Event ID 14 for policy key or value rename activity.
- Event ID 11 when Firefox writes a matching profile XPI or `extensions.json` artifact.

Sysmon records telemetry; it does not itself block extensions or generate an alert. Firefox enforces the policy, and a SIEM or XDR rule must convert matching Sysmon events into alerts.

## Roll back the policy

1. Close all Firefox windows.
2. Export the current `Firefox` policy key if a final backup is required.
3. Delete only the `ExtensionSettings` value, or restore the previously exported value.
4. Restart Firefox.
5. Confirm `ExtensionSettings` is absent or restored in `about:policies`.

Extensions removed by the default-deny policy are not automatically reinstalled when the policy is removed.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| `ExtensionSettings` does not appear in `about:policies` | Confirm the HKLM path, value name, and `REG_MULTI_SZ` type; then fully restart Firefox. |
| `about:policies` reports JSON errors | Validate commas, quotes, braces, and the absence of comments or trailing commas. |
| An approved extension is blocked | Confirm the exact Firefox add-on ID, including braces for UUID IDs. Do not use the AMO slug or a Chromium ID. |
| An unapproved extension installs | Confirm the `"*"` entry is present and set to `blocked`, and check for another policy source overriding this registry policy. |
| An existing extension disappears | Its ID was not explicitly overridden when the `"*"` block was activated. Add the approved ID and reinstall it from AMO. |
| No Sysmon registry event appears | Confirm the current Sysmon XML is loaded and query Event IDs 12-14 under `SOFTWARE\Policies\Mozilla\Firefox`. |

## Sources

- [Firefox administrator reference: ExtensionSettings](https://firefox-admin-docs.mozilla.org/reference/policies/extensionsettings/)
- [Firefox administrator reference: InstallAddonsPermission](https://firefox-admin-docs.mozilla.org/reference/policies/installaddonspermission/)
- [Mozilla Extension Workshop: Enterprise distribution](https://extensionworkshop.com/documentation/enterprise/enterprise-distribution/)
- [Mozilla Gecko logging](https://firefox-source-docs.mozilla.org/xpcom/logging.html)
- [Mozilla Add-on Manager source documentation](https://firefox-source-docs.mozilla.org/toolkit/mozapps/extensions/addon-manager/)