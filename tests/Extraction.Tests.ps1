$ErrorActionPreference = 'Stop'
$root = Join-Path ([IO.Path]::GetTempPath()) ('hdr-ketarin-extract-test-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
$repo = Split-Path $PSScriptRoot
$script = Join-Path $repo 'ketarin\Extract-Package.ps1'
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$app = [pscustomobject]@{ PreviousLocation = (Join-Path $root '_.zip'); Variables = @{version = [pscustomobject]@{CachedContent = ('a' * 40)}} }
$prefix = 'hdr-context-menu-' + ('a' * 40) + '/'
function Make-TestArchive([bool]$Invalid) {
    if (Test-Path -LiteralPath $app.PreviousLocation) { Remove-Item -LiteralPath $app.PreviousLocation }
    $archive = [IO.Compression.ZipFile]::Open($app.PreviousLocation, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($file in Get-ChildItem -LiteralPath $repo -File) {
            if ($file.Name -eq 'AsusMode.exe') { continue }
            [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,$file.FullName,($prefix+$file.Name)) | Out-Null
        }

        if ($Invalid) { $archive.CreateEntry($prefix+'../../escape.txt') | Out-Null }
    } finally { $archive.Dispose() }
}
Make-TestArchive $false
& $script
if ([IO.File]::ReadAllText((Join-Path $root 'Package\package.commit')) -ne ('a' * 40)) { throw 'Commit marker missing' }
# A cached archive under the old name and a fresh renamed archive must both work.
$prefix = 'hdr-control-' + ('a' * 40) + '/'
Make-TestArchive $false
& $script
if ([IO.File]::ReadAllText((Join-Path $root 'Package\package.commit')) -ne ('a' * 40)) { throw 'Renamed archive commit marker missing' }
Set-Content -LiteralPath (Join-Path $root 'Package\old-only.txt') -Value 'old package'
$packageCreated = (Get-Item -LiteralPath (Join-Path $root 'Package')).CreationTimeUtc
New-Item -ItemType Directory -Path (Join-Path $root 'Package\obsolete-dir') | Out-Null
Set-Content -LiteralPath (Join-Path $root 'Package\obsolete-dir\old.txt') -Value 'obsolete'
New-Item -ItemType Directory -Path (Join-Path $root 'Package.previous') -Force | Out-Null
$previousCreated = (Get-Item -LiteralPath (Join-Path $root 'Package.previous')).CreationTimeUtc
$backupPath = Join-Path $root 'before-sync-20261028-120000.zip'
Copy-Item -LiteralPath $app.PreviousLocation -Destination $backupPath
New-Item -ItemType Directory -Path (Join-Path $root 'Package (1)') | Out-Null
New-Item -ItemType Directory -Path (Join-Path $root 'Package (2)') | Out-Null
Set-Content -LiteralPath (Join-Path $root 'Package (2)\notes.txt') -Value 'Keep user files'
Set-Content -LiteralPath (Join-Path $root 'before-sync-20261028-120001.zip') -Value 'Not an HDR archive'
& $script
if ((Get-Item -LiteralPath (Join-Path $root 'Package')).CreationTimeUtc -ne $packageCreated) { throw 'Current folder identity was replaced' }
if ((Get-Item -LiteralPath (Join-Path $root 'Package.previous')).CreationTimeUtc -ne $previousCreated) { throw 'Previous folder identity was replaced' }
if (Test-Path -LiteralPath (Join-Path $root 'Package\obsolete-dir')) { throw 'Obsolete directory survived replacement' }
if (Test-Path -LiteralPath $backupPath) { throw 'Old HDR backup archive survived cleanup' }
if (Test-Path -LiteralPath (Join-Path $root 'Package (1)')) { throw 'Empty duplicate folder survived cleanup' }
if (-not (Test-Path -LiteralPath (Join-Path $root 'Package (2)\notes.txt'))) { throw 'Cleanup removed user files' }
if (-not (Test-Path -LiteralPath (Join-Path $root 'before-sync-20261028-120001.zip'))) { throw 'Cleanup removed an unrelated archive' }
if (-not (Test-Path -LiteralPath $app.PreviousLocation)) { throw 'Cleanup removed the current archive' }
if (Test-Path -LiteralPath (Join-Path $root 'Package\old-only.txt')) { throw 'Stale file survived package replacement' }
if (-not (Test-Path -LiteralPath (Join-Path $root 'Package.previous\old-only.txt'))) { throw 'Previous package was not retained' }
$before = (Get-FileHash -LiteralPath (Join-Path $root 'Package\Setup.ps1')).Hash
Copy-Item -LiteralPath $app.PreviousLocation -Destination $backupPath
Make-TestArchive $true
$rejected = $false
try { & $script } catch { $rejected = $_.Exception.Message -match 'invalid file path' }
if (-not $rejected) { throw 'Traversal archive was not rejected' }
if (-not (Test-Path -LiteralPath $backupPath)) { throw 'Failed update removed a recovery archive' }
if ($before -ne (Get-FileHash -LiteralPath (Join-Path $root 'Package\Setup.ps1')).Hash) { throw 'Rejected archive changed the prepared package' }
if (Test-Path -LiteralPath (Join-Path $root 'escape.txt')) { throw 'Archive escaped its staging folder' }
Write-Output 'PASS: extraction, replacement, retention, safe cleanup, and traversal rejection without damaging the prepared package.'
