[CmdletBinding()]
param([string]$Version, [switch]$FunctionsOnly)

# Stable releases use MAJOR.MINOR.PATCH. Preview releases are never offered.
function ConvertTo-HdrVersion([string]$Value) {
    if ($Value -cnotmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$') { throw 'Invalid release version.' }
    return [version]$Value
}

function Get-HdrPackageFiles {
    return @('Setup.ps1','HdrSdrMenu.ps1','HdrTray.ps1','HdrProfiles.ps1','HdrStartup.ps1','ProfilesUi.cs','ProcessGridTheme.cs','TrayTheme.cs','HdrLocation.cs','Start-Tray.vbs','Toggle-HdrSdr.vbs',
        'Update-HdrApp.ps1','HdrApps.community.txt','VERSION','HdrSdrMenu.ico','HdrEnabled.ico','HdrAutoEnabled.ico','HdrEnabledPaused.ico','HdrAutoIdle.ico','HdrDisabled.ico','HdrUnavailable.ico',
        'HdrEnableAction.ico','HdrDisableAction.ico','HdrUnavailableAction.ico','hdr-context-menu.nss')
}

function Expand-HdrUpdate([string]$Archive, [string]$Destination, [string]$ExpectedVersion) {
    [void](ConvertTo-HdrVersion $ExpectedVersion)
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($Archive)
    try {
        $roots = @($zip.Entries | ForEach-Object { $_.FullName.Split('/')[0] } | Select-Object -Unique)
        if ($roots.Count -ne 1 -or $roots[0] -cnotmatch ('^hdr-(?:control|context-menu)-v?' + [regex]::Escape($ExpectedVersion) + '$')) { throw 'The update archive has an unexpected root folder.' }
        $root = $roots[0] + '/'
        $required = @(Get-HdrPackageFiles)
        $found = @{}
        $total = 0L
        foreach ($entry in $zip.Entries) {
            $name = $entry.FullName
            if (-not $name.StartsWith($root,[StringComparison]::Ordinal) -or $name.Contains('\') -or $name.Contains(':') -or $name -match '(^|/)\.\.?(/|$)') {
                throw 'The update archive contains an unsafe path.'
            }
            if ((($entry.ExternalAttributes -shr 16) -band 0xF000) -eq 0xA000) { throw 'The update archive contains a symbolic link.' }
            $total += $entry.Length
            if ($total -gt 100MB) { throw 'The update archive is too large.' }
            $relative = $name.Substring($root.Length)
            if ($relative -in $required) {
                if ($found.ContainsKey($relative)) { throw 'The update archive contains a duplicate file.' }
                $found[$relative] = $entry
            }
        }
        foreach ($name in $required) { if (-not $found.ContainsKey($name)) { throw ('The update is missing ' + $name) } }
        $reader = [IO.StreamReader]::new($found['VERSION'].Open())
        try { $packageVersion = $reader.ReadToEnd().Trim() } finally { $reader.Dispose() }
        if ($packageVersion -cne $ExpectedVersion) { throw 'The downloaded version does not match the offered update.' }
        if (Test-Path -LiteralPath $Destination) { throw 'Update staging directory already exists.' }
        New-Item -ItemType Directory -Path $Destination -ErrorAction Stop | Out-Null
        foreach ($name in $required) {
            [IO.Compression.ZipFileExtensions]::ExtractToFile($found[$name],(Join-Path $Destination $name))
        }
        foreach ($name in @('Setup.ps1','HdrSdrMenu.ps1','HdrTray.ps1','HdrProfiles.ps1','HdrStartup.ps1','Update-HdrApp.ps1')) {
            $parseErrors = $null
            [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $Destination $name),[ref]$null,[ref]$parseErrors)
            if ($parseErrors) { throw ('The update contains an invalid script: ' + $name) }
        }
    } finally { $zip.Dispose() }
}

function Receive-HdrUpdate([string]$ReleaseVersion, [string]$Archive) {
    [void](ConvertTo-HdrVersion $ReleaseVersion)
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $url = 'https://codeload.github.com/notuxius/hdr-control/zip/refs/tags/v' + $ReleaseVersion
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $Archive -TimeoutSec 120 -ErrorAction Stop
}

function Restore-HdrCommunityBundle([string]$Source) {
    $newFiles=@('HdrAutoEnabled.ico','HdrEnabledPaused.ico','HdrAutoIdle.ico','HdrApps.community.txt','HdrProfiles.ps1','HdrStartup.ps1','ProfilesUi.cs','ProcessGridTheme.cs','HdrLocation.cs')
    $missing=@($newFiles | Where-Object { -not (Test-Path -LiteralPath (Join-Path $Source $_) -PathType Leaf) })
    if (-not $missing.Count) { return }
    # Older updaters stage only their known runtime files. Recover new modules
    # from their already-downloaded release archive, without a network call.
    $parent = Split-Path $Source
    if ((Split-Path $Source -Leaf) -ne 'Package' -or (Split-Path $parent -Leaf) -notmatch '^hdr-update-[a-f0-9]{32}$') {
        throw ('Package file missing: '+($missing -join ', '))
    }
    $stage = Join-Path $parent ('CommunityBundle-' + [Guid]::NewGuid().ToString('N'))
    try {
        $version = [IO.File]::ReadAllText((Join-Path $Source 'VERSION')).Trim()
        Expand-HdrUpdate (Join-Path $parent 'update.zip') $stage $version
        # Only recover data belonging to the exact staged installer/runtime.
        foreach ($name in @('Setup.ps1','HdrTray.ps1','Update-HdrApp.ps1')) {
            if ((Get-FileHash -LiteralPath (Join-Path $Source $name)).Hash -ne (Get-FileHash -LiteralPath (Join-Path $stage $name)).Hash) {
                throw 'The release archive does not match the staged update.'
            }
        }
        foreach ($name in $missing) { Copy-Item -LiteralPath (Join-Path $stage $name) -Destination $Source -ErrorAction Stop }
    } finally {
        $full = [IO.Path]::GetFullPath($stage)
        if ([IO.Path]::GetDirectoryName($full) -eq [IO.Path]::GetFullPath($parent) -and
            [IO.Path]::GetFileName($full) -match '^CommunityBundle-[a-f0-9]{32}$' -and (Test-Path -LiteralPath $full)) {
            Remove-Item -LiteralPath $full -Recurse -Force
        }
    }
}

function Start-HdrInstaller([string]$Source) {
    return Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList (
        '-NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -NoRestart' -f (Join-Path $Source 'Setup.ps1')
    ) -Verb RunAs -WindowStyle Hidden -PassThru -ErrorAction Stop
}

function Install-HdrUpdate([string]$Source, [string]$Installed, [string]$Backup, [string]$ExpectedVersion) {
    New-Item -ItemType Directory -Path $Backup -ErrorAction Stop | Out-Null
    foreach ($name in (@(Get-HdrPackageFiles) + @('package.commit'))) {
        $file = Join-Path $Installed $name
        if (Test-Path -LiteralPath $file -PathType Leaf) { Copy-Item -LiteralPath $file -Destination (Join-Path $Backup $name) -ErrorAction Stop }
    }
    $installer = $null
    try {
        $installer = Start-HdrInstaller $Source
        $installer.WaitForExit()
        if ($installer.ExitCode -ne 0) { throw 'The installer did not complete.' }
        if ([IO.File]::ReadAllText((Join-Path $Installed 'VERSION')).Trim() -cne $ExpectedVersion) { throw 'Installed version verification failed.' }
    } catch {
        if ($null -ne $installer) {
            $restore = $null
            try {
                $restore = Start-HdrInstaller $Backup
                $restore.WaitForExit()
                if ($restore.ExitCode -ne 0) { throw 'Recovery installer failed.' }
            } catch { throw ('Update recovery needs attention. The previous files are saved in: ' + $Backup) }
            finally { if ($null -ne $restore) { $restore.Dispose() } }
            throw 'The update failed. Your previous version has been restored.'
        }
        throw 'The update was cancelled or could not start. Your current version is unchanged.'
    } finally { if ($null -ne $installer) { $installer.Dispose() } }
}

if ($FunctionsOnly) { return }
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$work = Join-Path $tempRoot ('hdr-update-' + [Guid]::NewGuid().ToString('N'))
$preserve = $false
$result = 0
try {
    [void](ConvertTo-HdrVersion $Version)
    $installed = Join-Path $env:ProgramData 'HdrSdrMenu'
    $current = ConvertTo-HdrVersion ([IO.File]::ReadAllText((Join-Path $installed 'VERSION')).Trim())
    if ((ConvertTo-HdrVersion $Version) -le $current) { throw 'This version is already installed or is older than your current version.' }
    New-Item -ItemType Directory -Path $work | Out-Null
    $archive = Join-Path $work 'update.zip'
    Receive-HdrUpdate $Version $archive
    $source = Join-Path $work 'Package'
    Expand-HdrUpdate $archive $source $Version
    $backup = Join-Path $work 'Previous'
    try { Install-HdrUpdate $source $installed $backup $Version }
    catch { if ($_.Exception.Message -like 'Update recovery needs attention*') { $preserve = $true }; throw }
    [void][Windows.Forms.MessageBox]::Show(('HDR Control has been updated to version ' + $Version + '.'),'Update complete','OK','Information')
} catch {
    $result = 1
    [void][Windows.Forms.MessageBox]::Show(('Could not finish the update.' + "`n`n" + $_.Exception.Message),'HDR Control','OK','Warning')
} finally {
    # This unique temporary folder is the only recursive cleanup target.
    if (-not $preserve -and (Test-Path -LiteralPath $work)) {
        $full = [IO.Path]::GetFullPath($work)
        if ([IO.Path]::GetDirectoryName($full) -eq $tempRoot -and [IO.Path]::GetFileName($full) -match '^hdr-update-[a-f0-9]{32}$') {
            $links = @(Get-Item -LiteralPath $full) + @(Get-ChildItem -LiteralPath $full -Recurse -Force)
            if (-not ($links | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint })) { Remove-Item -LiteralPath $full -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
}
exit $result
