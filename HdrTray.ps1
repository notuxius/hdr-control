# Loaded by the existing Watch action after the display API is initialized.
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
. (Join-Path $PSScriptRoot 'Update-HdrApp.ps1') -FunctionsOnly
if (-not ('LocalHdrMenu.TrayMenuTheme' -as [type])) {
    Add-Type -Path @((Join-Path $PSScriptRoot 'TrayTheme.cs'),(Join-Path $PSScriptRoot 'ProfilesUi.cs')) -ReferencedAssemblies System.Windows.Forms,System.Drawing,UIAutomationProvider,UIAutomationTypes,WindowsBase
}

[LocalHdrMenu.BrightnessLocation]::HelperPath = Join-Path $PSScriptRoot 'HDR Control.exe'
if ($null -eq [LocalHdrMenu.DialogForm]::ApplicationIcon) {
    [LocalHdrMenu.DialogForm]::ApplicationIcon = [Drawing.Icon]::new((Join-Path $PSScriptRoot 'HdrSdrMenu.ico'))
}

. (Join-Path $PSScriptRoot 'HdrProfiles.ps1')
. (Join-Path $PSScriptRoot 'HdrStartup.ps1')

$script:hdrBrightnessHistoryPath = 'HKCU:\Software\HdrContextMenu\SdrBrightness\LastUsed'

$script:hdrUpdateSettingsKey = 'HKEY_CURRENT_USER\Software\HdrContextMenu'

function Show-HdrNotification([string]$Message, [switch]$OpenAbout, [string]$InstallVersion) {
    try {
        # NotifyIcon balloons inherit the PowerShell host's sender name.
        # Register and address our own sender in the interactive user's session.
        if ($null -eq $script:hdrNotifier) {
            $appId = 'Notuxius.HdrControl'
            $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey("Software\Classes\AppUserModelId\$appId")
            try {
                $key.SetValue('DisplayName', 'HDR Control')
                $key.SetValue('IconUri', (Join-Path $PSScriptRoot 'HdrSdrMenu.ico'))
            } finally { $key.Dispose() }
            $script:hdrNotifier = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType=WindowsRuntime]::CreateToastNotifier($appId)
        }
        $xml = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType=WindowsRuntime]::new()
        $xml.LoadXml('<toast><visual><binding template="ToastGeneric"/></visual></toast>')
        if ($OpenAbout -or $InstallVersion) {
            try { Register-HdrNotificationProtocol } catch {
                Write-HdrDiagnostic 'NOTIFICATION' $_.Exception.Message
                if ($InstallVersion) { $Message = ($Message -split "\r?\n",2)[0] + "`nOpen About and select Install update." }
                $OpenAbout = $false
                $InstallVersion = ''
            }
        }
        if ($OpenAbout -or $InstallVersion) {
            $launch = 'notuxius-hdr-control:about'
            if ($InstallVersion) {
                # Only a link issued for this user's offered release can start the updater.
                $offer = [string][Microsoft.Win32.Registry]::GetValue($script:hdrUpdateSettingsKey,'UpdateOffer','')
                $id,$version = $offer -split '/',2
                if ($version -cne $InstallVersion -or $id -cnotmatch '^[a-f0-9]{32}$') {
                    $id = [Guid]::NewGuid().ToString('N')
                    [Microsoft.Win32.Registry]::SetValue($script:hdrUpdateSettingsKey,'UpdateOffer',"$id/$InstallVersion")
                }
                $launch = "notuxius-hdr-control:install/$id"
            }
            $xml.DocumentElement.SetAttribute('activationType','protocol')
            $xml.DocumentElement.SetAttribute('launch',$launch)
        }
        $binding=$xml.GetElementsByTagName('binding').Item(0)
        foreach ($line in ($Message -split '\r?\n',2)) {
            $text=$xml.CreateElement('text')
            $text.InnerText=$line
            [void]$binding.AppendChild($text)
        }
        $script:hdrNotifier.Show([Windows.UI.Notifications.ToastNotification, Windows.UI.Notifications, ContentType=WindowsRuntime]::new($xml))
    } catch { Write-HdrDiagnostic 'NOTIFICATION' ($Message + ': ' + $_.Exception.Message) }
}

function Get-HdrBrightnessKey($Display) {
    if ([string]::IsNullOrWhiteSpace($Display.DevicePath)) { return '' }
    $hash = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::Unicode.GetBytes($Display.DevicePath.ToUpperInvariant())))).Replace('-','') }
    finally { $hash.Dispose() }
}

function Get-HdrBrightnessPreference([string]$Key) {
    if ($Key -cnotmatch '^[A-F0-9]{64}$') { return $null }
    $data = Get-ItemProperty -LiteralPath 'HKCU:\Software\HdrContextMenu\SdrBrightness' -ErrorAction SilentlyContinue
    if ($null -eq $data -or -not $data.$Key) { return $null }
    try {
        $value = $data.$Key | ConvertFrom-Json -ErrorAction Stop
        if ($value.Version -eq 1) {
            if ($value.Restore -isnot [bool] -or $value.Level -isnot [int] -or $value.Level -lt 1000 -or $value.Level -gt 6000) { return $null }
            $value = New-HdrBrightnessSettings $value.Level $value.Restore
        }
        Test-HdrBrightnessSettings $value
        return $value
    } catch { return $null }
}

function New-HdrBrightnessSettings([uint32]$Level, [bool]$Restore = $false) {
    return [pscustomobject]@{ Version=2; Level=[int]$Level; Restore=$Restore; DayLevel=[int]$Level; NightLevel=[int]$Level;
        Mode='Manual'; DayStart=480; NightStart=1080; Enforce=$false }
}

function Test-HdrBrightnessSettings($Settings) {
    if ($null -eq $Settings -or $Settings.Version -ne 2 -or $Settings.Restore -isnot [bool] -or
        $Settings.Enforce -isnot [bool] -or $Settings.Mode -notin @('Manual','Schedule','NightLight','SunriseSunset')) { throw 'Invalid brightness settings.' }
    foreach ($field in @('Level','DayLevel','NightLevel')) {
        if ($Settings.$field -isnot [int] -or $Settings.$field -lt 1000 -or $Settings.$field -gt 6000) { throw 'Brightness must be between 0 and 100%.' }
    }
    foreach ($field in @('DayStart','NightStart')) {
        if ($Settings.$field -isnot [int] -or $Settings.$field -lt 0 -or $Settings.$field -gt 1439) { throw 'Enter a valid schedule time in HH:mm format, for example 08:00 or 18:30.' }
    }
    if ($Settings.DayStart -eq $Settings.NightStart) { throw 'Day and night must start at different times.' }
}

function Get-HdrBrightnessTime { return [DateTime]::Now }
function Get-HdrBrightnessLocation {
    [LocalHdrMenu.BrightnessLocation]::Request($false)
    return [LocalHdrMenu.BrightnessLocation]::Current
}
function Get-HdrNightLightState {
    # Cache the read for ten seconds. Unknown encodings remain unknown; never
    # guess that Night Light is disabled or modify Windows' CloudStore data.
    $now=[DateTime]::UtcNow
    if ($null -eq $script:hdrNightLightReadAt -or ($now-$script:hdrNightLightReadAt).TotalSeconds -ge 10) {
        $script:hdrNightLightValue=[LocalHdrMenu.NightLightReader]::Read()
        $script:hdrNightLightReadAt=$now
    }
    return $script:hdrNightLightValue
}

function Get-HdrBrightnessDecision($Settings) {
    if ($Settings.Mode -eq 'Manual') { return [pscustomobject]@{Phase='Manual';Source='Manual';Level=$Settings.Level} }
    $night=$null; $source='Schedule'
    if ($Settings.Mode -eq 'NightLight') {
        $night=Get-HdrNightLightState
        $source=if ($null -eq $night) {'Schedule fallback: Night Light unavailable'} else {'Windows Night Light'}
    }
    if ($Settings.Mode -eq 'SunriseSunset') {
        $location=Get-HdrBrightnessLocation
        if ($null -eq $location) { $source='Schedule fallback: location unavailable' }
        else {
            $now=Get-HdrBrightnessTime
            $night=-not [LocalHdrMenu.BrightnessSun]::IsDay($now.ToUniversalTime(),$location.Latitude,$location.Longitude)
            $source='Sunrise / sunset (Windows location)'
        }
    }
    if ($null -eq $night) {
        $now=Get-HdrBrightnessTime
        $minutes=$now.Hour*60+$now.Minute
        $night=if ($Settings.NightStart -gt $Settings.DayStart) {
            $minutes -ge $Settings.NightStart -or $minutes -lt $Settings.DayStart
        } else { $minutes -ge $Settings.NightStart -and $minutes -lt $Settings.DayStart }
    }
    return [pscustomobject]@{ Phase=$(if ($night) {'Night'} else {'Day'}); Source=$source;
        Level=$(if ($night) {$Settings.NightLevel} else {$Settings.DayLevel}) }
}

function Save-HdrBrightnessPreference([string]$Key, [uint32]$Level, [bool]$Restore, $Settings) {
    if ($Key -cnotmatch '^[A-F0-9]{64}$' -or $Level -lt 1000 -or $Level -gt 6000) { throw 'Invalid saved brightness.' }
    $path = 'HKCU:\Software\HdrContextMenu\SdrBrightness'
    if (-not (Test-Path -LiteralPath $path)) { New-Item -Path $path -Force -ErrorAction Stop | Out-Null }
    # One value makes the level and opt-in flag an atomic preference update.
    if ($null -eq $Settings) { $Settings=New-HdrBrightnessSettings $Level $Restore }
    Test-HdrBrightnessSettings $Settings
    $json = $Settings | ConvertTo-Json -Compress
    New-ItemProperty -LiteralPath $path -Name $Key -Value $json -PropertyType String -Force -ErrorAction Stop | Out-Null
}

function Test-HdrBrightnessAvailable($Display) {
    return $null -ne $Display -and $Display.HdrEnabled -and $Display.HdrActive -and
        $null -ne $Display.SdrWhiteLevel -and $Display.SdrWhiteLevel -ge 1000 -and $Display.SdrWhiteLevel -le 6000
}

function Get-HdrLastBrightnessLevels {
    $levels=@{}
    $history=Get-Item -LiteralPath $script:hdrBrightnessHistoryPath -ErrorAction SilentlyContinue
    if ($null -ne $history) {
        foreach ($key in $history.GetValueNames()) {
            $level=$history.GetValue($key)
            if ($key -cmatch '^[A-F0-9]{64}$' -and $level -is [int] -and $level -ge 1000 -and $level -le 6000) { $levels[$key]=$level }
        }
    }
    return $levels
}

function Save-HdrLastBrightnessLevel([string]$Key, [uint32]$Level) {
    if (-not $Key -or $script:hdrTray.LastBrightness[$Key] -eq $Level) { return }
    $script:hdrTray.LastBrightness[$Key]=$Level
    try {
        if (-not (Test-Path -LiteralPath $script:hdrBrightnessHistoryPath)) {
            New-Item -Path $script:hdrBrightnessHistoryPath -Force -ErrorAction Stop | Out-Null
        }
        New-ItemProperty -LiteralPath $script:hdrBrightnessHistoryPath -Name $Key -Value $Level -PropertyType DWord -Force -ErrorAction Stop | Out-Null
    } catch { Write-HdrDiagnostic 'SETTINGS' ('Could not save brightness history: '+$_.Exception.Message) }
}

function Start-HdrBrightnessChange($Display, [uint32]$Level, [bool]$Restore, [switch]$Automatic, $Settings, [string]$PreferenceKey, $Edit) {
    if ($null -ne $script:hdrTray.Pending -or $null -ne $script:hdrTray.UpdateProcess -or (-not $Automatic -and $null -ne $script:hdrTray.Scene)) { return $false }
    if (-not (Test-HdrBrightnessAvailable $Display) -or $Display.DisplayId -cnotmatch '^[A-Za-z0-9+/=]+$' -or
        $Level -lt 1000 -or $Level -gt 6000) { throw 'SDR brightness is unavailable for this monitor.' }
    $operation = @{ DisplayId=$Display.DisplayId; Key=(Get-HdrBrightnessKey $Display); Level=$Level; Restore=$Restore;
        Automatic=[bool]$Automatic; Settings=$Settings; Edit=$Edit; Scene=($null -ne $script:hdrTray.Scene) }
    if ($PSBoundParameters.ContainsKey('PreferenceKey')) { $operation.Key = $PreferenceKey }
    $process = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList (
        '-NoLogo -NoProfile -NonInteractive -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" -Action Brightness -DisplayId "{1}" -SdrWhiteLevel {2}' -f $installedScript,$Display.DisplayId,$Level
    ) -WindowStyle Hidden -PassThru -ErrorAction Stop
    $script:hdrTray.BrightnessPending = $operation
    $script:hdrTray.Pending = $process
    $script:hdrTray.Exit.Enabled = $false
    $script:hdrTray.Command.Enabled = $false
    Set-HdrDisplayCommandsEnabled $false
    if (-not $Automatic -and $script:hdrTray.BrightnessStates.ContainsKey($Display.DisplayId)) {
        $script:hdrTray.BrightnessStates[$Display.DisplayId].Due = $false
    }
    return $true
}

function Complete-HdrBrightnessChange([bool]$Success) {
    $operation = $script:hdrTray.BrightnessPending
    $script:hdrTray.BrightnessPending = $null
    if ($Success -and $operation.Key) { Save-HdrLastBrightnessLevel $operation.Key $operation.Level }
    # Presets have their own completion/rollback policy, not restoration retries.
    if ($operation.Scene) { return }
    $state = $script:hdrTray.BrightnessStates[$operation.DisplayId]
    if ($Success) {
        if ($null -ne $state) { $state.Due = $false; $state.NextCheck=[DateTime]::UtcNow.AddSeconds(15) }
        if (-not $operation.Automatic) {
            try {
                if ($operation.Key) { Save-HdrBrightnessPreference $operation.Key $operation.Level $operation.Restore $operation.Settings }
            }
            catch {
                if ($operation.Edit -and $script:hdrTray.SettingsWindow) { $script:hdrTray.SettingsWindow.RejectedBrightness($operation.Edit) }
                [void](Show-HdrMessage 'Brightness changed, but the settings could not be saved.'); return
            }
        }
        if ($null -ne $operation.Edit -and $null -ne $script:hdrTray.SettingsWindow) {
            $script:hdrTray.SettingsWindow.AppliedBrightness($operation.Edit)
        }
    } else {
        if ($operation.Edit -and $script:hdrTray.SettingsWindow) { $script:hdrTray.SettingsWindow.RejectedBrightness($operation.Edit) }
        if ($null -ne $state -and $operation.Automatic) {
            $state.RetryAt = [DateTime]::UtcNow.AddSeconds(30)
            if ($state.Attempts -lt 3) { return }
            $state.Due = $false
            $state.Blocked = $true
        }
        Show-HdrNotification 'Windows could not confirm the SDR brightness change. Saved preferences were not changed. Try HDR settings or refresh displays.'
    }
}

function Get-HdrBrightnessDisplays($Displays) {
    $capable=@($Displays | Where-Object { $_.HdrSupported -and $_.DisplayId })
    $keys=@{}; $names=@{}
    foreach ($d in $capable) {
        $keys[(Get-HdrBrightnessKey $d)]++
        $names[[string]$d.Name]++
    }
    $busy=$null -ne $script:hdrTray.Pending -or $null -ne $script:hdrTray.UpdateProcess -or $null -ne $script:hdrTray.Scene
    for ($i=0;$i -lt $capable.Count;$i++) {
        $d=$capable[$i]; $key=Get-HdrBrightnessKey $d
        if ($keys[$key] -ne 1) { $key='' }
        $p=Get-HdrBrightnessPreference $key
        $available=Test-HdrBrightnessAvailable $d
        $item=[LocalHdrMenu.MonitorBrightness]::new()
        $item.DisplayId=$d.DisplayId; $item.PreferenceKey=$key; $item.Name=$d.Name
        $item.HdrOff=-not $d.HdrEnabled
        if ($names[[string]$d.Name] -gt 1) { $item.Name='{0} (display {1})' -f $d.Name,($i+1) }
        if ($available) { $item.CurrentLevel=$d.SdrWhiteLevel; $item.Level=$d.SdrWhiteLevel }
        elseif ($null -ne $p) { $item.Level=$p.Level }
        if (-not $d.HdrEnabled -and $key) {
            # Keep the legacy manual value even if the user next saves an automatic mode.
            if (-not $script:hdrTray.LastBrightness.ContainsKey($key) -and $p.Mode -eq 'Manual') {
                Save-HdrLastBrightnessLevel $key $p.Level
            }
            $item.LastUsedLevel=$script:hdrTray.LastBrightness[$key]
        }
        if ($null -ne $p) {
            $decision=Get-HdrBrightnessDecision $p
            $item.Runtime=if ($decision.Phase -eq 'Manual') { 'Manual control' } else { '{0} {1} {2}' -f $decision.Phase,[char]0x00B7,$decision.Source }
        } else {
            $p=New-HdrBrightnessSettings $item.Level
            $item.Runtime='Manual control'
        }
        foreach ($field in @('Restore','DayLevel','NightLevel','Mode','DayStart','NightStart','Enforce')) { $item.$field=$p.$field }
        $item.Busy=$busy
        $item.Saving=$busy -and $script:hdrTray.BrightnessPending.Edit.DisplayId -ceq $d.DisplayId
        $item.Status=if ($busy) { 'Waiting for the display change to finish...' }
            elseif (-not $d.HdrEnabled) { '' }
            elseif (-not $available) { 'SDR brightness is unavailable on this display or Windows version.' }
            else { 'Current Windows level: {0}%. Changes save automatically.' -f [Math]::Round(($d.SdrWhiteLevel-1000)/50.0,[MidpointRounding]::AwayFromZero) }
        $item
    }
}

function Update-HdrBrightnessPanel($Displays) {
    $window=$script:hdrTray.SettingsWindow
    if ($null -ne $window -and -not $window.IsDisposed) { $window.SetDisplays(@(Get-HdrBrightnessDisplays $Displays)) }
}

function Save-HdrBrightnessPanel([LocalHdrMenu.MonitorBrightness]$edit) {
    if ($null -eq $edit) { return }
    if ($null -ne $script:hdrTray.Pending -or $null -ne $script:hdrTray.UpdateProcess -or $null -ne $script:hdrTray.Scene) {
        $script:hdrTray.BrightnessEdits[$edit.DisplayId]=$edit
        return
    }
    $script:hdrTray.BrightnessEdits.Remove($edit.DisplayId)
    try {
        $displays = @([LocalHdrMenu.DisplayApi]::Read())
        $selected = @($displays | Where-Object { $_.DisplayId -ceq $edit.DisplayId })
        if ($selected.Count -ne 1) { throw 'This monitor is no longer available.' }
        $display = $selected[0]
        $key=Get-HdrBrightnessKey $display
        if ($key -and @($displays | Where-Object { (Get-HdrBrightnessKey $_) -ceq $key }).Count -ne 1) { $key='' }
        if ($key -cne $edit.PreferenceKey -or -not $display.HdrSupported) { throw 'The selected display changed. Select it again before applying brightness.' }
        if ($edit.Level -lt 1000) {
            if ($script:hdrTray.SettingsWindow) { $script:hdrTray.SettingsWindow.RejectedBrightness($edit) }
            return
        }
        $settings=New-HdrBrightnessSettings $edit.Level $edit.Restore
        $settings.DayLevel=[int]$edit.DayLevel; $settings.NightLevel=[int]$edit.NightLevel
        $settings.Mode=$edit.Mode
        $settings.DayStart=$edit.DayStart
        $settings.NightStart=$edit.NightStart
        $settings.Enforce=$edit.Enforce
        Test-HdrBrightnessSettings $settings
        $decision=Get-HdrBrightnessDecision $settings
        if (Test-HdrBrightnessAvailable $display) {
            if ($display.SdrWhiteLevel -ne $decision.Level) {
                [void](Start-HdrBrightnessChange $display $decision.Level $edit.Restore -Settings $settings -PreferenceKey $edit.PreferenceKey -Edit $edit)
                Update-HdrBrightnessPanel $displays
                return
            } else {
                if ($edit.PreferenceKey) { Save-HdrBrightnessPreference $edit.PreferenceKey $edit.Level $edit.Restore $settings }
            }
        } elseif ($edit.PreferenceKey -and $edit.Level -ge 1000) {
            if ($edit.LevelEdited) { throw 'Enable HDR before applying the changed brightness level.' }
            Save-HdrBrightnessPreference $edit.PreferenceKey $edit.Level $edit.Restore $settings
        } else { throw 'Enable HDR and reopen brightness controls to read the current level.' }
        if ($null -ne $script:hdrTray.SettingsWindow) { $script:hdrTray.SettingsWindow.AppliedBrightness($edit) }
        Update-HdrBrightnessPanel $displays
    } catch {
        if ($script:hdrTray.SettingsWindow) { $script:hdrTray.SettingsWindow.RejectedBrightness($edit) }
        [void](Show-HdrMessage $_.Exception.Message)
    }
}

function Update-HdrBrightness($Displays) {
    $states = $script:hdrTray.BrightnessStates
    if ($null -eq $states) { return }
    $present = @{}
    $pathCounts=@{}
    foreach ($display in $Displays) { $pathCounts[[string]$display.DevicePath]++ }
    foreach ($display in $Displays) {
        $id = $display.DisplayId
        if (-not $id) { continue }
        $present[$id] = $true
        $active = [bool]($display.HdrEnabled -and $display.HdrActive)
        if (-not $states.ContainsKey($id)) { $states[$id] = @{ Active=$false; Due=$false; Attempts=0; RetryAt=[DateTime]::MinValue;
            Token=''; Blocked=$false; Suppressed=$false; NextCheck=[DateTime]::MinValue } }
        $state = $states[$id]
        $key=Get-HdrBrightnessKey $display
        if ($key -and $pathCounts[$display.DevicePath] -eq 1 -and (Test-HdrBrightnessAvailable $display)) {
            Save-HdrLastBrightnessLevel $key $display.SdrWhiteLevel
        }
        $preference=Get-HdrBrightnessPreference $key
        $state.Preference=$preference
        if ($null -ne $preference) {
            $decision=Get-HdrBrightnessDecision $preference
            $token=($preference | ConvertTo-Json -Compress)+'|'+$decision.Phase
            $transition=$state.Token -and $token -cne $state.Token
            $enabled=$active -and -not $state.Active
            if ($enabled -or $transition) {
                $state.Due=$active -and ($preference.Restore -or $preference.Enforce -or ($transition -and $preference.Mode -ne 'Manual'))
                $state.Attempts=0; $state.RetryAt=[DateTime]::MinValue; $state.Blocked=$false; $state.Suppressed=$false
            }
            $state.Token=$token; $state.Level=$decision.Level
            if ($active -and $preference.Enforce -and -not $state.Blocked -and -not $state.Suppressed -and
                [DateTime]::UtcNow -ge $state.NextCheck) {
                if ($display.SdrWhiteLevel -ne $decision.Level) { $state.Due=$true }
                $state.NextCheck=[DateTime]::UtcNow.AddSeconds(15)
            }
        } else { $state.Due=$false; $state.Token='' }
        if (-not $active) { $state.Due=$false }
        $state.Active = $active
        if ($null -ne $script:hdrTray.Scene -and (Get-HdrMonitorKey $display) -in $script:hdrTray.Scene.SuppressBrightness) {
            $state.Due=$false; $state.Suppressed=$true
        }
    }
    foreach ($id in @($states.Keys)) { if (-not $present.ContainsKey($id)) { $states.Remove($id) } }
    Update-HdrBrightnessPanel $Displays
    if ($null -ne $script:hdrTray.Pending -or $null -ne $script:hdrTray.UpdateProcess -or $null -ne $script:hdrTray.Scene) { return }
    foreach ($display in $Displays) {
        $state = $states[$display.DisplayId]
        if ($null -eq $state -or -not $state.Due -or -not (Test-HdrBrightnessAvailable $display)) { continue }
        if ($script:hdrTray.SettingsWindow.ActiveBrightnessId -ceq $display.DisplayId) { $state.Due=$false; continue }
        $key = Get-HdrBrightnessKey $display
        $preference = $state.Preference
        if (-not $key -or $null -eq $preference -or
            $pathCounts[$display.DevicePath] -ne 1) { $state.Due=$false; continue }
        if ($display.SdrWhiteLevel -eq $state.Level) { $state.Due=$false; continue }
        if ([DateTime]::UtcNow -lt $state.RetryAt) { continue }
        $state.Attempts++
        try { [void](Start-HdrBrightnessChange $display $state.Level $preference.Restore -Automatic) }
        catch {
            $state.RetryAt=[DateTime]::UtcNow.AddSeconds(30)
            if ($state.Attempts -ge 3) { $state.Due=$false; $state.Blocked=$true }
        }
        return
    }
}

function Get-HdrAutomationPreference([ValidateSet('AutomaticHdr','UseCommunityApps')][string]$Name) {
    $settings = Get-ItemProperty -LiteralPath 'HKCU:\Software\HdrContextMenu' -ErrorAction SilentlyContinue
    $value = if ($null -ne $settings) { $settings.$Name } else { $null }
    if ($null -eq $value) { return $Name -eq 'UseCommunityApps' }
    return $value -ne 0
}

function Set-HdrAutomationPreference([ValidateSet('AutomaticHdr','UseCommunityApps')][string]$Name, [bool]$Enabled) {
    if (-not (Test-Path -LiteralPath 'HKCU:\Software\HdrContextMenu')) {
        New-Item -Path 'HKCU:\Software\HdrContextMenu' -ErrorAction Stop | Out-Null
    }
    New-ItemProperty -LiteralPath 'HKCU:\Software\HdrContextMenu' -Name $Name -Value ([int]$Enabled) -PropertyType DWord -Force -ErrorAction Stop | Out-Null
}

function Set-HdrAutomaticMenuState([bool]$Enabled) {
    if ($script:hdrTray.Automatic.Checked -ne $Enabled -and $null -ne $script:hdrTray.SettingsWindow -and -not $script:hdrTray.SettingsWindow.IsDisposed) {
        $script:hdrTray.SettingsWindow.SetAutomaticSwitching($Enabled)
        Update-HdrGameListsPanel
    }
    $script:hdrTray.Automatic.Checked = $Enabled
    $script:hdrTray.Automatic.Text = if ($Enabled) { 'Disable auto-switching' } else { 'Enable auto-switching' }
}

function Switch-HdrAutomaticHdr([switch]$Enable) {
    try {
        $current = Get-HdrAutomationPreference 'AutomaticHdr'
        $enabled = $Enable -or -not $current
        if ($current -ne $enabled) {
            Set-HdrAutomationPreference 'AutomaticHdr' $enabled
            # Pausing releases control without changing the user's current HDR state.
            $script:hdrTray.Automation = New-HdrAutomationState
            if ($enabled -or $script:hdrTray.Launches.Count) { Set-HdrDecision 'Checking apps' }
            else { Set-HdrDecision 'Automatic HDR is paused' }
            Show-HdrNotification $(if ($enabled) { 'Automatic HDR switching is enabled.' } else { 'Automatic HDR switching is disabled.' })
        }
    } catch {
        Show-HdrNotification 'The automatic HDR preference could not be saved.'
    }
    Set-HdrAutomaticMenuState (Get-HdrAutomationPreference 'AutomaticHdr')
    if ($null -ne $script:hdrTray.LastDisplays -and -not $script:hdrTray.DisplayReadError) {
        Set-HdrTrayState (Get-HdrTrayState $script:hdrTray.LastDisplays)
    }
}

function Get-HdrCustomAppsPath { return Join-Path $PSScriptRoot 'HdrApps.custom.txt' }
function Get-HdrDetectedAppsPath { return Join-Path $PSScriptRoot 'HdrApps.detected.json' }

function Read-HdrDetectedApps {
    $path = Get-HdrDetectedAppsPath
    $apps = @{}
    if (-not [IO.File]::Exists($path)) { return $apps }
    if ([IO.FileInfo]::new($path).Length -gt 1MB) { throw 'Detected games file is too large.' }
    $data = [IO.File]::ReadAllText($path) | ConvertFrom-Json -ErrorAction Stop
    if ($data.Version -ne 1 -or $null -eq $data.Apps) { throw 'Invalid detected games file.' }
    foreach ($entry in @($data.Apps)) {
        $key = ConvertTo-HdrAppKey $entry.Executable
        $date = [DateTime]::MinValue
        if (-not $key -or $entry.Executable -isnot [string] -or
            -not $entry.Executable.EndsWith('.exe', [StringComparison]::OrdinalIgnoreCase) -or
            $entry.Executable.StartsWith('!') -or $key -eq 'launcher' -or
            -not [DateTime]::TryParseExact([string]$entry.DetectedUtc, 'o', [Globalization.CultureInfo]::InvariantCulture,
                [Globalization.DateTimeStyles]::RoundtripKind, [ref]$date)) { throw 'Invalid detected game entry.' }
        $apps[$key] = [pscustomobject]@{Executable=[string]$entry.Executable;DetectedUtc=$date.ToUniversalTime().ToString('o')}
    }
    return $apps
}

function Save-HdrDetectedApps([string[]]$Names, [hashtable]$Defaults) {
    # Only record current, enabled community matches. Custom names alone are not HDR evidence.
    $known = @($Names | Where-Object { $Defaults.ContainsKey((ConvertTo-HdrAppKey $_)) })
    if (-not $known.Count) { return }
    $apps = Read-HdrDetectedApps
    $changed = $false
    foreach ($name in $known) {
        $key = ConvertTo-HdrAppKey $name
        if (-not $apps.ContainsKey($key)) {
            $apps[$key] = [pscustomobject]@{Executable=($name -replace '(?i)\.exe$', '') + '.exe';DetectedUtc=[DateTime]::UtcNow.ToString('o')}
            $changed = $true
        }
    }
    if (-not $changed) { return }
    Write-HdrDetectedApps $apps
    if ($null -ne $script:hdrTray.SettingsWindow -and -not $script:hdrTray.SettingsWindow.IsDisposed) {
        Update-HdrGameListsPanel
    }
}

function Write-HdrDetectedApps([hashtable]$Apps) {
    $text = @{Version=1;Apps=@($Apps.Values | Sort-Object Executable)} | ConvertTo-Json -Depth 3
    Write-HdrAtomicText (Get-HdrDetectedAppsPath) $text
}

function Get-HdrCommunityCachePath { return Join-Path $PSScriptRoot 'HdrApps.community.cache.txt' }
function Get-HdrCommunityBundlePath { return Join-Path $PSScriptRoot 'HdrApps.community.txt' }

function ConvertFrom-HdrCommunityList([string]$Text) {
    if ($Text.Length -gt 1MB) { throw 'Community list is too large.' }
    $lines = $Text -split '\r?\n'
    if ($lines[0] -cne '# HDR Context Menu community list v1') { throw 'Unrecognized community list format.' }
    $names = @{}
    foreach ($line in $lines) {
        $value = $line.Trim()
        if (-not $value -or $value.StartsWith('#')) { continue }
        $key = ConvertTo-HdrAppKey $value
        if (-not $key -or -not $value.EndsWith('.exe', [StringComparison]::OrdinalIgnoreCase) -or
            $value.StartsWith('!') -or $value -match '[\x00-\x1f]' -or $key -eq 'launcher') {
            throw 'Community list contains an invalid executable name.'
        }
        $names[$key] = $true
    }
    if ($names.Count -eq 0) { throw 'Community list is empty.' }
    return @($names.Keys | Sort-Object)
}

function Read-HdrCommunityList([string]$Path) {
    if ([IO.FileInfo]::new($Path).Length -gt 1MB) { throw 'Community list is too large.' }
    return ConvertFrom-HdrCommunityList ([IO.File]::ReadAllText($Path, [Text.UTF8Encoding]::new($false, $true)))
}

function Get-HdrDefaultAppNames {
    # Keep the last good in-memory list if the cache is temporarily unreadable.
    # On a fresh launch, an absent or damaged cache falls back to the bundle.
    try {
        $names = @(Read-HdrCommunityList (Get-HdrCommunityCachePath))
        $script:hdrCommunityLastGood = $names
        return $names
    } catch { }
    if ($null -ne $script:hdrCommunityLastGood) { return $script:hdrCommunityLastGood }
    return Read-HdrCommunityList (Get-HdrCommunityBundlePath)
}

function Save-HdrCommunityList([string]$Text) {
    $names = @(ConvertFrom-HdrCommunityList $Text)
    $path = Get-HdrCommunityCachePath
    $temporary = $path + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::WriteAllText($temporary, $Text, [Text.UTF8Encoding]::new($false))
        # Replace atomically, so interrupted downloads/writes cannot damage the cache.
        if ([IO.File]::Exists($path)) { [IO.File]::Replace($temporary, $path, [NullString]::Value) }
        else { [IO.File]::Move($temporary, $path) }
        $script:hdrCommunityLastGood = $names
    } finally {
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
    }
    return $names.Count
}

function Update-HdrCommunityUpdateButton {
    $panel = $script:hdrTray.SettingsWindow
    if ($null -eq $panel -or $panel.IsDisposed) { return }
    $updating = $null -ne $script:hdrTray.CommunityUpdate
    $panel.UpdateCommunityButton.Enabled = -not ($updating -or $null -ne $script:hdrTray.UpdateCheck -or $null -ne $script:hdrTray.UpdateProcess)
    $panel.UpdateCommunityButton.Text = if ($updating) { 'Updating community list...' } else { 'Update community list' }
}

function Start-HdrCommunityUpdate {
    if ($null -ne $script:hdrTray.CommunityUpdate -or $null -ne $script:hdrTray.UpdateCheck -or
        $null -ne $script:hdrTray.UpdateProcess) { return }
    try {
        $script:hdrTray.CommunityUpdate = [LocalHdrMenu.CommunityListDownload]::new()
        $script:hdrTray.CommunityUpdate.Start()
        $script:hdrTray.CommunitySaveConfirmation=$script:hdrTray.SettingsWindow.SaveConfirmation
        Update-HdrCommunityUpdateButton
        $script:hdrTray.CheckUpdates.Enabled = $false
    } catch {
        $script:hdrTray.CommunityUpdate = $null
        $script:hdrTray.CommunitySaveConfirmation=$null
        Update-HdrCommunityUpdateButton
        [void](Show-HdrMessage 'Could not start the community list update. Your saved list is unchanged.')
    }
}

function Complete-HdrCommunityUpdate {
    $download = $script:hdrTray.CommunityUpdate
    if ($null -eq $download -or -not $download.Finished) { return }
    $script:hdrTray.CommunityUpdate = $null
    $confirmation=$script:hdrTray.CommunitySaveConfirmation
    $script:hdrTray.CommunitySaveConfirmation=$null
    Update-HdrCommunityUpdateButton
    $script:hdrTray.CheckUpdates.Enabled = $true
    try {
        if ($download.Error) { throw $download.Error }
        $count = Save-HdrCommunityList $download.Result
        Update-HdrGameListsPanel
        [void](Show-HdrMessage ("Community list updated: $count apps.`nYour custom additions and exclusions are preserved."))
        Confirm-HdrSettingsSave $confirmation
    } catch {
        [void](Show-HdrMessage 'Could not update the community list. Your saved list is unchanged and remains available offline. Check your connection and try again later.')
    }
}

function Edit-HdrCustomApps {
    try {
        $path = Get-HdrCustomAppsPath
        if (-not [IO.File]::Exists($path)) {
            $stream = [IO.File]::Open($path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write)
            $writer = [IO.StreamWriter]::new($stream, [Text.UTF8Encoding]::new($true))
            try {
                $writer.WriteLine('# One executable name per line; .exe is optional. Save to apply.')
                $writer.WriteLine('# Example: MyGame.exe')
                $writer.WriteLine('# Use !MyGame.exe to exclude an entry from the community list.')
                $writer.WriteLine('# Names are case insensitive. Lines starting with # are comments.')
            } finally { $writer.Dispose() }
        }
        Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\notepad.exe') -ArgumentList ('"{0}"' -f $path) -ErrorAction Stop | Out-Null
    } catch {
        Show-HdrNotification 'The custom app list could not be opened.'
    }
}

function ConvertTo-HdrAppKey([string]$Name) {
    $value = $Name.Trim()
    if (-not $value -or $value.StartsWith('#')) { return $null }
    # Exact executable names only; paths and wildcard rules can match unrelated apps.
    if ($value.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) { return $null }
    if ($value.EndsWith('.exe', [StringComparison]::OrdinalIgnoreCase)) { $value = $value.Substring(0, $value.Length - 4) }
    if (-not $value -or $value -eq '.' -or $value -eq '..') { return $null }
    return $value.ToLowerInvariant()
}

function Get-HdrAppListState([switch]$IncludeDisabledDefaults) {
    $names = @{}
    $defaults = @{}
    $custom = @{}
    $useDefaults = Get-HdrAutomationPreference 'UseCommunityApps'
    if ($useDefaults -or $IncludeDisabledDefaults) {
        foreach ($line in Get-HdrDefaultAppNames) {
            $key = ConvertTo-HdrAppKey $line
            if ($key) {
                $defaults[$key] = $true
                if ($useDefaults) { $names[$key] = $true }
            }
        }
    }
    $path = Get-HdrCustomAppsPath
    # Missing custom files are normal. Other read failures must not look like app exits.
    $lines = @()
    try { $lines = [IO.File]::ReadAllLines($path) }
    catch [IO.FileNotFoundException] { }
    $excluded = @{}
    foreach ($line in $lines) {
        $value = $line.Trim()
        $exclude = $value.StartsWith('!')
        if ($exclude) { $value = $value.Substring(1) }
        $key = ConvertTo-HdrAppKey $value
        if ($key) {
            if ($exclude) { $excluded[$key] = $true }
            else { $names[$key] = $true; $custom[$key] = $true }
        }
    }
    foreach ($key in $excluded.Keys) { $names.Remove($key) }
    $defaultOverrides=@{}
    foreach ($rule in (Read-HdrProfiles).Rules) {
        $key=ConvertTo-HdrAppKey $rule.Executable
        if ($rule.KeepInDefaults -and $defaults.ContainsKey($key) -and -not $custom.ContainsKey($key) -and -not $excluded.ContainsKey($key)) {
            $defaultOverrides[$key]=$true
        }
        $custom[$key]=$true
        if ($rule.Enabled) { $names[$key]=$true; $excluded.Remove($key) }
        else { $names.Remove($key); $excluded[$key]=$true }
    }
    return @{Defaults=$defaults;Custom=$custom;Excluded=$excluded;Effective=$names;DefaultOverrides=$defaultOverrides}
}

function Get-HdrWatchedApps { return (Get-HdrAppListState).Effective }

function Get-HdrInstalledExecutableNames {
    $locations = @('HKCU:\SOFTWARE','HKLM:\SOFTWARE','HKLM:\SOFTWARE\WOW6432Node')
    $roots = @(foreach ($location in $locations) {
        $base = "$location\Microsoft\Windows\CurrentVersion"
        foreach ($app in Get-ItemProperty "$base\Uninstall\*" -ErrorAction SilentlyContinue) {
            if ($app.InstallLocation) { $app.InstallLocation }
        }
    })
    $manifests = Join-Path $env:ProgramData 'Epic\EpicGamesLauncher\Data\Manifests'
    $roots += @(foreach ($item in Get-ChildItem -LiteralPath $manifests -Filter '*.item' -ErrorAction SilentlyContinue) {
        try {
            $game = [IO.File]::ReadAllText($item.FullName) | ConvertFrom-Json -ErrorAction Stop
            if (-not $game.bIsIncompleteInstall -and $game.InstallLocation) { $game.InstallLocation }
        } catch { continue }
    })
    foreach ($location in $locations) {
        foreach ($app in Get-ItemProperty "$location\Microsoft\Windows\CurrentVersion\App Paths\*" -ErrorAction SilentlyContinue) {
            $path = [Environment]::ExpandEnvironmentVariables([string]$app.'(default)').Trim('"')
            if ([IO.File]::Exists($path)) { [IO.Path]::GetFileName($path) }
        }
    }
    $pending = [Collections.Generic.Stack[string]]::new()
    $seen = @{}
    foreach ($root in $roots) {
        $path = [Environment]::ExpandEnvironmentVariables($root.Trim().Trim('"')).TrimEnd('\')
        # Only walk specific local install directories, never a whole drive or system folder.
        if ($path -notmatch '^[A-Za-z]:\\' -or $path -in @($env:ProgramFiles,${env:ProgramFiles(x86)},$env:USERPROFILE,$env:LOCALAPPDATA,$env:ProgramData) -or
            $path -eq $env:SystemRoot -or $path.StartsWith("$env:SystemRoot\",[StringComparison]::OrdinalIgnoreCase)) { continue }
        $pending.Push($path)
    }
    while ($pending.Count) {
        $path = $pending.Pop()
        if ($seen.ContainsKey($path)) { continue }
        $seen[$path] = $true
        try {
            if ([IO.File]::GetAttributes($path) -band [IO.FileAttributes]::ReparsePoint) { continue }
            foreach ($file in [IO.Directory]::EnumerateFiles($path,'*.exe')) { [IO.Path]::GetFileName($file) }
            foreach ($dir in [IO.Directory]::EnumerateDirectories($path)) { $pending.Push($dir) }
        } catch [IO.IOException] { continue } catch [UnauthorizedAccessException] { continue }
    }
}

function Start-HdrInstalledScan {
    if ($script:hdrTray.InstalledScan) { return }
    $worker = [PowerShell]::Create()
    try {
        [void]$worker.AddScript(${function:Get-HdrInstalledExecutableNames}.ToString())
        $script:hdrTray.InstalledScan = @{ Worker=$worker; Result=$worker.BeginInvoke() }
    } catch { $worker.Dispose(); throw }
}

function Complete-HdrInstalledScan {
    $scan = $script:hdrTray.InstalledScan
    if (-not $scan -or -not $scan.Result.IsCompleted) { return }
    $script:hdrTray.InstalledScan = $null
    try {
        $found = @{}
        foreach ($name in $scan.Worker.EndInvoke($scan.Result)) {
            if ($name.EndsWith('.exe',[StringComparison]::OrdinalIgnoreCase)) {
                $found[[IO.Path]::GetFileNameWithoutExtension($name)] = $true
            }
        }
        $script:hdrTray.InstalledApps = $found
    } catch { Write-HdrDiagnostic 'GAME LISTS' $_.Exception.Message }
    finally { $scan.Worker.Dispose() }
    Update-HdrGameListsPanel
}

function Get-HdrGameListRows {
    $lists = Get-HdrAppListState -IncludeDisabledDefaults
    $detected = Read-HdrDetectedApps
    $all = @{}
    $installed = @{}
    foreach ($name in Get-HdrRunningAppNames) { $installed[$name] = $true }
    if ($script:hdrTray.InstalledApps) {
        foreach ($key in $script:hdrTray.InstalledApps.Keys) { $installed[$key] = $true }
    }
    foreach ($key in $installed.Keys) { if ($lists.Defaults.ContainsKey($key)) { $all[$key] = $true } }
    foreach ($map in @($lists.Custom,$lists.Excluded,$detected)) {
        foreach ($key in $map.Keys) { $all[$key] = $true }
    }
    $automatic = Get-HdrAutomationPreference 'AutomaticHdr'
    foreach ($key in @($all.Keys | Sort-Object)) {
        $section = if ($detected.ContainsKey($key)) { 'Auto-detected' }
            elseif ($lists.DefaultOverrides.ContainsKey($key) -and $installed.ContainsKey($key)) { 'Installed' }
            elseif ($lists.Custom.ContainsKey($key) -or $lists.Excluded.ContainsKey($key)) { 'Custom' } else { 'Installed' }
        $status = if ($lists.Excluded.ContainsKey($key)) { 'Excluded by custom list' }
            elseif (-not $lists.Effective.ContainsKey($key)) {
                if ($lists.Defaults.ContainsKey($key)) { 'Defaults disabled' } else { 'No longer in defaults' }
            } elseif (-not $automatic) { 'Auto-enable HDR is off' }
            elseif ($lists.Custom.ContainsKey($key) -and -not $lists.Defaults.ContainsKey($key)) { 'Custom entry (HDR not verified)' }
            else { 'Watching' }
        [pscustomobject]@{
            Section=$section
            Enabled=$lists.Effective.ContainsKey($key)
            CanRemove=($detected.ContainsKey($key) -or $lists.Custom.ContainsKey($key) -or $lists.Excluded.ContainsKey($key))
            Executable=$(if ($detected.ContainsKey($key)) { $detected[$key].Executable } else { $key + '.exe' })
            Status=$status
            Detected=$(if ($detected.ContainsKey($key)) { ([DateTime]::Parse($detected[$key].DetectedUtc)).ToLocalTime().ToString('g') } else { '' })
        }
    }
}

function Set-HdrGameEnabled([string[]]$Executable,[bool]$Enabled) {
    $profiles=Read-HdrProfiles
    $byName=@{}
    foreach ($rule in $profiles.Rules) { $byName[(ConvertTo-HdrAppKey $rule.Executable)]=$rule }
    $newRules=@(foreach ($name in $Executable) {
        $key=ConvertTo-HdrAppKey $name
        $rule=$byName[$key]
        if ($null -eq $rule) {
            $rule=New-HdrGameRule $name
            # A checkbox on a default should remain in place so it can be checked again.
            $rule | Add-Member NoteProperty KeepInDefaults $true
            $byName[$key]=$rule
            $rule
        }
        $rule.Enabled=$Enabled
    })
    if ($newRules.Count) {
        $profiles.Rules+= $newRules
    }
    Save-HdrProfiles $profiles
}

# Remove the local entries that contributed this row. The downloaded catalog is read-only.
function Remove-HdrLocalGame([string]$Executable) {
    $key=ConvertTo-HdrAppKey $Executable
    if (-not $key) { throw 'Invalid executable name.' }
    $profiles=Read-HdrProfiles
    $history=Read-HdrDetectedApps
    $path=Get-HdrCustomAppsPath
    try { $custom=[IO.File]::ReadAllText($path) }
    catch [IO.FileNotFoundException] { $custom='' }
    # Keep comments, blank lines and original line endings on all other entries.
    $updated=[regex]::Replace($custom,'[^\r\n]+(?:\r\n|\n|\r|$)',{
        param($line)
        $value=$line.Value.Trim()
        if ($value.StartsWith('!')) { $value=$value.Substring(1) }
        if ((ConvertTo-HdrAppKey $value) -eq $key) { return '' }
        return $line.Value
    })
    if ($updated -cne $custom) { Write-HdrAtomicText $path $updated }
    if ($history.ContainsKey($key)) { $history.Remove($key); Write-HdrDetectedApps $history }
    $remaining=@($profiles.Rules | Where-Object { (ConvertTo-HdrAppKey $_.Executable) -ne $key })
    if ($remaining.Count -ne $profiles.Rules.Count) { $profiles.Rules=$remaining; Save-HdrProfiles $profiles }
}

function Update-HdrGameListsPanel {
    $panel = $script:hdrTray.SettingsWindow
    if ($null -eq $panel -or $panel.IsDisposed) { return }
    try {
        $panel.RefreshButton.Enabled = -not $script:hdrTray.InstalledScan
        $panel.RefreshButton.Text = if ($script:hdrTray.InstalledScan) { 'Scanning...' } else { 'Refresh' }
        $rows = @(Get-HdrGameListRows)
        $panel.ClearRows()
        foreach ($row in $rows) { $panel.AddRow($row.Section,$row.Executable,$row.Status,$row.Detected,$row.Enabled,$row.CanRemove) }
        $panel.FinishRows()
    } catch { [void](Show-HdrMessage 'The game lists could not be read. Your saved lists have not been changed.') }
}

function Show-HdrAppSettings([string]$DisplayId) {
    if ($null -eq $script:hdrTray.SettingsWindow -or $script:hdrTray.SettingsWindow.IsDisposed) {
        $script:hdrTray.SettingsWindow = [LocalHdrMenu.SettingsWindow]::new()
        $script:hdrTray.SettingsWindow.SetAutomaticSwitching((Get-HdrAutomationPreference 'AutomaticHdr'))
        $script:hdrTray.SettingsWindow.SetCommunityApps((Get-HdrAutomationPreference 'UseCommunityApps'))
        $script:hdrTray.SettingsWindow.add_CommandRequested({ param($command,$data)
            try {
                switch ($command) {
                    'LoadGames' { Start-HdrInstalledScan; Update-HdrGameListsPanel }
                    'EnableAutomatic' {
                        try { Switch-HdrAutomaticHdr -Enable }
                        finally { $script:hdrTray.SettingsWindow.SetAutomaticSwitching((Get-HdrAutomationPreference 'AutomaticHdr')) }
                    }
                    'EnableHdr' { if ($data) { Start-HdrChange 'On' ([string]$data) } }
                    'SaveBrightness' { Save-HdrBrightnessPanel $data }
                    'SetCommunityApps' {
                        try { Set-HdrAutomationPreference 'UseCommunityApps' $data }
                        finally { $script:hdrTray.SettingsWindow.SetCommunityApps((Get-HdrAutomationPreference 'UseCommunityApps')) }
                        Confirm-HdrSettingsSave
                        Update-HdrGameListsPanel
                    }
                    'Calibrate' { Open-HdrCalibration }
                    'HdrSettings' { Open-HdrSettings 'ms-settings:display-hdr' }
                    'NightLight' { Open-HdrSettings 'ms-settings:nightlight' }
                    'Location' { Open-HdrSettings 'ms-settings:privacy-location' }
                    'LoadProfiles' { Initialize-HdrProfileSettings }
                    'SaveGeneral' { Save-HdrGeneralSettings $data }
                    'CopyDiagnostics' {
                        [Windows.Forms.Clipboard]::SetText((Get-HdrDiagnostics))
                        $script:hdrTray.SettingsWindow.DiagnosticsCopied($true)
                    }
                    default { Invoke-HdrProfileButton $command ([string]$data) }
                }
            } catch { [void](Show-HdrMessage $_.Exception.Message) }
        })
        $script:hdrTray.SettingsWindow.add_Failed({ param($sender,$eventArgs) [void](Show-HdrMessage $sender.Error.Message) })
        $script:hdrTray.SettingsWindow.RefreshButton.add_Click({ Start-HdrInstalledScan; Update-HdrGameListsPanel })
        $script:hdrTray.SettingsWindow.UpdateCommunityButton.add_Click({ Start-HdrCommunityUpdate })
        $script:hdrTray.SettingsWindow.EditCustomButton.add_Click({ Edit-HdrCustomApps })
        $script:hdrTray.SettingsWindow.AddRunningButton.add_Click({ Show-HdrRunningApps })
        $script:hdrTray.SettingsWindow.AddGameButton.add_Click({ [void](Show-HdrGameRule) })
        $script:hdrTray.SettingsWindow.EditRuleButton.add_Click({
            $exe=$script:hdrTray.SettingsWindow.SelectedExecutable
            if ($exe) { [void](Show-HdrGameRule $exe) } else { [void](Show-HdrMessage 'Select a game first.') }
        })
        $script:hdrTray.SettingsWindow.LaunchButton.add_Click({
            try { $rule=Get-HdrSelectedGameRule; if ($null -ne $rule) { Start-HdrLaunch $rule } }
            catch { [void](Show-HdrMessage $_.Exception.Message) }
        })
        $script:hdrTray.SettingsWindow.ShortcutButton.add_Click({ Show-HdrShortcutSave })
        $script:hdrTray.SettingsWindow.add_EnableRequested({
            param($exe,$enabled)
            try { Set-HdrGameEnabled $exe $enabled; Confirm-HdrSettingsSave }
            catch { $script:hdrTray.SettingsWindow.FinishRows(); [void](Show-HdrMessage $_.Exception.Message) }
            Update-HdrGameListsPanel
        })
        $script:hdrTray.SettingsWindow.RemoveButton.add_Click({
            $exe=$script:hdrTray.SettingsWindow.SelectedExecutable
            if (-not $exe) { return }
            $prompt="Remove the local entry for ${exe}, including its saved settings and detection history?"
            try {
                if ((Get-HdrAppListState -IncludeDisabledDefaults).Defaults.ContainsKey((ConvertTo-HdrAppKey $exe))) {
                    $prompt+="`n`nThis game will follow the community list setting and appear under Installed if found on this PC."
                }
                if ((Show-HdrMessage $prompt 'YesNo') -eq [Windows.Forms.DialogResult]::Yes) {
                    Remove-HdrLocalGame $exe
                    Confirm-HdrSettingsSave
                }
            } catch { [void](Show-HdrMessage $_.Exception.Message) }
            Update-HdrGameListsPanel
        })
        Update-HdrCommunityUpdateButton
    }
    if ($script:hdrTray.DisplayReadError) { Update-HdrBrightnessPanel @() }
    else { Update-HdrBrightnessPanel $script:hdrTray.LastDisplays }
    if ($DisplayId) { $script:hdrTray.SettingsWindow.SelectDisplay($DisplayId) }
    $script:hdrTray.SettingsWindow.Show()
}

function Get-HdrRunningAppNames {
    # Match the running game itself, including direct EXE/offline installs.
    # No storefront client, parent launcher, install path, or store manifest is required.
    $session = [Diagnostics.Process]::GetCurrentProcess().SessionId
    $processes = @(Get-Process -ErrorAction Stop)
    foreach ($process in $processes) {
        try {
            if ($process.SessionId -eq $session) { $process.ProcessName }
        } catch [InvalidOperationException] {
            # A process can exit between enumeration and reading its name.
        } finally { $process.Dispose() }
    }
}

function Get-HdrAutomationTime { return [DateTime]::UtcNow }

function New-HdrAutomationState { return New-HdrPolicyState }
function Update-HdrAutomation($Displays) { Update-HdrPolicy $Displays }

function Get-HdrTrayState($Displays) {
    $capable = @($Displays | Where-Object HdrSupported)
    $enabledDisplays = @($capable | Where-Object HdrEnabled)
    $enabled = $enabledDisplays.Count
    $autoEnabled = $false
    foreach ($display in $enabledDisplays) {
        if (-not $script:hdrTray.Automation.Displays.Count) { break }
        $entry = $script:hdrTray.Automation.Displays[(Get-HdrMonitorKey $display)]
        if ($entry.Owned -and $entry.Expected -and -not $entry.Released -and $entry.DisplayId -ceq $display.DisplayId) {
            $autoEnabled = $true
            break
        }
    }
    $status = if (-not $capable.Count) { 'HDR: Unavailable' }
        elseif ($enabled -eq $capable.Count) { 'HDR: Enabled' }
        elseif ($enabled -eq 0) { 'HDR: Disabled' }
        else { 'HDR: Mixed' }
    $enableNext = $enabled -lt $capable.Count
    [pscustomobject]@{
        Status = $status
        IconState = if ($autoEnabled) { 'AutoEnabled' } elseif ($enabled) { 'Enabled' } elseif ($capable.Count) { 'Disabled' } else { 'Unavailable' }
        Command = if ($enableNext) { 'Enable HDR' } else { 'Disable HDR' }
        Action = if ($enableNext) { 'On' } else { 'Off' }
        Available = $capable.Count -gt 0
        DisplayName = if (@($Displays).Count -eq 1) { [string]$Displays[0].Name } else { '' }
        Details = @($Displays | ForEach-Object {
            $mode = if (-not $_.HdrSupported) { 'HDR: Unavailable' }
                elseif ($_.HdrEnabled) { 'HDR: Enabled' } else { 'HDR: Disabled' }
            [pscustomobject]@{
                Name = [string]$_.Name; Status = $mode; DisplayId = [string]$_.DisplayId
                Available = $_.HdrSupported -and -not [string]::IsNullOrEmpty($_.DisplayId)
                Action = if ($_.HdrEnabled) { 'Off' } else { 'On' }
            }
        })
    }
}

function Set-HdrTrayState($State) {
    $script:hdrTray.Status.SetCombinedStatus($State.Status, $script:hdrTray.Decision)
    $automatic = Get-HdrAutomationPreference 'AutomaticHdr'
    Set-HdrAutomaticMenuState $automatic
    $script:hdrTray.Icon.Icon = switch ($State.IconState) {
        { $_ -in 'Enabled','AutoEnabled' } { if ($automatic) { $script:hdrTray.AutoEnabledIcon } else { $script:hdrTray.EnabledIcon } }
        'Disabled' { if ($automatic) { $script:hdrTray.AutoIdleIcon } else { $script:hdrTray.DisabledIcon } }
        default { $script:hdrTray.UnavailableIcon }
    }
    # Explorer can miss an icon update during a display reconnect. Resend even
    # when the managed Icon property already holds the desired image.
    [LocalHdrMenu.TrayIconPosition]::Refresh($script:hdrTray.Icon)
    if ($null -ne $script:hdrTray.PressTracker) { $script:hdrTray.PressTracker.RefreshAnchor() }
    $script:hdrTray.Command.Text = if ($State.Available) { $State.Command } else { 'Enable HDR' }
    $script:hdrTray.Command.Tag = $State.Action
    $script:hdrTray.Command.Enabled = $State.Available -and $null -eq $script:hdrTray.Pending -and $null -eq $script:hdrTray.UpdateProcess -and $null -eq $script:hdrTray.Scene
    $script:hdrTray.ControlsMenu.SuspendLayout()
    $multipleDisplays = $State.Details.Count -gt 1
    $showDisplays = $multipleDisplays -or -not $State.Available
    if ($multipleDisplays -and $State.Available) { $script:hdrTray.Command.Text += ' on all displays' }
    $script:hdrTray.DisplayName.Text = [string]$State.DisplayName
    $script:hdrTray.DisplayName.Available = -not $showDisplays
    $script:hdrTray.Status.Available = $State.Status -ne 'HDR: Unavailable'
    $script:hdrTray.Displays.Available = $showDisplays
    if (-not $showDisplays -or -not $State.Details.Count) { $script:hdrTray.Displays.DropDown.Close() }
    $script:hdrTray.Command.Available = $State.Available
    $script:hdrTray.Automatic.Available = $State.Available
    $script:hdrTray.Brightness.Available = $State.Details.Count -eq 1 -and $State.Details[0].Available
    $script:hdrTray.Brightness.Tag = if ($State.Details.Count -eq 1) { $State.Details[0].DisplayId } else { $null }
    $script:hdrTray.CommandSeparator.Available = $State.Available
    $script:hdrTray.ControlsMenu.ResumeLayout($true)
    $details = ConvertTo-Json -InputObject @($State.Details) -Compress
    if ($details -ne $script:hdrTray.DetailsText) {
        $script:hdrTray.Displays.DropDown.SuspendLayout()
        try {
            foreach ($item in @($script:hdrTray.Displays.DropDownItems)) { $item.Dispose() }
            $script:hdrTray.Displays.DropDownItems.Clear()
            foreach ($display in $State.Details) {
                if ($script:hdrTray.Displays.DropDownItems.Count -gt 0) {
                    [void]$script:hdrTray.Displays.DropDownItems.Add((New-Object Windows.Forms.ToolStripSeparator))
                }
                foreach ($kind in @('Name','Status')) {
                    $item = New-Object LocalHdrMenu.TrayStatusItem
                    $item.Text = $display.$kind
                    $item.Name = if ($kind -eq 'Name') { 'Displays' } else { 'HdrStatus' }
                    $item.Tag = if ($kind -eq 'Status') { $display.Status } else { $null }
                    $item.Enabled = $false
                    $item.Padding = $script:hdrTray.Displays.Padding
                    [void]$script:hdrTray.Displays.DropDownItems.Add($item)
                }
                if ($display.Available) {
                    $item = New-Object Windows.Forms.ToolStripMenuItem
                    $item.Name = 'HdrAction'
                    $item.Text = if ($display.Action -eq 'On') { 'Enable HDR' } else { 'Disable HDR' }
                    $item.Tag = @{ Action = $display.Action; DisplayId = $display.DisplayId }
                    $item.Padding = $script:hdrTray.Displays.Padding
                    $item.add_Click({
                        param($sender, $eventArgs)
                        Start-HdrChange $sender.Tag.Action $sender.Tag.DisplayId
                    })
                    [void]$script:hdrTray.Displays.DropDownItems.Add($item)
                    $brightness = New-Object Windows.Forms.ToolStripMenuItem('SDR brightness...')
                    $brightness.Name = 'SdrBrightness'
                    $brightness.Tag = $display.DisplayId
                    $brightness.Padding = $script:hdrTray.Displays.Padding
                    $brightness.add_Click({ param($sender, $eventArgs) Show-HdrAppSettings ([string]$sender.Tag) })
                    [void]$script:hdrTray.Displays.DropDownItems.Add($brightness)
                }
            }
            $script:hdrTray.DetailsText = $details
        } finally { $script:hdrTray.Displays.DropDown.ResumeLayout($true) }
    }
    $script:hdrTray.Displays.Enabled = $State.Details.Count -gt 0
    Set-HdrDisplayCommandsEnabled ($null -eq $script:hdrTray.Pending -and $null -eq $script:hdrTray.UpdateProcess -and $null -eq $script:hdrTray.Scene)
    if ($null -ne $script:hdrTray.Pending) {
        $script:hdrTray.Command.Text = if ($null -ne $script:hdrTray.BrightnessPending) { 'Changing SDR brightness...' } else { 'Changing HDR...' }
    }
}

function Set-HdrDisplayCommandsEnabled([bool]$Enabled) {
    $script:hdrTray.Brightness.Enabled = $Enabled
    $script:hdrTray.Exit.Enabled = $null -eq $script:hdrTray.BrightnessPending -and $null -eq $script:hdrTray.Scene
    foreach ($item in $script:hdrTray.Displays.DropDownItems) {
        if ($item.Name -in @('HdrAction','SdrBrightness')) { $item.Enabled = $Enabled }
    }
}

function Update-HdrTray([switch]$NotifyRefresh) {
    if ($script:hdrTray.Refreshing) { return }
    $script:hdrTray.Refreshing=$true
    try {
        if ($null -ne $script:hdrTray.Pending -and $script:hdrTray.Pending.HasExited) {
            $succeeded = $script:hdrTray.Pending.ExitCode -eq 0
            $script:hdrTray.Pending.Dispose()
            $script:hdrTray.Pending = $null
            Complete-HdrPolicyCommand $succeeded
            Complete-HdrSceneStep $succeeded
            if ($null -ne $script:hdrTray.BrightnessPending) {
                Complete-HdrBrightnessChange $succeeded
            } elseif (-not $succeeded) {
                Show-HdrNotification 'Windows could not change HDR. Check HDR settings and try again.'
            } elseif ($script:hdrTray.ManualResult) {
                Show-HdrNotification $script:hdrTray.ManualResult
            }
            $script:hdrTray.ManualResult=$null
        }
        foreach ($id in @($script:hdrTray.BrightnessEdits.Keys)) {
            if ($null -ne $script:hdrTray.Pending -or $null -ne $script:hdrTray.UpdateProcess -or $null -ne $script:hdrTray.Scene) { break }
            Save-HdrBrightnessPanel $script:hdrTray.BrightnessEdits[$id]
        }
        try { $displays = @([LocalHdrMenu.DisplayApi]::Read()) }
        catch {
            Receive-HdrLaunchRequests -UpdatesOnly
            if ($NotifyRefresh) { Show-HdrNotification 'Could not refresh displays. Try again.' }
            throw
        }
        $script:hdrTray.LastDisplays=$displays
        $script:hdrTray.DisplayReadError=$null
        # Background reads establish the initial baseline but never consume changes.
        if ($NotifyRefresh -or $null -eq $script:hdrTray.RefreshDisplayIds) {
            $ids=@(foreach ($d in $displays) {
                if ($d.DevicePath) { $d.DevicePath.ToUpperInvariant() } else { $d.DisplayId }
            })
            $previous=$script:hdrTray.RefreshDisplayIds
            $script:hdrTray.RefreshDisplayIds=$ids
            if ($NotifyRefresh) {
                $changes=@(if ($null -ne $previous) { Compare-Object $previous $ids -CaseSensitive })
                $added=@($changes | Where-Object SideIndicator -eq '=>').Count
                $removed=$changes.Count-$added
                $total=if ($displays.Count -eq 1) { '1 display connected' } else { "$($displays.Count) displays connected" }
                Show-HdrNotification "Displays refreshed.`n$added added, $removed removed. $total."
            }
        }
        try {
            $profiles=Read-HdrProfiles
            foreach ($d in $displays) { $d.Name=Get-HdrMonitorName $d $profiles }
        } catch { Write-HdrDiagnostic 'SETTINGS' $_.Exception.Message }
        Set-HdrTrayState (Get-HdrTrayState $displays)
        # A transient file/registry failure must not stop the tray or its timer.
        try { Sync-HdrMenu $displays } catch { }
        Receive-HdrLaunchRequests
        Update-HdrScene $displays
        Update-HdrAutomation $displays
        Update-HdrLaunches $displays
        Update-HdrBrightness $displays
    } catch {
        $script:hdrTray.DisplayReadError=$_.Exception.Message
        Write-HdrDiagnostic 'DISPLAY' $_.Exception.Message
        Update-HdrBrightnessPanel @()
        Set-HdrTrayState ([pscustomobject]@{
            Status='HDR: Temporarily unreadable'; IconState='Unavailable'; Available=$false; Action='On'; Command='Enable HDR'; DisplayName=''; Details=@()
        })
    } finally { $script:hdrTray.Refreshing=$false }
}

function Open-HdrCalibration {
    # Query this user's registration each time, so installs/uninstalls take effect
    # without restarting the tray. Launch the packaged app through Windows Shell.
    try {
        $package = Get-AppxPackage -Name 'MicrosoftCorporationII.WindowsHDRCalibration' -ErrorAction Stop | Select-Object -First 1
        if ($null -ne $package) {
            Start-Process -FilePath (Join-Path $env:WINDIR 'explorer.exe') -ArgumentList (
                'shell:AppsFolder\{0}!App' -f $package.PackageFamilyName
            ) -ErrorAction Stop | Out-Null
            return
        }
    } catch { } # Missing/broken registration or launch: offer the Store listing.
    try {
        $store = Get-AppxPackage -Name 'Microsoft.WindowsStore' -ErrorAction Stop | Select-Object -First 1
        if ($null -ne $store) {
            Start-Process -FilePath 'ms-windows-store://pdp/?ProductId=9N7F2SM5D1LR' -ErrorAction Stop | Out-Null
            return
        }
    } catch { } # Do not invoke an unregistered Store protocol; use the web below.
    try {
        Start-Process -FilePath 'https://apps.microsoft.com/detail/9n7f2sm5d1lr' -ErrorAction Stop | Out-Null
    } catch {
        [void](Show-HdrMessage 'Windows HDR Calibration and its Microsoft Store page could not be opened. Visit https://apps.microsoft.com/detail/9n7f2sm5d1lr in your browser.')
    }
}

function Open-HdrSettings([string]$Uri) {
    try { Start-Process -FilePath $Uri | Out-Null }
    catch { Show-HdrNotification 'Windows Settings could not be opened.' }
}

function Switch-HdrStartup {
    try {
        $enabled=-not (Get-HdrStartupEnabled)
        Set-HdrStartupEnabled $enabled
        if (-not $enabled) { Show-HdrNotification 'The app will no longer start with Windows.' }
        elseif (-not (Get-HdrStartupEnabled)) { Show-HdrNotification 'To start with Windows, enable this app in Settings > Apps > Startup.' }
    }
    catch { Show-HdrNotification 'The startup preference could not be saved.' }
    $script:hdrTray.Startup.Checked = Get-HdrStartupEnabled
}

function Get-HdrInstalledVersion {
    $path = Join-Path $PSScriptRoot 'VERSION'
    if (Test-Path -LiteralPath $path) {
        $value = [IO.File]::ReadAllText($path).Trim()
        [void](ConvertTo-HdrVersion $value)
        return $value
    }
    return $null
}

function Show-HdrMessage([string]$Text, [Windows.Forms.MessageBoxButtons]$Buttons = 'OK') {
    $dialog=[LocalHdrMenu.DialogMessageForm]::new($Text,$Buttons)
    try { return $dialog.ShowDialog() }
    finally { $dialog.Dispose() }
}

function New-HdrAboutWindow {
    $version = Get-HdrInstalledVersion
    $label = if ($version) { $version } else { 'Unknown' }
    return [LocalHdrMenu.DialogMessageForm]::new("Left click: HDR controls`nRight click: Settings and app options`nMiddle click: Toggle HDR", 'OK', $label)
}

function Show-HdrAbout {
    $window=$script:hdrTray.AboutWindow
    if ($window.Visible) { $window.Activate(); return }
    [void]$window.ShowDialog()
}

function Start-HdrUpdateCheck([switch]$FromNotification, [switch]$Automatic) {
    if ($null -ne $script:hdrTray.UpdateCheck -or $null -ne $script:hdrTray.UpdateProcess -or $null -ne $script:hdrTray.CommunityUpdate) { return }
    if ($Automatic -and -not $script:hdrTray.AboutWindow.AutoCheckUpdates.Checked) { return }
    if ($script:hdrTray.AboutWindow.AutoCheckUpdates.Checked) {
        $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        if ($Automatic -and $now -lt $script:hdrTray.NextUpdateCheck) { return }
        $script:hdrTray.NextUpdateCheck = $now + 86400
        try { [Microsoft.Win32.Registry]::SetValue($script:hdrUpdateSettingsKey,'NextUpdateCheck',$script:hdrTray.NextUpdateCheck,[Microsoft.Win32.RegistryValueKind]::QWord) }
        catch { Write-HdrDiagnostic 'UPDATE' ('Could not save the next update check: ' + $_.Exception.Message) }
    }
    $script:hdrTray.AboutWindow.SetUpToDate($false)
    $script:hdrTray.CheckUpdates.Enabled = $false
    $script:hdrTray.CheckUpdates.Text = 'Checking for updates...'
    $script:hdrTray.CheckFromNotification = $FromNotification.IsPresent
    $script:hdrTray.AutomaticUpdateCheck = $Automatic.IsPresent
    $script:hdrTray.UpdateCheck = [LocalHdrMenu.UpdateCheck]::new()
    $script:hdrTray.UpdateCheck.Start()
    Update-HdrCommunityUpdateButton
}

function Complete-HdrUpdateCheck {
    $check = $script:hdrTray.UpdateCheck
    if ($null -eq $check -or -not $check.Finished) { return }
    $script:hdrTray.UpdateCheck = $null
    Update-HdrCommunityUpdateButton
    $script:hdrTray.CheckUpdates.Enabled = $true
    $script:hdrTray.CheckUpdates.Text = 'Check for updates'
    try {
        if ($check.Error) { throw $check.Error }
        $installed = Get-HdrInstalledVersion
        $currentVersion = ConvertTo-HdrVersion $installed
        if (-not $check.NoRelease) {
            $release = $check.Result | ConvertFrom-Json -ErrorAction Stop
            if ($release.draft -ne $false -or $release.prerelease -ne $false -or $release.tag_name -cnotmatch '^v(.+)$') { throw 'Invalid release response' }
            $latest = $Matches[1]
            if ((ConvertTo-HdrVersion $latest) -gt $currentVersion) {
                $script:hdrTray.AvailableVersion = $latest
                $script:hdrTray.CheckUpdates.Text = 'Install update'
                $script:hdrTray.AboutWindow.SetAvailableVersion($latest)
                $script:hdrTray.CheckedForUpdates = $true
                if (-not $script:hdrTray.CheckFromNotification) {
                    Show-HdrNotification "A newer version is available: $latest (installed: $installed).`nClick to install the update." -InstallVersion $latest
                }
                return
            }
        }
        $script:hdrTray.AvailableVersion = $null
        Remove-ItemProperty -LiteralPath ('Registry::'+$script:hdrUpdateSettingsKey) -Name UpdateOffer -ErrorAction SilentlyContinue
        $script:hdrTray.AboutWindow.SetAvailableVersion($null)
        $script:hdrTray.CheckedForUpdates = $true
        if ($script:hdrTray.AboutWindow.Visible) { $script:hdrTray.AboutWindow.SetUpToDate($true) }
        if (-not $script:hdrTray.CheckFromNotification -and -not $script:hdrTray.AutomaticUpdateCheck) {
            if ($check.NoRelease) { Show-HdrNotification "No newer version is available. Current version: $installed." -OpenAbout }
            else { Show-HdrNotification "You have the latest version ($installed)." -OpenAbout }
        }
    } catch {
        if ($script:hdrTray.AvailableVersion) { $script:hdrTray.CheckUpdates.Text = 'Install update' }
        if ($script:hdrTray.AutomaticUpdateCheck) { Write-HdrDiagnostic 'UPDATE' $_.Exception.Message }
        else { [void](Show-HdrMessage 'Could not check for updates. Check your internet connection and try again later.') }
    }
}

function Install-HdrNotificationUpdate([string]$Id) {
    $offer = [string][Microsoft.Win32.Registry]::GetValue($script:hdrUpdateSettingsKey,'UpdateOffer','')
    $token,$version = $offer -split '/',2
    if ($Id -cnotmatch '^[a-f0-9]{32}$' -or $token -cne $Id) { return }
    if ((ConvertTo-HdrVersion $version) -le (ConvertTo-HdrVersion (Get-HdrInstalledVersion))) { return }
    if ($null -ne $script:hdrTray.UpdateProcess) { return }
    if ($null -ne $script:hdrTray.CommunityUpdate) {
        [void](Show-HdrMessage 'Please wait for the community list update to finish, then click the update notification again.')
        return
    }
    # Ignore a background check that would otherwise overwrite the installer's button state.
    $script:hdrTray.UpdateCheck = $null
    $script:hdrTray.AvailableVersion = $version
    $script:hdrTray.AboutWindow.SetAvailableVersion($version)
    $script:hdrTray.CheckUpdates.Text = 'Install update'
    $script:hdrTray.CheckUpdates.Enabled = $true
    Update-HdrCommunityUpdateButton
    Start-HdrAppUpdate $version
}

function Start-HdrAppUpdate([string]$Version) {
    if ($null -ne $script:hdrTray.UpdateProcess -or $null -ne $script:hdrTray.CommunityUpdate) { return }
    if ($null -ne $script:hdrTray.Pending -or $null -ne $script:hdrTray.Scene -or @($script:hdrTray.Launches.Values | Where-Object { -not $_.Started }).Count) { [void](Show-HdrMessage 'Please wait for the HDR change to finish, then check for updates again.'); return }
    try {
        [void](ConvertTo-HdrVersion $Version)
        $script:hdrTray.UpdateProcess = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList (
            '-NoProfile -NonInteractive -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" -Version {1}' -f (Join-Path $PSScriptRoot 'Update-HdrApp.ps1'),$Version
        ) -WindowStyle Hidden -PassThru -ErrorAction Stop
        $script:hdrTray.CheckUpdates.Text = 'Updating...'
        Update-HdrCommunityUpdateButton
        $script:hdrTray.CheckUpdates.Enabled = $false
        $script:hdrTray.Command.Enabled = $false
        Set-HdrDisplayCommandsEnabled $false
    } catch { [void](Show-HdrMessage 'The update could not be started. Please try again.') }
}

function Complete-HdrAppUpdate {
    if ($null -ne $script:hdrTray.UpdateProcess -and $script:hdrTray.UpdateProcess.HasExited) {
        $script:hdrTray.UpdateProcess.Dispose()
        $script:hdrTray.UpdateProcess = $null
        Update-HdrCommunityUpdateButton
        $script:hdrTray.CheckUpdates.Text = if ($script:hdrTray.AvailableVersion) { 'Install update' } else { 'Check for updates' }
        $script:hdrTray.CheckUpdates.Enabled = $true
    }
}

function Start-HdrChange([string]$NextAction, [string]$DisplayId, [switch]$Automatic) {
    if ($null -ne $script:hdrTray.Pending -or $null -ne $script:hdrTray.UpdateProcess -or $NextAction -notin @('On','Off','Toggle') -or (-not $Automatic -and $null -ne $script:hdrTray.Scene)) { return }
    try {
        $targetArgument = ''
        if ($DisplayId) {
            if ($DisplayId -cnotmatch '^[A-Za-z0-9+/=]+$') { throw 'Invalid display identity.' }
            $targetArgument = ' -DisplayId "{0}"' -f $DisplayId
        }
        # Keep the menu responsive while Windows changes display mode. Use the
        # explicit action offered by the menu. Middle-click uses Toggle, which
        # reads the current Windows state in the child before choosing On/Off.
        $script:hdrTray.Pending = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList (
            '-NoLogo -NoProfile -NonInteractive -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" -Action {1}{2} -FromHelper' -f $installedScript,$NextAction,$targetArgument
        ) -WindowStyle Hidden -PassThru
        if (-not $Automatic) {
            if ($NextAction -in 'On','Off') {
                $state=if ($NextAction -eq 'On') { 'enabled' } else { 'disabled' }
                $display=$script:hdrTray.LastDisplays | Where-Object { $DisplayId -and $_.DisplayId -ceq $DisplayId } | Select-Object -First 1
                $script:hdrTray.ManualResult=if ($display.Name) { "HDR $state on $($display.Name)." } else { "HDR $state." }
            }
            Release-HdrAutomationDisplay $DisplayId
            Write-HdrDiagnostic 'MANUAL' ('Requested '+$NextAction)
        }
        $script:hdrTray.Command.Enabled = $false
        Set-HdrDisplayCommandsEnabled $false
        $script:hdrTray.Command.Text = 'Changing HDR...'
    } catch {
        Show-HdrNotification 'The HDR command could not be started.'
    }
}

function Show-HdrControls {
    Show-HdrTrayMenu $script:hdrTray.ControlsMenu $script:hdrTray.Menu
}

function Show-HdrSettingsMenu {
    Show-HdrTrayMenu $script:hdrTray.Menu $script:hdrTray.ControlsMenu
}

function Show-HdrTrayMenu($Menu, $OtherMenu) {
    if ($script:hdrTray.PressTracker.ConsumeHide($Menu)) {
        if ($Menu.Visible) { $Menu.Close() }
        return
    }
    if ($OtherMenu.Visible) { $OtherMenu.Close() }
    $script:hdrTray.PressTracker.RefreshAnchor()
    # Reuse NotifyIcon's native popup handling for focus, taskbar placement,
    # keyboard navigation, and dismissal when clicking elsewhere (.NET 4.x).
    $script:hdrTray.Icon.ContextMenuStrip = $Menu
    try {
        [void]$script:hdrTray.ShowMenuMethod.Invoke($script:hdrTray.Icon, $null)
    } finally {
        # Leave automatic right-click opening disabled; both buttons use this
        # toggle path, after Windows has delivered their button-up event.
        $script:hdrTray.Icon.ContextMenuStrip = $null
    }
}

function Initialize-HdrTray {
    [Windows.Forms.Application]::EnableVisualStyles()
    $script:hdrTray = @{
        Icon = New-Object Windows.Forms.NotifyIcon
        Menu = New-Object LocalHdrMenu.TrayPopupMenu
        ControlsMenu = New-Object LocalHdrMenu.TrayPopupMenu
        ShowMenuMethod = [Windows.Forms.NotifyIcon].GetMethod('ShowContextMenu', [Reflection.BindingFlags]'Instance,NonPublic')
        Status = New-Object LocalHdrMenu.TrayStatusItem
        DisplayName = New-Object LocalHdrMenu.TrayStatusItem
        Command = New-Object Windows.Forms.ToolStripMenuItem
        Brightness = New-Object Windows.Forms.ToolStripMenuItem('SDR brightness...')
        BrightnessPending = $null
        BrightnessEdits = @{}
        SettingsWindow = $null
        BrightnessStates = @{}
        LastBrightness = Get-HdrLastBrightnessLevels
        CommandSeparator = New-Object Windows.Forms.ToolStripSeparator
        Displays = New-Object Windows.Forms.ToolStripMenuItem('Displays')
        Refresh = New-Object Windows.Forms.ToolStripMenuItem('Refresh displays')
        Startup = New-Object Windows.Forms.ToolStripMenuItem('Start with Windows')
        Automatic = New-Object Windows.Forms.ToolStripMenuItem
        AppSettings = New-Object Windows.Forms.ToolStripMenuItem('Settings...')
        CommunityUpdate = $null
        Automation = New-HdrAutomationState
        PolicyPending = $null
        Scene = $null
        Launches = @{}
        Decision = ''
        EventWindow = New-Object LocalHdrMenu.HdrEventWindow
        EventTimer = New-Object Windows.Forms.Timer
        EventRetries = 0
        HotkeyBindings = @{}
        AboutWindow = New-HdrAboutWindow
        About = New-Object Windows.Forms.ToolStripMenuItem('About')
        UpdateCheck = $null
        UpdateProcess = $null
        Exit = New-Object Windows.Forms.ToolStripMenuItem('Exit')
        Timer = New-Object Windows.Forms.Timer
        EnabledIcon = [Drawing.Icon]::new((Join-Path $PSScriptRoot 'HdrEnabledPaused.ico'), [Windows.Forms.SystemInformation]::SmallIconSize)
        AutoEnabledIcon = [Drawing.Icon]::new((Join-Path $PSScriptRoot 'HdrAutoEnabled.ico'), [Windows.Forms.SystemInformation]::SmallIconSize)
        AutoIdleIcon = [Drawing.Icon]::new((Join-Path $PSScriptRoot 'HdrAutoIdle.ico'), [Windows.Forms.SystemInformation]::SmallIconSize)
        DisabledIcon = [Drawing.Icon]::new((Join-Path $PSScriptRoot 'HdrDisabled.ico'), [Windows.Forms.SystemInformation]::SmallIconSize)
        UnavailableIcon = [Drawing.Icon]::new((Join-Path $PSScriptRoot 'HdrUnavailable.ico'), [Windows.Forms.SystemInformation]::SmallIconSize)
        MenuFont = New-Object Drawing.Font('Segoe UI',10)
        Pending = $null
        DetailsText = $null
    }
    $script:hdrTray.Status.Enabled = $false
    $script:hdrTray.DisplayName.Enabled = $false
    $script:hdrTray.Icon.Icon = $script:hdrTray.UnavailableIcon
    $script:hdrTray.Icon.ContextMenuStrip = $null
    $script:hdrTray.Status.add_TextChanged({ $script:hdrTray.Icon.Text = $script:hdrTray.Status.TrayIconText })
    $script:hdrTray.Menu.ShowImageMargin = $false
    $script:hdrTray.ControlsMenu.ShowImageMargin = $false
    $script:hdrTray.Menu.AnchorIcon = $script:hdrTray.Icon
    $script:hdrTray.ControlsMenu.AnchorIcon = $script:hdrTray.Icon
    $script:hdrTray.Menu.ShowActionIcons = $true
    $script:hdrTray.ControlsMenu.ShowActionIcons = $true
    [void]$script:hdrTray.ControlsMenu.Items.Add($script:hdrTray.DisplayName)
    [void]$script:hdrTray.ControlsMenu.Items.Add($script:hdrTray.Displays)
    [void]$script:hdrTray.ControlsMenu.Items.Add($script:hdrTray.Status)
    [void]$script:hdrTray.ControlsMenu.Items.Add($script:hdrTray.Refresh)
    [void]$script:hdrTray.ControlsMenu.Items.Add($script:hdrTray.CommandSeparator)
    [void]$script:hdrTray.ControlsMenu.Items.Add($script:hdrTray.Command)
    [void]$script:hdrTray.ControlsMenu.Items.Add($script:hdrTray.Automatic)
    [void]$script:hdrTray.ControlsMenu.Items.Add($script:hdrTray.Brightness)
    [void]$script:hdrTray.Menu.Items.Add($script:hdrTray.AppSettings)
    [void]$script:hdrTray.Menu.Items.Add((New-Object Windows.Forms.ToolStripSeparator))
    [void]$script:hdrTray.Menu.Items.Add($script:hdrTray.Startup)
    [void]$script:hdrTray.Menu.Items.Add($script:hdrTray.About)
    [void]$script:hdrTray.Menu.Items.Add((New-Object Windows.Forms.ToolStripSeparator))
    [void]$script:hdrTray.Menu.Items.Add($script:hdrTray.Exit)
    $script:hdrTray.Command.Name = 'HdrAction'
    $script:hdrTray.Brightness.Name = 'SdrBrightness'
    $script:hdrTray.Status.Name = 'HdrStatus'
    $script:hdrTray.DisplayName.Name = 'Displays'
    $script:hdrTray.Displays.Name = 'Displays'
    $script:hdrTray.Exit.Name = 'ExitAction'
    $script:hdrTray.Refresh.Name = 'RefreshDisplays'
    $script:hdrTray.Startup.Name = 'Startup'
    $script:hdrTray.Startup.Checked = Get-HdrStartupEnabled
    $script:hdrTray.Automatic.Name = 'AutoHdrPreference'
    $script:hdrTray.AppSettings.Name = 'AppSettings'
    Set-HdrAutomaticMenuState (Get-HdrAutomationPreference 'AutomaticHdr')
    $script:hdrTray.CheckUpdates = $script:hdrTray.AboutWindow.CheckUpdates
    $autoCheck = $script:hdrTray.AboutWindow.AutoCheckUpdates
    $autoCheck.Checked = [Microsoft.Win32.Registry]::GetValue($script:hdrUpdateSettingsKey,'AutoCheckUpdates',0) -eq 1
    $nextCheck = [Microsoft.Win32.Registry]::GetValue($script:hdrUpdateSettingsKey,'NextUpdateCheck',0)
    $script:hdrTray.NextUpdateCheck = if ($nextCheck -is [long]) { [Math]::Min($nextCheck,[DateTimeOffset]::UtcNow.AddDays(1).ToUnixTimeSeconds()) } else { 0 }
    $autoCheck.add_Click({
        param($sender,$eventArgs)
        try { [Microsoft.Win32.Registry]::SetValue($script:hdrUpdateSettingsKey,'AutoCheckUpdates',[int]$sender.Checked) }
        catch {
            $sender.Checked = -not $sender.Checked
            [void](Show-HdrMessage 'Could not save the daily update preference.')
        }
    })
    $script:hdrTray.About.Name = 'About'
    $script:hdrTray.Displays.DropDown = New-Object LocalHdrMenu.TrayPopupMenu
    $script:hdrTray.Displays.DropDown.ShowActionIcons = $true
    [LocalHdrMenu.TrayMenuTheme]::Apply($script:hdrTray.Menu, $script:hdrTray.MenuFont)
    [LocalHdrMenu.TrayMenuTheme]::Apply($script:hdrTray.ControlsMenu, $script:hdrTray.MenuFont)
    [LocalHdrMenu.TrayMenuTheme]::Apply($script:hdrTray.Displays.DropDown, $script:hdrTray.MenuFont)
    $script:hdrTray.Command.add_Click({ Start-HdrChange ([string]$script:hdrTray.Command.Tag) })
    $script:hdrTray.Brightness.add_Click({ Show-HdrAppSettings ([string]$script:hdrTray.Brightness.Tag) })
    $script:hdrTray.Refresh.add_Click({ Update-HdrTray -NotifyRefresh })
    $script:hdrTray.Startup.add_Click({ Switch-HdrStartup })
    $script:hdrTray.Automatic.add_Click({ Switch-HdrAutomaticHdr })
    $script:hdrTray.AppSettings.add_Click({ Show-HdrAppSettings })
    $script:hdrTray.CheckUpdates.add_Click({
        if ($script:hdrTray.AvailableVersion) { Start-HdrAppUpdate $script:hdrTray.AvailableVersion }
        else { Start-HdrUpdateCheck }
    })
    $script:hdrTray.About.add_Click({ Show-HdrAbout })
    # MouseClick suppresses the second click of a double-click; MouseUp lets
    # every left/right click toggle, including fast consecutive clicks.
    $script:hdrTray.Icon.add_MouseUp({
        param($sender, $eventArgs)
        if ($eventArgs.Button -eq [Windows.Forms.MouseButtons]::Left) { Show-HdrControls }
        elseif ($eventArgs.Button -eq [Windows.Forms.MouseButtons]::Right) { Show-HdrSettingsMenu }
    })
    $script:hdrTray.Icon.add_MouseClick({
        param($sender, $eventArgs)
        if ($eventArgs.Button -eq [Windows.Forms.MouseButtons]::Middle) {
            $script:hdrTray.ControlsMenu.Close()
            $script:hdrTray.Menu.Close()
            Start-HdrChange 'Toggle'
        }
    })
    $script:hdrTray.ControlsMenu.add_Opening({ Update-HdrTray })
    $script:hdrTray.Menu.add_Opening({ $script:hdrTray.ControlsMenu.Close(); Update-HdrTray; $script:hdrTray.Startup.Checked = Get-HdrStartupEnabled })
    $script:hdrTray.Exit.add_Click({ [Windows.Forms.Application]::ExitThread() })
    $script:hdrTray.Timer.Interval = 2000
    $script:hdrTray.Timer.add_Tick({
        if (-not (Test-Path -LiteralPath $installedScript)) { [Windows.Forms.Application]::ExitThread(); return }
        Update-HdrTray
        Complete-HdrUpdateCheck
        Complete-HdrAppUpdate
        Complete-HdrCommunityUpdate
        Complete-HdrInstalledScan
        if ($script:hdrTray.AboutWindow.AutoCheckUpdates.Checked) { Start-HdrUpdateCheck -Automatic }
        if ($aboutRequest -and $aboutRequest.WaitOne(0)) {
            [void]$script:hdrTray.EventWindow.BeginInvoke([Action]{
                if (-not $script:hdrTray.CheckedForUpdates) { Start-HdrUpdateCheck -FromNotification }
                Show-HdrAbout
            })
        }
    })
    $script:hdrTray.EventTimer.Interval=350
    $script:hdrTray.EventWindow.add_DisplayChanged({
        $script:hdrTray.EventRetries=3
        $script:hdrTray.EventTimer.Start()
    })
    $script:hdrTray.EventTimer.add_Tick({
        Update-HdrTray
        $script:hdrTray.EventRetries--
        if ($script:hdrTray.EventRetries -le 0) { $script:hdrTray.EventTimer.Stop() }
    })
    $script:hdrTray.EventWindow.add_HotkeyPressed({ param($sender,$args)
        $binding=$script:hdrTray.HotkeyBindings[$sender.LastHotkey]
        if ($null -ne $binding) { Invoke-HdrBinding $binding }
    })
    try { Register-HdrBindings } catch { Write-HdrDiagnostic 'SHORTCUT' $_.Exception.Message }
    $script:hdrTray.PressTracker = [LocalHdrMenu.TrayPressTracker]::new($script:hdrTray.Icon,$script:hdrTray.ControlsMenu,$script:hdrTray.Menu)
}

function Close-HdrTray {
    if ($script:hdrTray.InstalledScan) { $script:hdrTray.InstalledScan.Worker.Dispose() }
    $script:hdrTray.AboutWindow.Dispose()
    if ($null -ne $script:hdrTray.RunningAppsPicker) { $script:hdrTray.RunningAppsPicker.Dispose() }
    if ($null -ne $script:hdrTray.EventTimer) { $script:hdrTray.EventTimer.Stop(); $script:hdrTray.EventTimer.Dispose() }
    if ($null -ne $script:hdrTray.EventWindow) { $script:hdrTray.EventWindow.Dispose() }
    if ($null -ne $script:hdrTray.SettingsWindow) { $script:hdrTray.SettingsWindow.Dispose() }
    $script:hdrTray.Timer.Stop()
    if ($null -ne $script:hdrTray.PressTracker) { $script:hdrTray.PressTracker.Dispose() }
    $script:hdrTray.Icon.Visible = $false
    $script:hdrTray.Timer.Dispose()
    $script:hdrTray.Icon.Dispose()
    $script:hdrTray.Menu.Dispose()
    $script:hdrTray.ControlsMenu.Dispose()
    $script:hdrTray.EnabledIcon.Dispose()
    $script:hdrTray.AutoEnabledIcon.Dispose()
    $script:hdrTray.AutoIdleIcon.Dispose()
    $script:hdrTray.DisabledIcon.Dispose()
    $script:hdrTray.UnavailableIcon.Dispose()
    $script:hdrTray.MenuFont.Dispose()
    if ($null -ne $script:hdrTray.Pending) { $script:hdrTray.Pending.Dispose() }
    if ($null -ne $script:hdrTray.UpdateProcess) { $script:hdrTray.UpdateProcess.Dispose() }
}

function Start-HdrTray {
    try { Register-HdrNotificationProtocol -RefreshShell } catch { Write-HdrDiagnostic 'NOTIFICATION' $_.Exception.Message }
    Initialize-HdrTray
    Write-HdrDiagnostic 'STARTUP' ('HDR Control '+(Get-HdrInstalledVersion)+'; profiles and event refresh ready')
    try {
        Update-HdrTray
        $script:hdrTray.Icon.Visible = $true
        $script:hdrTray.Timer.Start()
        [Windows.Forms.Application]::Run()
    } finally { Close-HdrTray }
}
