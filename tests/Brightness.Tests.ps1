# Run in a fresh Windows PowerShell 5.1 process. Display writes are simulated.
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot
$installedScript = Join-Path $repo 'HdrSdrMenu.ps1'
. (Join-Path $repo 'HdrTray.ps1')
function Show-HdrNotification { }
function Assert($Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
$savingText=([string][char]0x2193)+' Saving'+[char]0x2026
function Wait-Saved($Panel) {
    $wait=[Diagnostics.Stopwatch]::StartNew()
    while ($Panel.Status.Text -eq $savingText -and $wait.ElapsedMilliseconds -lt 3000) {
        [Windows.Forms.Application]::DoEvents()
        [Threading.Thread]::Sleep(15)
    }
}
function Expect-Failure($Work, [string]$Message) {
    $failed=$false
    try { & $Work | Out-Null } catch { $failed=$true }
    Assert $failed $Message
}
$ast=[Management.Automation.Language.Parser]::ParseFile($installedScript,[ref]$null,[ref]$null)
$function=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-HdrBrightness'},$true)
Invoke-Expression $function.Extent.Text
function Start-Sleep { param($Milliseconds) }
Add-Type @'
using System;
using System.Collections.Generic;
namespace LocalHdrMenu {
    public class Display {
        public string Name="Same model";
        public string DisplayId;
        public string DevicePath;
        public bool HdrSupported=true, HdrEnabled=true, HdrActive=true;
        public uint? SdrWhiteLevel=2000;
        public Display Copy() { return (Display)MemberwiseClone(); }
    }
    public static class DisplayApi {
        public static Display[] Displays;
        public static List<string> Calls=new List<string>();
        public static string Fault;
        public static Display[] Read() { return Array.ConvertAll(Displays,d=>d.Copy()); }
        public static void SetBrightness(Display d,uint level) {
            Calls.Add(d.DisplayId+":"+level);
            if (Fault=="reject") throw new Exception("Unsupported setter");
            foreach(var current in Displays) {
                if(current.DisplayId!=d.DisplayId) continue;
                if(Fault!="ignore") current.SdrWhiteLevel=level;
                if(Fault=="replace") current.DisplayId="Replacement";
                if(Fault=="off") current.HdrActive=current.HdrEnabled=false;
            }
        }
    }
}
'@
function Reset-Displays {
    $a=[LocalHdrMenu.Display]::new(); $a.DisplayId='QQ=='; $a.DevicePath='monitor-path-a'
    $b=[LocalHdrMenu.Display]::new(); $b.DisplayId='Qg=='; $b.DevicePath='monitor-path-b'
    [LocalHdrMenu.DisplayApi]::Displays=@($a,$b)
    [LocalHdrMenu.DisplayApi]::Calls.Clear(); [LocalHdrMenu.DisplayApi]::Fault=''
}
Reset-Displays
Invoke-HdrBrightness 'QQ==' 3000
Assert ([LocalHdrMenu.DisplayApi]::Displays[0].SdrWhiteLevel -eq 3000 -and [LocalHdrMenu.DisplayApi]::Displays[1].SdrWhiteLevel -eq 2000) 'Manual change affected the wrong display'
Invoke-HdrBrightness 'QQ==' 3000
Assert ([LocalHdrMenu.DisplayApi]::Calls.Count -eq 1) 'Unchanged level must not write again'
foreach($id in @('', 'Missing', 'qq==')) { Expect-Failure { Invoke-HdrBrightness $id 2000 } 'Invalid or stale target accepted' }
foreach($level in @(999,6001)) { Expect-Failure { Invoke-HdrBrightness 'QQ==' $level } 'Out-of-range brightness accepted' }
foreach($fault in @('ignore','reject','replace','off')) {
    Reset-Displays; [LocalHdrMenu.DisplayApi]::Fault=$fault
    Expect-Failure { Invoke-HdrBrightness 'QQ==' 3000 } ('Unverified change accepted: '+$fault)
    Assert ([LocalHdrMenu.DisplayApi]::Displays[1].SdrWhiteLevel -eq 2000) 'Failure fallback affected another monitor'
}
Reset-Displays
[LocalHdrMenu.DisplayApi]::Displays[0].HdrEnabled=$false
Expect-Failure { Invoke-HdrBrightness 'QQ==' 3000 } 'HDR-disabled monitor accepted'
[LocalHdrMenu.DisplayApi]::Displays[0].HdrEnabled=$true
[LocalHdrMenu.DisplayApi]::Displays[0].SdrWhiteLevel=$null
Expect-Failure { Invoke-HdrBrightness 'QQ==' 3000 } 'Unreadable brightness accepted'
Assert ([LocalHdrMenu.DisplayApi]::Calls.Count -eq 0) 'Unavailable display caused a write'

# Exercise real preference serialization in an isolated registry key.
$testPath='HKCU:\Software\HdrBrightnessTests-'+[Guid]::NewGuid().ToString('N')
$script:hdrBrightnessHistoryPath=Join-Path $testPath 'LastUsed'
$originalGet=${function:Get-HdrBrightnessPreference}.ToString()
$originalSave=${function:Save-HdrBrightnessPreference}.ToString()
Set-Item Function:Get-HdrBrightnessPreference ([scriptblock]::Create($originalGet.Replace('HKCU:\Software\HdrContextMenu\SdrBrightness',$testPath)))
Set-Item Function:Save-HdrBrightnessPreference ([scriptblock]::Create($originalSave.Replace('HKCU:\Software\HdrContextMenu\SdrBrightness',$testPath)))
function Show-HdrMessage([string]$Text) { $script:lastMessage=$Text }
function Sync-HdrMenu($Displays) { }
function Get-HdrAutomationPreference([string]$Name) { return $false }
function Get-HdrStartupEnabled { return [bool]$script:testStartup }
function Set-HdrStartupEnabled([bool]$Enabled) { throw 'Brightness must never write the startup preference' }
function Get-HdrBrightnessTime { return [DateTime]'2026-11-01T12:00:00' }
function Start-Process {
    param($FilePath,$ArgumentList,$WindowStyle,[switch]$PassThru,$ErrorAction)
    $script:launches.Add($ArgumentList)
    $p=[pscustomobject]@{HasExited=$false;ExitCode=0}
    $p | Add-Member ScriptMethod Dispose {}
    return $p
}
$script:launches=[Collections.Generic.List[string]]::new()
Initialize-HdrTray
try {
    Reset-Displays
    $a=[LocalHdrMenu.DisplayApi]::Displays[0]; $b=[LocalHdrMenu.DisplayApi]::Displays[1]
    $key=Get-HdrBrightnessKey $a
    $otherKey=Get-HdrBrightnessKey $b
    Assert ($key -ne $otherKey) 'Same-model displays must have different preferences'
    $oldId=$a.DisplayId; $a.DisplayId='Qw=='
    Assert ((Get-HdrBrightnessKey $a) -eq $key) 'Preferences must survive a changed session target ID'
    $a.DisplayId=$oldId
    Assert ($null -eq (Get-HdrBrightnessPreference $key)) 'Restore must default to off without creating a preset'
    $b.SdrWhiteLevel=1000
    Update-HdrBrightness @($a,$b)
    $a.HdrEnabled=$a.HdrActive=$b.HdrEnabled=$b.HdrActive=$false
    $script:hdrTray.LastBrightness=Get-HdrLastBrightnessLevels
    $off=@(Get-HdrBrightnessDisplays @($a,$b))
    Assert ($off[0].LastUsedLevel -eq 2000 -and $off[1].LastUsedLevel -eq 1000 -and $off[1].CurrentLevel -eq 0) 'HDR-off history must survive reload and keep each monitor separate, including 0%'
    Assert ($null -eq (Get-HdrBrightnessPreference $otherKey)) 'Reading a live level created a restore preference'
    $b.DevicePath=$a.DevicePath
    $ambiguous=@(Get-HdrBrightnessDisplays @($a,$b))
    Assert ($ambiguous[0].LastUsedLevel -eq 0 -and $ambiguous[1].LastUsedLevel -eq 0) 'Duplicate monitor identities shared brightness history'
    $b.DevicePath='monitor-path-b'
    $a.HdrEnabled=$a.HdrActive=$b.HdrEnabled=$b.HdrActive=$true
    New-Item -Path $testPath -Force | Out-Null
    New-ItemProperty -LiteralPath $testPath -Name $key -Value '{"Version":1,"Level":2033,"Restore":true}' -PropertyType String -Force | Out-Null
    $migrated=Get-HdrBrightnessPreference $key
    $script:hdrTray.LastBrightness.Remove($key)
    $a.HdrEnabled=$a.HdrActive=$false
    Assert ((Get-HdrBrightnessDisplays @($a)).LastUsedLevel -eq 2033) 'An existing manual setting should be shown before a live reading is available'
    $edit=Get-HdrBrightnessDisplays @($a)
    $edit.Mode='Schedule'; $edit.DayLevel=4000; $edit.NightLevel=1500
    Save-HdrBrightnessPanel $edit
    $script:hdrTray.LastBrightness=Get-HdrLastBrightnessLevels
    $afterSwitch=Get-HdrBrightnessDisplays @($a)
    Assert ($afterSwitch.Mode -eq 'Schedule' -and $afterSwitch.LastUsedLevel -eq 2033 -and $script:launches.Count -eq 0) 'Switching away from a legacy manual setting with HDR off must preserve the last used level across restarts'
    $a.HdrEnabled=$a.HdrActive=$true
    Assert ($migrated.Version -eq 2 -and $migrated.Level -eq 2033 -and $migrated.DayLevel -eq 2033 -and $migrated.NightLevel -eq 2033 -and $migrated.Mode -eq 'Manual' -and -not $migrated.Enforce -and $migrated.Restore) 'Existing brightness preferences must migrate without enabling new automation or rounding'
    Save-HdrBrightnessPreference $key 2033 $true
    $pref=Get-HdrBrightnessPreference $key
    Assert ($pref.Level -eq 2033 -and $pref.Restore) 'Preference round trip lost exact level or opt-in'
    $solar=New-HdrBrightnessSettings 2033 $true
    $solar.Mode='SunriseSunset'; $solar.DayLevel=3033; $solar.NightLevel=1500
    Save-HdrBrightnessPreference $key 2033 $true $solar
    $pref=Get-HdrBrightnessPreference $key
    Assert ($pref.Mode -eq 'SunriseSunset' -and $pref.DayLevel -eq 3033 -and $pref.DayStart -eq 480 -and $pref.NightStart -eq 1080) 'Solar mode must persist exact levels and fallback times'
    $a.SdrWhiteLevel=2200
    Update-HdrBrightness @($a,$b)
    $a.HdrEnabled=$a.HdrActive=$false
    Assert ((Get-HdrBrightnessDisplays @($a)).LastUsedLevel -eq 2200) 'A scheduled target replaced the last observed Windows level'
    $a.HdrEnabled=$a.HdrActive=$true
    New-ItemProperty -LiteralPath $testPath -Name $key -Value '{broken' -PropertyType String -Force | Out-Null
    Assert ($null -eq (Get-HdrBrightnessPreference $key)) 'Corrupt preference must not restore'
    Save-HdrBrightnessPreference $key 3000 $false
    Update-HdrBrightness @($a,$b)
    Assert ($script:launches.Count -eq 0) 'Opt-out must not change brightness'
    Save-HdrBrightnessPreference $key 3000 $true
    $a.HdrEnabled=$a.HdrActive=$false; Update-HdrBrightness @($a,$b)
    $a.HdrEnabled=$a.HdrActive=$true
    $script:hdrTray.Pending=[pscustomobject]@{HasExited=$false}
    Update-HdrBrightness @($a,$b)
    Assert ($script:launches.Count -eq 0 -and $script:hdrTray.BrightnessStates[$a.DisplayId].Due) 'Restoration must wait for HDR commands'
    $script:hdrTray.Pending=$null
    Update-HdrBrightness @($a,$b)
    Assert ($script:launches.Count -eq 1 -and $script:launches[0] -match '-Action Brightness -DisplayId "QQ==" -SdrWhiteLevel 3000') 'Restore command targeted wrong monitor or level'
    Assert ($script:hdrTray.BrightnessPending.Automatic) 'Restoration must not rewrite saved preferences'
    Complete-HdrBrightnessChange $true; $script:hdrTray.Pending=$null
    $a.SdrWhiteLevel=2500
    Update-HdrBrightness @($a,$b)
    Assert ($script:launches.Count -eq 1) 'Continuous enforcement overwrote an external adjustment'
    Update-HdrBrightness @($b)
    $a.DisplayId='RA=='
    Update-HdrBrightness @($a,$b)
    Assert ($script:launches.Count -eq 2 -and $script:hdrTray.BrightnessPending.DisplayId -eq 'RA==') 'Reconnect failed to restore the same monitor'
    Complete-HdrBrightnessChange $false; $script:hdrTray.Pending=$null
    Update-HdrBrightness @($a,$b)
    Assert ($script:launches.Count -eq 2) 'Failed restore must back off'
    $state=$script:hdrTray.BrightnessStates[$a.DisplayId]
    $state.Attempts=3; $state.RetryAt=[DateTime]::MinValue
    $script:hdrTray.BrightnessPending=@{DisplayId=$a.DisplayId;Automatic=$true}
    Complete-HdrBrightnessChange $false
    Assert (-not $state.Due) 'Restore retries must be bounded'
    # A failed manual write must preserve both previous level and restore flag.
    [void](Start-HdrBrightnessChange $a 4000 $false)
    Complete-HdrBrightnessChange $false; $script:hdrTray.Pending=$null
    $pref=Get-HdrBrightnessPreference $key
    Assert ($pref.Level -eq 3000 -and $pref.Restore) 'Failed write saved an unconfirmed level'
    [void](Start-HdrBrightnessChange $a 4000 $false)
    Complete-HdrBrightnessChange $true; $script:hdrTray.Pending=$null
    $pref=Get-HdrBrightnessPreference $key
    Assert ($pref.Level -eq 4000 -and -not $pref.Restore) 'Confirmed manual change did not save opt-out'
    [void](Start-HdrBrightnessChange $a 3500 $false)
    $script:hdrTray.Pending.HasExited=$true
    Update-HdrTray
    Assert ($null -eq $script:hdrTray.Pending -and $null -eq $script:hdrTray.BrightnessPending -and $script:hdrTray.Exit.Enabled) 'Tray did not complete the brightness operation and release its command slot'
    Assert ((Get-HdrBrightnessPreference $key).Level -eq 3500) 'Tray completion did not save the verified request'
    $script:hdrTray.BrightnessStates.Clear(); $script:launches.Clear()
    Save-HdrBrightnessPreference $key 3000 $true
    $b.DevicePath=$a.DevicePath
    Update-HdrBrightness @($a,$b)
    Assert ($script:launches.Count -eq 0) 'Ambiguous identities must not restore'
    $b.DevicePath='monitor-path-b'
    $script:hdrTray.BrightnessStates.Clear()
    $script:hdrTray.UpdateProcess=[pscustomobject]@{HasExited=$false}
    Update-HdrBrightness @($a,$b)
    Assert ($script:launches.Count -eq 0) 'Restore overlapped an app update'
    $script:hdrTray.UpdateProcess=$null

    $a.SdrWhiteLevel=2033
    $window=[LocalHdrMenu.SettingsForm]::new()
    $script:hdrTray.SettingsWindow=$window
    Update-HdrBrightnessPanel @($a,$b)
    Update-HdrBrightness @($a,$b)
    $panel=$window.Brightness

    Assert ($panel.SelectedLevel -eq 2033 -and -not $panel.LevelEdited) 'Opening UI rounded the current Windows value'
    $panel.Slider.Value=70
    Assert ($panel.SelectedLevel -eq 4500 -and $panel.LevelEdited) 'Slider mapping is incorrect'
    $a.HdrEnabled=$a.HdrActive=$false
    Update-HdrBrightnessPanel @($a,$b)
    Assert (-not $panel.Slider.Enabled -and $panel.Slider.Value -eq 21 -and $panel.SelectedLevel -eq 4500) 'The disabled slider must show the last used level without overwriting the pending edit'
    $readout=$panel.Runtime.Parent.Parent
    Assert ($readout.Controls.AccessibleName -contains 'Last used brightness 21%') 'HDR-off readout showed an unsaved edit or a restore target instead of the last Windows level'
    Save-HdrBrightnessPanel ([LocalHdrMenu.MonitorBrightness]::Capture($panel))
    Assert ($script:lastMessage -match 'Enable HDR' -and (Get-HdrBrightnessPreference $key).Level -eq 3000) 'HDR turning off saved an unapplied slider change'
    Update-HdrBrightnessPanel @($b)
    Assert ($null -eq $window.Brightness -and $window.DisplayPicker.SelectedIndex -eq -1) 'Disconnected target silently switched to another monitor'
    $a.HdrEnabled=$a.HdrActive=$true
    Update-HdrBrightnessPanel @($a,$b)
    $panel=$window.Brightness
    Assert ($panel.Slider.Enabled) 'Available panel did not recover'
    $script:hdrTray.Pending=[pscustomobject]@{HasExited=$false}
    Update-HdrBrightnessPanel @($a,$b)
    Assert (-not $panel.Restore.Enabled -and -not $panel.Slider.Enabled) 'Pending operation did not disable controls'
    Assert ($panel.Status.Text -like 'Waiting*') 'An unrelated operation must not show save feedback'
    $script:hdrTray.Pending=$null
    # Save per-monitor settings only after the effective Day level is confirmed.
    Update-HdrBrightnessPanel @($a,$b)
    $panel.LoadSettings(3033,1500,'Schedule',480,1080,$true)

    $panel.DayStart.Text='25:00'
    $before=$script:launches.Count
    Expect-Failure { [LocalHdrMenu.MonitorBrightness]::Capture($panel) } 'Invalid time accepted in brightness settings'
    Assert ($null -eq $script:hdrTray.Pending -and $script:launches.Count -eq $before) 'Invalid time started a brightness change'
    $panel.DayStart.Value=[DateTime]'2026-11-01T08:00:00'
    Save-HdrBrightnessPanel ([LocalHdrMenu.MonitorBrightness]::Capture($panel))
    Assert ($script:hdrTray.BrightnessPending.Level -eq 3033) 'Apply must use the effective Day level'
    Assert ($panel.Status.Text -eq $savingText -and -not $panel.DaySlider.Enabled) 'The saving icon must appear when the controls are disabled'
    $snapshots=@(Get-HdrBrightnessDisplays @($a,$b))
    Assert ($snapshots[0].Saving -and -not $snapshots[1].Saving -and $snapshots[1].Busy) 'Save feedback must identify the edited monitor'
    $script:hdrTray.Pending.HasExited=$true; $script:hdrTray.Pending.ExitCode=1
    Update-HdrTray
    Assert ((Get-HdrBrightnessPreference $key).Mode -eq 'Manual') 'Failed settings Apply replaced preferences'
    Assert ($panel.Status.Text -like 'Current Windows level*' -and $panel.DaySlider.Enabled) 'A failed save must clear the saving icon without confirming'
    Save-HdrBrightnessPanel ([LocalHdrMenu.MonitorBrightness]::Capture($panel))
    $script:hdrTray.Pending.HasExited=$true; $script:hdrTray.Pending.ExitCode=0
    Update-HdrTray
    $saved=Get-HdrBrightnessPreference $key
    Assert ($saved.Mode -eq 'Schedule' -and $saved.DayLevel -eq 3033 -and $saved.NightLevel -eq 1500 -and $saved.Enforce) 'Confirmed settings Apply lost schedule, exact levels, or enforcement'
    Assert ($null -eq (Get-HdrBrightnessPreference $otherKey)) 'Saving settings leaked to another monitor'
    $savedText=([string][char]0x2713)+' Saved'
    Wait-Saved $panel
    Assert ($panel.Status.Text -eq $savedText -and $panel.DaySlider.Enabled) 'A confirmed save must replace the arrow with a checkmark'
    Update-HdrBrightnessPanel @($a,$b)
    Assert ($panel.Status.Text -eq $savedText) 'A status poll erased the save confirmation'
    $oldEdit=[LocalHdrMenu.MonitorBrightness]::Capture($panel)
    $panel.Restore.Checked=-not $panel.Restore.Checked
    $window.AppliedBrightness($oldEdit)
    Assert ($panel.Status.Text -ne $savedText) 'A stale completion confirmed a newer checkbox change'
    $panel.LoadSettings(3033,1500,'Manual',480,1080,$false)
    $panel.Slider.Value=38
    Save-HdrBrightnessPanel ([LocalHdrMenu.MonitorBrightness]::Capture($panel))
    $before=$script:launches.Count
    foreach ($percent in @(45,60)) {
        $panel.Slider.Value=$percent
        Save-HdrBrightnessPanel ([LocalHdrMenu.MonitorBrightness]::Capture($panel))
    }
    Assert ($script:launches.Count -eq $before) 'An edit overlapped a pending display write'
    $script:hdrTray.Pending.HasExited=$true
    Update-HdrTray
    Assert ($script:hdrTray.BrightnessPending.Level -eq 4000 -and $script:launches.Count -eq $before+1) 'A busy display lost the latest brightness edit'
    $script:hdrTray.Pending.HasExited=$true
    Update-HdrTray
    Assert ((Get-HdrBrightnessPreference $key).Level -eq 4000) 'The final queued edit was not persisted'
    $a.SdrWhiteLevel=4000
    $panel.Restore.Checked=-not $panel.Restore.Checked
    Save-HdrBrightnessPanel ([LocalHdrMenu.MonitorBrightness]::Capture($panel))
    Assert ($panel.Status.Text -eq $savingText -and $panel.Slider.Enabled -and $null -eq $script:hdrTray.Pending) 'A quick preference save must show the arrow while controls stay available'
    Wait-Saved $panel
    Assert ($panel.Status.Text -eq $savedText) 'A preference-only save must show its checkmark'
    $wait=[Diagnostics.Stopwatch]::StartNew()
    while ($panel.Status.Text -eq $savedText -and $wait.ElapsedMilliseconds -lt 3500) {
        [Windows.Forms.Application]::DoEvents()
        [Threading.Thread]::Sleep(20)
    }
    Assert ($panel.Status.Text -like 'Current Windows level*') 'The saved checkmark did not return to the normal status'
    $b.HdrEnabled=$b.HdrActive=$false
    Update-HdrBrightnessPanel @($a,$b)
    $window.SelectDisplay($b.DisplayId)
    $panel=$window.Brightness
    Assert (-not $panel.Slider.Enabled -and -not $panel.Switching.Enabled) 'Uninitialized brightness must disable editing'
    Save-HdrBrightnessPanel ([LocalHdrMenu.MonitorBrightness]::Capture($panel))
    Assert ($null -eq (Get-HdrBrightnessPreference $otherKey) -and $null -eq $script:hdrTray.Pending) 'Uninitialized Apply fabricated brightness settings or changed a display'
    Write-Output 'PASS: targeted brightness, verification failures, exact preference persistence, opt-in transitions, reconnect, manual precedence, bounded retries, update concurrency, and panel state.'
} finally {
    $script:hdrTray.Pending=$null; $script:hdrTray.UpdateProcess=$null
    Close-HdrTray
    if ($testPath -match '^HKCU:\\Software\\HdrBrightnessTests-[a-f0-9]{32}$') { Remove-Item -LiteralPath $testPath -Recurse -ErrorAction SilentlyContinue }
}
