$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot
. (Join-Path $repo 'Update-HdrApp.ps1') -FunctionsOnly
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
function Assert($Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
function Reject([scriptblock]$Action,[string]$Message) {
    $rejected = $false
    try { & $Action } catch { $rejected = $true }
    Assert $rejected $Message
}
$root = Join-Path ([IO.Path]::GetTempPath()) ('hdr-update-tests-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
try {
    Assert ((ConvertTo-HdrVersion '1.10.0') -gt (ConvertTo-HdrVersion '1.9.9')) 'Versions must compare numerically'
    Assert ((ConvertTo-HdrVersion '2.0.0') -gt (ConvertTo-HdrVersion '1.99.99')) 'Major version ordering is wrong'
    foreach ($invalid in @('01.0.0','1.0','1.0.0.0','v1.0.0','1.0.0-beta','1.0.0;exit')) {
        Reject { ConvertTo-HdrVersion $invalid } ('Accepted invalid stable version: ' + $invalid)
    }
    $package = Join-Path $root 'hdr-control-1.1.0'
    New-Item -ItemType Directory -Path $package | Out-Null
    foreach ($name in Get-HdrPackageFiles) { Copy-Item -LiteralPath (Join-Path $repo $name) -Destination (Join-Path $package $name) }
    [IO.File]::WriteAllText((Join-Path $package 'VERSION'), '1.1.0')
    $good = Join-Path $root 'good.zip'
    $zip = [IO.Compression.ZipFile]::Open($good,[IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($name in Get-HdrPackageFiles) {
            [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,(Join-Path $package $name),('hdr-control-1.1.0/'+$name))
        }
    } finally { $zip.Dispose() }
    $staged = Join-Path $root 'Staged'
    Expand-HdrUpdate $good $staged '1.1.0'
    Assert ((Get-FileHash (Join-Path $staged 'Setup.ps1')).Hash -eq (Get-FileHash (Join-Path $repo 'Setup.ps1')).Hash) 'Staged package content differs'
    Assert ((Get-FileHash (Join-Path $staged 'HdrApps.community.txt')).Hash -eq (Get-FileHash (Join-Path $repo 'HdrApps.community.txt')).Hash) 'Package did not include the offline community list'
    # Renaming the repository changes GitHub's archive root, including old tags.
    # Keep accepting cached archives from the original name, but no other repo.
    foreach ($archiveRoot in @('hdr-context-menu-1.1.0','hdr-context-menu-v1.1.0','hdr-control-v1.1.0','unrelated-1.1.0','hdr-control-1.1.1')) {
        $archivePath = Join-Path $root ($archiveRoot + '.zip')
        $archiveDestination = Join-Path $root ('Root-' + $archiveRoot)
        $zip = [IO.Compression.ZipFile]::Open($archivePath,[IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($name in Get-HdrPackageFiles) {
                [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,(Join-Path $package $name),($archiveRoot+'/'+$name))
            }
        } finally { $zip.Dispose() }
        if ($archiveRoot -in @('unrelated-1.1.0','hdr-control-1.1.1')) {
            Reject { Expand-HdrUpdate $archivePath $archiveDestination '1.1.0' } ('Accepted wrong archive root: ' + $archiveRoot)
        } else {
            Expand-HdrUpdate $archivePath $archiveDestination '1.1.0'
            Assert ((Get-FileHash (Join-Path $archiveDestination 'Setup.ps1')).Hash -eq (Get-FileHash (Join-Path $repo 'Setup.ps1')).Hash) ('Renamed/legacy archive content differs: ' + $archiveRoot)
        }
    }
    $legacyRoot = Join-Path $root ('hdr-update-' + [Guid]::NewGuid().ToString('N'))
    $legacyStage = Join-Path $legacyRoot 'Package'
    New-Item -ItemType Directory -Path $legacyStage -Force | Out-Null
    Copy-Item -LiteralPath $good -Destination (Join-Path $legacyRoot 'update.zip')
    foreach ($name in Get-HdrPackageFiles) {
        if ($name -notin @('HdrAutoEnabled.ico','HdrEnabledPaused.ico','HdrAutoIdle.ico','HdrApps.community.txt','HdrProfiles.ps1','ProfilesUi.cs','ProcessGridTheme.cs','HdrLocation.cs')) { Copy-Item -LiteralPath (Join-Path $staged $name) -Destination $legacyStage }
    }
    Restore-HdrCommunityBundle $legacyStage
    Assert ((Get-FileHash (Join-Path $legacyStage 'HdrAutoEnabled.ico')).Hash -eq (Get-FileHash (Join-Path $repo 'HdrAutoEnabled.ico')).Hash) 'Legacy updater did not recover the auto-enabled tray icon'
    Assert ((Get-FileHash (Join-Path $legacyStage 'HdrApps.community.txt')).Hash -eq (Get-FileHash (Join-Path $repo 'HdrApps.community.txt')).Hash) 'Legacy updater could not recover the bundled list from its archive'
    foreach ($module in @('HdrProfiles.ps1','ProfilesUi.cs','ProcessGridTheme.cs','HdrLocation.cs')) { Assert ((Get-FileHash (Join-Path $legacyStage $module)).Hash -eq (Get-FileHash (Join-Path $repo $module)).Hash) ('Legacy updater did not recover '+$module) }
    Remove-Item -LiteralPath (Join-Path $legacyStage 'HdrApps.community.txt')
    Add-Content -LiteralPath (Join-Path $legacyStage 'Setup.ps1') -Value '# altered'
    Reject { Restore-HdrCommunityBundle $legacyStage } 'Legacy recovery accepted a mismatched archive'
    Assert (-not (Test-Path (Join-Path $legacyStage 'HdrApps.community.txt'))) 'Failed recovery wrote the list'
    foreach ($case in @('traversal','absolute','duplicate','missing','mismatch')) {
        $bad = Join-Path $root ($case + '.zip')
        Copy-Item -LiteralPath $good -Destination $bad
        $zip = [IO.Compression.ZipFile]::Open($bad,[IO.Compression.ZipArchiveMode]::Update)
        try {
            $entryName = switch ($case) {
                'traversal' {'hdr-control-1.1.0/../escape.txt'}
                'absolute' {'C:/escape.txt'}
                'duplicate' {'hdr-control-1.1.0/Setup.ps1'}
                'missing' { $zip.GetEntry('hdr-control-1.1.0/Setup.ps1').Delete(); $null }
                'mismatch' { $zip.GetEntry('hdr-control-1.1.0/VERSION').Delete(); 'hdr-control-1.1.0/VERSION' }
            }
            if ($entryName) {
                $writer = [IO.StreamWriter]::new($zip.CreateEntry($entryName).Open())
                try { $writer.Write('9.0.0') } finally { $writer.Dispose() }
            }
        } finally { $zip.Dispose() }
        Reject { Expand-HdrUpdate $bad (Join-Path $root ('Rejected-' + $case)) '1.1.0' } ('Accepted unsafe/incomplete archive: ' + $case)
    }
    Assert (-not (Test-Path -LiteralPath (Join-Path $root 'escape.txt'))) 'Archive escaped staging'

    $installed = Join-Path $root 'Installed'
    New-Item -ItemType Directory -Path $installed | Out-Null
    foreach ($name in Get-HdrPackageFiles) { Copy-Item -LiteralPath (Join-Path $repo $name) -Destination (Join-Path $installed $name) }
    [IO.File]::WriteAllText((Join-Path $installed 'HdrApps.community.cache.txt'),'preserve downloaded list')
    [IO.File]::WriteAllText((Join-Path $installed 'HdrApps.custom.txt'),'preserve custom list')
    $script:fakeTarget = $installed
    $script:fakeFail = $false
    $script:fakeCancel = $false
    $script:fakeCalls = 0
    function Start-HdrInstaller([string]$Source) {
        $script:fakeCalls++
        if ($script:fakeCancel) { throw 'Approval cancelled' }
        foreach ($name in Get-HdrPackageFiles) { Copy-Item -LiteralPath (Join-Path $Source $name) -Destination (Join-Path $script:fakeTarget $name) -Force }
        $code = if ($script:fakeFail) { $script:fakeFail=$false; 1 } else { 0 }
        $process = [pscustomobject]@{ExitCode=$code}
        $process | Add-Member ScriptMethod WaitForExit {}
        $process | Add-Member ScriptMethod Dispose {}
        return $process
    }
    Install-HdrUpdate $staged $installed (Join-Path $root 'Backup-success') '1.1.0'
    Assert ([IO.File]::ReadAllText((Join-Path $installed 'VERSION')) -eq '1.1.0') 'Installer did not apply the new version'
    Assert ($script:fakeCalls -eq 1) 'Successful update should install only once'
    [IO.File]::WriteAllText((Join-Path $installed 'VERSION'),'1.0.0')
    $script:fakeFail=$true
    Reject { Install-HdrUpdate $staged $installed (Join-Path $root 'Backup-failure') '1.1.0' } 'Failed installer must report failure'
    Assert ([IO.File]::ReadAllText((Join-Path $installed 'VERSION')) -eq '1.0.0') 'Failed update did not restore the previous version'
    Assert ($script:fakeCalls -eq 3) 'Failed update must run recovery exactly once'
    $script:fakeCancel=$true
    Reject { Install-HdrUpdate $staged $installed (Join-Path $root 'Backup-cancelled') '1.1.0' } 'Cancelled approval must stop the update'
    Assert ([IO.File]::ReadAllText((Join-Path $installed 'VERSION')) -eq '1.0.0') 'Cancelled approval changed the installed version'
    Assert ($script:fakeCalls -eq 4) 'Cancelled approval must not trigger a recovery installer'
    Assert ([IO.File]::ReadAllText((Join-Path $installed 'HdrApps.community.cache.txt')) -eq 'preserve downloaded list') 'Update or rollback overwrote community cache'
    Assert ([IO.File]::ReadAllText((Join-Path $installed 'HdrApps.custom.txt')) -eq 'preserve custom list') 'Update or rollback overwrote custom entries'
    'PASS: semantic version ordering, package integrity, unsafe archives, direct installation, rollback, and cancelled approval.'
} finally {
    $full = [IO.Path]::GetFullPath($root)
    $expectedParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    if ([IO.Path]::GetDirectoryName($full) -ne $expectedParent -or [IO.Path]::GetFileName($full) -notmatch '^hdr-update-tests-[a-f0-9]{32}$') { throw 'Invalid test cleanup path' }
    Remove-Item -LiteralPath $full -Recurse -Force
}
