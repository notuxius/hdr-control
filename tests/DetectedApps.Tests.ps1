# Windows PowerShell 5.1 -STA. Isolated local history, simulated HDR commands.
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot
. (Join-Path $repo 'HdrTray.ps1')
function Assert($Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
$root = Join-Path ([IO.Path]::GetTempPath()) ('hdr-detected-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
function Get-HdrCustomAppsPath { return Join-Path $root 'custom.txt' }
function Get-HdrDetectedAppsPath { return Join-Path $root 'detected.json' }
function Get-HdrProfilesPath { return Join-Path $root 'profiles.json' }
function Get-HdrDefaultAppNames { return $script:defaults }
function Get-HdrRunningAppNames { return $script:running }
function Get-HdrAutomationPreference([string]$Name) {
    if ($Name -eq 'AutomaticHdr') { return $script:automatic }
    return $script:community
}
function Get-HdrAutomationTime { return $script:now }
function Start-HdrChange([string]$NextAction, [string]$DisplayId, [switch]$Automatic) { $script:requests.Add($NextAction); $script:hdrTray.Pending=[pscustomobject]@{HasExited=$false} }
function Poll {
    $script:now = $script:now.AddSeconds(2)
    Update-HdrAutomation @([pscustomobject]@{DevicePath='Test monitor';DisplayId='dGVzdA==';HdrSupported=$true;HdrEnabled=$false})
}
$icon = [pscustomobject]@{Warnings=0}
function Show-HdrNotification { $icon.Warnings++ }
$script:hdrTray = @{Automation=(New-HdrAutomationState);Icon=$icon;Pending=$null;UpdateProcess=$null}
$script:requests = New-Object 'Collections.Generic.List[string]'
$script:now = [DateTime]::UtcNow
$script:defaults = @('KnownOne.exe','KnownTwo.exe','NeverLaunched.exe','Excluded.exe')
$script:running = @('KnownOne','KNOWNTWO','KnownOne','CustomOnly','Excluded','Unknown')
$script:automatic = $false
$script:community = $true
$panel = $null
try {
    [IO.File]::WriteAllLines((Get-HdrCustomAppsPath), @('CustomOnly.exe','!Excluded.exe'))
    Poll
    Assert (-not [IO.File]::Exists((Get-HdrDetectedAppsPath))) 'Disabled automation recorded history'
    Assert ($requests.Count -eq 0) 'Disabled automation changed HDR'
    $script:automatic = $true
    Poll
    $history = Read-HdrDetectedApps
    Assert ($history.Count -eq 2 -and $history.ContainsKey('knownone') -and $history.ContainsKey('knowntwo')) 'Must record all known matches, excluding unknown/custom-only/excluded games'
    Assert ($requests.Count -eq 1 -and $requests[0] -eq 'On') 'Recording broke automatic HDR'
    $saved = [IO.File]::ReadAllText((Get-HdrDetectedAppsPath))
    $stamp = [IO.File]::GetLastWriteTimeUtc((Get-HdrDetectedAppsPath))
    Poll
    Assert ([IO.File]::GetLastWriteTimeUtc((Get-HdrDetectedAppsPath)) -eq $stamp) 'Repeated detections rewrote history'
    $script:hdrTray.Pending=$null; $script:hdrTray.PolicyPending=$null
    $script:hdrTray.Automation = New-HdrAutomationState
    Poll
    Assert ([IO.File]::ReadAllText((Get-HdrDetectedAppsPath)) -ceq $saved) 'Restart reset first detection or duplicated games'
    $rows = @(Get-HdrGameListRows)
    Assert ($rows.Count -eq 5) 'Rows must be deduplicated across lists'
    Assert (@($rows | Where-Object Section -eq 'Auto-detected').Count -eq 2) 'Detected section missing'
    Assert (@($rows | Where-Object Section -eq 'Defaults').Count -eq 1) 'Unseen defaults are misclassified'
    Assert (@($rows | Where-Object Section -eq 'Custom').Count -eq 2) 'Custom entries and exclusions missing'
    $panel = [LocalHdrMenu.GameListsForm]::new()
    $script:hdrTray.SettingsWindow = $panel
    Update-HdrGameListsPanel
    $tabs = @($panel.Controls | Where-Object { $_ -is [LocalHdrMenu.DialogTabs] })[0]
    Assert ($tabs.TabPages[0].Text -eq 'Auto-detected (2/2)' -and $tabs.TabPages[1].Text -eq 'Defaults (1/1)' -and $tabs.TabPages[2].Text -eq 'Custom (1/2)') 'Window sections/counts differ from saved records'
    # A later custom exclusion must override existing detection history.
    [IO.File]::AppendAllText((Get-HdrCustomAppsPath), "`r`n!KnownOne.exe")
    Assert (-not (Get-HdrWatchedApps).ContainsKey('knownone')) 'History bypassed exclusion'
    Assert ((@(Get-HdrGameListRows | Where-Object Executable -eq 'KnownOne.exe'))[0].Status -eq 'Excluded by custom list') 'Detected exclusion status missing'
    # Corrected defaults retain history but cannot continue watching removed entries.
    $script:defaults = @('NeverLaunched.exe','Excluded.exe')
    Assert (-not (Get-HdrWatchedApps).ContainsKey('knowntwo')) 'Removed default still active through history'
    Assert ((@(Get-HdrGameListRows | Where-Object Executable -eq 'KNOWNTWO.exe'))[0].Status -eq 'No longer in defaults') 'Removed default history status missing'
    $script:community = $false
    $script:running = @('NeverLaunched','CustomOnly')
    Poll
    Assert ((Read-HdrDetectedApps).Count -eq 2) 'Disabled community list or custom-only match recorded history'
    # Existing file replacement and immediate panel refresh on a new match.
    $script:community = $true
    Poll
    Assert ((Read-HdrDetectedApps).Count -eq 3) 'Second save failed to atomically replace history'
    Assert ($tabs.TabPages[0].Text -eq 'Auto-detected (1/3)') 'Open window did not refresh on detection'
    # Corruption must not get overwritten, and HDR must continue despite history errors.
    $script:hdrTray.SettingsWindow = $null
    [IO.File]::WriteAllText((Get-HdrDetectedAppsPath), '{broken')
    $script:hdrTray.Pending=$null; $script:hdrTray.PolicyPending=$null
    $script:hdrTray.Automation = New-HdrAutomationState
    $script:requests.Clear()
    Poll
    Poll
    Assert ($icon.Warnings -eq 1 -and $requests.Count -eq 1) 'History failure blocked HDR or repeated warnings'
    Assert ([IO.File]::ReadAllText((Get-HdrDetectedAppsPath)) -ceq '{broken') 'Corrupt history was overwritten'
    [IO.File]::WriteAllText((Get-HdrDetectedAppsPath), $saved)
    $lock = [IO.File]::Open((Get-HdrDetectedAppsPath), 'Open', 'Read', 'Read')
    try {
        $failed = $false
        try { Save-HdrDetectedApps @('NeverLaunched') @{neverlaunched=$true} } catch { $failed = $true }
        Assert $failed 'Locked history should fail replacement'
    } finally { $lock.Dispose() }
    Assert ([IO.File]::ReadAllText((Get-HdrDetectedAppsPath)) -ceq $saved) 'Failed save damaged last good history'
    Assert (@(Get-ChildItem -LiteralPath $root -Filter '*.tmp').Count -eq 0) 'Failed save left temporary files'
    $profiles=New-HdrProfiles
    $rule=New-HdrGameRule 'CustomOnly.exe'; $rule.LaunchPath='C:\Games\CustomOnly.exe'; $rule.ExitDelay=12
    $profiles.Rules=@($rule); Save-HdrProfiles $profiles
    $script:automatic=$false
    Set-HdrGameEnabled 'NeverLaunched.exe' $false
    $default=Get-HdrGameListRows | Where-Object Executable -eq 'NeverLaunched.exe'
    Assert (-not $default.Enabled -and $default.Section -eq 'Defaults') 'Unchecking a default moved it out of the tab'
    Remove-HdrLocalGame 'NeverLaunched.exe'
    Set-HdrGameEnabled 'CUSTOMONLY' $false
    Assert (-not (Get-HdrWatchedApps).ContainsKey('customonly')) 'Unchecked custom game still watched'
    Set-HdrGameEnabled 'customonly.exe' $true
    $restored=(Read-HdrProfiles).Rules[0]
    Assert ($restored.Id -eq $rule.Id -and $restored.LaunchPath -eq $rule.LaunchPath -and $restored.ExitDelay -eq 12) 'Checkbox reset existing rule settings'
    $entry=Get-HdrGameListRows | Where-Object Executable -eq 'customonly.exe'
    Assert ($entry.Enabled -and $entry.CanRemove -and $entry.Status -eq 'Auto-enable HDR is off') 'Checkbox should show per-game state when automatic HDR is off'
    $other="# Keep these lines`r`n!Excluded.exe`r`n`r`nOther.exe"
    [IO.File]::WriteAllText((Get-HdrCustomAppsPath)," customONLY `n!CustomOnly.exe`r`n"+$other)
    Remove-HdrLocalGame 'CustomOnly.exe'
    Assert ([IO.File]::ReadAllText((Get-HdrCustomAppsPath)) -ceq $other) 'Remove changed unrelated text or left a duplicate entry'
    Assert ((Read-HdrProfiles).Rules.Count -eq 0 -and -not @(Get-HdrGameListRows | Where-Object Executable -eq 'customonly.exe').Count) 'Remove did not delete local rule and text entries'
    $script:defaults+=@('KnownOne.exe')
    Set-HdrGameEnabled 'KnownOne.exe' $false
    $entry=Get-HdrGameListRows | Where-Object Executable -eq 'KnownOne.exe'
    Assert (-not $entry.Enabled -and $entry.CanRemove -and $entry.Section -eq 'Auto-detected') 'Detected game checkbox ignored its local exclusion'
    Remove-HdrLocalGame 'KNOWNONE'
    $entry=Get-HdrGameListRows | Where-Object Executable -eq 'KnownOne.exe'
    Assert ($entry.Enabled -and -not $entry.CanRemove -and $entry.Section -eq 'Defaults' -and (Read-HdrDetectedApps).ContainsKey('knowntwo')) 'Removing a local override did not restore the default or damaged unrelated history'
    'PASS: game detection, checkboxes, rule preservation, personal entry removal, default restoration, and history failures.'
} finally {
    if ($null -ne $panel) { $panel.Dispose() }
    $full = [IO.Path]::GetFullPath($root)
    if ([IO.Path]::GetDirectoryName($full) -ne [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') -or
        [IO.Path]::GetFileName($full) -notmatch '^hdr-detected-[a-f0-9]{32}$') { throw 'Invalid test cleanup path' }
    Remove-Item -LiteralPath $full -Recurse -Force
}
