# Windows PowerShell 5.1 -STA. Real standalone process; simulated HDR commands.
# No store client, store metadata, network calls, or real display changes.
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot
. (Join-Path $repo 'HdrTray.ps1')
function Assert($Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
$root = Join-Path ([IO.Path]::GetTempPath()) ('hdr-direct-launch-' + [Guid]::NewGuid().ToString('N'))
$gameName = 'HdrStandalone-' + [Guid]::NewGuid().ToString('N')
$game = $null
New-Item -ItemType Directory -Path $root | Out-Null
function Get-HdrCustomAppsPath { return Join-Path $root 'custom.txt' }
function Get-HdrProfilesPath { return Join-Path $root 'profiles.json' }
function Get-HdrDetectedAppsPath { return Join-Path $root 'detected.json' }
function Get-HdrDefaultAppNames { return @($gameName + '.exe') }
function Get-HdrAutomationPreference([string]$Name) {
    if ($Name -eq 'AutomaticHdr') { return $script:automatic }
    return $script:community
}
function Get-HdrAutomationTime { return $script:now }
function Start-HdrChange([string]$NextAction, [string]$DisplayId, [switch]$Automatic) {
    Assert $Automatic 'Expected an automatic request'
    $script:requests.Add($NextAction)
    $script:hdrTray.Pending=[pscustomobject]@{HasExited=$false}
}
function Poll($Displays) {
    if ($null -ne $script:hdrTray.PolicyPending) {
        $op=$script:hdrTray.PolicyPending
        $script:hdrTray.Pending=$null
        Complete-HdrPolicyCommand (@($Displays | Where-Object { $_.HdrEnabled -eq $op.Target }).Count -gt 0)
    }
    $script:now = $script:now.AddSeconds(2)
    Update-HdrAutomation $Displays
}
$off = @([pscustomobject]@{DevicePath='Test monitor';DisplayId='dGVzdA==';HdrSupported=$true;HdrEnabled=$false})
$on = @([pscustomobject]@{DevicePath='Test monitor';DisplayId='dGVzdA==';HdrSupported=$true;HdrEnabled=$true})
$icon = [pscustomobject]@{}
function Show-HdrNotification($Message) {
    Assert ($Message -in @('HDR turned on automatically.','HDR turned off automatically.')) $Message
}
try {
    $template = Join-Path $root ($gameName + '.exe')
    Add-Type -TypeDefinition 'public static class HdrStandaloneTest { public static void Main() { System.Threading.Thread.Sleep(120000); } }' -OutputAssembly $template -OutputType WindowsApplication
    foreach ($folder in @('GOG offline install', 'Arbitrary games folder')) {
        $directory = Join-Path $root $folder
        New-Item -ItemType Directory -Path $directory | Out-Null
        $executable = Join-Path $directory ($gameName + '.exe')
        Copy-Item -LiteralPath $template -Destination $executable
        [IO.File]::Delete((Get-HdrCustomAppsPath))
        $script:requests = New-Object 'Collections.Generic.List[string]'
        $script:now = [DateTime]::UtcNow
        $script:automatic = $false
        $script:community = $true
        $window=[LocalHdrMenu.HdrEventWindow]::new()
        $script:hdrTray = @{Automation=(New-HdrAutomationState);Pending=$null;UpdateProcess=$null;Icon=$icon;EventWindow=$window}
        # Start the EXE itself: no game launcher, store manifest, or store install path.
        $game = Start-Process -FilePath $executable -WorkingDirectory $directory -WindowStyle Hidden -PassThru
        Assert (@(Get-HdrRunningAppNames) -contains $gameName) 'Directly launched EXE was not enumerated'
        Poll $off
        Assert ($requests.Count -eq 0) 'Experimental feature must remain inactive until enabled'
        $script:automatic = $true
        Poll $off
        Assert ($requests.Count -eq 1 -and $requests[0] -eq 'On') 'Community matching required a launcher or a particular install path'

        [IO.File]::WriteAllText((Get-HdrCustomAppsPath), ('!' + $gameName + '.exe'))
        Poll $on
        Poll $on
        Assert ($requests.Count -eq 2 -and $requests[1] -eq 'Off') 'Custom exclusion did not override direct-launch community matching'

        $script:community = $false
        $script:hdrTray.Automation = New-HdrAutomationState
        $script:requests.Clear()
        [IO.File]::WriteAllText((Get-HdrCustomAppsPath), ($gameName.ToUpperInvariant() + '.EXE'))
        $config=New-HdrProfiles
        $rule=New-HdrGameRule ($gameName+'.exe')
        Assert ($rule.ExitDelay -eq 0) 'New game rules must default to immediate restoration'
        if ($folder -eq 'Arbitrary games folder') { $rule.ExitDelay=1 }
        $config.Rules=@($rule); Save-HdrProfiles $config
        Poll $off
        Assert ($requests.Count -eq 1 -and $requests[0] -eq 'On') 'Custom-only direct launch was not recognized'
        Poll $on
        $exitStart=$script:now
        $window.add_GameExitCheck({
            $script:now=$exitStart.Add($elapsed.Elapsed)
            $script:hdrTray.Automation.LastPoll=[DateTime]::MinValue
            Update-HdrAutomation $on
        })
        $elapsed=[Diagnostics.Stopwatch]::StartNew()
        $game.Kill()
        Assert ($game.WaitForExit(5000)) 'Test process did not exit'
        $game.Dispose()
        $game = $null
        while ($requests.Count -eq 1 -and $elapsed.ElapsedMilliseconds -lt 5000) {
            [Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 5
        }
        Assert ($requests.Count -eq 2 -and $requests[1] -eq 'Off') 'Process exit must request Off without a periodic poll'
        Assert ($elapsed.ElapsedMilliseconds -ge 1000*$rule.ExitDelay) 'Process exit skipped the configured delay'
        Write-Output ("Delay {0}s: simulated Off requested within {1} ms of stopping the process." -f $rule.ExitDelay,$elapsed.ElapsedMilliseconds)
        $window.Dispose(); $window=$null
        [IO.File]::Delete((Get-HdrProfilesPath))
    }
    'PASS: real direct-EXE launch/exit from arbitrary offline folders, community/custom matching, exclusions, and default-off behavior without storefront integration.'
} finally {
    if ($null -ne $window) { $window.Dispose() }
    if ($null -ne $game) {
        if (-not $game.HasExited) { $game.Kill(); [void]$game.WaitForExit(5000) }
        $game.Dispose()
    }
    $full = [IO.Path]::GetFullPath($root)
    if ([IO.Path]::GetDirectoryName($full) -ne [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') -or
        [IO.Path]::GetFileName($full) -notmatch '^hdr-direct-launch-[a-f0-9]{32}$') { throw 'Invalid test cleanup path' }
    Remove-Item -LiteralPath $full -Recurse -Force
}
