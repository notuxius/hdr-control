# HDR Control

Current version: **1.6.0**.

Control HDR, automate switching, and adjust SDR brightness on Windows. Formerly **HDR Context Menu**.

The GitHub repository is now `notuxius/hdr-control`. Older installed updaters that only recognize `hdr-context-menu` archive folders need a one-time manual upgrade with the HDR Control installer. Existing preferences are retained. The current updater accepts both archive names.

The desktop right-click action shows: **Enable HDR** when HDR is off and **Disable HDR** when it is on. With Nilesoft Shell, the action appears directly above **Display settings**.

The desktop entry matches the tray menu's action icons: a green check for **Enable HDR**, a yellow minus for **Disable HDR**, and a red X for **HDR: Unavailable**. Nilesoft shows the unavailable entry when no active display supports HDR. The native Windows entry stays hidden in that state.

The label follows changes made through Windows Settings, Win+Alt+B, or other apps. A background helper checks Windows display state every two seconds and starts when you sign in. Clicking the menu sets the requested state explicitly and checks that Windows applied it.

## Tray icon

The same helper also shows an HDR icon in the notification area (it may initially appear inside the hidden-icons arrow). Hover over it for current status.

The system tray icon is **green** when HDR is on and **yellow** when HDR is off. In both states, the lower-right badge shows **play** when automatic HDR switching is on and **pause** when it is off. Hovering over the icon shows **HDR Control -** followed by the left-click menu status, for example **HDR Control - HDR: Enabled · Auto: Idle**. A **red X** means HDR is unavailable or cannot be read. With mixed displays, the icon is green and the tooltip and menu show **HDR: Mixed**.

Both menus open centered above the tray icon, shifting inward near screen edges to stay visible. The icon's position is queried each time; the cursor is a fallback only if Windows cannot locate the icon. They use a compact dark style with rounded corners, larger Segoe UI text, spacious rows, and clear hover states. Display details use the same style, and Windows high-contrast colors take precedence when enabled.

**Left-click** the icon to show or hide the controls menu. Each click toggles it, including rapid consecutive clicks. The menu contains:

- One informational row shows the current HDR state and what automatic switching is doing, for example **HDR: Disabled · Auto: Idle** or **HDR: Enabled · Auto: Enabled for game.exe**. The display name appears above it. With multiple monitors, the **Displays** submenu takes the place of the name, and the summary shows **HDR: Mixed** when HDR is enabled on some capable monitors and disabled on others. The submenu lists each monitor’s HDR state and offers a toggle for each capable monitor.
- **Enable HDR / Disable HDR**, matching the current state. With multiple displays this reads **Enable HDR on all displays / Disable HDR on all displays** and affects all HDR-capable displays. When HDR is unavailable, open **Displays** to see each connected monitor and its HDR status. With no connected monitors, **Displays** is dimmed. The HDR action reappears automatically when HDR becomes available.
- **Enable auto-switching** appears directly below the manual HDR action. Once enabled, the same row reads **Disable auto-switching**. Automatic switching starts off by default. In **Settings → Game lists**, a notice shows when game detection is paused. Choose **Enable auto-switching** there to resume detection.
- **Refresh displays** sends the number of displays added and removed since your last refresh, plus the total currently connected. The first refresh compares against the helper's first successful scan. Manual HDR changes and switching automation on or off also send a confirmation to Notification Center.

**Right-click** the icon to show or hide the settings menu. Clicking the other mouse button switches menus. The settings menu contains:

- **Settings...** opens one window with **SDR brightness**, **Game lists**, and **Profiles and shortcuts** tabs. You can switch tabs while editing.
- In **Settings... → SDR brightness**, **Windows HDR settings** opens the Windows HDR page. The button is directly below **Windows HDR Calibration**.
- In **Settings...**, **Game lists** shows **Auto-detected**, **Installed**, and **Custom** sections, including exclusions and whether each entry is being watched. Select a game for **Game settings...**, **Launch with HDR**, or **Create launch shortcut...**. **Add running game...** and **Add game...** create personal rules. **Add running game...** uses Windows PowerShell's standard selection grid, styled to match the app's dark windows, with built-in filtering and sorting. Double-click an executable, or select it and click **OK**, to configure HDR. The process snapshot stays unchanged while you browse; close and reopen the grid to refresh it. The grid runs separately from the tray helper.
- Each **Game lists** tab remembers its sort column and direction when you reopen Settings. New tabs default to **Executable**, A–Z. Only the active sort column shows an arrow. Click just to the right of the header checkbox to show checked games first. Click there again to show unchecked games first. The checkbox toggles every game in the current tab. A dash means some games are enabled. **Executable**, **Status**, and **First detected** also sort in either direction.
- In **Auto-detected**, **Installed**, and **Custom**, rows load as you scroll. Sorting, keyboard search, and the header checkbox apply to the whole tab.
- In **Settings → Game lists**, **Use community app list** is on by default. Turn it off to watch only games on your custom list. Changes save immediately.
- In **Game lists**, **Update community list** downloads the latest list from our repository without updating or restarting the app. Your custom additions and exclusions are preserved.
- Check or uncheck a game (or press **Space** on its row) to enable or disable automatic HDR for that game without losing its settings. Right-click a row for the same toggle, game settings, launch, shortcut, and removal actions. **Remove game** clears a selected game's local settings, custom list entries, and detection history after confirmation. Locally installed community games return to **Installed**; to stop watching one, uncheck it.
- In **Game lists**, **Edit custom list...** opens your additions and exclusions in Notepad. Save the file to apply changes automatically.
- In **Settings...**, **Profiles and shortcuts** edits the default exit behavior, monitor aliases, display presets, and global keyboard shortcuts.
- **Start with Windows** registers HDR Control in your Windows Startup folder. Windows decides when to show its built-in startup notification. When you turn startup off in the tray, HDR Control confirms that it will no longer start at sign-in. Your preference survives updates.
- **About** shows the installed version and mouse controls. Select **Check for updates** to check for a stable release. If a newer version is available, click its Windows notification or select **Install update** in About to download and validate that version, run the installer, and restart the tray. Windows may request administrator approval. After a successful upgrade, HDR Control sends an **Update complete** notification with the installed version. An up-to-date notification opens About. Failed installations attempt to restore the previous version and retain startup preferences.
- Select **Check daily for updates** in About to let the tray check automatically every 24 hours. It is off by default. The tray checks when first enabled and remembers the next check across restarts. If the tray was closed when a check was due, it checks when it next runs. Background checks notify you only when a newer release is available.
- An available update adds a red dot to the tray icon, its version to the tooltip, and an **Update available** entry in the right-click menu that opens About. The badge survives restarts and temporary connection failures, and clears once that version is installed or a successful check confirms there is no newer release.
- About shows **Last checked** near the update button, using your local date and time. It remembers the last successful manual or automatic check across restarts; failed checks leave that timestamp unchanged.
- **Copy diagnostics**, at the bottom-left of **Profiles and shortcuts** on every tab, copies Windows/app versions, current display capabilities, and the last 80 local diagnostic events. A brief **Copied to clipboard** message confirms success.
- **Exit**, which closes the helper. Automatic desktop label refresh also stops until the helper is restarted (at the next sign-in if startup is enabled).

**Middle-click** (press the mouse wheel) to toggle HDR directly, using the current Windows display state. Further clicks are ignored while a change is in progress. As with the menu command, this affects all active HDR-capable displays.

Open **HDR Control** from the Start menu (or run **Start-Tray.vbs**) to restart it without signing out. Only one helper runs per session. Transient display disconnects show an unavailable status and recover automatically. Status updates every two seconds and whenever the left-click menu opens. The HDR shortcut uses `ms-settings:display-hdr`.

## SDR content brightness

Open **Settings...** and choose a display on the **SDR brightness** tab. The left-click tray menu also has an **SDR brightness...** shortcut that selects the monitor in the same window. With multiple monitors, each HDR-capable monitor has its own entry under **Displays**. The panel shows the current Windows level and a 0-100% slider. Release the slider to change brightness on the selected monitor. Keyboard adjustments save after a brief pause. This adjusts SDR desktop content while HDR is active, not hardware backlight brightness or HDR peak luminance. With HDR off, the slider stays visible and disabled at the last known brightness for that monitor. The percentage shows a dash if no level is known. Turn HDR on to adjust the level.

The brightness tab shows a single slider in **Manual** mode. Automatic modes show the current brightness above separate **Day** and **Night** cards, each with its own percentage and slider. Each monitor retains its own settings. **Custom schedule** switches between separate Day and Night levels at the chosen local Windows times (initially 08:00 and 18:00). **Follow Windows Night Light** uses the current Night Light state when its known Windows data format can be read, with your schedule as the fallback. The brightness readout names the active source, including fallback. Night Light is checked at most every ten seconds; schedules use the existing tray refresh cycle and handle midnight and resume by evaluating the current local time.

Day and Night start times use rounded 24-hour fields. Select the hours or minutes, then type a value or adjust it with the **+ / −** buttons or Up/Down keys; adjustments wrap through midnight. **Sunrise & sunset (location)** selects Day brightness at sunrise and Night brightness at sunset. It uses Windows location services and calculates approximate solar times locally using the [NOAA solar equations](https://gml.noaa.gov/grad/solcalc/solareqns.PDF), with local time-zone and daylight-saving conversion for the preview. Polar day and night keep the appropriate brightness even when there is no sunrise or sunset that day.

Location mode shows today's estimated sunrise/sunset, a **Refresh location** button, and a shortcut to **Windows location settings**. After the app accesses location, Windows lists **HDR Control** under **Let desktop apps access your location**. Location requests run in the background, respect Windows permissions, and time out after 12 seconds. Successful readings are refreshed after 30 minutes; failures retry after five minutes, and readings older than one hour are not used. Coordinates are kept only in memory; the app makes no IP-location or external solar-service request. If Windows location is disabled, denied, stale, or unavailable, the saved Day/Night start times remain the fallback and the brightness readout says so.

Day and Night both start from the current Windows value, or your existing saved level. Existing preferences migrate to Manual mode without enabling new automation. Changes to brightness, switching mode, schedule times, and restoration options save automatically. When HDR is active, the monitor uses the current level for the selected mode. If a requested brightness write fails, previous preferences are preserved. With HDR disabled, already-initialized schedule preferences can be saved for later. No arbitrary brightness is applied when the current level cannot be read.

Under **Restore brightness**, **When HDR turns on** is optional and off by default. It applies the Manual, Day, or Night level once after HDR becomes active, including startup/reconnect when HDR is already active. **After brightness is changed elsewhere** checks at most every 15 seconds and restores the active mode's level after an external adjustment. With that option off, manual Windows adjustments remain until the next scheduled Day/Night transition or opted-in HDR restoration. Opening brightness settings pauses automatic writes to that monitor while the window is open. Explicit monitor presets take priority until the next Day/Night transition, settings change, or HDR activation. Turning restoration off leaves current brightness unchanged unless you also apply a different level.

**Start with Windows** is available in the tray menu. **Windows HDR Calibration** launches the installed calibration app, or opens its Microsoft Store listing if it is not installed. If Microsoft Store is unavailable, it opens the listing in your browser. **Night Light settings** opens the Windows settings page. Time fields use 24-hour HH:mm format. Equal start times are rejected. Drag any edge or corner of Settings to change its size. All tabs share a minimum size, so switching tabs keeps the window at the size you chose. If the screen itself is smaller, the page scrolls. Settings remembers its width, height, and position when closed.

Brightness operations share the HDR command queue and wait for HDR changes and app updates. A failed automatic restoration retries at most three times, at least 30 seconds apart. Preferences are stored per user under `HKCU\Software\HdrContextMenu\SdrBrightness`, keyed by a hash of the monitor device path, and survive app updates and session target-ID changes. Windows can assign a different device path after changing ports or drivers; in that case, opt in again. Displays with missing or ambiguous device paths do not automatically restore. Uninstall removes these preferences.

Reading brightness uses Windows' documented SDR white-level query. Writing uses a private Windows operation whose availability can vary by Windows build or driver; errors do not disable HDR controls. There is no fallback that changes other monitors. The slider uses the conventional 1000-6000 white-level range; unsupported or out-of-range readings disable adjustment. The displayed percentage is rounded, but an untouched current value is preserved exactly.

Run `powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File tests\Brightness.Tests.ps1` for simulated display and persistence tests without changing real brightness. `tests\BrightnessSchedule.Tests.ps1` covers schedule boundaries, Night Light fallback, opt-in enforcement, and preset priority. `tests\BrightnessUi.Tests.ps1` checks panel layout and the native structure sizes without writing to a display. The day/night feature and best-effort Night Light integration were inspired by [HDR SDR Brightness](https://github.com/yinjunonly/hdr-sdr-brightness).

## Automatic HDR switching

When HDR Control turns HDR on after detecting a running game, the Windows notification says “HDR turned on automatically.” If HDR Control turns HDR off after the game exits and its exit delay expires, the notification says “HDR turned off automatically.” Each change is announced once, even if multiple monitors switch. A monitor that stays in its current HDR state does not trigger a notification.

Choose **Enable auto-switching** in the left-click controls menu to turn HDR on for listed apps and restore the previous HDR state after the last one exits. Your explicit choice is saved across restarts and updates. This controls Windows HDR for listed apps; it does not enable Windows Auto HDR or convert SDR games to HDR.

When enabled, the helper checks running apps in your Windows session every two seconds. For matched games, a process-exit notification triggers an immediate recheck. The regular scan also catches exits when Windows denies access to a game process. By default a match enables all active HDR-capable displays and returns them to SDR after the last matching app exits. **Profiles and shortcuts** lets you choose **Restore previous state** instead. Restoration remembers each monitor separately and only restores monitors the helper changed. Game rules can select monitors, set a startup delay (0-300 seconds), an exit delay (0-300 seconds, default 0), and override the default exit behavior. With the default delay, the helper requests restoration as soon as it detects the last matching process has exited. Set **After exit (s)** to a positive value if a launcher needs time to hand off to another process. No monitor selection means all active HDR-capable displays. Overlapping games keep a monitor enabled until their delays end; if their exit policies disagree, Return to SDR wins for that shared session. With no matching app session, automatic switching leaves HDR alone.

Recognition uses executable names, not inspection of a game's graphics or HDR setting. We maintain [HdrApps.community.txt](HdrApps.community.txt) in this repository, initially based on [noahz123/HDR-Auto](https://github.com/noahz123/HDR-Auto/blob/main/games_default.txt), retrieved November 1, 2026, with duplicates and the generic `Launcher.exe` entry removed. The source's MIT notice is retained in the file. **Update community list** fetches that file from this repository's `main` branch on GitHub and validates it before replacing the local cache. Downloads run in the background; failed or invalid downloads leave the previous list intact. The bundled list works offline from first installation, and successful downloads are cached as `HdrApps.community.cache.txt` beside the helper for future offline use. The cache survives app updates; a missing or damaged cache falls back to the bundle. Changes apply on the next monitoring cycle, normally within two seconds. There are no automatic network checks for the list. The shared list is restricted to games with evidence of native PC HDR. Auto HDR, RTX HDR, and mod-only support are not inclusion criteria. Each active entry links to HDR evidence; inherited entries that could not be confirmed are preserved as inactive review comments, not treated as proof that those games lack HDR. Executable matching still cannot identify the installed edition or verify in-game settings; add missing games or exclude false matches. Some games still require HDR enabled in their own settings, or before they start; use **Launch with HDR** for the latter.

**Launcher and store independent:** detection watches the running game's executable in your Windows session. It works when a game is opened directly from its `.exe`, a desktop shortcut, a GOG offline installation, or through Steam, Epic, GOG Galaxy, or another launcher. The helper does not require a store client, account, store manifest, particular install folder, or internet connection for detection. Store links in the community list are research references, not runtime dependencies. This does not change any launcher or DRM requirements imposed by the game itself.

Different editions or storefronts can use different executable names. Each verified name can have its own community entry; a name containing `Steam` is just that version's filename, not a requirement to run Steam. If your edition uses a different name, add the actual running game process through **Edit custom list...**. Renaming an executable is not necessary. We do not guess aliases by stripping store suffixes, since that can match unrelated programs.

Use **Edit custom list...** to add one executable name per line, with or without `.exe`. Names are case insensitive. Prefix an entry with `!` to exclude it from the community list. Blank lines and lines beginning with `#` are ignored. Use the actual game process name, which may differ from its launcher. For example:

```text
MyHdrGame.exe
MyHdrVideoPlayer
!UnwantedGame.exe
```

While automatic HDR and the community list are enabled, known HDR games seen running are saved under **Auto-detected** in **Game lists**, with their executable name and first detection time. **Installed** shows other community games whose executables were found in registered Windows install folders, App Paths, Epic install folders, or running processes. Open Settings or click **Refresh** to scan again. Portable games outside these locations can be added with **Add game...**. **Custom** shows personal entries for games outside the community list. Editing or disabling a community game keeps it in **Installed** or **Auto-detected** when it qualifies for that tab. A game appears only once; an excluded, previously detected game stays in Auto-detected with an excluded status. Custom-only matches are not recorded as verified HDR games. Detection history is local (`HdrApps.detected.json`), works offline, survives app updates, and is never uploaded. It records matches to the list, not inspection of HDR output. History does not keep a removed community entry active or bypass exclusions or a disabled community list.

To maintain the community list, edit `HdrApps.community.txt` and publish it to `main`; no app release is required. Preserve the format header and license notice, and use one executable filename ending in `.exe` per line. Blank lines and `#` comments are allowed. Paths, wildcards, exclusions, empty lists, and the generic `Launcher.exe` are rejected. Custom exclusions belong in the personal list.

Your list is saved as `HdrApps.custom.txt` beside the installed helper and survives updates. The two automatic-switching preferences are stored per user. A manual tray change or an observed external HDR change releases automatic control of the affected monitor for the rest of its current app session, including exit restoration. A later session takes a fresh baseline. Choosing **Disable auto-switching** or exiting the helper stops monitoring and leaves the current HDR setting unchanged. A command already in progress is allowed to finish. Display reconnects and temporary failures are retried; failed HDR commands retry at most once every 30 seconds.

Run `powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File tests\Automation.Tests.ps1` for simulated app lifecycle tests without changing real HDR settings.

## Profiles and launch shortcuts

Upgrading preserves your startup and automatic HDR preferences. Existing app-list entries continue to work without profiles.

**Game settings:** select a game in **Game lists**, then choose **Game settings...**. Unchecking **Enable this game** excludes it. The optional exact executable path narrows matching when unrelated programs share a filename; leave it blank for name-based, store-independent matching. Saved editor rules take precedence over the community and text lists. A process whose exact path cannot be read suspends automatic decisions until the scan succeeds.

**Launch with HDR:** save the program path, arguments, and optional working directory in Game settings. Use the launch button or create a `.lnk` shortcut in a location you choose. The helper resolves the selected monitors, enables HDR through its normal queue, verifies the result, and only then starts the program. Failure to prepare HDR within 45 seconds cancels the launch. For a launcher, set the watched executable to the actual game; the helper waits up to 45 seconds for that executable to appear. It never kills or restarts games. Explicit launches also work while automatic detection is off. If a game exits before its configured startup delay, ordinary detection does not turn HDR on afterward.

**Presets:** under **Profiles and shortcuts > Presets**, create named combinations such as Gaming or Evening. Each included monitor has an explicit HDR state and optional SDR brightness percentage. Leave brightness blank to keep its current level. Setting brightness requires HDR to be enabled. To apply a preset, double-click its name, press Enter with it selected, or use an assigned hotkey. All selected monitors must be available before any change starts. Failures attempt to restore the previous HDR/brightness settings and report incomplete recovery. Presets share the display queue with manual commands and automation.

**Keyboard shortcuts:** create Enable, Disable, Toggle, or Apply preset bindings with Ctrl/Alt/Shift/Win modifiers. Action bindings can target selected monitors; no selection means all active HDR-capable displays. Duplicate bindings are rejected. Keys reserved by Windows or another program are reported and remain inactive. Removing a preset also removes its shortcut bindings. No hotkeys are registered by default.

**Monitor aliases and persistence:** aliases and profile targets use a hash of the monitor device path, so session target-ID changes do not redirect a profile. Disconnected monitors remain editable. Missing or ambiguous monitor identities never redirect a selected action to another display. A port/driver change may require selecting the monitor again. Profiles are stored in `HdrProfiles.json` beside the helper and retained during updates and uninstall, like the custom app list. Profile/launch files are local and never uploaded.

**Diagnostics and refresh:** `HdrDiagnostics.log` rotates after approximately 256 KB, keeping one previous file. It records decisions, executable names, command outcomes, and errors; inspect copied diagnostics before sharing. Device paths and launch arguments are omitted from the normal report. A failed display query shows **HDR: Temporarily unreadable**. Display-change and resume notifications trigger three quick rereads, while the existing two-second poll remains the recovery path. No idle polling interval has been increased.

For local verification, run the scripts in `tests` with Windows PowerShell 5.1 and `-STA`. `Profiles.Tests.ps1`, `LaunchPreset.Tests.ps1`, and `ProfilesUi.Tests.ps1` cover the new policy, queue, launch, persistence, and editor behavior with simulated display writes. Real monitor switching still needs local hardware testing.

## Acknowledgments

Ideas for this project were inspired by:

- [HDR-Auto](https://github.com/noahz123/HDR-Auto) by noahz123: automatically enabling HDR when listed games/apps start and disabling it when they exit, with community and custom app lists. Its community game list is also bundled with this project, as described above.
- [HDRTray](https://github.com/res2k/HDRTray) by res2k: showing HDR status in a system tray icon and providing quick access to HDR toggling.

## Install

Download **HDR-Control-VERSION-Setup.exe** from the [latest release](https://github.com/notuxius/hdr-control/releases/latest) and run it. Alternatively, download the source ZIP, extract it, and run **Install.cmd**. Accept the Windows administrator prompt using your current account. Installation refreshes Explorer; open folder windows may close. Run the installer again to update.

- Windows 10/11, Windows PowerShell 5.1, Windows Script Host, and an active HDR-capable display are required.
- Tested on Windows 11 with Nilesoft Shell 1.9.17. No monitor model restriction.
- Nilesoft is optional and is not downloaded or installed by this package. It is detected at `%SystemRoot%\nilesoft`; for another location, run `Setup.ps1 -NilesoftPath "D:\Tools\Shell"`.
- Without Nilesoft, the native entry appears in the classic desktop menu (Windows 11: **Show more options**). Exact placement above Display settings requires Nilesoft and an English Display settings caption.
- The action affects all active HDR-capable displays. If any are off, the next action is Enable HDR. If all are on, it is Disable HDR. With no capable display, the Nilesoft action is disabled and the native entry is hidden.
- Setup itself does not change HDR. After installation, the restarted helper applies automatic HDR if a listed game/app is already running and automatic switching is enabled.

This package is intended for a single interactive user per PC. Install with that user's account. Files live in `%ProgramData%\HdrSdrMenu`, the native menu is registered for that user, and the `HdrSdrMenu-Label-<username>` scheduled task runs with limited privileges. Shared storage avoids packaged-app redirection of AppData.

## Ketarin

Import **[ketarin/HDR Context Menu.xml](ketarin/HDR%20Context%20Menu.xml)** into Ketarin.

1. **Update** checks the latest `main` commit and downloads its exact archive into `..\_Tweaks\HDR Context Menu\_.zip`, relative to Ketarin.
2. The post-download command validates and extracts it into `Package`, keeping only the last package in `Package.previous`. After a successful update, it removes old `before-sync-*.zip` HDR archives and empty numbered `Package (n)` folders. The current `_.zip` is retained; other files and nonempty numbered folders are left alone. Extraction uses the local temporary folder, and updates copy contents into stable `Package` and `Package.previous` folders to avoid cloud-sync rename conflicts.
3. **Install** applies the prepared package. Updating alone does not install it or change HDR.

The entry uses the full commit SHA as its version indicator. Repeated checks do not download an unchanged commit. The XML contains the same extraction code as `ketarin/Extract-Package.ps1`.

## Uninstall

Run **Uninstall.cmd**, or run the installed `Setup.ps1 -Action Uninstall`. This removes the desktop menu, Start menu shortcut, logon helper, installed program files, and saved startup/automatic-switching preferences. Your custom app list is retained. Nilesoft configuration backups remain under `%ProgramData%\HdrSdrMenu\backups`. Other Nilesoft customizations are preserved.

## How it works

`HdrSdrMenu.ps1` calls the Windows DisplayConfig APIs directly. Newer Windows versions use the HDR-specific API; older versions fall back to advanced-color support. `Toggle-HdrSdr.vbs` launches the helper without a console window. No third-party executable or network connection is needed to operate HDR.

`HdrTray.ps1` provides the Windows Forms tray menu inside the existing helper. The HDR command runs in a hidden child process so the menu remains responsive while Windows changes display mode. Run `powershell.exe -NoProfile -STA -File tests\Tray.Tests.ps1` for tray behavior tests using simulated displays; these tests do not change HDR.

Per-monitor commands use the selected display's identity, including its device path, rather than its name or position in the list. If that monitor disconnects, the command fails instead of falling back to all displays. All HDR buttons are disabled while a change or app update is running. Run `powershell.exe -NoProfile -File tests\Display.Tests.ps1` to test targeting, verification, and failure recovery using simulated displays.

To inspect state without changing it:

```powershell
powershell.exe -NoProfile -File "C:\ProgramData\HdrSdrMenu\HdrSdrMenu.ps1" -Action Status
```

`Status` includes a `DisplayId` for each active monitor. Pass that value to `-DisplayId` with `-Action On`, `Off`, or `Toggle` to change just that monitor. Omitting `-DisplayId` retains the all-monitor behavior. Read a fresh ID after reconnecting a display or restarting Windows.

The public source contains no machine-specific user paths, credentials, or display IDs.

## Versioned releases

`VERSION` is the installed and displayed MAJOR.MINOR.PATCH version. Increment the patch for fixes, the minor for backward-compatible features, and the major for incompatible changes. Update checks compare version numbers numerically, never commit IDs, and never offer equal or older versions. Preview releases are excluded.

To publish an update, commit the new `VERSION` and changes, push an annotated `vMAJOR.MINOR.PATCH` tag, and publish a non-draft, non-prerelease GitHub release for that tag. The tag must match `VERSION`; do not move published tags. The updater downloads the repository archive for that exact tag and checks its version and required files before installation. Repository commits without a published release are not offered as app updates.

Publishing a release runs the Windows installer workflow, which attaches a versioned EXE and SHA-256 checksum to that release. The EXE bundles the runtime files and runs the same `Setup.ps1` used by ZIP installations; it preserves the startup preference and adds the Start menu shortcut. The existing uninstall command remains available in the source ZIP. In-app updates continue to use the validated source archive.

To build an installer locally, install Inno Setup 6 and run `powershell.exe -NoProfile -File installer\Build-Installer.ps1 -SourceCommit (git rev-parse HEAD)`. Outputs are written to `dist`. Use `-SourceRoot` to build an installer for an older extracted release without changing its source. Silent installation supports `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART`; add `/NoRestartShell=1` when Explorer must remain running.

Run `powershell.exe -NoProfile -STA -File tests\Update.Tests.ps1` to verify version ordering, archive validation, installation, cancellation, and recovery using isolated files and mocked installers.
