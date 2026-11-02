# Pure schedule decisions and simulated display commands; no real display writes.
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot
. (Join-Path $repo 'HdrTray.ps1')
function Show-HdrNotification { }
function Assert($Condition,$Message) { if (-not $Condition) { throw $Message } }
function Get-HdrBrightnessTime { return $script:now }
function Get-HdrNightLightState { return $script:nightLight }
function Get-HdrBrightnessLocation { return $script:location }
function Get-HdrBrightnessPreference($Key) { return $script:preferences[$Key] }
function Save-HdrLastBrightnessLevel($Key,$Level) { }
function Get-HdrAutomationPreference($Name) { return $false }
function Start-HdrBrightnessChange($Display,[uint32]$Level,[bool]$Restore,[switch]$Automatic,$Settings,$PreferenceKey) {
    $script:calls.Add(@{Id=$Display.DisplayId;Level=$Level})
    $script:hdrTray.BrightnessPending=@{DisplayId=$Display.DisplayId;Automatic=[bool]$Automatic;Level=$Level}
    $script:hdrTray.Pending=[pscustomobject]@{HasExited=$false}
    return $true
}
$script:now=[DateTime]'2026-11-01T12:00:00'; $script:nightLight=$null
$settings=New-HdrBrightnessSettings 2033
Test-HdrBrightnessSettings $settings
Assert ($settings.DayLevel -eq 2033 -and $settings.NightLevel -eq 2033 -and $settings.Mode -eq 'Manual' -and -not $settings.Enforce) 'New settings must preserve brightness and default to manual'
$settings.Mode='Schedule'; $settings.DayLevel=3000; $settings.NightLevel=1500
foreach($case in @(@('07:59','Night',1500),@('08:00','Day',3000),@('17:59','Day',3000),@('18:00','Night',1500),@('00:00','Night',1500))) {
    $script:now=[DateTime]('2026-11-01T'+$case[0]+':00')
    $decision=Get-HdrBrightnessDecision $settings
    Assert ($decision.Phase -eq $case[1] -and $decision.Level -eq $case[2]) ('Wrong boundary: '+$case[0])
}
$settings.DayStart=1080; $settings.NightStart=480
$script:now=[DateTime]'2026-11-01T12:00:00'
Assert ((Get-HdrBrightnessDecision $settings).Phase -eq 'Night') 'Same-day night interval failed'
$settings.DayStart=480; $settings.NightStart=1080; $settings.Mode='NightLight'
$script:nightLight=$true
Assert ((Get-HdrBrightnessDecision $settings).Phase -eq 'Night') 'Night Light ON ignored'
$script:nightLight=$false
Assert ((Get-HdrBrightnessDecision $settings).Phase -eq 'Day') 'Night Light OFF must not be mistaken for unreadable'
$script:nightLight=$null
$decision=Get-HdrBrightnessDecision $settings
Assert ($decision.Phase -eq 'Day' -and $decision.Source -match 'fallback') 'Unreadable Night Light must disclose schedule fallback'
$settings.Mode='SunriseSunset'; $script:location=$null
$decision=Get-HdrBrightnessDecision $settings
Assert ($decision.Phase -eq 'Day' -and $decision.Source -match 'fallback: location') 'Missing location must disclose schedule fallback'
$script:location=[LocalHdrMenu.BrightnessLocationFix]::new(0,0,[DateTime]::UtcNow)
$script:now=([DateTime]'2026-03-20T12:00:00Z').ToLocalTime()
$decision=Get-HdrBrightnessDecision $settings
Assert ($decision.Phase -eq 'Day' -and $decision.Source -match 'Windows location' -and $decision.Level -eq 3000) 'Solar day must select Day brightness'
$script:now=([DateTime]'2026-03-20T00:00:00Z').ToLocalTime()
Assert ((Get-HdrBrightnessDecision $settings).Phase -eq 'Night') 'Solar night must select Night brightness'
Test-HdrBrightnessSettings $settings
$script:now=[DateTime]'2026-11-01T12:00:00'
$settings.NightStart=$settings.DayStart
$failed=$false; try { Test-HdrBrightnessSettings $settings } catch { $failed=$true }
Assert $failed 'Equal day/night start times must be rejected'
$settings.NightStart=1080
Assert ($null -eq [LocalHdrMenu.NightLightReader]::Decode([byte[]](1,2,3,4))) 'Unknown Night Light blob must not be guessed'
Assert ([LocalHdrMenu.NightLightReader]::Decode([byte[]](0x43,0x42,1,0,0x10,0,0,0,0,0,0,0)) -eq $true) 'Known active marker not decoded'
Assert ([LocalHdrMenu.NightLightReader]::Decode([byte[]](0x43,0x42,1,0,0,0,0,0,0,0,0,0)) -eq $false) 'Known inactive record not decoded'

$script:preferences=@{}; $script:calls=[Collections.Generic.List[object]]::new()
$a=[pscustomobject]@{Name='HDR A';DisplayId='QQ==';DevicePath='path-a';HdrEnabled=$true;HdrActive=$true;SdrWhiteLevel=2000}
$b=[pscustomobject]@{Name='HDR B';DisplayId='Qg==';DevicePath='path-b';HdrEnabled=$true;HdrActive=$true;SdrWhiteLevel=2200}
$key=Get-HdrBrightnessKey $a
$settings.Mode='Schedule'; $settings.Restore=$false
$script:preferences[$key]=$settings
Initialize-HdrTray
try {
    Update-HdrBrightness @($a,$b)
    Assert ($script:calls.Count -eq 0) 'Restoration off must leave startup brightness alone'
    $script:now=[DateTime]'2026-11-01T18:00:00'
    Update-HdrBrightness @($a,$b)
    Assert ($script:calls.Count -eq 1 -and $script:calls[0].Id -eq 'QQ==' -and $script:calls[0].Level -eq 1500) 'Night transition must affect only configured monitor'
    Complete-HdrBrightnessChange $true; $script:hdrTray.Pending=$null
    $a.SdrWhiteLevel=1900
    Update-HdrBrightness @($a,$b)
    Assert ($script:calls.Count -eq 1) 'Manual adjustment must survive until next phase when enforcement is off'
    $script:now=[DateTime]'2026-11-02T08:00:00'
    $script:hdrTray.UpdateProcess=[pscustomobject]@{HasExited=$false}
    Update-HdrBrightness @($a,$b)
    Assert ($script:calls.Count -eq 1 -and $script:hdrTray.BrightnessStates[$a.DisplayId].Due) 'Schedule must wait for app update'
    $script:hdrTray.UpdateProcess=$null
    Update-HdrBrightness @($a,$b)
    Assert ($script:calls.Count -eq 2 -and $script:calls[1].Level -eq 3000) 'Queued day transition did not resume'
    Complete-HdrBrightnessChange $true; $script:hdrTray.Pending=$null

    $settings.Enforce=$true
    Update-HdrBrightness @($a,$b)
    Assert ($script:calls.Count -eq 3) 'Explicit auto-restore did not correct a manual adjustment'
    Complete-HdrBrightnessChange $true; $script:hdrTray.Pending=$null
    Update-HdrBrightness @($a,$b)
    Assert ($script:calls.Count -eq 3) 'Auto-restore must wait between checks'
    $state=$script:hdrTray.BrightnessStates[$a.DisplayId]
    $state.NextCheck=[DateTime]::MinValue
    Update-HdrBrightness @($a,$b)
    Complete-HdrBrightnessChange $false; $script:hdrTray.Pending=$null
    Update-HdrBrightness @($a,$b)
    Assert ($script:calls.Count -eq 4) 'Failed enforcement ignored retry backoff'
    $state.Attempts=3; $script:hdrTray.BrightnessPending=@{DisplayId=$a.DisplayId;Automatic=$true}
    Complete-HdrBrightnessChange $false
    $state.NextCheck=$state.RetryAt=[DateTime]::MinValue
    Update-HdrBrightness @($a,$b)
    Assert ($script:calls.Count -eq 4 -and $state.Blocked) 'Auto-restore must stop after repeated failures'

    $script:now=[DateTime]'2026-11-02T18:00:00'
    $script:hdrTray.Scene=@{SuppressBrightness=@($key)}
    Update-HdrBrightness @($a,$b)
    $script:hdrTray.Scene=$null; $state.NextCheck=[DateTime]::MinValue
    Update-HdrBrightness @($a,$b)
    Assert ($script:calls.Count -eq 4 -and $state.Suppressed) 'Auto-restore must not undo an explicit preset'
    $script:now=[DateTime]'2026-11-03T08:00:00'
    Update-HdrBrightness @($a,$b)
    Assert ($script:calls.Count -eq 5 -and -not $state.Suppressed) 'Next phase must release preset suppression'
    Complete-HdrBrightnessChange $true; $script:hdrTray.Pending=$null
    $settings.Mode='NightLight'; $script:nightLight=$false
    Update-HdrBrightness @($a,$b)
    Complete-HdrBrightnessChange $true; $script:hdrTray.Pending=$null
    $count=$script:calls.Count
    $script:nightLight=$true
    Update-HdrBrightness @($a,$b)
    Assert ($script:calls.Count -eq $count+1 -and $script:calls[$count].Level -eq 1500) 'Live Night Light transition failed'
    Complete-HdrBrightnessChange $true; $script:hdrTray.Pending=$null
    $settings.Mode='SunriseSunset'
    $script:now=([DateTime]'2026-03-20T12:00:00Z').ToLocalTime()
    Update-HdrBrightness @($a,$b)
    Complete-HdrBrightnessChange $true; $script:hdrTray.Pending=$null
    $count=$script:calls.Count
    $script:now=([DateTime]'2026-03-20T23:00:00Z').ToLocalTime()
    Update-HdrBrightness @($a,$b)
    Assert ($script:calls.Count -eq $count+1 -and $script:calls[$count].Level -eq 1500) 'Solar transition after resume must use current sun phase'
    Complete-HdrBrightnessChange $true; $script:hdrTray.Pending=$null
    Write-Output 'PASS: Day/Night boundaries, overnight schedules, Night Light decoding/fallback, opt-in enforcement, manual precedence, bounded retries, preset priority, and pending updates.'
} finally {
    $script:hdrTray.Pending=$null; $script:hdrTray.UpdateProcess=$null; $script:hdrTray.Scene=$null
    Close-HdrTray
}
