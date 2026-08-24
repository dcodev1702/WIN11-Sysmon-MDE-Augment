# Changelog

All notable project changes are documented in this file.

## [Unreleased]

### Changed

- Moved all PowerShell automation into `scripts/` and updated default configuration resolution to continue loading the root-level `win11-sysmon-mde-augment.xml`.
- Updated README links and commands for the new script paths.
- Expanded Edge and Chrome registry monitoring to managed policy and native external-extension roots across HKLM, HKU user hives, native views, and WOW6432Node views.
- Updated validation and upstream-refresh protection to enforce all eight browser registry patterns.
- Set the Sysmon Operational channel maximum size to 4 GiB and made that setting part of `Enable-Sysmon.ps1`.
- Added a UTC-normalized ColorZilla timeline correlating `chrome_debug.log`, Sysmon Operational events, and `xdr_results.csv`.
- Moved generated HTML reports into the ignored `output/` directory and replaced the global `*.html` ignore rule with `output/`.

### Browser registry signal structure

- Browser extension registry telemetry is emitted by one `RegistryEvent onmatch="include"` block. Every browser rule is named `technique_id=T1176,technique_name=Browser Extensions`, making matching Events 12–14 directly identifiable by `RuleName`.
- The include block uses eight case-insensitive `TargetObject condition="contains"` patterns:
	- Managed Edge: `\SOFTWARE\Policies\Microsoft\Edge`
	- Managed Edge WOW6432: `\SOFTWARE\WOW6432Node\Policies\Microsoft\Edge`
	- Managed Chrome: `\SOFTWARE\Policies\Google\Chrome`
	- Managed Chrome WOW6432: `\SOFTWARE\WOW6432Node\Policies\Google\Chrome`
	- Native Edge external extensions: `\SOFTWARE\Microsoft\Edge\Extensions`
	- Native Edge external extensions WOW6432: `\SOFTWARE\WOW6432Node\Microsoft\Edge\Extensions`
	- Native Chrome external extensions: `\SOFTWARE\Google\Chrome\Extensions`
	- Native Chrome external extensions WOW6432: `\SOFTWARE\WOW6432Node\Google\Chrome\Extensions`
- Using path fragments rather than fixed hive prefixes makes each pattern match both machine state under `HKLM` and per-user state normalized by Sysmon under `HKU\<SID>`. Each pattern covers its root key and every descendant extension ID key/value.
- Managed-policy signals now include `ExtensionInstallAllowlist`, `ExtensionInstallBlocklist`, `ExtensionInstallForcelist`, `ExtensionSettings`, and other extension controls below the Edge or Chrome policy root.
- Native external-registration signals now include extension-ID child keys and values such as Chrome `update_url`/`update_URL`, including native and redirected 32-bit registry views.
- Sysmon event semantics for these paths are:
	- Event ID 12: `CreateKey`, `DeleteKey`, and `DeleteValue` object lifecycle activity.
	- Event ID 13: `SetValue`, including initial value creation and subsequent modification.
	- Event ID 14: key or value rename activity.
- Exclude precedence remains bounded to one approved AND rule: exact image `MsSense.exe`, exact `CreateKey` event type, and `HKLM\System\CurrentControlSet\Services\`. It cannot overlap any Edge or Chrome browser pattern, so browser extension registry events remain included regardless of the writing process.
- The ColorZilla capture demonstrates the managed signal path: Records `153155`, `153172`, `153173`, and `153174` surfaced allowlist value creation, rename/delete, and population with extension ID `bhlhnicpbhignbdhedgjhgdocnmhomnp` under RuleName T1176.
- The same capture exposed the former native-path gap at `HKLM\Software\Google\Chrome\Extensions\<extension-id>`. The eight-pattern structure closes that gap for future Chrome and Edge activity.
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