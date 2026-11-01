[CmdletBinding()]
param(
    [string]$SourceRoot,
    [string]$OutputDirectory,
    [string]$SourceCommit,
    [string]$CompilerPath
)
$ErrorActionPreference = 'Stop'
if (-not $SourceRoot) { $SourceRoot = Split-Path $PSScriptRoot }
if (-not $OutputDirectory) { $OutputDirectory = Join-Path (Split-Path $PSScriptRoot) 'dist' }
$SourceRoot = (Resolve-Path -LiteralPath $SourceRoot).Path
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
. (Join-Path $SourceRoot 'Update-HdrApp.ps1') -FunctionsOnly
$releaseVersion = [IO.File]::ReadAllText((Join-Path $SourceRoot 'VERSION')).Trim()
[void](ConvertTo-HdrVersion $releaseVersion)
if ($SourceCommit -and $SourceCommit -cnotmatch '^[a-f0-9]{40}$') { throw 'Invalid source commit.' }
if (-not $CompilerPath) {
    $command = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($command) { $CompilerPath = $command.Source }
    else {
        $CompilerPath = @(
            (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
            (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe')
        ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    }
}
if (-not $CompilerPath -or -not (Test-Path -LiteralPath $CompilerPath)) { throw 'Install Inno Setup 6 to build the Windows installer.' }
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$stage = Join-Path $tempRoot ('hdr-installer-build-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stage | Out-Null
try {
    # Only runtime files enter the EXE: no local state, backups, or credentials.
    foreach ($name in Get-HdrPackageFiles) {
        Copy-Item -LiteralPath (Join-Path $SourceRoot $name) -Destination (Join-Path $stage $name) -ErrorAction Stop
    }
    if ($SourceCommit) { [IO.File]::WriteAllText((Join-Path $stage 'package.commit'), $SourceCommit + "`n", [Text.UTF8Encoding]::new($false)) }
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    & $CompilerPath "/DSourceRoot=$stage" "/DAppVersion=$releaseVersion" "/DBuildOutput=$OutputDirectory" (Join-Path $PSScriptRoot 'HdrContextMenu.iss')
    if ($LASTEXITCODE -ne 0) { throw 'Installer compilation failed.' }
    $exe = Join-Path $OutputDirectory ('HDR-Context-Menu-' + $releaseVersion + '-Setup.exe')
    if (-not (Test-Path -LiteralPath $exe)) { throw 'Installer output is missing.' }
    $hash = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText(($exe + '.sha256'), $hash + '  ' + [IO.Path]::GetFileName($exe) + "`n", [Text.UTF8Encoding]::new($false))
    Write-Output ('Built: ' + $exe)
} finally {
    $full = [IO.Path]::GetFullPath($stage)
    if ([IO.Path]::GetDirectoryName($full) -eq $tempRoot -and [IO.Path]::GetFileName($full) -match '^hdr-installer-build-[a-f0-9]{32}$') {
        Remove-Item -LiteralPath $full -Recurse -Force
    }
}
