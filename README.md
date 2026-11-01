# HDR Context Menu

One desktop right-click action: **Enable HDR** when HDR is off and **Disable HDR** when it is on. With Nilesoft Shell, the action appears directly above **Display settings**.

The desktop entry matches the tray menu's action icons: a green check for **Enable HDR**, a yellow minus for **Disable HDR**, and a red X for **HDR: Unavailable**. Nilesoft shows the unavailable entry when no active display supports HDR. The native Windows entry stays hidden in that state.

The label follows changes made through Windows Settings, Win+Alt+B, or other apps. A background helper checks Windows display state every two seconds and starts when you sign in. Clicking the menu sets the requested state explicitly and checks that Windows applied it.

## Tray icon

The same helper also shows an HDR icon in the notification area (it may initially appear inside the hidden-icons arrow). Hover over it for current status.

The tray icon has a colored sparkle, a smaller white sparkle, and a status badge. A **green check** means HDR is enabled; a **yellow minus** means HDR is off; a **red X** means HDR is unavailable or its state cannot currently be read. With mixed displays, the icon is green when at least one display has HDR enabled; the tooltip and menu show **HDR: Mixed**. The icon refreshes along with the status.

Both menus open centered above the tray icon, shifting inward near screen edges to stay visible. The icon's position is queried each time; the cursor is a fallback only if Windows cannot locate the icon. They use a compact dark style with rounded corners, larger Segoe UI text, spacious rows, and clear hover states. Display details use the same style, and Windows high-contrast colors take precedence when enabled.

**Left-click** the icon to show or hide the controls menu. Each click toggles it, including rapid consecutive clicks. The menu contains:

- With one active display, a top **HDR: Enabled / Disabled / Unavailable** status row. With multiple displays, a **Displays** submenu with each monitor's status replaces that row. With no displays detected, the top row shows **HDR: Unavailable**.
- **Enable HDR / Disable HDR**, matching the current state. The action affects all HDR-capable displays. When HDR is unavailable, the header reads **HDR: Unavailable** and the action is hidden. It reappears automatically when HDR becomes available.

**Right-click** the icon to show or hide the settings menu. Clicking the other mouse button switches menus. The settings menu contains:

- **HDR settings** and **Display settings** shortcuts with solid gear icons.
- **Exit**, which closes the helper until the next sign-in. Automatic desktop label refresh also stops until the helper is restarted.

**Middle-click** (press the mouse wheel) to toggle HDR directly, using the current Windows display state. Further clicks are ignored while a change is in progress. As with the menu command, this affects all active HDR-capable displays.

Open **HDR Context Menu** from the Start menu (or run **Start-Tray.vbs**) to restart it without signing out. Only one helper runs per session. Transient display disconnects show an unavailable status and recover automatically. Status updates every two seconds and whenever the left-click menu opens. The HDR shortcut uses `ms-settings:display-hdr`; Display settings is also available for Windows versions that do not expose the dedicated HDR page.

## Install

Download this repository as a ZIP, extract it, and run **Install.cmd**. Accept the Windows administrator prompt using your current account. Installation refreshes Explorer; open folder windows may close. Run the installer again to update.

- Windows 10/11, Windows PowerShell 5.1, Windows Script Host, and an active HDR-capable display are required.
- Tested on Windows 11 with Nilesoft Shell 1.9.17. No monitor model restriction.
- Nilesoft is optional and is not downloaded or installed by this package. It is detected at `%SystemRoot%\nilesoft`; for another location, run `Setup.ps1 -NilesoftPath "D:\Tools\Shell"`.
- Without Nilesoft, the native entry appears in the classic desktop menu (Windows 11: **Show more options**). Exact placement above Display settings requires Nilesoft and an English Display settings caption.
- The action affects all active HDR-capable displays. If any are off, the next action is Enable HDR. If all are on, it is Disable HDR. With no capable display, the Nilesoft action is disabled and the native entry is hidden.
- Installation does not change the current HDR setting.

This package is intended for a single interactive user per PC. Install with that user's account. Files live in `%ProgramData%\HdrSdrMenu`, the native menu is registered for that user, and the `HdrSdrMenu-Label-<username>` scheduled task runs with limited privileges. Shared storage avoids packaged-app redirection of AppData.

## Ketarin

Import **[ketarin/HDR Context Menu.xml](ketarin/HDR%20Context%20Menu.xml)** into Ketarin.

1. **Update** checks the latest `main` commit and downloads its exact archive into `..\_Tweaks\HDR Context Menu\_.zip`, relative to Ketarin.
2. The post-download command validates and extracts it into `Package`, keeping only the last package in `Package.previous`. After a successful update, it removes old `before-sync-*.zip` HDR archives and empty numbered `Package (n)` folders. The current `_.zip` is retained; other files and nonempty numbered folders are left alone. Extraction uses the local temporary folder, and updates copy contents into stable `Package` and `Package.previous` folders to avoid cloud-sync rename conflicts.
3. **Install** applies the prepared package. Updating alone does not install it or change HDR.

The entry uses the full commit SHA as its version indicator. Repeated checks do not download an unchanged commit. The XML contains the same extraction code as `ketarin/Extract-Package.ps1`.

## Uninstall

Run **Uninstall.cmd**, or run the installed `Setup.ps1 -Action Uninstall`. This removes the desktop menu, Start menu shortcut, logon helper, and installed program files. Nilesoft configuration backups remain under `%ProgramData%\HdrSdrMenu\backups`. Other Nilesoft customizations are preserved.

## How it works

`HdrSdrMenu.ps1` calls the Windows DisplayConfig APIs directly. Newer Windows versions use the HDR-specific API; older versions fall back to advanced-color support. `Toggle-HdrSdr.vbs` launches the helper without a console window. No third-party executable or network connection is needed to operate HDR.

`HdrTray.ps1` provides the Windows Forms tray menu inside the existing helper. The HDR command runs in a hidden child process so the menu remains responsive while Windows changes display mode. Run `powershell.exe -NoProfile -STA -File tests\Tray.Tests.ps1` for tray behavior tests using simulated displays; these tests do not change HDR.

To inspect state without changing it:

```powershell
powershell.exe -NoProfile -File "C:\ProgramData\HdrSdrMenu\HdrSdrMenu.ps1" -Action Status
```

The public source contains no machine-specific user paths, credentials, or display IDs.
