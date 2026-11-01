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
    $package = Join-Path $root 'hdr-context-menu-1.1.0'
    New-Item -ItemType Directory -Path $package | Out-Null
    foreach ($name in Get-HdrPackageFiles) { Copy-Item -LiteralPath (Join-Path $repo $name) -Destination (Join-Path $package $name) }
    [IO.File]::WriteAllText((Join-Path $package 'VERSION'), '1.1.0')
    $good = Join-Path $root 'good.zip'
    $zip = [IO.Compression.ZipFile]::Open($good,[IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($name in Get-HdrPackageFiles) {
            [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,(Join-Path $package $name),('hdr-context-menu-1.1.0/'+$name))
        }
    } finally { $zip.Dispose() }
    $staged = Join-Path $root 'Staged'
    Expand-HdrUpdate $good $staged '1.1.0'
    Assert ((Get-FileHash (Join-Path $staged 'Setup.ps1')).Hash -eq (Get-FileHash (Join-Path $repo 'Setup.ps1')).Hash) 'Staged package content differs'
    foreach ($case in @('traversal','absolute','duplicate','missing','mismatch')) {
        $bad = Join-Path $root ($case + '.zip')
        Copy-Item -LiteralPath $good -Destination $bad
        $zip = [IO.Compression.ZipFile]::Open($bad,[IO.Compression.ZipArchiveMode]::Update)
        try {
            $entryName = switch ($case) {
                'traversal' {'hdr-context-menu-1.1.0/../escape.txt'}
                'absolute' {'C:/escape.txt'}
                'duplicate' {'hdr-context-menu-1.1.0/Setup.ps1'}
                'missing' { $zip.GetEntry('hdr-context-menu-1.1.0/Setup.ps1').Delete(); $null }
                'mismatch' { $zip.GetEntry('hdr-context-menu-1.1.0/VERSION').Delete(); 'hdr-context-menu-1.1.0/VERSION' }
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
    'PASS: semantic version ordering, package integrity, unsafe archives, direct installation, rollback, and cancelled approval.'
} finally {
    $full = [IO.Path]::GetFullPath($root)
    $expectedParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    if ([IO.Path]::GetDirectoryName($full) -ne $expectedParent -or [IO.Path]::GetFileName($full) -notmatch '^hdr-update-tests-[a-f0-9]{32}$') { throw 'Invalid test cleanup path' }
    Remove-Item -LiteralPath $full -Recurse -Force
}
