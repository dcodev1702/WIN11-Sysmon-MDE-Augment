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
6. Restart Firefox and verify the policy in `about:policies`.
7. Visit the new extension's AMO listing and select **Add to Firefox**.

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