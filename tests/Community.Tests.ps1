# Run with Windows PowerShell 5.1 -STA. No real HDR changes or network calls.
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot
. (Join-Path $repo 'HdrTray.ps1')
function Assert($Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Reject([scriptblock]$Action, [string]$Message) {
    $failed = $false
    try { & $Action | Out-Null } catch { $failed = $true }
    Assert $failed $Message
}
$root = Join-Path ([IO.Path]::GetTempPath()) ('hdr-community-tests-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
function Get-HdrCommunityCachePath { return Join-Path $root 'cache.txt' }
function Get-HdrCommunityBundlePath { return Join-Path $root 'bundle.txt' }
function Get-HdrCustomAppsPath { return Join-Path $root 'custom.txt' }
function Get-HdrAutomationPreference([string]$Name) { return $script:useCommunity }
function Show-HdrMessage([string]$Text) { $script:lastMessage = $Text }
function Update-HdrGameListsPanel { }
$script:useCommunity = $true
$header = "# HDR Context Menu community list v1`n"
$first = $header + "FirstGame.exe`nExcludedGame.exe`n"
$second = $header + "SecondGame.exe`nExcludedGame.exe`nsecondgame.EXE`n"
try {
    Copy-Item -LiteralPath (Join-Path $repo 'HdrApps.community.txt') -Destination (Get-HdrCommunityBundlePath)
    $bundle = @(Get-HdrDefaultAppNames)
    Assert ($bundle.Count -gt 0 -and $bundle -notcontains 'launcher') 'Offline first launch must use a valid bundle'
    foreach ($name in @('cyberpunk2077','rdr2','bg3_dx11','re2','re4','re7','re8','sb','asc-win64-shipping')) {
        Assert ($bundle -contains $name) ('Reviewed list is missing a confirmed executable: ' + $name)
    }
    foreach ($name in @('cube','masseffectlauncher','ontos','squadron42','stellarblade','jusant-win64-shipping')) {
        Assert ($bundle -notcontains $name) ('Inactive/replaced review entry leaked into active matching: ' + $name)
    }
    Assert ((Save-HdrCommunityList $first) -eq 2) 'First update must create a validated cache'
    Assert ((Save-HdrCommunityList $second) -eq 2) 'Subsequent updates must replace the cache and deduplicate'
    $script:hdrCommunityLastGood = $null
    Assert (@(Get-HdrDefaultAppNames) -contains 'secondgame') 'Cache must survive a fresh offline launch'
    [IO.File]::WriteAllText((Get-HdrCustomAppsPath), "CustomGame.exe`n!ExcludedGame.exe`n")
    $names = Get-HdrWatchedApps
    Assert ($names.Count -eq 2 -and $names.ContainsKey('customgame') -and $names.ContainsKey('secondgame')) 'Downloaded list must preserve custom additions and exclusions'
    $customHash = (Get-FileHash (Get-HdrCustomAppsPath)).Hash
    $cacheHash = (Get-FileHash (Get-HdrCommunityCachePath)).Hash
    foreach ($bad in @('', '<html>error</html>', $header, ($header + 'Launcher.exe'), ($header + '!Excluded.exe'),
        ($header + '*.exe'), ($header + 'C:\Game.exe'), ($header + '../Game.exe'), ($header + 'Game'),
        ($header + "Good.exe`nBad.exe`0"), ($header + ('x' * 1MB)))) {
        Reject { Save-HdrCommunityList $bad } 'Invalid download was accepted'
        Assert ((Get-FileHash (Get-HdrCommunityCachePath)).Hash -eq $cacheHash) 'Invalid download changed the cache'
    }
    $script:hdrTray = @{
        CommunityUpdate = $null; UpdateCheck = $null; UpdateProcess = $null
        SettingsWindow = [pscustomobject]@{IsDisposed=$false;UpdateCommunityButton=[pscustomobject]@{Enabled=$true;Text='Update community list'}}
        CheckUpdates = [pscustomobject]@{Enabled=$true;Text='Check for updates'}
    }
    foreach ($case in @('offline','invalid','success')) {
        $script:hdrTray.CommunityUpdate = [pscustomobject]@{
            Finished=$false; Error=$(if ($case -eq 'offline') {'Network unavailable'} else {$null})
            Result=$(if ($case -eq 'invalid') {'<html>error</html>'} else {$first})
        }
        $download = $script:hdrTray.CommunityUpdate
        Start-HdrCommunityUpdate
        Assert ([Object]::ReferenceEquals($download, $script:hdrTray.CommunityUpdate)) 'Repeated clicks started overlapping downloads'
        Start-HdrUpdateCheck
        Start-HdrAppUpdate '1.1.0'
        Assert ($null -eq $hdrTray.UpdateCheck -and $null -eq $hdrTray.UpdateProcess) 'App updater overlapped a list update'
        Complete-HdrCommunityUpdate
        Assert ($null -ne $hdrTray.CommunityUpdate) 'Unfinished download was consumed'
        $download.Finished = $true
        Complete-HdrCommunityUpdate
        Assert ($null -eq $hdrTray.CommunityUpdate -and $hdrTray.SettingsWindow.UpdateCommunityButton.Enabled -and $hdrTray.CheckUpdates.Enabled -and $hdrTray.SettingsWindow.UpdateCommunityButton.Text -eq 'Update community list') 'Completion did not restore update controls'
        if ($case -eq 'success') {
            Assert ($lastMessage -match 'updated: 2 apps' -and @(Get-HdrDefaultAppNames) -contains 'firstgame') 'Successful update did not apply'
        } else {
            Assert ($lastMessage -match 'saved list is unchanged' -and (Get-FileHash (Get-HdrCommunityCachePath)).Hash -eq $cacheHash) 'Failed update lost offline support'
        }
    }
    Assert ((Get-FileHash (Get-HdrCustomAppsPath)).Hash -eq $customHash) 'Updating modified the custom file'
    $names = Get-HdrWatchedApps
    Assert ($names.ContainsKey('firstgame') -and $names.ContainsKey('customgame') -and -not $names.ContainsKey('excludedgame')) 'Refresh did not apply with custom overrides'
    $script:useCommunity = $false
    Assert ((Get-HdrWatchedApps).Count -eq 1) 'Custom-only preference must still work'
    $script:useCommunity = $true
    $lock = [IO.File]::Open((Get-HdrCommunityCachePath), [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        Reject { Save-HdrCommunityList $second } 'Locked cache write should fail'
        Assert (@(Get-HdrDefaultAppNames) -contains 'firstgame') 'Transient read failure must retain last known apps'
    } finally { $lock.Dispose() }
    Assert (@(Get-ChildItem -LiteralPath $root -Filter '*.tmp').Count -eq 0) 'Failed save left temporary files'
    Assert (@(Get-HdrDefaultAppNames) -contains 'firstgame') 'Failed write replaced previous cache'
    [IO.File]::WriteAllText((Get-HdrCommunityCachePath), 'corrupted')
    $script:hdrCommunityLastGood = $null
    Assert ((@(Get-HdrDefaultAppNames) -join '|') -eq ($bundle -join '|')) 'Damaged cache must fall back to bundled list on restart'
    Remove-Item -LiteralPath (Get-HdrCommunityCachePath)
    Assert ((@(Get-HdrDefaultAppNames) -join '|') -eq ($bundle -join '|')) 'Missing cache must fall back to bundled list'
    'PASS: offline bundle/cache, validation, atomic replacement, failed downloads/writes, async completion, custom overrides, and updater concurrency.'
} finally {
    $full = [IO.Path]::GetFullPath($root)
    if ([IO.Path]::GetDirectoryName($full) -ne [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') -or
        [IO.Path]::GetFileName($full) -notmatch '^hdr-community-tests-[a-f0-9]{32}$') { throw 'Invalid test cleanup path' }
    Remove-Item -LiteralPath $full -Recurse -Force
}
