# HDR Context Menu

One desktop right-click action: **Enable HDR** when HDR is off and **Disable HDR** when it is on. With Nilesoft Shell, the action appears directly above **Display settings**.

The desktop entry uses the same softer monitor icons as the tray: green for on, yellow for off, and red for unavailable. Nilesoft shows **HDR: Unavailable** when no active display supports HDR. The native Windows entry stays hidden in that state.

The label follows changes made through Windows Settings, Win+Alt+B, or other apps. A background helper checks Windows display state every two seconds and starts when you sign in. Clicking the menu sets the requested state explicitly and checks that Windows applied it.

## Tray icon

The same helper also shows an HDR icon in the notification area (it may initially appear inside the hidden-icons arrow). Hover over it for current status.

The monitor icon contains white, yellow, and blue stars. A **green check** means HDR is enabled; a **yellow minus** means HDR is off; a **red X** means HDR is unavailable or its state cannot currently be read. With mixed displays, the icon is green when at least one display has HDR enabled; the tooltip and menu show **HDR: Mixed**. The icon refreshes along with the status.

Both menus open centered above the tray icon, shifting inward near screen edges to stay visible. The icon's position is queried each time; the cursor is a fallback only if Windows cannot locate the icon. They use a compact dark style with rounded corners, larger Segoe UI text, spacious rows, and clear hover states. Display details use the same style, and Windows high-contrast colors take precedence when enabled.

**Left-click** the icon for:

- **HDR: On / Off / Mixed**, plus a **Displays** submenu using the same **HDR: On**, **HDR: Off**, and **HDR: Unavailable** wording for each display.
- **Enable HDR / Disable HDR**, matching the current state. The action affects all HDR-capable displays. When HDR is unavailable, the header reads **HDR: Unavailable** and the action is hidden. It reappears automatically when HDR becomes available.

**Right-click** the icon for:

- **HDR settings** and **Display settings** shortcuts with solid gear icons.
- **Exit**, which closes the helper until the next sign-in. Automatic desktop label refresh also stops until the helper is restarted.

**Middle-click** (press the mouse wheel) to toggle HDR directly, using the current Windows display state. Further clicks are ignored while a change is in progress. As with the menu command, this affects all active HDR-capable displays.

Run **Start-Tray.vbs** to restart it without signing out. Only one helper runs per session. Transient display disconnects show an unavailable status and recover automatically. Status updates every two seconds and whenever the left-click menu opens. The HDR shortcut uses `ms-settings:display-hdr`; Display settings is also available for Windows versions that do not expose the dedicated HDR page.

## Install

Download this repository as a ZIP, extract it, and run **Install.cmd**. Accept the Windows administrator prompt using your current account. Installation refreshes Explorer; open folder windows may close. Run the installer again to update.

- Windows 10/11, Windows PowerShell 5.1, Windows Script Host, and an active HDR-capable display are required.
- Tested on Windows 11 with Nilesoft Shell 1.9.17. No monitor model restriction.
- Nilesoft is optional and is not downloaded or installed by this package. It is detected at `%SystemRoot%\nilesoft`; for another location, run `Setup.ps1 -NilesoftPath "D:\Tools\Shell"`.
- Without Nilesoft, the native entry appears in the classic desktop menu (Windows 11: **Show more options**). Exact placement above Display settings requires Nilesoft and an English Display settings caption.
- The action affects all active HDR-capable displays. If any are off, the next action is Enable HDR. If all are on, it is Disable HDR. With no capable display, the Nilesoft action is disabled and the native entry is hidden.
- Installation does not change the current HDR setting.

This package is intended for a single interactive user per PC. Install with that user's account. Files live in `%ProgramData%\HdrSdrMenu`, the native menu is registered for that user, and the `HdrSdrMenu-Label-<username>` scheduled task runs with limited privileges. Shared storage avoids packaged-app redirection of AppData.

## Uninstall

Run **Uninstall.cmd**, or run the installed `Setup.ps1 -Action Uninstall`. This removes the menu, logon helper, and installed program files. Nilesoft configuration backups remain under `%ProgramData%\HdrSdrMenu\backups`. Other Nilesoft customizations are preserved.

## How it works

`HdrSdrMenu.ps1` calls the Windows DisplayConfig APIs directly. Newer Windows versions use the HDR-specific API; older versions fall back to advanced-color support. `Toggle-HdrSdr.vbs` launches the helper without a console window. No third-party executable or network connection is needed to operate HDR.

`HdrTray.ps1` provides the Windows Forms tray menu inside the existing helper. The HDR command runs in a hidden child process so the menu remains responsive while Windows changes display mode. Run `powershell.exe -NoProfile -STA -File tests\Tray.Tests.ps1` for tray behavior tests using simulated displays; these tests do not change HDR.

To inspect state without changing it:

```powershell
powershell.exe -NoProfile -File "C:\ProgramData\HdrSdrMenu\HdrSdrMenu.ps1" -Action Status
```

The public source contains no machine-specific user paths, credentials, or display IDs.
