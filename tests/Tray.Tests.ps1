# Run in a fresh Windows PowerShell process. No real display settings change.
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot
$installedIcon = Join-Path $repo 'HdrSdrMenu.ico'
$installedScript = Join-Path $repo 'HdrSdrMenu.ps1'
. (Join-Path $repo 'HdrTray.ps1')
$script:realStartHdrChange = ${function:Start-HdrChange}
$script:realShowHdrControls = ${function:Show-HdrControls}
$script:realShowHdrSettings = ${function:Show-HdrSettingsMenu}
Add-Type @'
namespace LocalHdrMenu {
    public static class DisplayApi {
        public static object[] Displays;
        public static bool Fail;
        public static object[] Read() {
            if (Fail) throw new System.Exception("Display temporarily disconnected");
            return Displays;
        }
    }
}
'@
function Sync-HdrMenu($Displays) { $script:syncCount++ }
function Start-HdrChange([string]$NextAction) { $script:requestedAction = $NextAction }
function Open-HdrSettings([string]$Uri) { $script:requestedUri = $Uri }
function Show-HdrControls { $script:controlsOpened++ }
function Show-HdrSettingsMenu { $script:settingsOpened++ }
function Get-HdrStartupEnabled { return $script:testStartup }
function Set-HdrStartupEnabled([bool]$Enabled) { $script:testStartup = $Enabled }
function Get-HdrInstalledVersion { return ('a' * 40) }
function Show-HdrMessage([string]$Text, $Buttons = 'OK') { $script:lastMessage = $Text; return [Windows.Forms.DialogResult]::OK }
$script:testStartup = $true
function Assert($Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Display([string]$Name, [bool]$Supported, [bool]$Enabled) {
    [pscustomobject]@{Name=$Name;HdrSupported=$Supported;HdrEnabled=$Enabled}
}
$script:syncCount=0
Initialize-HdrTray
try {
    Assert ($null -ne $script:hdrTray.ShowMenuMethod) 'Native tray popup method unavailable'
    Assert ($null -eq $script:hdrTray.Icon.ContextMenuStrip) 'Automatic right-click opening must stay disabled'
    Assert (($script:hdrTray.Menu.Items | Where-Object {$_ -is [Windows.Forms.ToolStripMenuItem] -and $_ -isnot [LocalHdrMenu.TrayStatusItem]} | ForEach-Object Text) -join '|' -eq 'HDR settings|Start with Windows|Check for updates|About|Exit') 'Right-click menu contains wrong items'
    Assert ($script:hdrTray.Menu.Items.Count -eq 7 -and $script:hdrTray.Menu.Items[1] -is [Windows.Forms.ToolStripSeparator] -and $script:hdrTray.Menu.Items[5] -is [Windows.Forms.ToolStripSeparator]) 'Right-click menu groups are incorrect'
    Assert ($script:hdrTray.Startup.Checked) 'Startup should reflect the stored preference'
    $script:hdrTray.Startup.PerformClick()
    Assert (-not $script:testStartup -and -not $script:hdrTray.Startup.Checked) 'Startup toggle should save disabled without exiting the tray'
    $script:hdrTray.Startup.PerformClick()
    Assert ($script:testStartup -and $script:hdrTray.Startup.Checked) 'Startup toggle should save enabled'
    $script:hdrTray.About.PerformClick()
    Assert ($script:lastMessage -match 'aaaaaaa' -and $script:lastMessage -match 'Middle click') 'About should show version and controls'
    foreach ($case in @('current','different','offline','invalid')) {
        $result = switch ($case) { 'current' { '{"sha":"' + ('a' * 40) + '"}' } 'different' { '{"sha":"' + ('b' * 40) + '"}' } default { '{}' } }
        $script:hdrTray.UpdateCheck = [pscustomobject]@{Finished=$true;Result=$result;Error=$(if ($case -eq 'offline') {'offline'} else {$null})}
        $script:hdrTray.CheckUpdates.Enabled = $false
        Complete-HdrUpdateCheck
        Assert ($null -eq $script:hdrTray.UpdateCheck -and $script:hdrTray.CheckUpdates.Enabled) 'Update check must restore the menu item'
        $expected = switch ($case) { 'current' {'latest version'} 'different' {'different version'} default {'Could not check'} }
        Assert ($script:lastMessage -match $expected) ('Wrong update result: ' + $case)
    }
    Assert ($script:hdrTray.Menu.ShowActionIcons) 'Right-click menu icons are missing'
    foreach ($popup in @($script:hdrTray.ControlsMenu,$script:hdrTray.Menu,$script:hdrTray.Displays.DropDown)) {
        Assert ($popup.TransitionsDisabled) 'Windows should accept disabling popup transitions to avoid squeezed frames'
    }
    Assert ($script:hdrTray.PressTracker.IsListening) 'Early tray press tracking did not start'
    Assert ($script:hdrTray.ControlsMenu.Items.Contains($script:hdrTray.Displays)) 'Displays missing from left-click menu'
    Assert ($script:hdrTray.ControlsMenu.Items.Contains($script:hdrTray.Command)) 'HDR action missing from left-click menu'
    Assert ($script:hdrTray.ControlsMenu.Items.Contains($script:hdrTray.Refresh)) 'Refresh displays missing from left-click menu'
    $mouseClick = [Windows.Forms.NotifyIcon].GetMethod('OnMouseClick',[Reflection.BindingFlags]'Instance,NonPublic')
    $mouseUp = [Windows.Forms.NotifyIcon].GetMethod('OnMouseUp',[Reflection.BindingFlags]'Instance,NonPublic')
    $script:controlsOpened=0
    $script:settingsOpened=0
    foreach ($button in @([Windows.Forms.MouseButtons]::Left,[Windows.Forms.MouseButtons]::Right,[Windows.Forms.MouseButtons]::Middle)) {
        $eventArgs = New-Object Windows.Forms.MouseEventArgs($button,1,0,0,0)
        [void]$mouseClick.Invoke($script:hdrTray.Icon,@($eventArgs.PSObject.BaseObject))
        [void]$mouseUp.Invoke($script:hdrTray.Icon,@($eventArgs.PSObject.BaseObject))
    }
    Assert ($script:controlsOpened -eq 1) 'Controls should open only on left click'
    Assert ($script:settingsOpened -eq 1) 'Settings should open only on right click'
    $eventArgs = New-Object Windows.Forms.MouseEventArgs([Windows.Forms.MouseButtons]::Left,2,0,0,0)
    [void]$mouseUp.Invoke($script:hdrTray.Icon,@($eventArgs.PSObject.BaseObject))
    Assert ($script:controlsOpened -eq 2) 'Fast second left click should not be swallowed as a double-click'
    $eventArgs = New-Object Windows.Forms.MouseEventArgs([Windows.Forms.MouseButtons]::Right,2,0,0,0)
    [void]$mouseUp.Invoke($script:hdrTray.Icon,@($eventArgs.PSObject.BaseObject))
    Assert ($script:settingsOpened -eq 2) 'Fast second right click should not be swallowed as a double-click'
    Assert ($script:requestedAction -eq 'Toggle') 'Middle click must request a live HDR toggle'
    $script:requestedUri=$null
    $doubleClick = [Windows.Forms.NotifyIcon].GetMethod('OnDoubleClick',[Reflection.BindingFlags]'Instance,NonPublic')
    [void]$doubleClick.Invoke($script:hdrTray.Icon,@([EventArgs]::Empty))
    Assert ($null -eq $script:requestedUri) 'Double click must not unexpectedly open settings'
    [LocalHdrMenu.DisplayApi]::Displays = @((Display 'Primary' $true $false))
    Update-HdrTray
    Assert ($script:hdrTray.Status.Text -eq 'HDR: Disabled') 'SDR status incorrect'
    Assert ($script:hdrTray.Status.Available -and -not $script:hdrTray.Displays.Available) 'One display should show only the top status'
    Assert ($script:hdrTray.Displays.DropDownItems[0].Text -eq 'Primary - HDR: Disabled') 'Off labels should be consistent across menus'
    Assert ($script:hdrTray.Icon.Icon.Handle -eq $script:hdrTray.DisabledIcon.Handle) 'SDR should use the yellow monitor icon'
    Assert ($script:hdrTray.Command.Text -eq 'Enable HDR') 'SDR command incorrect'
    $script:hdrTray.Command.PerformClick()
    Assert ($script:requestedAction -eq 'On') 'Enable did not request On'
    [LocalHdrMenu.DisplayApi]::Displays = @((Display 'Primary' $true $true))
    Update-HdrTray
    Assert ($script:hdrTray.Status.Text -eq 'HDR: Enabled') 'HDR status incorrect'
    Assert ($script:hdrTray.Displays.DropDownItems[0].Text -eq 'Primary - HDR: Enabled') 'On labels should be consistent across menus'
    Assert ($script:hdrTray.Icon.Icon.Handle -eq $script:hdrTray.EnabledIcon.Handle) 'HDR should use the green monitor icon'
    Assert ($script:hdrTray.Icon.Text.EndsWith('HDR: Enabled')) 'Tooltip did not update'
    $script:hdrTray.Command.PerformClick()
    Assert ($script:requestedAction -eq 'Off') 'Disable did not request Off'
    [LocalHdrMenu.DisplayApi]::Displays = @((Display 'Primary' $true $true),(Display 'Secondary' $true $false))
    Update-HdrTray
    Assert ($script:hdrTray.Status.Text -eq 'HDR: Mixed') 'Mixed status incorrect'
    Assert (-not $script:hdrTray.Status.Available -and $script:hdrTray.Displays.Available) 'Multiple displays should show the submenu instead of the top status'
    Assert ($script:hdrTray.Icon.Icon.Handle -eq $script:hdrTray.EnabledIcon.Handle) 'Mixed state should show HDR is enabled on a display'
    Assert ($script:hdrTray.Command.Tag -eq 'On') 'Mixed state should enable all'
    Assert ($script:hdrTray.Displays.DropDownItems.Count -eq 2) 'Per-display status missing'
    [LocalHdrMenu.DisplayApi]::Displays = @((Display 'SDR only' $false $false))
    Update-HdrTray
    Assert (-not $script:hdrTray.Command.Enabled) 'Unsupported display has an enabled command'
    Assert ($script:hdrTray.Status.Text -eq 'HDR: Unavailable') 'Unavailable caption is incorrect'
    Assert ($script:hdrTray.Status.Available -and -not $script:hdrTray.Displays.Available) 'Returning to one display should restore the top status'
    Assert ($script:hdrTray.Displays.DropDownItems[0].Text -eq 'SDR only - HDR: Unavailable') 'Unavailable labels should be consistent across menus'
    Assert (-not $script:hdrTray.Command.Available) 'Unsupported display should hide the HDR action'
    Assert (-not $script:hdrTray.CommandSeparator.Available) 'Hidden action should not leave a separator'
    Assert ($script:hdrTray.Icon.Icon.Handle -eq $script:hdrTray.UnavailableIcon.Handle) 'Unsupported display should use the red X icon'
    Assert ($script:hdrTray.Displays.DropDownItems.Count -eq 1) 'Stale display entry remained'
    [LocalHdrMenu.DisplayApi]::Displays = @()
    Update-HdrTray
    Assert (-not $script:hdrTray.Displays.Enabled) 'Empty display list is enabled'
    Assert ($script:hdrTray.Status.Available -and -not $script:hdrTray.Displays.Available) 'No displays should retain the unavailable status without an empty submenu'
    Assert (-not $script:hdrTray.Command.Available) 'No displays should hide the HDR action'
    Assert ($script:hdrTray.Icon.Icon.Handle -eq $script:hdrTray.UnavailableIcon.Handle) 'No displays should use the red X icon'
    [LocalHdrMenu.DisplayApi]::Fail = $true
    Update-HdrTray
    Assert ($script:hdrTray.Status.Text -eq 'HDR: Unavailable') 'Transient failure left stale status'
    Assert (-not $script:hdrTray.Command.Available) 'Unreadable HDR state should hide the action'
    Assert (-not $script:hdrTray.Command.Enabled) 'Transient failure left action enabled'
    Assert ($script:hdrTray.Icon.Icon.Handle -eq $script:hdrTray.UnavailableIcon.Handle) 'Unreadable HDR state should use the red X icon'
    [LocalHdrMenu.DisplayApi]::Fail = $false
    [LocalHdrMenu.DisplayApi]::Displays = @((Display 'Primary' $true $false))
    Update-HdrTray
    Assert ($script:hdrTray.Command.Enabled) 'Tray failed to recover after display read failure'
    Assert ($script:hdrTray.Icon.Icon.Handle -eq $script:hdrTray.DisabledIcon.Handle) 'Recovery to HDR off should restore the yellow minus icon'
    Assert ($script:hdrTray.Command.Available -and $script:hdrTray.CommandSeparator.Available) 'HDR action did not reappear on recovery'
    $script:hdrTray.HdrSettings.PerformClick()
    Assert ($script:requestedUri -eq 'ms-settings:display-hdr') 'HDR settings link incorrect'
    Assert ($script:syncCount -eq 6) 'Desktop label synchronization stopped'
    [LocalHdrMenu.DisplayApi]::Displays = @((Display 'Reconnected' $false $false))
    $script:hdrTray.Refresh.PerformClick()
    Assert ($script:hdrTray.Status.Text -eq 'HDR: Unavailable' -and $script:hdrTray.Refresh.Available) 'Refresh must reread displays and remain available without HDR'
    Assert ($script:syncCount -eq 7) 'Manual refresh did not synchronize the desktop menu'
    # Reconnect sequence: capable/disabled -> two unavailable displays ->
    # capable again. Keep the submenu open while its rows are replaced.
    [LocalHdrMenu.DisplayApi]::Displays = @((Display 'Laptop' $false $false),(Display 'External' $true $false))
    Update-HdrTray
    $script:hdrTray.Displays.DropDown.Show([Drawing.Point]::new(50,50))
    try {
        [LocalHdrMenu.DisplayApi]::Displays = @((Display 'Laptop' $false $false),(Display 'External' $false $false))
        Update-HdrTray
        Assert ($script:hdrTray.Icon.Icon.Handle -eq $script:hdrTray.UnavailableIcon.Handle) 'Reconnect left a yellow tray icon when every display is unavailable'
        Assert ($script:hdrTray.Displays.DropDownItems.Count -eq 2) 'Reconnect lost display rows'
        Assert (@($script:hdrTray.Displays.DropDownItems | Where-Object {$_.Text -notlike '*HDR: Unavailable'}).Count -eq 0) 'Reconnect left stale display labels'
        Assert (-not $script:hdrTray.Command.Available) 'Reconnect left an HDR action for unavailable displays'
        # An unchanged status must still repair a stale icon, not trust a
        # remembered state string while the rendered image is different.
        $script:hdrTray.Icon.Icon = $script:hdrTray.DisabledIcon
        Update-HdrTray
        Assert ($script:hdrTray.Icon.Icon.Handle -eq $script:hdrTray.UnavailableIcon.Handle) 'Repeated unavailable status failed to repair a stale yellow icon'
        [LocalHdrMenu.DisplayApi]::Displays = @((Display 'Laptop' $false $false),(Display 'External' $true $true))
        Update-HdrTray
        Assert ($script:hdrTray.Icon.Icon.Handle -eq $script:hdrTray.EnabledIcon.Handle) 'Reconnected HDR display did not restore the green icon'
        Assert ($script:hdrTray.Displays.DropDownItems[1].Text -eq 'External - HDR: Enabled') 'Reconnected HDR display label did not recover'
        Assert ($script:hdrTray.Command.Available) 'Reconnected HDR display did not restore its action'
    } finally { $script:hdrTray.Displays.DropDown.Close() }
    # Placement covers both screen edges and monitors with negative coordinates.
    $size = [Drawing.Size]::new(240,126)
    $area = [Drawing.Rectangle]::new(0,0,1920,1040)
    foreach ($case in @(@(960,1080,840,914),@(5,1000,0,868),@(1915,1000,1680,868),@(960,5,840,0))) {
        $point = [LocalHdrMenu.TrayPopupMenu]::CenteredLocation([Drawing.Point]::new($case[0],$case[1]),$size,$area,6)
        Assert ($point.X -eq $case[2] -and $point.Y -eq $case[3]) 'Popup should be centered above the cursor and clamped to the work area'
    }
    $point = [LocalHdrMenu.TrayPopupMenu]::CenteredLocation([Drawing.Point]::new(-960,1000),$size,[Drawing.Rectangle]::new(-1920,0,1920,1040),6)
    Assert ($point.X -eq -1080 -and $point.Y -eq 868) 'Negative monitor coordinates should be preserved'
    Assert ($null -eq $script:hdrTray.Displays.DropDown.AnchorIcon) 'Display submenu must retain native side placement'
    $iconBounds=[Drawing.Rectangle]::Empty
    Assert (-not [LocalHdrMenu.TrayIconPosition]::TryGetBounds($script:hdrTray.Icon,[ref]$iconBounds)) 'Hidden icon should use fallback placement'
    $script:hdrTray.Icon.Visible=$true
    [Windows.Forms.Application]::DoEvents()
    # Refresh the visible native icon repeatedly without replacing its handle
    # or recreating the notification-area entry.
    $refreshMethod = [Windows.Forms.NotifyIcon].GetMethod('UpdateIcon',[Reflection.BindingFlags]'Instance,NonPublic')
    Assert ($null -ne $refreshMethod) 'Native icon refresh is unavailable on this runtime'
    $iconHandle = $script:hdrTray.Icon.Icon.Handle
    Update-HdrTray
    Update-HdrTray
    Assert ($script:hdrTray.Icon.Icon.Handle -eq $iconHandle) 'Refreshing the tray should reuse the icon handle'
    Assert ([LocalHdrMenu.TrayIconPosition]::TryGetBounds($script:hdrTray.Icon,[ref]$iconBounds)) 'Windows did not return the registered tray icon bounds'
    # Use the real NotifyIcon popup path, including its final native positioning.
    foreach ($supported in @($true,$false)) {
        [LocalHdrMenu.DisplayApi]::Displays = @((Display 'Primary' $supported $false))
        foreach ($leftClick in @($true,$false)) {
            Assert ([LocalHdrMenu.TrayIconPosition]::TryGetBounds($script:hdrTray.Icon,[ref]$iconBounds)) 'Tray icon bounds unavailable'
            $anchor = [Drawing.Point]::new($iconBounds.Left+[int]($iconBounds.Width/2),$iconBounds.Top)
            if ($leftClick) { $toggle=$script:realShowHdrControls; $menu=$script:hdrTray.ControlsMenu }
            else { $toggle=$script:realShowHdrSettings; $menu=$script:hdrTray.Menu }
            & $toggle
            try {
                [Windows.Forms.Application]::DoEvents()
                $graphics=$menu.CreateGraphics()
                try { $gap=[int][Math]::Round(6*$graphics.DpiY/96) } finally { $graphics.Dispose() }
                $expected=[LocalHdrMenu.TrayPopupMenu]::CenteredLocation($anchor,$menu.Size,[Windows.Forms.Screen]::FromPoint($anchor).WorkingArea,$gap)
                Assert ($menu.Visible -and $menu.Location -eq $expected) 'Native tray popup did not stay centered on the icon'
                    Assert ($null -eq $script:hdrTray.Icon.ContextMenuStrip) 'Showing a menu must not restore automatic right-click opening'
                    & $toggle
                    Assert (-not $menu.Visible) 'Second click should hide the menu'
                    & $toggle
                    Assert ($menu.Visible) 'Third click should reopen the menu immediately'
                    $menu.Close([Windows.Forms.ToolStripDropDownCloseReason]::Keyboard)
                    Assert (-not $menu.Visible) 'Escape-style dismissal should still close the menu'
                    & $toggle
                    Assert ($menu.Visible) 'Click after keyboard dismissal should open the menu'
            } finally { $menu.Close() }
        }
    }
    & $script:realShowHdrControls
    & $script:realShowHdrSettings
    Assert ($script:hdrTray.Menu.Visible -and -not $script:hdrTray.ControlsMenu.Visible) 'Right click should switch from controls to settings'
    & $script:realShowHdrControls
    Assert ($script:hdrTray.ControlsMenu.Visible -and -not $script:hdrTray.Menu.Visible) 'Left click should switch from settings to controls'
    $script:hdrTray.ControlsMenu.Close()
    # Replay actual ordering: press -> native dismissal -> tray button-up.
    # Old tests called the toggle while Visible was still true and missed this.
    foreach ($sequence in @(@('L','R','R'),@('R','L','L'),@('L','L','L','L'),@('R','R','R','R'))) {
        $script:hdrTray.ControlsMenu.Close()
        $script:hdrTray.Menu.Close()
        $expectedKind=''
        foreach ($kind in $sequence) {
            $script:hdrTray.PressTracker.RefreshAnchor()
            Assert ([LocalHdrMenu.TrayIconPosition]::TryGetBounds($script:hdrTray.Icon,[ref]$iconBounds)) 'Tray bounds unavailable for input ordering test'
            $press=[Drawing.Point]::new($iconBounds.Left+2,$iconBounds.Top+2)
            $script:hdrTray.PressTracker.CapturePress($press)
            foreach ($popup in @($script:hdrTray.ControlsMenu,$script:hdrTray.Menu)) {
                if ($popup.Visible) { $popup.Close([Windows.Forms.ToolStripDropDownCloseReason]::AppFocusChange) }
                Assert (-not $popup.Visible) 'Native dismissal must finish without being cancelled'
            }
            $expectedKind=if ($expectedKind -eq $kind) { '' } else { $kind }
            if ($kind -eq 'L') { & $script:realShowHdrControls } else { & $script:realShowHdrSettings }
            Assert ($script:hdrTray.ControlsMenu.Visible -eq ($expectedKind -eq 'L')) ('Wrong controls state after '+($sequence -join ' -> '))
            Assert ($script:hdrTray.Menu.Visible -eq ($expectedKind -eq 'R')) ('Wrong settings state after '+($sequence -join ' -> '))
        }
    }
    $script:hdrTray.ControlsMenu.Close()
    $script:hdrTray.Menu.Close()
    # A new outside press must invalidate an abandoned icon gesture.
    & $script:realShowHdrControls
    $script:hdrTray.PressTracker.CapturePress($press)
    $script:hdrTray.ControlsMenu.Close()
    $script:hdrTray.PressTracker.CapturePress([Drawing.Point]::new(-32000,-32000))
    & $script:realShowHdrControls
    Assert ($script:hdrTray.ControlsMenu.Visible) 'Abandoned gesture swallowed a later click'
    $script:hdrTray.ControlsMenu.Close()
    # Exercise the real launch validation without starting a process or changing HDR.
    function Start-Process {
        param($FilePath,$ArgumentList,$WindowStyle,[switch]$PassThru)
        $script:launches++
        $script:launchArguments=$ArgumentList
        [pscustomobject]@{HasExited=$false}
    }
    $script:launches=0
    try {
        & $script:realStartHdrChange 'Toggle'
        Assert ($script:launchArguments -match '-Action Toggle$') 'Toggle did not reach the display helper'
        Assert (-not $script:hdrTray.Command.Enabled) 'HDR action should be disabled during a change'
        & $script:realStartHdrChange 'Toggle'
        Assert ($script:launches -eq 1) 'Repeated middle clicks must not start overlapping changes'
    } finally { $script:hdrTray.Pending=$null }
    'PASS: click routing, native popup placement and screen edges, toggle concurrency, menu contents, state updates, recovery, and settings links.'
} finally { Close-HdrTray }
