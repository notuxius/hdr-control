# Simulated display changes only. No real HDR writes, processes, or global hotkeys.
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot
. (Join-Path $repo 'HdrTray.ps1')
function Assert($Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
$root=Join-Path ([IO.Path]::GetTempPath()) ('hdr-profiles-'+[Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root) | Out-Null
function Get-HdrProfilesPath { Join-Path $root 'profiles.json' }
function Get-HdrCustomAppsPath { Join-Path $root 'custom.txt' }
function Get-HdrDefaultAppNames { @('game.exe','second.exe') }
function Get-HdrRunningAppNames { if ($script:scanFails) { throw 'Scan failed' }; $script:running }
function Get-HdrAutomationPreference($Name) { if ($Name -eq 'AutomaticHdr') { return $script:enabled }; return $true }
function Get-HdrAutomationTime { $script:now }
function Write-HdrDiagnostic($Category,$Message) { }
function Save-HdrDetectedApps { }
function Show-HdrMessage($Text) { $script:message=$Text }
function Show-HdrNotification($Message) { $script:notifications.Add($Message) }
function Start-HdrChange($NextAction,$DisplayId,[switch]$Automatic) {
    $script:calls.Add([pscustomobject]@{Action=$NextAction;Id=$DisplayId})
    $script:hdrTray.Pending=[pscustomobject]@{HasExited=$false}
}
function D($Name,$Enabled) { [pscustomobject]@{Name=$Name;DevicePath=$Name;DisplayId=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Name));HdrSupported=$true;HdrEnabled=$Enabled;HdrActive=$Enabled;SdrWhiteLevel=2000} }
function Reset {
    $script:config=New-HdrProfiles; Save-HdrProfiles $config
    $script:a=D 'A' $false; $script:b=D 'B' $true; $script:displays=@($a,$b)
    $script:now=[DateTime]::UtcNow; $script:running=@(); $script:enabled=$true; $script:scanFails=$false
    $script:calls=New-Object 'Collections.Generic.List[object]'
    $script:notifications=New-Object 'Collections.Generic.List[string]'
    $script:hdrTray=@{Automation=(New-HdrAutomationState);Pending=$null;UpdateProcess=$null;Launches=@{};Scene=$null;BrightnessStates=@{};PolicyPending=$null}
}
function Poll { $script:now=$script:now.AddSeconds(2); Update-HdrAutomation $script:displays }
function Finish([bool]$Success=$true) {
    $call=$calls[$calls.Count-1]
    if ($Success) { foreach ($d in $script:displays) { if ($d.DisplayId -eq $call.Id) { $d.HdrEnabled=$call.Action -eq 'On'; $d.HdrActive=$d.HdrEnabled } } }
    $script:hdrTray.Pending=$null; Complete-HdrPolicyCommand $Success
}
function AddRule($Name,$Keys,$Policy='Restore',$Start=0,$Exit=2) {
    $rule=New-HdrGameRule $Name; $rule.Targets=@($Keys); $rule.ExitPolicy=$Policy; $rule.StartDelay=$Start; $rule.ExitDelay=$Exit
    $script:config.Rules+=@($rule); Save-HdrProfiles $config; return $rule
}
try {
    Reset
    $b.HdrEnabled=$false
    $script:running=@('game'); Poll
    Assert ($notifications.Count -eq 0) 'Pending HDR must stay quiet'
    Finish; Poll; Finish; Poll
    Assert ($calls.Count -eq 2 -and $notifications.Count -eq 1 -and $notifications[0] -ceq 'HDR turned on automatically for game.exe.') 'Enabling two monitors must notify once with the detected game name'
    $script:running=@(); Poll; Poll
    Assert ($notifications.Count -eq 1) 'An exit must wait for a confirmed off command'
    Finish; Poll; Finish; Poll
    Assert ($notifications.Count -eq 2 -and $notifications[1] -ceq 'HDR turned off automatically after game.exe exited.') 'Restoring two monitors must notify once'
    $script:running=@('game'); Poll; Finish
    Assert ($notifications.Count -eq 3) 'A new launch must notify again'

    Reset
    $a.HdrEnabled=$true
    $script:running=@('game'); Poll; Poll
    Assert ($calls.Count -eq 0 -and $notifications.Count -eq 0) 'Already-enabled HDR must stay quiet'

    Reset
    $rule=AddRule 'game.exe' @((Get-HdrBrightnessKey $a))
    $script:running=@('game'); Poll
    Assert ($calls.Count -eq 1 -and $calls[0].Id -eq $a.DisplayId -and $calls[0].Action -eq 'On') 'Game must target only its selected display'
    Assert ((Get-HdrTrayState $displays).IconState -eq 'Enabled') 'A pending automatic command must not claim pre-existing HDR'
    Finish; Poll
    Assert ((Get-HdrTrayState $displays).IconState -eq 'AutoEnabled') 'Successful automatic HDR must show the play badge'
    Assert ((Get-HdrTrayState @($b)).IconState -eq 'Enabled') 'A disconnected auto-enabled monitor must not claim ownership of another display'
    $script:running=@(); Poll
    Assert ($calls.Count -eq 1) 'Exit grace period was skipped'
    Poll
    Assert ($calls.Count -eq 2 -and $calls[1].Action -eq 'Off') 'Restore must undo HDR enabled by automation'
    Finish; Poll
    Assert ($b.HdrEnabled -and -not $hdrTray.Automation.Active) 'Unselected monitor or session cleanup incorrect'

    Reset
    $config.ExitPolicy='Restore'; Save-HdrProfiles $config
    $script:running=@('game'); Poll; Finish; Poll
    $script:running=@(); Poll; Poll
    Assert ($calls.Count -eq 2 -and $calls[1].Id -eq $a.DisplayId) 'Mixed baseline must restore each monitor separately'
    Finish; Poll; Assert $b.HdrEnabled 'Pre-existing HDR must be preserved'

    Reset
    $rule=AddRule 'game.exe' @((Get-HdrBrightnessKey $a))
    $script:running=@('game'); Poll; Finish
    Release-HdrAutomationDisplay $a.DisplayId
    Assert ((Get-HdrTrayState $displays).IconState -eq 'Enabled') 'A manual override must clear automation ownership'
    $script:running=@(); Poll; Poll
    Assert ($calls.Count -eq 1 -and $a.HdrEnabled) 'Manual override must relinquish restoration as well as enabling'

    Reset
    $rule=AddRule 'game.exe' @((Get-HdrBrightnessKey $a))
    $script:running=@('game'); Poll; Finish; Poll
    $a.HdrEnabled=$false; Poll; Poll
    Assert ($calls.Count -eq 1 -and $hdrTray.Automation.Displays[(Get-HdrMonitorKey $a)].Released) 'External change must not be fought'

    Reset
    $rule=AddRule 'game.exe' @((Get-HdrBrightnessKey $a)) 'Restore' 4 6
    $rule2=AddRule 'second.exe' @((Get-HdrBrightnessKey $a))
    $script:running=@('game'); Poll; Poll
    Assert ($calls.Count -eq 0) 'Startup delay ignored'
    Poll; Finish; $script:running=@('game','second'); Poll
    $script:running=@('second'); Poll; Poll; Poll; Poll
    Assert ($calls.Count -eq 1) 'Overlapping game must keep HDR enabled'
    $script:running=@(); Poll; Poll
    Assert ($calls.Count -eq 2) 'Last game must release display'
    Finish $false; Poll
    Assert ($notifications.Count -eq 1) 'A failed off command must not announce success'
    $script:now=$now.AddSeconds(30); Poll; Finish
    Assert ($notifications.Count -eq 2 -and $notifications[1] -ceq 'HDR turned off automatically after second.exe exited.') 'A successful exit retry must name the last game on the monitor'

    Reset
    $rule=AddRule 'game.exe' @((Get-HdrBrightnessKey $a))
    $script:running=@('game'); Poll; Finish $false; Poll
    Assert ($notifications.Count -eq 0) 'Failed enable must not send a success notification'
    Assert ($calls.Count -eq 1) 'Failed request retried too soon'
    $script:now=$now.AddSeconds(30); Poll
    Assert ($calls.Count -eq 2) 'Failed request never retried'
    Finish; $script:scanFails=$true; $script:running=@(); Poll; Poll
    Assert ($notifications.Count -eq 1) 'Successful retry must notify once'
    Assert ($calls.Count -eq 2) 'Process scan failure must preserve state'
    $script:scanFails=$false; Poll; Poll
    Assert ($calls.Count -eq 3) 'Scan recovery failed'

    Reset
    $rule=AddRule 'game.exe' @((Get-HdrBrightnessKey $a))
    $script:running=@('game'); $script:displays=@($b); Poll
    Assert ($calls.Count -eq 0) 'Missing selected monitor must never fall back to another display'
    $a.DisplayId='bmV3'; $script:displays=@($a,$b); Poll
    Assert ($calls.Count -eq 1 -and $calls[0].Id -eq 'bmV3') 'Reconnect must resolve fresh target identity'

    # Validation and atomic persistence reject corrupt edits without losing prior data.
    $saved=[IO.File]::ReadAllText((Get-HdrProfilesPath))
    $config.Rules[0].StartDelay=-1
    $failed=$false; try { Save-HdrProfiles $config } catch { $failed=$true }
    Assert ($failed -and [IO.File]::ReadAllText((Get-HdrProfilesPath)) -ceq $saved) 'Invalid rule replaced good configuration'
    $config=Read-HdrProfiles; $config.Rules[0].Enabled=$false; Save-HdrProfiles $config
    Assert (-not (Get-HdrWatchedApps).ContainsKey('game')) 'Rule exclusion did not override community entry'

    Reset
    $rule=AddRule 'game.exe' @((Get-HdrBrightnessKey $a)) 'Restore' 8 6
    $script:running=@('game'); Poll; $script:running=@(); Poll; Poll; Poll; Poll
    Assert ($calls.Count -eq 0) 'A game exiting before startup delay must never enable HDR afterward'

    Reset
    $config.Bindings=@([pscustomobject]@{Id=('1'*32);Modifiers=3;Key=72;Action='Toggle';Targets=@();PresetId=''},[pscustomobject]@{Id=('2'*32);Modifiers=3;Key=73;Action='Off';Targets=@();PresetId=''})
    Save-HdrProfiles $config
    $fakeHost=[pscustomobject]@{Cleared=$false}
    $fakeHost | Add-Member ScriptMethod ClearHotkeys { $this.Cleared=$true }
    $fakeHost | Add-Member ScriptMethod Bind { param($Id,$Modifiers,$Key) return $Id -eq 1 }
    $hdrTray.EventWindow=$fakeHost; Register-HdrBindings
    Assert ($fakeHost.Cleared -and $hdrTray.HotkeyBindings.Count -eq 1 -and $message -match 'in use') 'Shortcut conflict must leave only successful bindings active and explain the conflict'
    $config.Bindings[1].Key=72
    $failed=$false; try { Save-HdrProfiles $config } catch { $failed=$true }
    Assert $failed 'Duplicate keyboard shortcuts must be rejected before saving'

    # Native event/hotkey host can be created and disposed without registering keys.
    $hostWindow=[LocalHdrMenu.HdrEventWindow]::new(); Assert ($hostWindow.Handle -ne [IntPtr]::Zero) 'Event host missing'
    $script:eventCount=0; $hostWindow.add_DisplayChanged({$script:eventCount++})
    $method=$hostWindow.GetType().GetMethod('WndProc',[Reflection.BindingFlags]'Instance,NonPublic')
    $messageObject=[Windows.Forms.Message]::Create($hostWindow.Handle,0x007e,[IntPtr]::Zero,[IntPtr]::Zero)
    [void]$method.Invoke($hostWindow,@($messageObject))
    $messageObject=[Windows.Forms.Message]::Create($hostWindow.Handle,0x0218,[IntPtr]18,[IntPtr]::Zero)
    [void]$method.Invoke($hostWindow,@($messageObject))
    Assert ($eventCount -eq 2) 'Display-change and resume messages must notify the refresh queue'
    $hostWindow.Dispose()
    foreach ($type in @('GameRuleForm','PresetForm','ShortcutForm','ProfileSettingsForm')) {
        $form=New-Object ('LocalHdrMenu.'+$type)
        Assert ($form.ClientSize.Width -ge 600) ('Editor width: '+$type)
        $form.Dispose()
    }
    'PASS: profiles, monitor targets, mixed-state restoration, manual/external precedence, overlapping games, delays, retries, read failures, reconnects, persistence, exclusions, and UI construction.'
} finally {
    $full=[IO.Path]::GetFullPath($root)
    if ([IO.Path]::GetDirectoryName($full) -ne [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') -or [IO.Path]::GetFileName($full) -notmatch '^hdr-profiles-[a-f0-9]{32}$') { throw 'Invalid test cleanup path' }
    Remove-Item -LiteralPath $full -Recurse -Force
}
