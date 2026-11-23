# Exercise package comparison and rollback retention without installing anything.
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'Setup.ps1'),[ref]$null,[ref]$null)
foreach ($name in 'Get-HdrChangedRuntimeFiles','Save-HdrRuntimeSnapshot','Remove-HdrOldRuntimeSnapshots') {
    $definition = $ast.Find({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
    },$true)
    . ([scriptblock]::Create($definition.Extent.Text))
}
function Assert($Condition,[string]$Message) { if (-not $Condition) { throw $Message } }

$root = Join-Path ([IO.Path]::GetTempPath()) ('hdr-setup-tests-' + [Guid]::NewGuid().ToString('N'))
$source = Join-Path $root 'source'
$installed = Join-Path $root 'installed'
[void][IO.Directory]::CreateDirectory($source)
[void][IO.Directory]::CreateDirectory($installed)
try {
    $files = 'VERSION','HdrTray.ps1','package.commit'
    foreach ($dir in $source,$installed) {
        [IO.File]::WriteAllText((Join-Path $dir 'VERSION'),'1.0.0')
        [IO.File]::WriteAllText((Join-Path $dir 'HdrTray.ps1'),'old content')
    }
    Assert (-not @(Get-HdrChangedRuntimeFiles $source $installed $files).Count) 'Identical packages must not trigger a backup or runtime copy'
    [IO.File]::WriteAllText((Join-Path $source 'HdrTray.ps1'),'new content')
    [IO.File]::WriteAllText((Join-Path $installed 'package.commit'),'old commit')
    $changed = @(Get-HdrChangedRuntimeFiles $source $installed $files)
    Assert (($changed -join '|') -ceq 'HdrTray.ps1|package.commit') 'Changed bytes and removed package metadata must be detected'
    Assert (-not @(Get-HdrChangedRuntimeFiles $source $source $files).Count) 'Setup run from the install directory must not copy its own files'

    $backupDir = Join-Path $installed 'backups'
    [void][IO.Directory]::CreateDirectory($backupDir)
    $legacy = Join-Path $backupDir '2026-old-HdrTray.ps1'
    [IO.File]::WriteAllText($legacy,'legacy backup')
    foreach ($patch in 1..4) {
        [IO.File]::WriteAllText((Join-Path $installed 'VERSION'),"1.0.$patch")
        Save-HdrRuntimeSnapshot $installed $files
    }
    Remove-HdrOldRuntimeSnapshots $installed $files
    $remaining = @(Get-ChildItem -LiteralPath $backupDir -Directory | Sort-Object Name)
    Assert ($remaining.Count -eq 3 -and [IO.File]::Exists($legacy)) 'Retention must keep three snapshots and preserve legacy files'
    $versions = foreach ($snapshot in $remaining) {
        Assert (@(Get-ChildItem -LiteralPath $snapshot.FullName -File).Count -eq $files.Count) 'A snapshot must preserve every installed runtime file'
        [IO.File]::ReadAllText((Join-Path $snapshot.FullName 'VERSION'))
    }
    Assert (($versions -join '|') -eq '1.0.2|1.0.3|1.0.4') 'Retention removed a newer snapshot'
    'PASS: byte comparison, optional metadata, complete rollback snapshots, and three-snapshot retention.'
} finally {
    $full = [IO.Path]::GetFullPath($root)
    if ([IO.Path]::GetDirectoryName($full) -ne [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') -or
        [IO.Path]::GetFileName($full) -notmatch '^hdr-setup-tests-[a-f0-9]{32}$') { throw 'Invalid test cleanup path' }
    Remove-Item -LiteralPath $full -Recurse -Force
}
