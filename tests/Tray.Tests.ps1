# Run in a fresh Windows PowerShell process. No real display settings change.
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot
$installedIcon = Join-Path $repo 'HdrSdrMenu.ico'
$installedScript = Join-Path $repo 'HdrSdrMenu.ps1'
. (Join-Path $repo 'HdrTray.ps1')
$script:realStartHdrChange = ${function:Start-HdrChange}
$script:realShowHdrControls = ${function:Show-HdrControls}
$script:realShowHdrSettings = ${function:Show-HdrSettingsMenu}
$script:realStartAppUpdate = ${function:Start-HdrAppUpdate}
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
function Start-HdrChange([string]$NextAction, [string]$DisplayId) { $script:requestedAction = $NextAction; $script:requestedDisplayId = $DisplayId }
function Show-HdrControls { $script:controlsOpened++ }
function Show-HdrSettingsMenu { $script:settingsOpened++ }
function Show-HdrAppSettings { $script:appSettingsOpened++ }
function Get-HdrStartupEnabled { return $script:testStartup }
function Set-HdrStartupEnabled([bool]$Enabled) { $script:testStartup = $Enabled }
function Get-HdrAutomationPreference([string]$Name) { return $Name -eq 'AutomaticHdr' -and $script:testAutomatic }
function Set-HdrAutomationPreference([string]$Name,[bool]$Enabled) { if ($Name -eq 'AutomaticHdr') { $script:testAutomatic=$Enabled } }
function Get-HdrInstalledVersion { return '1.0.0' }
function Start-HdrAppUpdate([string]$Version) { $script:offeredVersion = $Version }
function Show-HdrMessage([string]$Text, $Buttons = 'OK') { $script:lastMessage = $Text; return $script:messageResponse }
$script:messageResponse = [Windows.Forms.DialogResult]::No
$script:testStartup = $true
function Assert($Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Display([string]$Name, [bool]$Supported, [bool]$Enabled) {
    [pscustomobject]@{Name=$Name;HdrSupported=$Supported;HdrEnabled=$Enabled;DisplayId=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Name))}
}
$script:syncCount=0
Initialize-HdrTray
try {
    Assert ($null -ne $script:hdrTray.ShowMenuMethod) 'Native tray popup method unavailable'
    Assert ($null -eq $script:hdrTray.Icon.ContextMenuStrip) 'Automatic right-click opening must stay disabled'
    Assert (-not $script:hdrTray.Automatic.Checked -and $script:hdrTray.Automatic.Text -eq 'Enable auto-switching') 'A disabled preference must offer to enable automatic HDR switching'
    Assert (($script:hdrTray.Menu.Items | Where-Object {$_ -is [Windows.Forms.ToolStripMenuItem] -and $_ -isnot [LocalHdrMenu.TrayStatusItem]} | ForEach-Object Text) -join '|' -eq 'Settings...|Start with Windows|Check for updates|About|Exit') 'Right-click menu contains wrong items'
    Assert ($script:hdrTray.Menu.Items.Count -eq 7 -and $script:hdrTray.Menu.Items[1] -is [Windows.Forms.ToolStripSeparator] -and $script:hdrTray.Menu.Items[5] -is [Windows.Forms.ToolStripSeparator]) 'Right-click menu groups are incorrect'
    Assert ($script:hdrTray.Menu.Items[0] -eq $script:hdrTray.AppSettings -and $script:hdrTray.AppSettings.Enabled) 'Settings command must be first in the right-click menu'
    Assert ($script:hdrTray.Status -is [LocalHdrMenu.TrayStatusItem] -and -not $script:hdrTray.Status.Enabled -and -not $script:hdrTray.Status.CanSelect) 'Combined status must be informational'
    $script:appSettingsOpened=0
    $script:hdrTray.AppSettings.PerformClick()
    Assert ($script:appSettingsOpened -eq 1) 'Settings command must open the shared settings window'
    Assert ($script:hdrTray.Startup.Checked) 'Startup should reflect the stored preference'
    $script:hdrTray.Startup.PerformClick()
    Assert (-not $script:testStartup -and -not $script:hdrTray.Startup.Checked) 'Startup toggle should save disabled without exiting the tray'
    $script:hdrTray.Startup.PerformClick()
    Assert ($script:testStartup -and $script:hdrTray.Startup.Checked) 'Startup toggle should save enabled'
    $script:hdrTray.About.PerformClick()
    Assert ($script:lastMessage -match '1.0.0' -and $script:lastMessage -match 'Middle click') 'About should show version and controls'
    foreach ($case in @('current','newer','older','none','preview','offline','invalid')) {
        $tag = switch ($case) { 'current' {'v1.0.0'} 'newer' {'v1.10.0'} 'older' {'v0.9.0'} 'preview' {'v1.1.0-beta'} default {'invalid'} }
        $result = @{tag_name=$tag;draft=$false;prerelease=($case -eq 'preview')} | ConvertTo-Json
        $script:hdrTray.UpdateCheck = [pscustomobject]@{Finished=$true;Result=$result;NoRelease=($case -eq 'none');Error=$(if ($case -eq 'offline') {'offline'} else {$null})}
        $script:hdrTray.CheckUpdates.Enabled = $false
        Complete-HdrUpdateCheck
        Assert ($null -eq $script:hdrTray.UpdateCheck -and $script:hdrTray.CheckUpdates.Enabled) 'Update check must restore the menu item'
        $expected = switch ($case) { 'current' {'latest version'} 'older' {'latest version'} 'newer' {'newer version is available: 1.10.0'} 'none' {'No newer version'} default {'Could not check'} }
        Assert ($script:lastMessage -match $expected) ('Wrong update result: ' + $case)
        Assert ($script:lastMessage -notmatch 'Ketarin|Open GitHub') 'Update messages must stay inside the app'
        Assert ($null -eq $script:offeredVersion) 'Declining an update must not start installation'
    }
    $script:messageResponse = [Windows.Forms.DialogResult]::Yes
    $script:hdrTray.UpdateCheck = [pscustomobject]@{Finished=$true;Result='{"tag_name":"v1.1.0","draft":false,"prerelease":false}';NoRelease=$false;Error=$null}
    Complete-HdrUpdateCheck
    Assert ($script:offeredVersion -eq '1.1.0') 'Accepting a newer release must launch the in-app installer'
    Assert ($null -eq $script:requestedUri) 'Updating must not open a browser'
    $script:messageResponse = [Windows.Forms.DialogResult]::No
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
    $separator = ' ' + [char]0xB7 + ' Auto: '
    Assert ($script:hdrTray.Status.Text -eq ('HDR: Disabled' + $separator + 'Paused')) 'SDR status incorrect'
    Assert ($script:hdrTray.Status.Available -and -not $script:hdrTray.Displays.Available) 'One display should show its status without a submenu'
    $visible = @($script:hdrTray.ControlsMenu.Items | Where-Object Available)
    Assert ($visible[0] -eq $script:hdrTray.DisplayName -and $visible[1] -eq $script:hdrTray.Status -and $visible[2] -eq $script:hdrTray.Refresh) 'One combined status must appear between the display name and Refresh'
    Assert ($visible[5] -eq $script:hdrTray.Automatic -and $visible[4] -eq $script:hdrTray.Command) 'Auto-enable HDR must appear directly below the HDR action'
    Assert ($script:hdrTray.DisplayName.Available -and $script:hdrTray.DisplayName.Text -eq 'Primary') 'Single display name is missing'
    Assert ($script:hdrTray.ControlsMenu.Items.IndexOf($script:hdrTray.DisplayName) -lt $script:hdrTray.ControlsMenu.Items.IndexOf($script:hdrTray.Status)) 'Display name must appear above HDR status'
    Assert (-not $script:hdrTray.DisplayName.Enabled -and -not $script:hdrTray.DisplayName.CanSelect) 'Display name must not highlight or act as a command'
    Assert ($script:hdrTray.Displays.DropDownItems[1].Text -eq 'HDR: Disabled') 'Off labels should be consistent across menus'
    Assert ($script:hdrTray.Icon.Icon.Handle -eq $script:hdrTray.DisabledIcon.Handle) 'SDR should use the yellow monitor icon'
    $script:hdrTray.Automatic.PerformClick()
    Assert ($script:hdrTray.Automatic.Checked -and $script:hdrTray.Icon.Icon.Handle -eq $script:hdrTray.AutoIdleIcon.Handle) 'Checking auto-enable with HDR off must immediately show yellow with play'
    Assert ($script:hdrTray.Automatic.Text -eq 'Disable auto-switching') 'Enabling automation must immediately offer the disable action'
    $script:hdrTray.Automatic.PerformClick()
    Assert ($script:hdrTray.Icon.Icon.Handle -eq $script:hdrTray.DisabledIcon.Handle) 'Unchecking auto-enable with HDR off must immediately show yellow with pause'
    Assert ($script:hdrTray.Automatic.Text -eq 'Enable auto-switching') 'Disabling automation must immediately offer the enable action'
    Assert ($script:hdrTray.Command.Text -eq 'Enable HDR') 'SDR command incorrect'
    $script:hdrTray.Command.PerformClick()
    Assert ($script:requestedAction -eq 'On') 'Enable did not request On'
    [LocalHdrMenu.DisplayApi]::Displays = @((Display 'Primary' $true $true))
    Update-HdrTray
    Assert ($script:hdrTray.Status.Text -eq ('HDR: Enabled' + $separator + 'Paused')) 'HDR status incorrect'
    foreach ($decision in @('Automatic HDR: idle','Enabled for game.exe','Manual override active')) {
        Set-HdrDecision $decision
        $expected = if ($decision -eq 'Automatic HDR: idle') { 'Idle' } else { $decision }
        Assert ($script:hdrTray.Status.Text -eq ('HDR: Enabled' + $separator + $expected)) 'Automation decision did not refresh the combined label'
        Assert ($script:hdrTray.Status.Tag -eq 'HDR: Enabled' -and $script:hdrTray.Status.AutomationDecision -eq $decision) 'Combined icon lost its HDR color or automation badge state'
    }
    Assert ($script:hdrTray.Displays.DropDownItems[1].Text -eq 'HDR: Enabled') 'On labels should be consistent across menus'
    Assert ($script:hdrTray.Icon.Icon.Handle -eq $script:hdrTray.EnabledIcon.Handle) 'HDR should use the green monitor icon'
    Assert ($script:hdrTray.Icon.Text.EndsWith('HDR: Enabled')) 'Tooltip did not update'
    $script:hdrTray.Automatic.PerformClick()
    Assert ($script:hdrTray.Icon.Icon.Handle -eq $script:hdrTray.AutoEnabledIcon.Handle -and $script:hdrTray.Icon.Text -like '*auto-enable on*') 'Checking auto-enable with HDR already on must show a play badge without claiming the app enabled it'
    $script:hdrTray.Automatic.PerformClick()
    Assert ($script:hdrTray.Icon.Icon.Handle -eq $script:hdrTray.EnabledIcon.Handle) 'Unchecking auto-enable with HDR on must immediately show green with pause'
    $primary = [LocalHdrMenu.DisplayApi]::Displays[0]
    $key = Get-HdrMonitorKey $primary
    $script:hdrTray.Automation.Displays[$key] = @{DisplayId=$primary.DisplayId; Owned=$true; Expected=$true; Released=$false}
    Set-HdrTrayState (Get-HdrTrayState @($primary))
    Assert ($script:hdrTray.Icon.Icon.Handle -eq $script:hdrTray.EnabledIcon.Handle -and $script:hdrTray.Icon.Text -like '*auto-enabled*') 'A display enabled by a launch must show pause when automatic HDR is off and identify automation in the tooltip'
    $script:hdrTray.Automation.Displays.Clear()
    $script:hdrTray.Command.PerformClick()
    Assert ($script:requestedAction -eq 'Off') 'Disable did not request Off'
    [LocalHdrMenu.DisplayApi]::Displays = @((Display 'Primary' $true $true),(Display 'Secondary' $true $false))
    Update-HdrTray
    Assert ($script:hdrTray.Status.Text -eq ('HDR: Mixed' + $separator + 'Paused')) 'Mixed status incorrect'
    Assert ($script:hdrTray.Status.Available -and $script:hdrTray.Displays.Available) 'Multiple displays should show the submenu and combined summary'
    Assert (-not $script:hdrTray.DisplayName.Available) 'Multiple displays should hide the single display heading'
    Assert ($script:hdrTray.Icon.Icon.Handle -eq $script:hdrTray.EnabledIcon.Handle) 'Mixed state should show HDR is enabled on a display'
    Assert ($script:hdrTray.Command.Tag -eq 'On') 'Mixed state should enable all'
    Assert ($script:hdrTray.Command.Text -eq 'Enable HDR on all displays') 'Global action must clearly identify its scope'
    Assert ($script:hdrTray.Displays.DropDownItems.Count -eq 9) 'Per-display groups missing'
    $rows = $script:hdrTray.Displays.DropDownItems
    Assert ($rows[0].Text -eq 'Primary' -and $rows[1].Text -eq 'HDR: Enabled' -and $rows[5].Text -eq 'Secondary' -and $rows[6].Text -eq 'HDR: Disabled') 'Display names must appear above their own HDR status'
    Assert ($rows[4] -is [Windows.Forms.ToolStripSeparator]) 'Display groups need a divider'
    foreach ($row in @($rows[0],$rows[1],$rows[5],$rows[6])) {
        Assert (-not $row.Enabled -and -not $row.CanSelect) 'Display details must not highlight on hover'
    }
    Assert ($rows[2].Text -eq 'Disable HDR' -and $rows[7].Text -eq 'Enable HDR') 'Each display must offer its own action'
    Assert ($rows[3].Name -eq 'SdrBrightness' -and $rows[8].Name -eq 'SdrBrightness') 'Each capable display needs brightness controls'
    Assert ($rows[3].Tag -ceq [LocalHdrMenu.DisplayApi]::Displays[0].DisplayId -and $rows[8].Tag -ceq [LocalHdrMenu.DisplayApi]::Displays[1].DisplayId) 'Brightness entries must target their own monitors'
    $rows[2].PerformClick()
    Assert ($script:requestedAction -eq 'Off' -and $script:requestedDisplayId -ceq [LocalHdrMenu.DisplayApi]::Displays[0].DisplayId) 'Primary action targeted the wrong display'
    $rows[7].PerformClick()
    Assert ($script:requestedAction -eq 'On' -and $script:requestedDisplayId -ceq [LocalHdrMenu.DisplayApi]::Displays[1].DisplayId) 'Secondary action targeted the wrong display'
    $script:hdrTray.Command.PerformClick()
    Assert ([string]::IsNullOrEmpty($script:requestedDisplayId)) 'Global action inherited a monitor target'
    $script:hdrTray.Pending = [pscustomobject]@{HasExited=$false}
    Set-HdrTrayState (Get-HdrTrayState ([LocalHdrMenu.DisplayApi]::Displays))
    Assert (-not $rows[2].Enabled -and -not $rows[7].Enabled -and -not $rows[3].Enabled -and -not $rows[8].Enabled) 'Per-monitor commands must disable while a change is pending'
    $script:hdrTray.Pending = $null
    Set-HdrTrayState (Get-HdrTrayState ([LocalHdrMenu.DisplayApi]::Displays))
    Assert ($rows[2].Enabled -and $rows[7].Enabled -and $rows[3].Enabled -and $rows[8].Enabled) 'Unchanged display state must restore commands after a change'
    $script:hdrTray.UpdateProcess = [pscustomobject]@{HasExited=$false}
    Set-HdrTrayState (Get-HdrTrayState ([LocalHdrMenu.DisplayApi]::Displays))
    Assert (-not $rows[2].Enabled -and -not $rows[6].Enabled) 'Per-monitor commands must disable during updates'
    $script:hdrTray.UpdateProcess = $null

    [LocalHdrMenu.DisplayApi]::Displays = @((Display 'SDR only' $false $false))
    Update-HdrTray
    Assert (-not $script:hdrTray.Command.Enabled) 'Unsupported display has an enabled command'
    Assert ($script:hdrTray.Status.Text -eq 'HDR: Unavailable' -and -not $script:hdrTray.Status.AutomationDecision) 'Unavailable HDR must hide the automation label and badge'
    Assert ($script:hdrTray.Displays.Available -and $script:hdrTray.Displays.Enabled -and -not $script:hdrTray.Status.Available) 'An unsupported monitor must expose Displays in place of the main HDR status'
    Assert (-not $script:hdrTray.DisplayName.Available -and $script:hdrTray.Displays.DropDownItems[0].Text -eq 'SDR only') 'Show the unsupported monitor name inside Displays'
    Assert ($script:hdrTray.Displays.DropDownItems[1].Text -eq 'HDR: Unavailable') 'Unavailable labels should be consistent across menus'
    Assert (-not $script:hdrTray.Command.Available) 'Unsupported display should hide the HDR action'
    Assert (-not $script:hdrTray.CommandSeparator.Available -and -not $script:hdrTray.Automatic.Available) 'Unavailable HDR must hide the automation toggle and trailing divider'
    Assert ($script:hdrTray.Icon.Icon.Handle -eq $script:hdrTray.UnavailableIcon.Handle) 'Unsupported display should use the red X icon'
    Assert ($script:hdrTray.Displays.DropDownItems.Count -eq 2) 'Stale display entry remained'
    [LocalHdrMenu.DisplayApi]::Displays = @()
    Update-HdrTray
    Assert (-not $script:hdrTray.Displays.Enabled) 'Empty display list is enabled'
    Assert ($script:hdrTray.Displays.Available -and -not $script:hdrTray.Status.Available) 'Keep the Displays heading when no monitors are connected'
    Assert (-not $script:hdrTray.DisplayName.Available) 'No displays should hide stale display names'
    Assert (-not $script:hdrTray.Command.Available) 'No displays should hide the HDR action'
    Assert ($script:hdrTray.Icon.Icon.Handle -eq $script:hdrTray.UnavailableIcon.Handle) 'No displays should use the red X icon'
    [LocalHdrMenu.DisplayApi]::Fail = $true
    Update-HdrTray
    Assert ($script:hdrTray.Status.Text -eq 'HDR: Temporarily unreadable' -and -not $script:hdrTray.Automatic.Available) 'Transient failure left stale automation controls'
    Assert (-not $script:hdrTray.Command.Available) 'Unreadable HDR state should hide the action'
    Assert (-not $script:hdrTray.Command.Enabled) 'Transient failure left action enabled'
    Assert ($script:hdrTray.Icon.Icon.Handle -eq $script:hdrTray.UnavailableIcon.Handle) 'Unreadable HDR state should use the red X icon'
    [LocalHdrMenu.DisplayApi]::Fail = $false
    [LocalHdrMenu.DisplayApi]::Displays = @((Display 'Primary' $true $false))
    Update-HdrTray
    Assert ($script:hdrTray.Command.Enabled) 'Tray failed to recover after display read failure'
    Assert ($script:hdrTray.DisplayName.Available -and $script:hdrTray.Status.Available -and -not $script:hdrTray.Displays.Available) 'One capable monitor must recover its name and main HDR status'
    Assert ($script:hdrTray.Icon.Icon.Handle -eq $script:hdrTray.DisabledIcon.Handle) 'Recovery to HDR off with auto-enable off should restore the yellow pause icon'
    Assert ($script:hdrTray.Command.Available -and $script:hdrTray.CommandSeparator.Available -and $script:hdrTray.Automatic.Available -and $script:hdrTray.Status.Text -eq ('HDR: Disabled' + $separator + 'Paused')) 'HDR and automation controls did not reappear on recovery'
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
        Assert ($script:hdrTray.Displays.DropDownItems.Count -eq 5) 'Reconnect lost display rows'
        Assert ($script:hdrTray.Displays.Available -and -not $script:hdrTray.Status.Available) 'Multiple unsupported monitors must keep unavailable status inside Displays'
        Assert (@($script:hdrTray.Displays.DropDownItems | Where-Object {$_.Name -eq 'HdrStatus' -and $_.Text -ne 'HDR: Unavailable'}).Count -eq 0) 'Reconnect left stale display labels'
        Assert (-not $script:hdrTray.Command.Available) 'Reconnect left an HDR action for unavailable displays'
        # An unchanged status must still repair a stale icon, not trust a
        # remembered state string while the rendered image is different.
        $script:hdrTray.Icon.Icon = $script:hdrTray.DisabledIcon
        Update-HdrTray
        Assert ($script:hdrTray.Icon.Icon.Handle -eq $script:hdrTray.UnavailableIcon.Handle) 'Repeated unavailable status failed to repair a stale yellow icon'
        [LocalHdrMenu.DisplayApi]::Displays = @((Display 'Laptop' $false $false),(Display 'External' $true $true))
        Update-HdrTray
        Assert ($script:hdrTray.Icon.Icon.Handle -eq $script:hdrTray.EnabledIcon.Handle) 'Reconnected HDR display did not restore the green icon'
        Assert ($script:hdrTray.Displays.DropDownItems[4].Text -eq 'HDR: Enabled' -and $script:hdrTray.Displays.DropDownItems[3].Text -eq 'External') 'Reconnected HDR display label did not recover'
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
    # Raw input arrives asynchronously: replay a press delivered after dismissal.
    $captureAt=$script:hdrTray.PressTracker.GetType().GetMethod('CapturePressAt',[Reflection.BindingFlags]'Instance,NonPublic')
    & $script:realShowHdrControls
    $pressTime=[Environment]::TickCount
    $script:hdrTray.ControlsMenu.Close()
    [void]$captureAt.Invoke($script:hdrTray.PressTracker,@($press,$pressTime))
    & $script:realShowHdrControls
    Assert (-not $script:hdrTray.ControlsMenu.Visible) 'Delayed mouse notification reopened the dismissed menu'
    [void]$captureAt.Invoke($script:hdrTray.PressTracker,@($press,([Environment]::TickCount+100)))
    & $script:realShowHdrControls
    Assert $script:hdrTray.ControlsMenu.Visible 'A later tray press was confused with the dismissal'
    $script:hdrTray.ControlsMenu.Close()
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
        $first = Display 'Same model' $true $true
        $second = Display 'Same model' $true $false
        $second.DisplayId = 'U2Vjb25k'
        [LocalHdrMenu.DisplayApi]::Displays = @($first,$second)
        Update-HdrTray
        $actions = @($script:hdrTray.Displays.DropDownItems | Where-Object Name -eq 'HdrAction')
        $actions[1].PerformClick()
        Assert ($script:requestedDisplayId -ceq 'U2Vjb25k') 'Identical monitor names must not affect selection'
        & $script:realStartHdrChange 'On' $script:requestedDisplayId
        Assert ($script:launchArguments.EndsWith('-Action On -DisplayId "U2Vjb25k" -FromHelper')) 'Selected identity and helper-origin flag did not reach the display helper'
        Assert (@($actions | Where-Object Enabled).Count -eq 0) 'Launching a change must immediately disable all monitor commands'
        & $script:realStartHdrChange 'Off' $first.DisplayId
        Assert ($script:launches -eq 1) 'Per-display commands must not overlap'
    } finally { $script:hdrTray.Pending=$null }
    $script:launches=0
    try {
        & $script:realStartHdrChange 'Toggle'
        Assert ($script:launchArguments -match '-Action Toggle -FromHelper$') 'Toggle and helper-origin flag did not reach the display helper'
        Assert (-not $script:hdrTray.Command.Enabled) 'HDR action should be disabled during a change'
        & $script:realStartHdrChange 'Toggle'
        Assert ($script:launches -eq 1) 'Repeated middle clicks must not start overlapping changes'
    } finally { $script:hdrTray.Pending=$null }
    $script:launches=0
    try {
        & $script:realStartAppUpdate '1.1.0'
        Assert ($script:launchArguments -match 'Update-HdrApp.ps1" -Version 1.1.0$') 'Accepted update must launch the installed updater directly'
        Assert (-not $script:hdrTray.CheckUpdates.Enabled -and $script:hdrTray.CheckUpdates.Text -eq 'Updating...') 'Update progress is missing'
        & $script:realStartAppUpdate '1.1.0'
        Assert ($script:launches -eq 1) 'Repeated updates must not launch overlapping installers'
        $script:hdrTray.UpdateProcess.HasExited=$true
        $script:hdrTray.UpdateProcess | Add-Member ScriptMethod Dispose {}
        Complete-HdrAppUpdate
        Assert ($null -eq $script:hdrTray.UpdateProcess -and $script:hdrTray.CheckUpdates.Enabled) 'Exited updater must allow retry after cancellation or failure'
    } finally { $script:hdrTray.UpdateProcess=$null }
    'PASS: click routing, native popup placement and screen edges, toggle concurrency, menu contents, state updates, recovery, and settings links.'
} finally { Close-HdrTray }
