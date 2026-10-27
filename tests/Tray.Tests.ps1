# Run in a fresh Windows PowerShell process. No real display settings change.
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot
$installedIcon = Join-Path $repo 'HdrSdrMenu.ico'
$installedScript = Join-Path $repo 'HdrSdrMenu.ps1'
. (Join-Path $repo 'HdrTray.ps1')
$script:realStartHdrChange = ${function:Start-HdrChange}
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
function Assert($Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Display([string]$Name, [bool]$Supported, [bool]$Enabled) {
    [pscustomobject]@{Name=$Name;HdrSupported=$Supported;HdrEnabled=$Enabled}
}
$script:syncCount=0
Initialize-HdrTray
try {
    Assert ($null -ne $script:hdrTray.ShowMenuMethod) 'Native tray popup method unavailable'
    Assert ($script:hdrTray.Icon.ContextMenuStrip -eq $script:hdrTray.Menu) 'Right click not bound to settings menu'
    Assert (($script:hdrTray.Menu.Items | Where-Object {$_ -is [Windows.Forms.ToolStripMenuItem]} | ForEach-Object Text) -join '|' -eq 'HDR settings|Display settings|Exit') 'Right-click menu contains wrong items'
    Assert ($script:hdrTray.ControlsMenu.Items.Contains($script:hdrTray.Displays)) 'Displays missing from left-click menu'
    Assert ($script:hdrTray.ControlsMenu.Items.Contains($script:hdrTray.Command)) 'HDR action missing from left-click menu'
    $mouseClick = [Windows.Forms.NotifyIcon].GetMethod('OnMouseClick',[Reflection.BindingFlags]'Instance,NonPublic')
    $script:controlsOpened=0
    foreach ($button in @([Windows.Forms.MouseButtons]::Left,[Windows.Forms.MouseButtons]::Right,[Windows.Forms.MouseButtons]::Middle)) {
        $eventArgs = New-Object Windows.Forms.MouseEventArgs($button,1,0,0,0)
        [void]$mouseClick.Invoke($script:hdrTray.Icon,@($eventArgs.PSObject.BaseObject))
    }
    Assert ($script:controlsOpened -eq 1) 'Controls should open only on left click'
    Assert ($script:requestedAction -eq 'Toggle') 'Middle click must request a live HDR toggle'
    $script:requestedUri=$null
    $doubleClick = [Windows.Forms.NotifyIcon].GetMethod('OnDoubleClick',[Reflection.BindingFlags]'Instance,NonPublic')
    [void]$doubleClick.Invoke($script:hdrTray.Icon,@([EventArgs]::Empty))
    Assert ($null -eq $script:requestedUri) 'Double click must not unexpectedly open settings'
    [LocalHdrMenu.DisplayApi]::Displays = @((Display 'Primary' $true $false))
    Update-HdrTray
    Assert ($script:hdrTray.Status.Text -eq 'HDR: Off') 'SDR status incorrect'
    Assert ($script:hdrTray.Icon.Icon.Handle -eq $script:hdrTray.DisabledIcon.Handle) 'SDR should use the gray monitor icon'
    Assert ($script:hdrTray.Command.Text -eq 'Enable HDR') 'SDR command incorrect'
    $script:hdrTray.Command.PerformClick()
    Assert ($script:requestedAction -eq 'On') 'Enable did not request On'
    [LocalHdrMenu.DisplayApi]::Displays = @((Display 'Primary' $true $true))
    Update-HdrTray
    Assert ($script:hdrTray.Status.Text -eq 'HDR: On') 'HDR status incorrect'
    Assert ($script:hdrTray.Icon.Icon.Handle -eq $script:hdrTray.EnabledIcon.Handle) 'HDR should use the green monitor icon'
    Assert ($script:hdrTray.Icon.Text.EndsWith('HDR: On')) 'Tooltip did not update'
    $script:hdrTray.Command.PerformClick()
    Assert ($script:requestedAction -eq 'Off') 'Disable did not request Off'
    [LocalHdrMenu.DisplayApi]::Displays = @((Display 'Primary' $true $true),(Display 'Secondary' $true $false))
    Update-HdrTray
    Assert ($script:hdrTray.Status.Text -eq 'HDR: Mixed') 'Mixed status incorrect'
    Assert ($script:hdrTray.Icon.Icon.Handle -eq $script:hdrTray.EnabledIcon.Handle) 'Mixed state should show HDR is enabled on a display'
    Assert ($script:hdrTray.Command.Tag -eq 'On') 'Mixed state should enable all'
    Assert ($script:hdrTray.Displays.DropDownItems.Count -eq 2) 'Per-display status missing'
    [LocalHdrMenu.DisplayApi]::Displays = @((Display 'SDR only' $false $false))
    Update-HdrTray
    Assert (-not $script:hdrTray.Command.Enabled) 'Unsupported display has an enabled command'
    Assert ($script:hdrTray.Status.Text -eq 'HDR: Unavailable') 'Unavailable caption is incorrect'
    Assert (-not $script:hdrTray.Command.Available) 'Unsupported display should hide the HDR action'
    Assert (-not $script:hdrTray.CommandSeparator.Available) 'Hidden action should not leave a separator'
    Assert ($script:hdrTray.Icon.Icon.Handle -eq $script:hdrTray.UnavailableIcon.Handle) 'Unsupported display should use the red X icon'
    Assert ($script:hdrTray.Displays.DropDownItems.Count -eq 1) 'Stale display entry remained'
    [LocalHdrMenu.DisplayApi]::Displays = @()
    Update-HdrTray
    Assert (-not $script:hdrTray.Displays.Enabled) 'Empty display list is enabled'
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
    Assert ($script:hdrTray.Icon.Icon.Handle -eq $script:hdrTray.DisabledIcon.Handle) 'Recovery to HDR off should restore the gray minus icon'
    Assert ($script:hdrTray.Command.Available -and $script:hdrTray.CommandSeparator.Available) 'HDR action did not reappear on recovery'
    $script:hdrTray.HdrSettings.PerformClick()
    Assert ($script:requestedUri -eq 'ms-settings:display-hdr') 'HDR settings link incorrect'
    $script:hdrTray.DisplaySettings.PerformClick()
    Assert ($script:requestedUri -eq 'ms-settings:display') 'Display settings link incorrect'
    Assert ($script:syncCount -eq 6) 'Desktop label synchronization stopped'
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
    'PASS: left/right/middle click routing, toggle launch and concurrency guard, menu contents, state updates, recovery, and settings links.'
} finally { Close-HdrTray }
