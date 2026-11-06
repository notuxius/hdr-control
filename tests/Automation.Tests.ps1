# Run in Windows PowerShell 5.1. Displays and HDR commands are simulated.
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot
. (Join-Path $repo 'HdrTray.ps1')
function Assert($Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
$id = [Guid]::NewGuid().ToString('N')
$root = Join-Path ([IO.Path]::GetTempPath()) ('hdr-automation-test-' + $id)
$key = 'HKCU:\Software\HdrContextMenu-AutomationTest-' + $id
New-Item -ItemType Directory -Path $root | Out-Null
try {
    # Exercise the real registry helpers against an isolated key.
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'HdrTray.ps1'),[ref]$null,[ref]$null)
    foreach ($name in @('Get-HdrAutomationPreference','Set-HdrAutomationPreference')) {
        $node = $ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
        . ([scriptblock]::Create($node.Extent.Text.Replace('HKCU:\Software\HdrContextMenu',$key)))
    }
    Assert (-not (Get-HdrAutomationPreference 'AutomaticHdr')) 'Experimental automatic HDR must default to disabled'
    Assert (Get-HdrAutomationPreference 'UseCommunityApps') 'Community list must default to enabled'
    Set-HdrAutomationPreference 'UseCommunityApps' $true
    Assert (-not (Get-HdrAutomationPreference 'AutomaticHdr')) 'A partial settings key must not opt into experimental automatic HDR'
    Set-HdrAutomationPreference 'AutomaticHdr' $false
    Assert (-not (Get-HdrAutomationPreference 'AutomaticHdr')) 'Disabled preference did not persist'
    Set-HdrAutomationPreference 'UseCommunityApps' $false
    Assert (-not (Get-HdrAutomationPreference 'AutomaticHdr')) 'Community-list toggle erased the disabled automatic-HDR preference'
    Set-HdrAutomationPreference 'AutomaticHdr' $true
    Assert (-not (Get-HdrAutomationPreference 'UseCommunityApps')) 'Automatic-HDR toggle erased the disabled community-list preference'
    Set-HdrAutomationPreference 'UseCommunityApps' $true
    Assert (Get-HdrAutomationPreference 'AutomaticHdr') 'Enabled preference did not persist'
    function Get-HdrCustomAppsPath { return Join-Path $root 'custom.txt' }
    $custom = Get-HdrCustomAppsPath
    $defaults = Get-HdrWatchedApps
    Assert ($defaults.Count -gt 0 -and $defaults.ContainsKey('alanwake2')) 'Bundled list missing'
    Assert (-not $defaults.ContainsKey('launcher')) 'Generic launcher must not be enabled'
    [IO.File]::WriteAllLines($custom,@(' # comment',' TestGame.EXE ','testgame','Other Game','!AlanWake2.exe','*.exe','C:\Other.exe','','.exe'))
    $names = Get-HdrWatchedApps
    Assert ($names.ContainsKey('testgame') -and $names.ContainsKey('other game')) 'Custom names or spaces failed'
    Assert (-not $names.ContainsKey('alanwake2') -and -not $names.ContainsKey('*') -and -not $names.ContainsKey('c:\other')) 'Exclusions or validation failed'
    Set-HdrAutomationPreference 'UseCommunityApps' $false
    $names = Get-HdrWatchedApps
    Assert ($names.Count -eq 2) 'Custom-only list must deduplicate case and extension'
    $ownName = [Diagnostics.Process]::GetCurrentProcess().ProcessName
    Assert (@(Get-HdrRunningAppNames) -contains $ownName) 'Real process enumeration missed this session'
    $script:realStart = ${function:Start-HdrChange}
    function Get-HdrRunningAppNames {
        if ($script:enumerationFails) { throw 'Process scan failed' }
        return $script:runningNames
    }
    function Get-HdrAutomationTime { return $script:now }
    function Start-HdrChange([string]$NextAction, [string]$DisplayId, [switch]$Automatic) {
        Assert $Automatic 'Automated requests must be marked automatic'
        Assert ($DisplayId -eq 'dGVzdA==') 'Automation must explicitly target the selected display'
        $script:requests.Add($NextAction)
        $script:hdrTray.Pending = [pscustomobject]@{HasExited=$false}
    }
    $icon = [pscustomobject]@{Warnings=0}
    function Show-HdrNotification($Message) { if ($Message -like 'Automatic HDR could not read*') { $icon.Warnings++ } }
    $script:hdrTray = @{
        Automation = New-HdrAutomationState
        Pending = $null; UpdateProcess = $null; Icon = $icon
        Command = [pscustomobject]@{Enabled=$true;Text='Enable HDR'}
        Automatic = [pscustomobject]@{Checked=$true; Text=''}
    }
    $script:requests = New-Object 'Collections.Generic.List[string]'
    $script:now = [DateTime]::UtcNow
    $script:runningNames = @()
    $script:enumerationFails = $false
    $off = @([pscustomobject]@{DevicePath='Test monitor';DisplayId='dGVzdA==';HdrSupported=$true;HdrEnabled=$false})
    $on = @([pscustomobject]@{DevicePath='Test monitor';DisplayId='dGVzdA==';HdrSupported=$true;HdrEnabled=$true})
    function Poll($Displays) {
        if ($null -eq $script:hdrTray.Pending -and $null -ne $script:hdrTray.PolicyPending) {
            $op=$script:hdrTray.PolicyPending
            Complete-HdrPolicyCommand (@($Displays | Where-Object { $_.HdrEnabled -eq $op.Target }).Count -gt 0)
        }
        $script:now = $script:now.AddSeconds(2); Update-HdrAutomation $Displays
    }
    function Reset-State {
        $script:hdrTray.Automation = New-HdrAutomationState
        $script:hdrTray.PolicyPending=$null
        $script:hdrTray.Pending = $null
        $script:hdrTray.UpdateProcess = $null
        $script:requests.Clear()
        $script:runningNames = @()
        $script:enumerationFails = $false
    }
    # Fresh/partial settings remain opt-in, even with a listed game running.
    Remove-ItemProperty -LiteralPath $key -Name AutomaticHdr
    $script:runningNames = @('testgame')
    Poll $off
    Assert ($requests.Count -eq 0 -and -not $hdrTray.Automation.Active) 'Default-off automation must not change HDR for running games'
    Set-HdrAutomationPreference 'AutomaticHdr' $true
    $script:runningNames = @()
    Poll $on
    Assert ($requests.Count -eq 0) 'Idle monitoring must leave pre-existing HDR alone'
    $script:runningNames = @('TESTGAME')
    Poll $off
    Assert ($requests.Count -eq 1 -and $requests[0] -eq 'On') 'App launch must turn HDR on'
    Poll $off
    Assert ($requests.Count -eq 1) 'Pending change must block overlap'
    $script:hdrTray.Pending = $null
    $script:runningNames = @('testgame','testgame','Other Game')
    Poll $on
    $script:runningNames = @('Other Game')
    Poll $on
    Assert ($requests.Count -eq 1) 'Closing some apps must leave HDR on'
    $script:runningNames = @()
    Poll $on
    Assert ($requests.Count -eq 2 -and $requests[1] -eq 'Off') 'The first scan after the last game exits must request Off by default'
    Update-HdrAutomation $on
    Assert ($requests.Count -eq 2) 'An immediate refresh must not duplicate the exit request'
    $script:hdrTray.Pending = $null
    Poll $off
    Assert (-not $hdrTray.Automation.Active) 'Successful off must release automatic control'
    Poll $on
    Assert ($requests.Count -eq 2) 'Later manual HDR must not be switched off while idle'

    Reset-State
    $script:runningNames = @('testgame')
    Poll $off
    $script:runningNames = @()
    Poll $off
    Poll $off
    Assert ($requests.Count -eq 1) 'App exit during On must wait for the command to finish'
    $script:hdrTray.Pending = $null
    Poll $on
    Assert ($requests.Count -eq 2 -and $requests[1] -eq 'Off') 'Late On completion must be followed by Off'

    Reset-State
    $script:runningNames = @('testgame')
    Poll @()
    Assert ($requests.Count -eq 0 -and $hdrTray.Automation.Active) 'Unavailable display must defer On'
    Poll $off
    Assert ($requests.Count -eq 1) 'Display reconnect must retry On'
    $script:hdrTray.Pending = $null
    Poll $off
    Assert ($requests.Count -eq 1) 'Failed commands must respect retry delay'
    $script:now = $script:now.AddSeconds(30)
    Poll $off
    Assert ($requests.Count -eq 2) 'Failed On must retry'
    $script:hdrTray.Pending = $null
    Poll $on
    $script:enumerationFails = $true
    $script:runningNames = @()
    Poll $on
    Poll $on
    Assert ($requests.Count -eq 2 -and $icon.Warnings -eq 1) 'Failed process scan must preserve HDR and warn once'
    $script:enumerationFails = $false
    Poll $on
    Poll $on
    Assert ($requests.Count -eq 3 -and $requests[2] -eq 'Off') 'Successful scans must recover after failure'
    $script:hdrTray.Pending = $null
    Poll $on
    Assert ($requests.Count -eq 3) 'Failed Off must respect retry delay'
    $script:now = $script:now.AddSeconds(30)
    Poll $on
    Assert ($requests.Count -eq 4 -and $requests[3] -eq 'Off') 'Failed Off must retry'
    $script:hdrTray.Pending = $null
    $script:runningNames = @('testgame')
    Poll $off
    Assert ($requests.Count -eq 5 -and $requests[4] -eq 'On') 'New app must supersede pending Off retry immediately'

    Reset-State
    $script:runningNames = @('testgame')
    $script:hdrTray.UpdateProcess = [pscustomobject]@{}
    Poll $off
    Assert ($requests.Count -eq 0) 'App updates must block HDR changes'
    $script:hdrTray.UpdateProcess = $null
    Poll $off
    Assert ($requests.Count -eq 1) 'Automation must resume after update ends'
    $script:hdrTray.Pending = $null
    Switch-HdrAutomaticHdr
    Poll $on
    Assert (-not $hdrTray.Automatic.Checked -and -not $hdrTray.Automation.Active -and $requests.Count -eq 1) 'Pausing must release control without changing HDR'
    Switch-HdrAutomaticHdr
    Poll $on
    Assert ($hdrTray.Automation.Active) 'Resuming must recognize an already running app'

    # Real manual command path must suppress automatic On, including per-display commands.
    function Set-HdrDisplayCommandsEnabled($Enabled) { }
    function Start-Process { param($FilePath,$ArgumentList,$WindowStyle,[switch]$PassThru) return [pscustomobject]@{HasExited=$false} }
    $installedScript = Join-Path $repo 'HdrSdrMenu.ps1'
    & $script:realStart 'Off' 'dGVzdA=='
    Assert ($hdrTray.Automation.SuppressOn) 'Manual change must take precedence over automatic On'
    $script:hdrTray.Pending = $null
    $count = $requests.Count
    Poll $off
    Assert ($requests.Count -eq $count) 'Automatic On must not fight the manual override'
    $script:runningNames = @()
    Poll $on
    Poll $on
    Assert ($requests.Count -eq $count) 'Manual override must also release automatic exit changes'

    Reset-State
    $script:runningNames = @('testgame')
    Poll $on
    $lock = [IO.File]::Open($custom,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try {
        $script:runningNames = @()
        Poll $on
        Poll $on
        Assert ($requests.Count -eq 0 -and $hdrTray.Automation.Active) 'Unreadable custom file must not cause Off'
    } finally { $lock.Dispose() }
    Reset-State
    # Live custom-list edits are loaded without restarting the helper.
    [IO.File]::WriteAllLines($custom,@('NewGame.exe'))
    $script:runningNames = @('newgame')
    Poll $off
    Assert ($requests.Count -eq 1 -and $requests[0] -eq 'On') 'Saved custom edits must apply on the next poll'
    'PASS: app lists, persistence, immediate exit after the last game, pending commands, retries, reconnects, read failures, pause/resume, and manual overrides.'
} finally {
    if (Test-Path -LiteralPath $key) { Remove-Item -LiteralPath $key }
    $file = Join-Path $root 'custom.txt'
    if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file }
    Remove-Item -LiteralPath $root
}
