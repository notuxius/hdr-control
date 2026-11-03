# Per-user profiles, automation ownership, launch requests, and diagnostic history.
# Loaded by HdrTray.ps1; importing this file never changes a display.
function Get-HdrProfilesPath { Join-Path $PSScriptRoot 'HdrProfiles.json' }
function New-HdrProfiles {
    [pscustomobject]@{Version=1;ExitPolicy='Sdr';Rules=@();Monitors=@();Presets=@();Bindings=@()}
}
function Test-HdrProfiles($Data) {
    if ($Data.Version -ne 1 -or $Data.ExitPolicy -notin @('Sdr','Restore')) { throw 'Invalid profiles version or exit behavior.' }
    foreach ($collection in @('Rules','Monitors','Presets','Bindings')) {
        if ($null -eq $Data.$collection -or @($Data.$collection).Count -gt 1000) { throw ('Invalid profiles: ' + $collection) }
    }
    $seen=@{}; $ids=@{}
    foreach ($rule in $Data.Rules) {
        $key=ConvertTo-HdrAppKey $rule.Executable
        if (-not $key -or $rule.Executable.StartsWith('!') -or $seen.ContainsKey($key) -or
            $rule.Enabled -isnot [bool] -or $rule.ExitPolicy -notin @('Default','Sdr','Restore') -or
            $rule.StartDelay -isnot [int] -or $rule.StartDelay -lt 0 -or $rule.StartDelay -gt 300 -or
            $rule.ExitDelay -isnot [int] -or $rule.ExitDelay -lt 2 -or $rule.ExitDelay -gt 300 -or
            $rule.Id -cnotmatch '^[a-f0-9]{32}$' -or $ids.ContainsKey([string]$rule.Id) -or $rule.Targets -isnot [array]) { throw 'Invalid or duplicate game rule.' }
        $seen[$key]=$true; $ids[$rule.Id]=$true
        if (@($rule.Targets | Select-Object -Unique).Count -ne @($rule.Targets).Count) { throw 'Duplicate game monitor.' }
        foreach ($key in @($rule.Targets)) { if ($key -cnotmatch '^[A-F0-9]{64}$') { throw 'Invalid monitor identity.' } }
        foreach ($field in @('ExactPath','LaunchPath','WorkingDirectory')) {
            if ($rule.$field -and (-not [IO.Path]::IsPathRooted($rule.$field) -or $rule.$field -match '[\x00-\x1f"]')) { throw ('Invalid ' + $field) }
        }
        if ($rule.Arguments -match '[\x00\r\n]') { throw 'Launch arguments must be one line.' }
        if ($rule.ExactPath -and (ConvertTo-HdrAppKey ([IO.Path]::GetFileName($rule.ExactPath))) -ne (ConvertTo-HdrAppKey $rule.Executable)) { throw 'Exact path must name the watched executable.' }
    }
    $seen=@{}
    foreach ($monitor in $Data.Monitors) {
        if ($monitor.Key -cnotmatch '^[A-F0-9]{64}$' -or $seen.ContainsKey($monitor.Key) -or
            $monitor.Alias -isnot [string] -or $monitor.Alias.Length -gt 80 -or $monitor.Alias -match '[\x00-\x1f]') { throw 'Invalid monitor alias.' }
        $seen[$monitor.Key]=$true
    }
    $seen=@{}
    foreach ($preset in $Data.Presets) {
        if ($preset.Id -cnotmatch '^[a-f0-9]{32}$' -or $seen.ContainsKey($preset.Id) -or
            [string]::IsNullOrWhiteSpace($preset.Name) -or $preset.Name.Length -gt 80 -or @($preset.Displays).Count -eq 0) { throw 'Invalid preset.' }
        $seen[$preset.Id]=$true; $targets=@{}
        foreach ($target in $preset.Displays) {
            if ($target.Key -cnotmatch '^[A-F0-9]{64}$' -or $targets.ContainsKey($target.Key) -or $target.Enabled -isnot [bool] -or
                ($null -ne $target.Level -and ($target.Level -isnot [int] -or $target.Level -lt 1000 -or $target.Level -gt 6000 -or -not $target.Enabled))) { throw 'Invalid preset display.' }
            $targets[$target.Key]=$true
        }
    }
    $seen=@{}; $ids=@{}
    foreach ($binding in $Data.Bindings) {
        if ($binding.Id -cnotmatch '^[a-f0-9]{32}$' -or $binding.Action -notin @('On','Off','Toggle','Preset') -or
            $binding.Key -isnot [int] -or $binding.Key -lt 48 -or $binding.Key -gt 123 -or
            $binding.Modifiers -isnot [int] -or $binding.Modifiers -lt 1 -or $binding.Modifiers -gt 15 -or
            $binding.Targets -isnot [array] -or $ids.ContainsKey([string]$binding.Id)) { throw 'Invalid keyboard shortcut.' }
        $ids[$binding.Id]=$true
        if (@($binding.Targets | Select-Object -Unique).Count -ne @($binding.Targets).Count) { throw 'Duplicate shortcut monitor.' }
        $chord='{0}:{1}' -f $binding.Modifiers,$binding.Key
        if ($seen.ContainsKey($chord)) { throw 'Two shortcuts use the same keys.' }; $seen[$chord]=$true
        foreach ($key in @($binding.Targets)) { if ($key -cnotmatch '^[A-F0-9]{64}$') { throw 'Invalid shortcut monitor.' } }
        if ($binding.Action -eq 'Preset' -and @($Data.Presets | Where-Object Id -eq $binding.PresetId).Count -ne 1) { throw 'A shortcut refers to a missing preset.' }
    }
}
function Read-HdrProfiles {
    $path=Get-HdrProfilesPath
    if (-not [IO.File]::Exists($path)) { return New-HdrProfiles }
    if ([IO.FileInfo]::new($path).Length -gt 1MB) { throw 'Profiles file is too large.' }
    $data=[IO.File]::ReadAllText($path) | ConvertFrom-Json -ErrorAction Stop
    Test-HdrProfiles $data
    return $data
}
function Save-HdrProfiles($Data) {
    Test-HdrProfiles $Data
    Write-HdrAtomicText (Get-HdrProfilesPath) ($Data | ConvertTo-Json -Depth 12)
}
function Write-HdrAtomicText([string]$Path,[string]$Text) {
    if ([Text.Encoding]::UTF8.GetByteCount($Text) -gt 1MB) { throw 'Settings file is too large.' }
    $temp=$Path+'.'+[Guid]::NewGuid().ToString('N')+'.tmp'
    try {
        [IO.File]::WriteAllText($temp,$Text,[Text.UTF8Encoding]::new($false))
        if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temp,$Path,[NullString]::Value) }
        else { [IO.File]::Move($temp,$Path) }
    } finally { if ([IO.File]::Exists($temp)) { [IO.File]::Delete($temp) } }
}
function New-HdrGameRule([string]$Executable) {
    [pscustomobject]@{Id=[Guid]::NewGuid().ToString('N');Executable=$Executable;Enabled=$true;ExactPath='';
        Targets=@();StartDelay=0;ExitDelay=2;ExitPolicy='Default';LaunchPath='';Arguments='';WorkingDirectory=''}
}
function Get-HdrMonitorKey($Display) {
    $key=Get-HdrBrightnessKey $Display
    if ($key) { return $key }
    # Missing hardware paths can be used during this connection, never persisted.
    if ($Display.DisplayId) { return 'session:'+$Display.DisplayId }
    return ''
}
function Get-HdrMonitorName($Display,$Profiles) {
    $key=Get-HdrBrightnessKey $Display
    $alias=@($Profiles.Monitors | Where-Object Key -eq $key)
    if ($key -and $alias.Count -eq 1 -and $alias[0].Alias) { return $alias[0].Alias }
    return $Display.Name
}
function Write-HdrDiagnostic([string]$Category,[string]$Message) {
    try {
        $line='{0} [{1}] {2}' -f [DateTime]::UtcNow.ToString('o'),$Category,($Message -replace '[\r\n]+',' ')
        $path=Join-Path $PSScriptRoot 'HdrDiagnostics.log'
        if ([IO.File]::Exists($path) -and [IO.FileInfo]::new($path).Length -gt 256KB) {
            [IO.File]::Copy($path,$path+'.previous',$true); [IO.File]::WriteAllText($path,'')
        }
        [IO.File]::AppendAllText($path,$line+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
    } catch { } # A full disk must not interrupt display controls.
}
function Set-HdrDecision([string]$Text) {
    if ($script:hdrTray.Decision -ne $Text) { Write-HdrDiagnostic 'AUTO' $Text }
    $script:hdrTray.Decision=$Text
    if ($script:hdrTray.Status.Tag) { $script:hdrTray.Status.SetCombinedStatus($script:hdrTray.Status.Tag, $Text) }
}
function Get-HdrDiagnostics {
    $lines=@('HDR Control '+(Get-HdrInstalledVersion), 'Windows '+[Environment]::OSVersion.VersionString,
        'PowerShell '+$PSVersionTable.PSVersion, 'Automation: '+$script:hdrTray.Decision)
    try {
        foreach ($d in @([LocalHdrMenu.DisplayApi]::Read())) {
            $lines+=('{0}: supported={1}, enabled={2}, active={3}, API={4}, SDR level={5}' -f $d.Name,$d.HdrSupported,$d.HdrEnabled,$d.HdrActive,$d.Api,$d.SdrWhiteLevel)
        }
    } catch { $lines+='Display read error: '+$_.Exception.Message }
    $path=Join-Path $PSScriptRoot 'HdrDiagnostics.log'
    if ([IO.File]::Exists($path)) { $lines+=@('','Recent events:'); $lines+=@(Get-Content -LiteralPath $path -Tail 80) }
    return ($lines -join [Environment]::NewLine)
}
function New-HdrPolicyState {
    @{Active=$false;SuppressOn=$false;LastPoll=[DateTime]::MinValue;Sessions=@{};Displays=@{};ReadWarning=$false;DetectionWriteWarning=$false}
}
function Release-HdrAutomationDisplay([string]$DisplayId) {
    $state=$script:hdrTray.Automation
    if ($null -eq $state.Displays) { return }
    foreach ($entry in $state.Displays.Values) {
        if (-not $DisplayId -or $entry.DisplayId -ceq $DisplayId) { $entry.Released=$true }
    }
    if ($state.Active) { $state.SuppressOn=$true; Set-HdrDecision 'Manual override active' }
}
function Test-HdrExactProcess([string]$Name,[string]$Path) {
    if (-not $Path) { return $true }
    $unreadable=$false
    foreach ($process in @(Get-Process -Name $Name -ErrorAction SilentlyContinue)) {
        try {
            if ($process.SessionId -eq [Diagnostics.Process]::GetCurrentProcess().SessionId) {
                if ($process.Path -ieq $Path) { return $true }
                if (-not $process.Path) { $unreadable=$true }
            }
        } catch { $unreadable=$true } finally { $process.Dispose() }
    }
    if ($unreadable) { throw 'A matching process path could not be read; preserving HDR until the next successful scan.' }
    return $false
}
function Update-HdrPolicy($Displays) {
    $state=$script:hdrTray.Automation; $now=Get-HdrAutomationTime
    if ($null -eq $script:hdrTray.Launches) { $script:hdrTray.Launches=@{} }
    if (($now-$state.LastPoll).TotalSeconds -lt 2) { return }; $state.LastPoll=$now
    $automatic=Get-HdrAutomationPreference 'AutomaticHdr'
    if (-not $automatic -and -not $script:hdrTray.Launches.Count -and -not $state.Active) { Set-HdrDecision 'Automatic HDR is paused'; return }
    try {
        $profiles=Read-HdrProfiles; $lists=Get-HdrAppListState
        $running=@{}; foreach ($name in @(Get-HdrRunningAppNames)) { $key=ConvertTo-HdrAppKey $name; if ($key) { $running[$key]=$name } }
        $rules=@{}; foreach ($rule in $profiles.Rules) { $rules[(ConvertTo-HdrAppKey $rule.Executable)]=$rule }
        $matches=@{}
        if ($automatic) {
            foreach ($key in $lists.Effective.Keys) {
                if ($running.ContainsKey($key)) {
                    $rule=$rules[$key]; if ($null -eq $rule) { $rule=New-HdrGameRule ($key+'.exe') }
                    if (Test-HdrExactProcess $key $rule.ExactPath) { $matches[$key]=$rule }
                }
            }
        }
        foreach ($launch in @($script:hdrTray.Launches.Values)) {
            $key=ConvertTo-HdrAppKey $launch.Rule.Executable
            if (-not $launch.Started -or $now -lt $launch.WaitUntil -or $running.ContainsKey($key)) {
                $matches[$key]=$launch.Rule
                if ($launch.Started -and $running.ContainsKey($key)) { $launch.WaitUntil=$now; $launch.Seen=$true }
            } else {
                if (-not $launch.Seen) { Write-HdrDiagnostic 'LAUNCH' ('No matching game appeared within 45 seconds: '+$launch.Rule.Executable) }
                $script:hdrTray.Launches.Remove($launch.Rule.Id)
            }
        }
        $state.ReadWarning=$false
        $known=@($matches.Keys | Where-Object { $automatic -and $lists.Defaults.ContainsKey($_) -and $lists.Effective.ContainsKey($_) } | ForEach-Object { $running[$_] } | Where-Object { $_ })
        if ($known.Count) {
            try { Save-HdrDetectedApps $known $lists.Defaults; $state.DetectionWriteWarning=$false }
            catch { if (-not $state.DetectionWriteWarning) {
                Write-HdrDiagnostic 'HISTORY' $_.Exception.Message; $state.DetectionWriteWarning=$true
                if ($null -ne $script:hdrTray.Icon) { Show-HdrNotification 'A known game was detected, but its history could not be saved.' }
            } }
        }
    } catch {
        foreach ($session in $state.Sessions.Values) { $session.EmptySince=$null }
        Set-HdrDecision 'Automation waiting: app list or process scan failed'
        if (-not $state.ReadWarning) {
            Write-HdrDiagnostic 'ERROR' $_.Exception.Message; $state.ReadWarning=$true
            if ($null -ne $script:hdrTray.Icon) { Show-HdrNotification 'Automatic HDR could not read the app list or running apps. It will retry automatically.' }
        }
        return
    }
    foreach ($key in $matches.Keys) {
        if (-not $state.Sessions.ContainsKey($key)) { $state.Sessions[$key]=@{First=$now;EmptySince=$null;Started=$false;Notified=$false;Rule=$matches[$key]} }
        $state.Sessions[$key].EmptySince=$null; $state.Sessions[$key].Rule=$matches[$key]
        if ($running.ContainsKey($key)) { $state.Sessions[$key].SeenRunning=$true }
    }
    foreach ($key in @($state.Sessions.Keys)) {
        $s=$state.Sessions[$key]
        if (-not $matches.ContainsKey($key)) {
            if ($null -eq $s.EmptySince) { $s.EmptySince=$now }
            if (($now-$s.EmptySince).TotalSeconds -ge $s.Rule.ExitDelay) {
                $s.Exited=$s.SeenRunning -and -not $running.ContainsKey($key)
                $state.Sessions.Remove($key)
            }
        }
    }
    $demand=@{}; $present=@{}
    foreach ($d in $Displays) {
        $key=Get-HdrMonitorKey $d; if (-not $key) { continue }
        if ($present.ContainsKey($key)) { $present[$key]=$null } else { $present[$key]=$d }
    }
    foreach ($session in $state.Sessions.Values) {
        if (($now-$session.First).TotalSeconds -lt $session.Rule.StartDelay) { continue }
        if ($null -ne $session.EmptySince -and -not $session.Started) { continue }
        $session.Started=$true
        foreach ($key in $present.Keys) {
            $d=$present[$key]
            if ($null -eq $d -or -not $d.HdrSupported -or (@($session.Rule.Targets).Count -and $key -notin $session.Rule.Targets)) { continue }
            if (-not $demand.ContainsKey($key)) { $demand[$key]=@() }
            $demand[$key]+=,$session
        }
    }
    foreach ($key in $demand.Keys) {
        $d=$present[$key]
        if (-not $state.Displays.ContainsKey($key)) {
            $state.Displays[$key]=@{DisplayId=$d.DisplayId;Before=[bool]$d.HdrEnabled;Expected=[bool]$d.HdrEnabled;
                Owned=$false;Released=$false;RetryAt=[DateTime]::MinValue;Pending=$false;ExitPolicy='Restore';Closing=$false}
        }
        $entry=$state.Displays[$key]; $entry.Closing=$false
        # Retain the last sessions demanding this monitor through exit retries.
        $entry.LastSessions=$demand[$key]
        foreach ($session in $demand[$key]) {
            $rule=$session.Rule
            $policy=if ($rule.ExitPolicy -eq 'Default') { $profiles.ExitPolicy } else { $rule.ExitPolicy }
            if ($policy -eq 'Sdr') { $entry.ExitPolicy='Sdr' }
        }
    }
    $state.Active=$state.Sessions.Count -gt 0 -or $state.Displays.Count -gt 0
    $busy=$null -ne $script:hdrTray.Pending -or $null -ne $script:hdrTray.UpdateProcess -or $null -ne $script:hdrTray.Scene
    $decision=if ($state.Sessions.Count) { 'Enabled for '+(($state.Sessions.Values | ForEach-Object { $_.Rule.Executable } | Sort-Object -Unique) -join ', ') } else { 'Automatic HDR: idle' }
    if (@($state.Sessions.Values | Where-Object { $null -ne $_.EmptySince }).Count) { $decision='Waiting for game exit delay' }
    if ($state.Sessions.Count -and -not $demand.Count) { $decision='Waiting for startup delay or selected monitor' }
    elseif (@($demand.Keys | Where-Object { -not $present[$_].HdrEnabled }).Count) { $decision='Preparing HDR for game session' }
    foreach ($key in @($state.Displays.Keys)) {
        $entry=$state.Displays[$key]; $d=$present[$key]; $wanted=$demand.ContainsKey($key)
        if ($null -eq $d) { if (-not $wanted -and -not $state.Sessions.Count) { $state.Displays.Remove($key) }; continue }
        $entry.DisplayId=$d.DisplayId
        if ($entry.Released) { $decision='Manual override active'; if (-not $wanted) { $state.Displays.Remove($key) }; continue }
        if ($busy) { continue }
        # Only a successful command establishes ownership; mismatches during retries
        # are failures, not evidence of an external manual change.
        if (-not $entry.Pending -and $entry.RetryAt -eq [DateTime]::MinValue -and $d.HdrEnabled -ne $entry.Expected) {
            $entry.Released=$true; $decision='Manual override active'; continue
        }
        if ($entry.Pending) { continue }
        $target=if ($wanted) { $true } elseif ($entry.ExitPolicy -eq 'Sdr') { $false } else { $entry.Before }
        if (-not $wanted -and $entry.ExitPolicy -eq 'Restore' -and -not $entry.Owned) { $state.Displays.Remove($key); continue }
        if ($d.HdrEnabled -eq $target) {
            $entry.Expected=[bool]$target; $entry.RetryAt=[DateTime]::MinValue
            if (-not $wanted) { $state.Displays.Remove($key) }
            continue
        }
        if ($now -lt $entry.RetryAt) { $decision='Waiting to retry display change'; continue }
        $entry.RetryAt=$now.AddSeconds(30); $entry.Pending=$true; $entry.Closing=-not $wanted
        # Explicit launches can demand HDR before the game process exists.
        $notifySessions=@(if ($automatic -and $wanted) {
            foreach ($session in $demand[$key]) {
                $gameKey=ConvertTo-HdrAppKey $session.Rule.Executable
                if (-not $session.Notified -and $running.ContainsKey($gameKey) -and $lists.Effective.ContainsKey($gameKey)) { $session }
            }
        } elseif (-not $wanted -and -not $target) {
            $entry.LastSessions | Where-Object { $_.Exited -and -not $_.ExitNotified }
        })
        $script:hdrTray.PolicyPending=@{Key=$key;Target=[bool]$target;Entry=$entry;NotifySessions=$notifySessions}
        Start-HdrChange -NextAction $(if ($target) {'On'} else {'Off'}) -DisplayId $d.DisplayId -Automatic
        if ($null -eq $script:hdrTray.Pending) { Complete-HdrPolicyCommand $false }
        $busy=$true
    }
    $state.Active=$state.Sessions.Count -gt 0 -or $state.Displays.Count -gt 0
    Set-HdrDecision $decision
}
function Complete-HdrPolicyCommand([bool]$Success) {
    $op=$script:hdrTray.PolicyPending; $script:hdrTray.PolicyPending=$null
    if ($null -eq $op) { return }
    $entry=$script:hdrTray.Automation.Displays[$op.Key]
    if ($null -eq $entry -or -not [object]::ReferenceEquals($entry,$op.Entry)) { return }
    $entry.Pending=$false
    if ($Success) { $entry.Expected=$op.Target; $entry.Owned=$true; $entry.RetryAt=[DateTime]::MinValue }
    if ($Success -and -not $entry.Released -and $op.NotifySessions.Count) {
        $games=($op.NotifySessions | ForEach-Object { $_.Rule.Executable } | Sort-Object -Unique) -join ', '
        if ($op.Target) {
            foreach ($session in $op.NotifySessions) { $session.Notified=$true }
            Show-HdrNotification ('HDR turned on automatically for '+$games+'.')
        } else {
            foreach ($session in $op.NotifySessions) { $session.ExitNotified=$true }
            Show-HdrNotification ('HDR turned off automatically after '+$games+' exited.')
        }
    }
    Write-HdrDiagnostic 'DISPLAY' ('Automatic change '+$op.Target+' success='+$Success)
}

function Start-HdrScene($Targets,[string]$Name) {
    if ($null -ne $script:hdrTray.Pending -or $null -ne $script:hdrTray.UpdateProcess -or $null -ne $script:hdrTray.Scene) { throw 'Wait for the current display change or update.' }
    $displays=@([LocalHdrMenu.DisplayApi]::Read()); $steps=@(); $undo=@()
    foreach ($target in $Targets) {
        $found=@($displays | Where-Object { (Get-HdrMonitorKey $_) -ceq $target.Key })
        if ($found.Count -ne 1 -or -not $found[0].HdrSupported) { throw 'A selected monitor is disconnected, ambiguous, or does not support HDR. Nothing was changed.' }
        $d=$found[0]
        $steps+=@{Key=$target.Key;Action=$(if ($target.Enabled) {'On'} else {'Off'});Level=$null}
        if ($null -ne $target.Level) { $steps+=@{Key=$target.Key;Action='Brightness';Level=$target.Level} }
        $undo+=@{Key=$target.Key;Action=$(if ($d.HdrEnabled) {'On'} else {'Off'});Level=$null}
        if ($d.HdrEnabled -and $null -ne $d.SdrWhiteLevel) { $undo+=@{Key=$target.Key;Action='Brightness';Level=$d.SdrWhiteLevel} }
    }
    if (-not $steps.Count) { throw 'Select at least one HDR-capable monitor.' }
    foreach ($target in $Targets) {
        $d=@($displays | Where-Object { (Get-HdrMonitorKey $_) -ceq $target.Key })[0]
        Release-HdrAutomationDisplay $d.DisplayId
    }
    $script:hdrTray.Scene=@{Name=$Name;Steps=$steps;Undo=$undo;Index=0;Pending=$false;Rollback=$false;Error='';SuppressBrightness=@($Targets | ForEach-Object Key)}
    Write-HdrDiagnostic 'PRESET' ('Applying '+$Name)
}
function Complete-HdrSceneStep([bool]$Success) {
    $scene=$script:hdrTray.Scene
    if ($null -eq $scene -or -not $scene.Pending) { return }
    $scene.Pending=$false
    if (-not $Success -and -not $scene.Rollback) {
        $scene.Rollback=$true; $scene.Steps=$scene.Undo; $scene.Index=0
        $scene.Error='A display change failed. Attempting to restore the previous settings.'
        Write-HdrDiagnostic 'PRESET' $scene.Error
    } else {
        if (-not $Success) { $scene.Error='Some previous settings could not be restored. Check connected displays.'; Write-HdrDiagnostic 'ERROR' $scene.Error }
        $scene.Index++
    }
}
function Update-HdrScene($Displays) {
    $scene=$script:hdrTray.Scene
    if ($null -eq $scene -or $null -ne $script:hdrTray.Pending -or $null -ne $script:hdrTray.UpdateProcess) { return }
    if ($scene.Index -ge $scene.Steps.Count) {
        Write-HdrDiagnostic 'PRESET' ($scene.Name+$(if ($scene.Rollback) {' failed; recovery finished'} else {' applied'}))
        $script:hdrTray.Scene=$null
        if ($scene.Error) { [void](Show-HdrMessage $scene.Error) }
        return
    }
    $step=$scene.Steps[$scene.Index]; $scene.Pending=$true
    try {
        $found=@($Displays | Where-Object { (Get-HdrMonitorKey $_) -ceq $step.Key })
        if ($found.Count -ne 1) { throw 'Selected monitor is disconnected or ambiguous.' }
        $d=$found[0]
        if ($step.Action -eq 'Brightness') {
            if ($d.SdrWhiteLevel -eq $step.Level) { Complete-HdrSceneStep $true; return }
            if (-not (Start-HdrBrightnessChange $d ([uint32]$step.Level) $false -Automatic)) { throw 'Display controls are busy.' }
        } else {
            if ($d.HdrEnabled -eq ($step.Action -eq 'On')) { Complete-HdrSceneStep $true; return }
            Start-HdrChange $step.Action $d.DisplayId -Automatic
            if ($null -eq $script:hdrTray.Pending) { throw 'Display command did not start.' }
        }
    } catch { Write-HdrDiagnostic 'ERROR' $_.Exception.Message; Complete-HdrSceneStep $false }
}
function Invoke-HdrBinding($Binding) {
    try {
        $profiles=Read-HdrProfiles
        if ($Binding.Action -eq 'Preset') {
            $preset=@($profiles.Presets | Where-Object Id -eq $Binding.PresetId)
            if ($preset.Count -ne 1) { throw 'This preset no longer exists.' }
            Start-HdrScene $preset[0].Displays $preset[0].Name
        } else {
            $selected=@([LocalHdrMenu.DisplayApi]::Read() | Where-Object { $_.HdrSupported -and (-not @($Binding.Targets).Count -or (Get-HdrMonitorKey $_) -in $Binding.Targets) })
            if (@($Binding.Targets).Count -and $selected.Count -ne @($Binding.Targets | Select-Object -Unique).Count) { throw 'A shortcut monitor is disconnected.' }
            $enable=if ($Binding.Action -eq 'Toggle') { @($selected | Where-Object { -not $_.HdrEnabled }).Count -gt 0 } else { $Binding.Action -eq 'On' }
            $targets=@($selected | ForEach-Object { @{Key=(Get-HdrMonitorKey $_);Enabled=$enable;Level=$null} })
            Start-HdrScene $targets ('Shortcut '+$Binding.Action)
        }
    } catch { Write-HdrDiagnostic 'SHORTCUT' $_.Exception.Message; [void](Show-HdrMessage $_.Exception.Message) }
}
function Register-HdrBindings {
    $hostWindow=$script:hdrTray.EventWindow
    if ($null -eq $hostWindow) { return }
    $profiles=Read-HdrProfiles; $hostWindow.ClearHotkeys(); $script:hdrTray.HotkeyBindings=@{}
    $failures=@(); $index=1
    foreach ($binding in $profiles.Bindings) {
        if ($hostWindow.Bind($index,[uint32]$binding.Modifiers,[uint32]$binding.Key)) { $script:hdrTray.HotkeyBindings[$index]=$binding }
        else { $failures+=('{0}+{1} is in use or unavailable' -f ([LocalHdrMenu.ShortcutForm]::ModifierText($binding.Modifiers)),[Windows.Forms.Keys]$binding.Key) }
        $index++
    }
    if ($failures.Count) { Write-HdrDiagnostic 'SHORTCUT' ($failures -join '; '); [void](Show-HdrMessage ($failures -join "`r`n")) }
}
function Get-HdrRequestDirectory {
    # Session-specific, under the existing user-writable runtime directory.
    Join-Path $PSScriptRoot ('requests-'+[Diagnostics.Process]::GetCurrentProcess().SessionId)
}
function Publish-HdrManualChange([string]$DisplayId) {
    $directory=Get-HdrRequestDirectory; [void][IO.Directory]::CreateDirectory($directory)
    Write-HdrAtomicText (Join-Path $directory ([Guid]::NewGuid().ToString('N')+'.json')) (
        @{Kind='Manual';DisplayId=$DisplayId;CreatedUtc=[DateTime]::UtcNow.ToString('o')} | ConvertTo-Json -Compress
    )
}
function Submit-HdrLaunch([string]$Id) {
    if ($Id -cnotmatch '^[a-f0-9]{32}$') { throw 'Invalid launch shortcut.' }
    $profiles=Read-HdrProfiles; $rule=@($profiles.Rules | Where-Object Id -eq $Id)
    if ($rule.Count -ne 1 -or -not $rule[0].LaunchPath -or -not $rule[0].Enabled) { throw 'The launch rule is missing, disabled, or has no program.' }
    $directory=Get-HdrRequestDirectory; [IO.Directory]::CreateDirectory($directory) | Out-Null
    $request=Join-Path $directory ([Guid]::NewGuid().ToString('N')+'.json')
    Write-HdrAtomicText $request (@{Id=$Id;CreatedUtc=[DateTime]::UtcNow.ToString('o')} | ConvertTo-Json -Compress)
    # A second Watch process exits through the existing single-instance guard.
    Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList (
        '-NoProfile -NonInteractive -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" -Action Watch' -f (Join-Path $PSScriptRoot 'HdrSdrMenu.ps1')
    ) -WindowStyle Hidden | Out-Null
}
function Receive-HdrLaunchRequests([switch]$UpdatesOnly) {
    $directory=Get-HdrRequestDirectory
    if (-not [IO.Directory]::Exists($directory)) { return }
    $filter = if ($UpdatesOnly) { 'update-*.json' } else { '*.json' }
    foreach ($file in @(Get-ChildItem -LiteralPath $directory -Filter $filter -File | Select-Object -First 10)) {
        try {
            if ($file.Length -gt 4096) { throw 'Oversized launch request.' }
            $request=[IO.File]::ReadAllText($file.FullName) | ConvertFrom-Json -ErrorAction Stop
            $created=[DateTime]::Parse($request.CreatedUtc).ToUniversalTime()
            if ([Math]::Abs(([DateTime]::UtcNow-$created).TotalSeconds) -gt 60) { throw 'Launch request expired.' }
            if ($request.Kind -eq 'InstallUpdate') {
                Install-HdrNotificationUpdate $request.Id
                continue
            }
            if ($request.Kind -eq 'Manual') {
                if ($request.DisplayId -and $request.DisplayId -cnotmatch '^[A-Za-z0-9+/=]+$') { throw 'Invalid manual target.' }
                Release-HdrAutomationDisplay ([string]$request.DisplayId)
                if ($null -ne $script:hdrTray.Scene) {
                    Write-HdrDiagnostic 'PRESET' 'Remaining preset steps cancelled by a desktop or command-line change'
                    $script:hdrTray.Scene=$null
                }
                Write-HdrDiagnostic 'MANUAL' 'Desktop or command-line override received'
                continue
            }
            $profiles=Read-HdrProfiles; $rule=@($profiles.Rules | Where-Object Id -ceq $request.Id)
            if ($rule.Count -ne 1 -or -not $rule[0].Enabled) { throw 'Launch rule is missing or disabled.' }
            Start-HdrLaunch $rule[0]
        } catch { Write-HdrDiagnostic 'LAUNCH' $_.Exception.Message }
        finally { [IO.File]::Delete($file.FullName) }
    }
}
function Start-HdrLaunch($Rule) {
    if ($script:hdrTray.Launches.ContainsKey($Rule.Id)) { throw 'This game already has an active launch session.' }
    if ($null -ne $script:hdrTray.Scene -or $null -ne $script:hdrTray.UpdateProcess) { throw 'Wait for the preset or update to finish.' }
    if (-not [IO.File]::Exists($Rule.LaunchPath) -or [IO.Path]::GetExtension($Rule.LaunchPath) -ine '.exe') { throw 'Choose an existing .exe to launch.' }
    if ($Rule.WorkingDirectory -and -not [IO.Directory]::Exists($Rule.WorkingDirectory)) { throw 'The working directory does not exist.' }
    $displays=@([LocalHdrMenu.DisplayApi]::Read() | Where-Object HdrSupported)
    $targets=@($displays | Where-Object { -not @($Rule.Targets).Count -or (Get-HdrMonitorKey $_) -in $Rule.Targets })
    if (-not $targets.Count -or (@($Rule.Targets).Count -and $targets.Count -ne $Rule.Targets.Count)) { throw 'A selected HDR monitor is disconnected.' }
    $copy=$Rule | ConvertTo-Json -Depth 6 | ConvertFrom-Json
    $copy.StartDelay=0
    # An explicit launch is a new manual request to enable its selected displays.
    foreach ($d in $targets) {
        $key=Get-HdrMonitorKey $d
        if ($script:hdrTray.Automation.Displays.ContainsKey($key) -and $script:hdrTray.Automation.Displays[$key].Released) {
            $script:hdrTray.Automation.Displays.Remove($key)
        }
    }
    $script:hdrTray.Launches[$Rule.Id]=@{Rule=$copy;Started=$false;Seen=$false;WaitUntil=[DateTime]::MaxValue;Deadline=(Get-HdrAutomationTime).AddSeconds(45);Targets=@($targets | ForEach-Object { Get-HdrMonitorKey $_ })}
    $script:hdrTray.Automation.LastPoll=[DateTime]::MinValue
    Write-HdrDiagnostic 'LAUNCH' ('Preparing HDR for '+$Rule.Executable)
}
function Update-HdrLaunches($Displays) {
    foreach ($launch in @($script:hdrTray.Launches.Values)) {
        if ($launch.Started) { continue }
        try {
            if ((Get-HdrAutomationTime) -gt $launch.Deadline) { throw 'HDR could not be prepared within 45 seconds; game was not started.' }
            if ($null -ne $script:hdrTray.Pending -or $null -ne $script:hdrTray.UpdateProcess -or $null -ne $script:hdrTray.Scene) { continue }
            $ready=$true
            foreach ($key in $launch.Targets) {
                $found=@($Displays | Where-Object { (Get-HdrMonitorKey $_) -ceq $key })
                if ($found.Count -ne 1 -or -not $found[0].HdrEnabled) { $ready=$false }
                $entry=$script:hdrTray.Automation.Displays[$key]
                if ($null -eq $entry -or $entry.Released) { $ready=$false }
            }
            if (-not $ready) { continue }
            $rule=$launch.Rule
            $arguments=@{FilePath=$rule.LaunchPath;WorkingDirectory=$(if ($rule.WorkingDirectory) {$rule.WorkingDirectory} else {Split-Path $rule.LaunchPath});PassThru=$true;ErrorAction='Stop'}
            if ($rule.Arguments) { $arguments.ArgumentList=$rule.Arguments }
            # This is the visible program explicitly requested by the user.
            $process=Start-Process @arguments
            $process.Dispose()
            $launch.Started=$true; $launch.WaitUntil=(Get-HdrAutomationTime).AddSeconds(45)
            Write-HdrDiagnostic 'LAUNCH' ('Started '+$rule.Executable+' after HDR verification')
        } catch {
            $script:hdrTray.Launches.Remove($launch.Rule.Id)
            Write-HdrDiagnostic 'LAUNCH' $_.Exception.Message
            Show-HdrNotification ('Launch with HDR: ' + $_.Exception.Message)
        }
    }
}
function New-HdrLaunchShortcut($Rule,[string]$Path) {
    if (-not $Rule.LaunchPath) { throw 'Choose and save a program before creating a shortcut.' }
    $shell=New-Object -ComObject WScript.Shell
    try {
        $shortcut=$shell.CreateShortcut($Path)
        $shortcut.TargetPath=Join-Path $env:SystemRoot 'System32\wscript.exe'
        $shortcut.Arguments='//NoLogo "{0}" Launch {1}' -f (Join-Path $PSScriptRoot 'Toggle-HdrSdr.vbs'),$Rule.Id
        $shortcut.WorkingDirectory=$PSScriptRoot; $shortcut.Description='Enable selected HDR displays, verify, then launch '+$Rule.Executable
        $shortcut.IconLocation=$Rule.LaunchPath+',0'; $shortcut.Save()
    } finally { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell) }
}

function Get-HdrEditorMonitors($Profiles,[string[]]$SavedKeys=@()) {
    $seen=@{}
    foreach ($d in @([LocalHdrMenu.DisplayApi]::Read())) {
        $key=Get-HdrBrightnessKey $d
        if (-not $key -or -not $d.HdrSupported) { continue }
        if ($seen.ContainsKey($key)) { throw 'Two monitors have the same identity; reconnect them before editing profiles.' }
        $seen[$key]=$true
        [pscustomobject]@{Key=$key;Name=(Get-HdrMonitorName $d $Profiles);Display=$d}
    }
    foreach ($key in @($SavedKeys | Select-Object -Unique)) {
        if (-not $seen.ContainsKey($key)) {
            $alias=@($Profiles.Monitors | Where-Object Key -eq $key)
            $name=if ($alias.Count -eq 1 -and $alias[0].Alias) { $alias[0].Alias } else { 'Monitor '+$key.Substring(0,8) }
            [pscustomobject]@{Key=$key;Name=$name+' (disconnected)';Display=$null}
        }
    }
}
function Confirm-HdrSettingsSave([Action]$Confirmation=$script:hdrTray.SettingsWindow.SaveConfirmation) {
    if ($null -ne $Confirmation) { $Confirmation.Invoke() }
}
function Show-HdrGameRule([string]$Executable='', [string]$LaunchPath='', [Action]$Confirmation=$script:hdrTray.SettingsWindow.SaveConfirmation) {
    $form=$null
    try {
        $profiles=Read-HdrProfiles
        $existing=@($profiles.Rules | Where-Object { (ConvertTo-HdrAppKey $_.Executable) -eq (ConvertTo-HdrAppKey $Executable) })
        $rule=if ($existing.Count) { $existing[0] } else { New-HdrGameRule $Executable }
        if (-not $existing.Count -and $Executable) { $rule.Enabled=-not (Get-HdrAppListState -IncludeDisabledDefaults).Excluded.ContainsKey((ConvertTo-HdrAppKey $Executable)) }
        if ($LaunchPath -and -not $rule.LaunchPath) { $rule.LaunchPath=$LaunchPath }
        $form=[LocalHdrMenu.GameRuleForm]::new()
        $form.Executable.Text=$rule.Executable; $form.ExactPath.Text=$rule.ExactPath; $form.RuleEnabled.Checked=$rule.Enabled
        $form.StartDelay.Value=$rule.StartDelay; $form.ExitDelay.Value=$rule.ExitDelay
        $form.ExitPolicy.SelectedIndex=@('Default','Sdr','Restore').IndexOf($rule.ExitPolicy)
        $form.LaunchPath.Text=$rule.LaunchPath; $form.Arguments.Text=$rule.Arguments; $form.WorkingDirectory.Text=$rule.WorkingDirectory
        foreach ($m in @(Get-HdrEditorMonitors $profiles $rule.Targets)) { $form.AddTarget($m.Key,$m.Name,($m.Key -in $rule.Targets)) }
        while ($form.ShowDialog($script:hdrTray.SettingsWindow) -eq [Windows.Forms.DialogResult]::OK) {
            try {
                $rule.Executable=$form.Executable.Text.Trim(); $rule.Enabled=$form.RuleEnabled.Checked; $rule.ExactPath=$form.ExactPath.Text.Trim()
                $rule.Targets=@($form.SelectedTargets()); $rule.StartDelay=[int]$form.StartDelay.Value; $rule.ExitDelay=[int]$form.ExitDelay.Value
                $rule.ExitPolicy=@('Default','Sdr','Restore')[$form.ExitPolicy.SelectedIndex]
                $rule.LaunchPath=$form.LaunchPath.Text.Trim(); $rule.Arguments=$form.Arguments.Text; $rule.WorkingDirectory=$form.WorkingDirectory.Text.Trim()
                $profiles=Read-HdrProfiles
                $profiles.Rules=@($profiles.Rules | Where-Object Id -ne $rule.Id)+@($rule)
                Save-HdrProfiles $profiles
                Confirm-HdrSettingsSave $Confirmation
                Update-HdrGameListsPanel
                Write-HdrDiagnostic 'SETTINGS' ('Saved game rule '+$rule.Executable)
                return $rule
            } catch { [void](Show-HdrMessage $_.Exception.Message) }
        }
    } catch { [void](Show-HdrMessage $_.Exception.Message) }
    finally { if ($null -ne $form) { $form.Dispose() } }
}
function Show-HdrRunningApps {
    $script:hdrTray.RunningAppsSaveConfirmation=$script:hdrTray.SettingsWindow.SaveConfirmation
    if ($null -ne $script:hdrTray.RunningAppsPicker) { $script:hdrTray.RunningAppsPicker.Activate(); return }
    $picker=[LocalHdrMenu.RunningAppsPicker]::new()
    $picker.ThemePath=Join-Path $PSScriptRoot 'ProcessGridTheme.cs'
    $script:hdrTray.RunningAppsPicker=$picker
    $picker.add_Completed({
        param($sender,$eventArgs)
        $script:hdrTray.RunningAppsPicker=$null
        $confirmation=$script:hdrTray.RunningAppsSaveConfirmation
        $script:hdrTray.RunningAppsSaveConfirmation=$null
        $exe=$sender.SelectedExecutable; $path=$sender.SelectedPath; $failure=$sender.Error
        $sender.Dispose()
        if ($null -ne $failure) { [void](Show-HdrMessage $failure.Message) }
        elseif ($exe) { [void](Show-HdrGameRule $exe $path -Confirmation $confirmation) }
    })
    try {
        $picker.Start()
    } catch {
        $script:hdrTray.RunningAppsPicker=$null; $script:hdrTray.RunningAppsSaveConfirmation=$null; $picker.Dispose()
        [void](Show-HdrMessage $_.Exception.Message)
    }
}
function Get-HdrSelectedGameRule {
    $exe=$script:hdrTray.SettingsWindow.SelectedExecutable
    if (-not $exe) { throw 'Select a game first.' }
    $profiles=Read-HdrProfiles; $rules=@($profiles.Rules | Where-Object { (ConvertTo-HdrAppKey $_.Executable) -eq (ConvertTo-HdrAppKey $exe) })
    if ($rules.Count -eq 1 -and $rules[0].LaunchPath) { return $rules[0] }
    return Show-HdrGameRule $exe
}
function Show-HdrShortcutSave {
    $dialog=$null
    try {
        $rule=Get-HdrSelectedGameRule
        if ($null -eq $rule) { return }
        $dialog=[Windows.Forms.SaveFileDialog]::new(); $dialog.Filter='Windows shortcut (*.lnk)|*.lnk'; $dialog.DefaultExt='lnk'
        $dialog.FileName=([IO.Path]::GetFileNameWithoutExtension($rule.Executable)+' (with HDR).lnk')
        $dialog.InitialDirectory=[Environment]::GetFolderPath('DesktopDirectory')
        if ($dialog.ShowDialog($script:hdrTray.SettingsWindow) -eq [Windows.Forms.DialogResult]::OK) {
            New-HdrLaunchShortcut $rule $dialog.FileName
            Confirm-HdrSettingsSave
        }
    } catch { [void](Show-HdrMessage $_.Exception.Message) }
    finally { if ($null -ne $dialog) { $dialog.Dispose() } }
}
function Update-HdrProfileSettings {
    $window=$script:hdrTray.SettingsWindow
    if ($null -eq $window -or $window.IsDisposed) { return }
    $profiles=Read-HdrProfiles
    $presets=@(foreach ($p in $profiles.Presets) { [LocalHdrMenu.DisplayChoice]::new($p.Id,$p.Name) })
    $shortcuts=@(foreach ($b in $profiles.Bindings) {
        $name=([LocalHdrMenu.ShortcutForm]::ModifierText($b.Modifiers))+'+'+([Windows.Forms.Keys]$b.Key)+' - '+$b.Action
        if ($b.Action -eq 'Preset') { $name+=' '+(@($profiles.Presets | Where-Object Id -eq $b.PresetId)[0].Name) }
        [LocalHdrMenu.DisplayChoice]::new($b.Id,$name)
    })
    $window.SetProfileLists($presets,$shortcuts)
}
function Save-HdrGeneralSettings($Edit) {
    try {
        $profiles=Read-HdrProfiles; $profiles.ExitPolicy=@('Sdr','Restore')[$Edit.ExitPolicy]
        $profiles.Monitors=@($Edit.Monitors | ForEach-Object { [pscustomobject]@{Key=$_.Key;Alias=$_.Alias;ModelName=$_.ModelName} })
        Save-HdrProfiles $profiles
        Confirm-HdrSettingsSave
        Write-HdrDiagnostic 'SETTINGS' 'Saved monitor aliases and default exit behavior'
        Update-HdrTray
    } catch { [void](Show-HdrMessage $_.Exception.Message) }
}
function Show-HdrPresetEditor([string]$Id='') {
    $form=$null
    try {
        $profiles=Read-HdrProfiles
        $preset=@($profiles.Presets | Where-Object Id -eq $Id) | Select-Object -First 1
        if ($null -eq $preset) { $preset=[pscustomobject]@{Id=[Guid]::NewGuid().ToString('N');Name='';Displays=@()} }
        $form=[LocalHdrMenu.PresetForm]::new(); $form.PresetName.Text=$preset.Name
        foreach ($m in @(Get-HdrEditorMonitors $profiles @($preset.Displays | ForEach-Object Key))) {
            $saved=@($preset.Displays | Where-Object Key -eq $m.Key) | Select-Object -First 1
            $enabled=if ($null -ne $saved) {$saved.Enabled} elseif ($null -ne $m.Display) {$m.Display.HdrEnabled} else {$false}
            $brightness=if ($null -ne $saved.Level) { [string](($saved.Level-1000)/50.0) } else { '' }
            $form.AddDisplay($m.Key,$m.Name,($null -ne $saved),$enabled,$brightness)
        }
        while ($form.ShowDialog($script:hdrTray.SettingsWindow) -eq [Windows.Forms.DialogResult]::OK) {
            try {
                [void]$form.Displays.EndEdit(); $targets=@()
                foreach ($row in $form.Displays.Rows) {
                    if (-not $row.Cells['Include'].Value) { continue }
                    $level=$null; $percent=[string]$row.Cells['Brightness'].Value
                    if (-not [string]::IsNullOrWhiteSpace($percent)) {
                        $number=0.0
                        if (-not [double]::TryParse($percent,[ref]$number) -or $number -lt 0 -or $number -gt 100 -or [double]::IsNaN($number)) { throw 'Brightness must be between 0 and 100, or blank.' }
                        $level=[int][Math]::Round(1000+50*$number)
                    }
                    $targets+=[pscustomobject]@{Key=[string]$row.Tag;Enabled=[bool]$row.Cells['Enabled'].Value;Level=$level}
                }
                $preset.Name=$form.PresetName.Text.Trim(); $preset.Displays=$targets
                $profiles=Read-HdrProfiles; $profiles.Presets=@($profiles.Presets | Where-Object Id -ne $preset.Id)+@($preset)
                Save-HdrProfiles $profiles; Confirm-HdrSettingsSave; Update-HdrProfileSettings; return
            } catch { [void](Show-HdrMessage $_.Exception.Message) }
        }
    } catch { [void](Show-HdrMessage $_.Exception.Message) }
    finally { if ($null -ne $form) { $form.Dispose() } }
}
function Show-HdrBindingEditor([string]$Id='') {
    $form=$null
    try {
        $profiles=Read-HdrProfiles; $binding=@($profiles.Bindings | Where-Object Id -eq $Id) | Select-Object -First 1
        if ($null -eq $binding) { $binding=[pscustomobject]@{Id=[Guid]::NewGuid().ToString('N');Modifiers=3;Key=72;Action='Toggle';PresetId='';Targets=@()} }
        $form=[LocalHdrMenu.ShortcutForm]::new(); $form.Modifiers=$binding.Modifiers; $form.Key.SelectedItem=[Windows.Forms.Keys]$binding.Key
        $form.Action.SelectedIndex=@('On','Off','Toggle','Preset').IndexOf($binding.Action)
        foreach ($p in $profiles.Presets) { $form.AddPreset($p.Id,$p.Name) }
        foreach ($item in $form.Preset.Items) { if ($item.Key -eq $binding.PresetId) { $form.Preset.SelectedItem=$item; break } }
        foreach ($m in @(Get-HdrEditorMonitors $profiles $binding.Targets)) { $form.AddTarget($m.Key,$m.Name,($m.Key -in $binding.Targets)) }
        while ($form.ShowDialog($script:hdrTray.SettingsWindow) -eq [Windows.Forms.DialogResult]::OK) {
            try {
                $binding.Modifiers=$form.Modifiers; $binding.Key=[int]$form.Key.SelectedItem
                $binding.Action=@('On','Off','Toggle','Preset')[$form.Action.SelectedIndex]
                $binding.PresetId=if ($null -ne $form.Preset.SelectedItem) { $form.Preset.SelectedItem.Key } else { '' }
                $binding.Targets=@($form.SelectedTargets())
                $profiles=Read-HdrProfiles; $profiles.Bindings=@($profiles.Bindings | Where-Object Id -ne $binding.Id)+@($binding)
                Save-HdrProfiles $profiles; Confirm-HdrSettingsSave; Register-HdrBindings; Update-HdrProfileSettings; return
            } catch { [void](Show-HdrMessage $_.Exception.Message) }
        }
    } catch { [void](Show-HdrMessage $_.Exception.Message) }
    finally { if ($null -ne $form) { $form.Dispose() } }
}
function Invoke-HdrProfileButton([string]$Action,[string]$Id) {
    try {
        $profiles=Read-HdrProfiles
        switch ($Action) {
            'NewPreset' { Show-HdrPresetEditor }
            'EditPreset' { if ($Id) { Show-HdrPresetEditor $Id } }
            'ApplyPreset' { if ($Id) { $p=@($profiles.Presets | Where-Object Id -eq $Id)[0]; Start-HdrScene $p.Displays $p.Name } }
            'DeletePreset' {
                if ($Id) {
                    $profiles.Presets=@($profiles.Presets | Where-Object Id -ne $Id)
                    $profiles.Bindings=@($profiles.Bindings | Where-Object PresetId -ne $Id)
                    Save-HdrProfiles $profiles; Confirm-HdrSettingsSave; Register-HdrBindings; Update-HdrProfileSettings
                }
            }
            'NewShortcut' { Show-HdrBindingEditor }
            'EditShortcut' { if ($Id) { Show-HdrBindingEditor $Id } }
            'DeleteShortcut' { if ($Id) { $profiles.Bindings=@($profiles.Bindings | Where-Object Id -ne $Id); Save-HdrProfiles $profiles; Confirm-HdrSettingsSave; Register-HdrBindings; Update-HdrProfileSettings } }
        }
    } catch { [void](Show-HdrMessage $_.Exception.Message) }
}
function Initialize-HdrProfileSettings {
    $profiles=Read-HdrProfiles
    $monitors=@(foreach ($m in @(Get-HdrEditorMonitors $profiles @($profiles.Monitors | ForEach-Object Key))) {
        $alias=@($profiles.Monitors | Where-Object Key -eq $m.Key) | Select-Object -First 1
        $modelName=if ($null -ne $m.Display) { $m.Display.Name } else { $alias.ModelName }
        [LocalHdrMenu.MonitorAlias]@{Key=$m.Key;ModelName=$modelName;Alias=[string]$alias.Alias;Disconnected=($null -eq $m.Display)}
    })
    Update-HdrProfileSettings
    $script:hdrTray.SettingsWindow.SetGeneral(@('Sdr','Restore').IndexOf($profiles.ExitPolicy),$monitors)
}
