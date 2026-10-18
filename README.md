# HDR Context Menu

One desktop right-click action: **Enable HDR** when HDR is off and **Disable HDR** when it is on. With Nilesoft Shell, the action appears directly above **Display settings**.

The label follows changes made through Windows Settings, Win+Alt+B, or other apps. A hidden helper checks Windows display state every two seconds and starts when you sign in. Clicking the menu sets the requested state explicitly and checks that Windows applied it.

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

To inspect state without changing it:

```powershell
powershell.exe -NoProfile -File "C:\ProgramData\HdrSdrMenu\HdrSdrMenu.ps1" -Action Status
```

The public source contains no machine-specific user paths, credentials, or display IDs.
