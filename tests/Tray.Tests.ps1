# Run in a fresh Windows PowerShell process. No real display settings change.
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot
$installedIcon = Join-Path $repo 'HdrSdrMenu.ico'
$installedScript = Join-Path $repo 'HdrSdrMenu.ps1'
. (Join-Path $repo 'HdrTray.ps1')
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
function Assert($Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Display([string]$Name, [bool]$Supported, [bool]$Enabled) {
    [pscustomobject]@{Name=$Name;HdrSupported=$Supported;HdrEnabled=$Enabled}
}
$script:syncCount=0
Initialize-HdrTray
try {
    [LocalHdrMenu.DisplayApi]::Displays = @((Display 'Primary' $true $false))
    Update-HdrTray
    Assert ($script:hdrTray.Status.Text -eq 'HDR: Off') 'SDR status incorrect'
    Assert ($script:hdrTray.Command.Text -eq 'Enable HDR') 'SDR command incorrect'
    $script:hdrTray.Command.PerformClick()
    Assert ($script:requestedAction -eq 'On') 'Enable did not request On'
    [LocalHdrMenu.DisplayApi]::Displays = @((Display 'Primary' $true $true))
    Update-HdrTray
    Assert ($script:hdrTray.Status.Text -eq 'HDR: On') 'HDR status incorrect'
    Assert ($script:hdrTray.Icon.Text.EndsWith('HDR: On')) 'Tooltip did not update'
    $script:hdrTray.Command.PerformClick()
    Assert ($script:requestedAction -eq 'Off') 'Disable did not request Off'
    [LocalHdrMenu.DisplayApi]::Displays = @((Display 'Primary' $true $true),(Display 'Secondary' $true $false))
    Update-HdrTray
    Assert ($script:hdrTray.Status.Text -eq 'HDR: Mixed') 'Mixed status incorrect'
    Assert ($script:hdrTray.Command.Tag -eq 'On') 'Mixed state should enable all'
    Assert ($script:hdrTray.Displays.DropDownItems.Count -eq 2) 'Per-display status missing'
    [LocalHdrMenu.DisplayApi]::Displays = @((Display 'SDR only' $false $false))
    Update-HdrTray
    Assert (-not $script:hdrTray.Command.Enabled) 'Unsupported display has an enabled command'
    Assert ($script:hdrTray.Displays.DropDownItems.Count -eq 1) 'Stale display entry remained'
    [LocalHdrMenu.DisplayApi]::Displays = @()
    Update-HdrTray
    Assert (-not $script:hdrTray.Displays.Enabled) 'Empty display list is enabled'
    [LocalHdrMenu.DisplayApi]::Fail = $true
    Update-HdrTray
    Assert ($script:hdrTray.Status.Text -eq 'HDR: Status unavailable') 'Transient failure left stale status'
    Assert (-not $script:hdrTray.Command.Enabled) 'Transient failure left action enabled'
    [LocalHdrMenu.DisplayApi]::Fail = $false
    [LocalHdrMenu.DisplayApi]::Displays = @((Display 'Primary' $true $false))
    Update-HdrTray
    Assert ($script:hdrTray.Command.Enabled) 'Tray failed to recover after display read failure'
    $script:hdrTray.HdrSettings.PerformClick()
    Assert ($script:requestedUri -eq 'ms-settings:display-advancedcolor') 'HDR settings link incorrect'
    $script:hdrTray.DisplaySettings.PerformClick()
    Assert ($script:requestedUri -eq 'ms-settings:display') 'Display settings link incorrect'
    Assert ($script:syncCount -eq 6) 'Desktop label synchronization stopped'
    'PASS: on/off commands, tooltip, mixed displays, hotplug, unavailable state, recovery, and settings links.'
} finally { Close-HdrTray }
