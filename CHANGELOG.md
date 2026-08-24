# Changelog

All notable project changes are documented in this file.

## [Unreleased]

### Added

- Added Mozilla Firefox extension telemetry for enterprise policy changes, defensive direct `Extensions` registry coverage, profile XPI writes, and `extensions.json` state changes.
- Added `FIREFOX-EXTENSION-POLICY-GUIDE.md`, a standalone Registry Editor guide for blocking extensions by default, allowing explicit Firefox add-on IDs, user-driven installation from AMO web pages, policy testing, Sysmon verification, and revocation.
- Added `scripts/Capture-FirefoxExtensionTelemetry.ps1` to capture Firefox Add-on Manager debug output, before/after extension state, UTC-scoped Sysmon events, policy state, and an optional XDR CSV in one evidence bundle; `-AddonId` and `-AddonUrl` support controlled captures of extensions other than the Grammarly defaults.
- Documented the verified Grammarly XPI stable endpoint, version, size, SHA-256, manifest ID, and signature containers.

### Changed

- Moved all PowerShell automation into `scripts/` and updated default configuration resolution to continue loading the root-level `win11-sysmon-mde-augment.xml`.
- Updated README links and commands for the new script paths.
- Expanded Edge and Chrome registry monitoring to managed policy and native external-extension roots across HKLM, HKU user hives, native views, and WOW6432Node views.
- Updated validation and upstream-refresh protection to enforce all twelve browser registry patterns, root/key/value descendant coverage, and both Firefox FileCreate rules.
- Added three exact Windows Time registry exclusions for periodic `svchost.exe` health-state operations while preserving all other W32Time activity.
- Kept RegistryEvent exclusion rules unnamed in XML after live testing showed partially matched named exclusions can overwrite `RuleName` on unrelated retained events; comments and validator labels preserve operator context.
- Set the Sysmon Operational channel maximum size to 4 GiB and made that setting part of `Enable-Sysmon.ps1`.
- Disabled Sysmon Event ID 22 explicitly and selected `Microsoft-Windows-DNS-Client/Operational` as the endpoint DNS correlation source.
- Updated `Enable-Sysmon.ps1` to test whether DNS Client Operational is enabled at exactly 2 GiB, remediate either failed condition, and verify the resulting state.
- Updated validation and upstream-refresh protection to prevent accidental Sysmon DNS re-enablement.
- Added a UTC-normalized ColorZilla timeline correlating `chrome_debug.log`, Sysmon Operational events, and `xdr_results.csv`.
- Moved generated HTML reports into the ignored `output/` directory and replaced the global `*.html` ignore rule with `output/`.

### Observed

- Profiled the retained Sysmon Operational log across 8.15 hours and found 5,418 W32Time health-state events: 1,806 each for one exact `CreateKey` target and two exact `SetValue` targets.
- Measured a 16.0045-second median interval and no greater than 16.0141-second p95 interval for those operations; all were emitted by `C:\Windows\System32\svchost.exe`, and `LastGoodSampleInfo` identified the VM IC Time Synchronization Provider.
- Measured 1,408 events over 763.87 seconds (1.84 events/second) with zero Event ID 255 errors in the pre-change current-configuration sample.
- Retained BAM execution-history writes, TCP/IP probes, MDE TelLib defense-health writes, VS Code high-signal ProcessAccess, and VS Code named-pipe startup bursts rather than suppressing them on volume alone.
- Observed 53 unrelated retained `svchost.exe` registry events carrying a partially matched W32Time exclusion name, then removed exclusion `name` attributes to preserve downstream RuleName fidelity.
- Post-load validation retained 176 events over 115.79 seconds (1.52 events/second) and 66 non-W32Time registry events while recording zero excluded W32Time tuples and zero Event ID 255 errors; after one queued interim-config event, the next 198 registry events had zero local-noise RuleName labels.
- Verified DNS Client correlation with a unique PowerShell NXDOMAIN lookup and an isolated Edge lookup. Edge's DNS event PID `13636` joined to Sysmon ProcessCreate Record `208373` and ProcessGuid `{825293f1-a8f9-6a8c-d245-000000002600}`; `MsSense.exe` generated 23 follow-up completions for the same unique name, while Sysmon retained zero Event ID 22 records.

### Browser registry signal structure

- Browser extension registry telemetry is emitted by one `RegistryEvent onmatch="include"` block. Every browser rule is named `technique_id=T1176,technique_name=Browser Extensions`, making matching Events 12–14 directly identifiable by `RuleName`.
- The include block uses twelve case-insensitive `TargetObject condition="contains"` patterns:
	- Managed Edge: `\SOFTWARE\Policies\Microsoft\Edge`
	- Managed Edge WOW6432: `\SOFTWARE\WOW6432Node\Policies\Microsoft\Edge`
	- Managed Chrome: `\SOFTWARE\Policies\Google\Chrome`
	- Managed Chrome WOW6432: `\SOFTWARE\WOW6432Node\Policies\Google\Chrome`
	- Managed Firefox: `\SOFTWARE\Policies\Mozilla\Firefox`
	- Defensive Firefox WOW6432 visibility: `\SOFTWARE\WOW6432Node\Policies\Mozilla\Firefox`
	- Native Edge external extensions: `\SOFTWARE\Microsoft\Edge\Extensions`
	- Native Edge external extensions WOW6432: `\SOFTWARE\WOW6432Node\Microsoft\Edge\Extensions`
	- Native Chrome external extensions: `\SOFTWARE\Google\Chrome\Extensions`
	- Native Chrome external extensions WOW6432: `\SOFTWARE\WOW6432Node\Google\Chrome\Extensions`
	- Defensive Firefox direct extensions: `\SOFTWARE\Mozilla\Firefox\Extensions`
	- Defensive Firefox direct extensions WOW6432: `\SOFTWARE\WOW6432Node\Mozilla\Firefox\Extensions`
- Using path fragments rather than fixed hive prefixes makes each pattern match both machine state under `HKLM` and per-user state normalized by Sysmon under `HKU\<SID>`. Each pattern covers its root key and every descendant extension ID key/value.
- Managed-policy signals now include Chromium `ExtensionInstallAllowlist`, `ExtensionInstallBlocklist`, and `ExtensionInstallForcelist` changes plus Firefox `ExtensionSettings` and `Extensions\Install`, `Extensions\Uninstall`, and `Extensions\Locked` changes.
- Native external-registration signals now include extension-ID child keys and values such as Chrome `update_url`/`update_URL`, including native and redirected 32-bit registry views.
- Sysmon event semantics for these paths are:
	- Event ID 12: `CreateKey`, `DeleteKey`, and `DeleteValue` object lifecycle activity.
	- Event ID 13: `SetValue`, including initial value creation and subsequent modification.
	- Event ID 14: key or value rename activity.
- Exclude precedence remains bounded to four approved AND rules: one exact MDE service-key probe boundary and three exact Windows Time health-state boundaries. None can overlap any Edge, Chrome, or Firefox browser pattern, so browser extension registry events remain included regardless of the writing process.
- Firefox Event ID 11 rules capture `firefox.exe` writes to profile `extensions\*.xpi` files as install/update artifacts and `extensions.json` as corroborating extension-state activity.
- The ColorZilla capture demonstrates the managed signal path: Records `153155`, `153172`, `153173`, and `153174` surfaced allowlist value creation, rename/delete, and population with extension ID `bhlhnicpbhignbdhedgjhgdocnmhomnp` under RuleName T1176.
- The same capture exposed the former native-path gap at `HKLM\Software\Google\Chrome\Extensions\<extension-id>`. The native-root patterns close that gap for future Edge, Chrome, and defensive Firefox direct-registration activity.
- Live validation exercised Chrome and Edge across HKLM/HKU and native/WOW6432 views. It produced 40 T1176 records across eight roots: one `CreateKey`, two `SetValue`, one `DeleteValue`, and one `DeleteKey` per root, with eight complete lifecycles and zero residual test keys.

## [1.1.0] - 2026-08-24

### Changed

- Exempted the per-user Microsoft VS Code executable from the broad AppData ProcessAccess masquerading rule. Independent credential-dumping, injection, suspicious call-trace, and dangerous-access rules remain active.
- Replaced upstream registry exclusions with one approved rule for repetitive `MsSense.exe` `CreateKey` probes under `HKLM\System\CurrentControlSet\Services\`.
- Updated configuration validation and upstream-refresh protection to enforce both noise-tuning boundaries without weakening Edge or Chrome policy monitoring.

### Observed

- Identified a baseline of 23,074 retained events over 267.5 seconds (86.26 events/second).
- Attributed 93.54% of retained events to routine VS Code ProcessAccess polling and 4.36% to MDE service-key probes.
- Confirmed a Chrome Web Store installation of Keepa (`neebplgakaahbhdphmkckjjcegoiijjo`, version `5.64_0`) surfaced through four FileCreateStreamHash events containing the CRX hash, Internet Zone metadata, and store referrer.
- Measured 247 events over 125.3 seconds (1.97 events/second) after tuning, a 97.7% reduction from baseline, with zero suppressed-pattern matches and zero Event ID 255 errors.

### Security

- Preserved unconditional create, modify, delete, and rename telemetry for native and WOW6432Node Microsoft Edge and Google Chrome policy trees.
- Preserved all non-registry MDE augment exclusions and all high-signal ProcessAccess rules outside the broad AppData path rule.

## [1.0.0] - 2026-08-24

### Added

- Initial Windows 11 built-in Sysmon deployment based on Olaf Hartong's MDE augment configuration.
- Native and WOW6432Node Edge and Chrome extension-policy monitoring.
- PowerShell installation, validation, and upstream-refresh protection scripts.

[Unreleased]: https://github.com/dcodev1702/WIN11-Sysmon-MDE-Augment/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/dcodev1702/WIN11-Sysmon-MDE-Augment/compare/948ee07620ac790ec19846f165810ea074068a8c...v1.1.0
[1.0.0]: https://github.com/dcodev1702/WIN11-Sysmon-MDE-Augment/tree/v1.0.0