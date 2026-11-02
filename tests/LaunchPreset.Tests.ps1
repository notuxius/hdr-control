# Runs the queue and launch coordinator with simulated display/process APIs.
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot
. (Join-Path $repo 'HdrTray.ps1')
Add-Type @'
namespace LocalHdrMenu { public static class DisplayApi { public static object[] Displays; public static object[] Read() { return Displays; } } }
'@
function Assert($Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
$root=Join-Path ([IO.Path]::GetTempPath()) ('hdr-launch-preset-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
function Get-HdrProfilesPath { Join-Path $root 'profiles.json' }
function Get-HdrRequestDirectory { Join-Path $root 'requests' }
function Write-HdrDiagnostic { }
function Show-HdrMessage($Text) { $script:message=$Text }
function Show-HdrNotification { }
function Get-HdrAutomationTime { $script:now }
function Start-HdrChange($NextAction,$DisplayId,[switch]$Automatic) {
    $script:calls.Add(@{Action=$NextAction;Id=$DisplayId})
    $script:hdrTray.Pending=[pscustomobject]@{HasExited=$false}
}
function Start-HdrBrightnessChange($Display,$Level,$Restore,[switch]$Automatic) {
    $script:calls.Add(@{Action='Brightness';Id=$Display.DisplayId;Level=$Level})
    $script:hdrTray.Pending=[pscustomobject]@{HasExited=$false}; return $true
}
function Start-Process($FilePath,$WorkingDirectory,$ArgumentList,[switch]$PassThru,$ErrorAction,$WindowStyle) {
    $script:launchCalls.Add(@{File=$FilePath;Directory=$WorkingDirectory;Arguments=$ArgumentList})
    $process=[pscustomobject]@{}; $process | Add-Member ScriptMethod Dispose {}; return $process
}
function Reset {
    $script:now=[DateTime]::UtcNow; $script:message=''
    $script:a=[pscustomobject]@{Name='Main';DevicePath='main';DisplayId='bWFpbg==';HdrSupported=$true;HdrEnabled=$false;HdrActive=$false;SdrWhiteLevel=2000}
    $script:b=[pscustomobject]@{Name='Side';DevicePath='side';DisplayId='c2lkZQ==';HdrSupported=$true;HdrEnabled=$true;HdrActive=$true;SdrWhiteLevel=2500}
    [LocalHdrMenu.DisplayApi]::Displays=@($a,$b)
    $script:calls=New-Object 'Collections.Generic.List[object]'; $script:launchCalls=New-Object 'Collections.Generic.List[object]'
    $icon=[pscustomobject]@{}
    $script:hdrTray=@{Pending=$null;Scene=$null;UpdateProcess=$null;Automation=(New-HdrAutomationState);Launches=@{};Icon=$icon}
}
function Step([bool]$Success=$true) {
    Update-HdrScene ([LocalHdrMenu.DisplayApi]::Displays)
    if ($null -ne $script:hdrTray.Pending) {
        $call=$calls[$calls.Count-1]
        if ($Success) {
            foreach($d in [LocalHdrMenu.DisplayApi]::Displays) { if($d.DisplayId -eq $call.Id) {
                if ($call.Action -eq 'Brightness') { $d.SdrWhiteLevel=$call.Level }
                else { $d.HdrEnabled=$call.Action -eq 'On'; $d.HdrActive=$d.HdrEnabled }
            } }
        }
        $script:hdrTray.Pending=$null; Complete-HdrSceneStep $Success
    }
}
try {
    Reset
    $targets=@(@{Key=(Get-HdrBrightnessKey $a);Enabled=$true;Level=3000},@{Key=(Get-HdrBrightnessKey $b);Enabled=$false;Level=$null})
    Start-HdrScene $targets 'Gaming'; Step; Step; Step; Step
    Assert ($a.HdrEnabled -and $a.SdrWhiteLevel -eq 3000 -and -not $b.HdrEnabled -and $null -eq $hdrTray.Scene) 'Preset HDR/brightness sequencing failed'
    Assert ($calls.Count -eq 3 -and $calls[1].Action -eq 'Brightness') 'Brightness must follow HDR verification'

    Reset
    Start-HdrScene $targets 'Gaming'; Step; Step $false
    Assert $hdrTray.Scene.Rollback 'Failed brightness must initiate preset recovery'
    for($i=0;$i -lt 8;$i++) { Step }
    Assert (-not $a.HdrEnabled -and $b.HdrEnabled -and $null -eq $hdrTray.Scene -and $message) 'Preset failure did not restore baseline or report failure'

    Reset
    [LocalHdrMenu.DisplayApi]::Displays=@($a)
    $failed=$false; try { Start-HdrScene $targets 'Missing monitor' } catch { $failed=$true }
    Assert ($failed -and $calls.Count -eq 0 -and $null -eq $hdrTray.Scene) 'Preset must validate all monitors before changing any'

    Reset
    $hdrTray.Pending=[pscustomobject]@{}
    $failed=$false; try { Start-HdrScene $targets 'Busy' } catch { $failed=$true }
    Assert $failed 'Preset must not overlap a manual command'

    Reset
    # A real existing executable path is validated, but Start-Process is mocked.
    $rule=New-HdrGameRule 'ExampleGame.exe'; $rule.Targets=@((Get-HdrBrightnessKey $a)); $rule.LaunchPath=Join-Path $PSHOME 'powershell.exe'
    $rule.Arguments='--example "two words"'; $rule.WorkingDirectory=$root
    Start-HdrLaunch $rule
    Update-HdrLaunches ([LocalHdrMenu.DisplayApi]::Displays)
    Assert ($launchCalls.Count -eq 0) 'Game launched before HDR was enabled'
    $a.HdrEnabled=$true; $hdrTray.Automation.Displays[(Get-HdrMonitorKey $a)]=@{Released=$false}
    $hdrTray.Pending=[pscustomobject]@{}
    Update-HdrLaunches ([LocalHdrMenu.DisplayApi]::Displays)
    Assert ($launchCalls.Count -eq 0) 'Game launched before display verification completed'
    $hdrTray.Pending=$null; Update-HdrLaunches ([LocalHdrMenu.DisplayApi]::Displays)
    Assert ($launchCalls.Count -eq 1 -and $launchCalls[0].Arguments -eq $rule.Arguments -and $launchCalls[0].Directory -eq $root) 'Launch lost arguments or working directory'
    Update-HdrLaunches ([LocalHdrMenu.DisplayApi]::Displays)
    Assert ($launchCalls.Count -eq 1) 'A launch request started the program twice'

    Reset
    Start-HdrLaunch $rule; $script:now=$now.AddSeconds(46); Update-HdrLaunches ([LocalHdrMenu.DisplayApi]::Displays)
    Assert ($launchCalls.Count -eq 0 -and $hdrTray.Launches.Count -eq 0) 'Failed HDR preparation must time out without launching'

    Reset
    $profiles=New-HdrProfiles; $profiles.Rules=@($rule); Save-HdrProfiles $profiles
    [void][IO.Directory]::CreateDirectory((Get-HdrRequestDirectory))
    Write-HdrAtomicText (Join-Path (Get-HdrRequestDirectory) 'stale.json') (@{Id=$rule.Id;CreatedUtc=[DateTime]::UtcNow.AddMinutes(-5).ToString('o')} | ConvertTo-Json)
    Receive-HdrLaunchRequests
    Assert ($hdrTray.Launches.Count -eq 0) 'Stale launch request must not execute'
    Write-HdrAtomicText (Join-Path (Get-HdrRequestDirectory) 'valid.json') (@{Id=$rule.Id;CreatedUtc=[DateTime]::UtcNow.ToString('o')} | ConvertTo-Json)
    Receive-HdrLaunchRequests
    Assert ($hdrTray.Launches.Count -eq 1 -and @(Get-ChildItem (Get-HdrRequestDirectory)).Count -eq 0) 'Valid launch request was not consumed once'
    $key=Get-HdrMonitorKey $a
    $hdrTray.Automation.Active=$true
    $hdrTray.Automation.Displays[$key]=@{DisplayId=$a.DisplayId;Released=$false}
    Publish-HdrManualChange $a.DisplayId
    Receive-HdrLaunchRequests
    Assert ($hdrTray.Automation.Displays[$key].Released) 'Desktop command notification must relinquish automatic ownership even when the HDR state is unchanged'

    # Shortcut content refers only to a saved ID, not interpolated game arguments.
    $shortcutPath=Join-Path $root 'Game (HDR).lnk'; New-HdrLaunchShortcut $rule $shortcutPath
    $shell=New-Object -ComObject WScript.Shell
    try { $shortcut=$shell.CreateShortcut($shortcutPath); Assert ($shortcut.Arguments -like ('* Launch '+$rule.Id) -and $shortcut.Arguments -notmatch '--example') 'Unsafe shortcut arguments' }
    finally { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell) }
    'PASS: preset sequencing, brightness, recovery, missing monitors, concurrency, verified prelaunch, arguments, working directory, timeout, request expiry/consumption, and shortcut contents.'
} finally {
    $full=[IO.Path]::GetFullPath($root)
    if ([IO.Path]::GetDirectoryName($full) -ne [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') -or [IO.Path]::GetFileName($full) -notmatch '^hdr-launch-preset-[a-f0-9]{32}$') { throw 'Invalid test cleanup path' }
    Remove-Item -LiteralPath $full -Recurse -Force
}
