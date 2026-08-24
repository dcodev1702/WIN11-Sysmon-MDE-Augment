# Changelog

All notable project changes are documented in this file.

## [Unreleased]

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