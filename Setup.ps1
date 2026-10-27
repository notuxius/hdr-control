# Install for the signed-in user. Nilesoft Shell integration is optional.
[CmdletBinding()]
param(
    [ValidateSet('Install','Uninstall')][string]$Action = 'Install',
    [string]$NilesoftPath = (Join-Path $env:SystemRoot 'nilesoft'),
    [switch]$NoRestart
)
$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Action {1} -NilesoftPath "{2}"' -f $PSCommandPath,$Action,$NilesoftPath
    if ($NoRestart) { $arguments += ' -NoRestart' }
    $elevated = Start-Process powershell.exe -Verb RunAs -ArgumentList $arguments -Wait -PassThru
    exit $elevated.ExitCode
}
$installDir = Join-Path $env:ProgramData 'HdrSdrMenu'
$runtime = Join-Path $installDir 'HdrSdrMenu.ps1'
$launcher = Join-Path $installDir 'Toggle-HdrSdr.vbs'
$taskName = 'HdrSdrMenu-Label-' + $env:USERNAME
$menuKey = 'HKCU:\Software\Classes\DesktopBackground\Shell\HdrToggle.LocalScript'
$owner = 'HdrSdrMenu.LocalScript.v1'
$config = Join-Path $NilesoftPath 'shell.nss'
$importFile = Join-Path $NilesoftPath 'imports\hdr-context-menu.nss'
$importLine = "import 'imports/hdr-context-menu.nss'"
$utf8 = New-Object Text.UTF8Encoding($true)
$hasShell = Test-Path -LiteralPath $config

function Write-Text([string]$Path, [string]$Text) {
    [IO.File]::WriteAllText($Path,$Text,$utf8)
}
function Backup-File([string]$Path) {
    if (Test-Path -LiteralPath $Path) {
        $backupDir = Join-Path $installDir 'backups'
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        Copy-Item -LiteralPath $Path -Destination (Join-Path $backupDir ((Get-Date -Format 'yyyyMMdd-HHmmss-fff')+'-'+[IO.Path]::GetFileName($Path)))
    }
}
function Stop-Helper {
    Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    # Task Scheduler can leave the hidden child running; stop only this helper.
    $session = (Get-Process -Id $PID).SessionId
    $patterns = @(
        ('(?i)-File\s+"' + [regex]::Escape($runtime) + '"\s+-Action\s+Watch(?:\s|$)'),
        ('(?i)"' + [regex]::Escape($launcher) + '"\s+Watch(?:\s|$)')
    )
    Get-CimInstance Win32_Process | Where-Object {
        $_.SessionId -eq $session -and $_.Name -in @('powershell.exe','wscript.exe') -and
        ($_.CommandLine -match $patterns[0] -or $_.CommandLine -match $patterns[1])
    } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}
function Refresh-Shell {
    if ($hasShell -and -not $NoRestart) {
        Start-Process -FilePath (Join-Path $NilesoftPath 'shell.exe') -ArgumentList '-restart','-silent' -WindowStyle Hidden -Wait
    }
}

try {
    if ((Test-Path -LiteralPath $menuKey) -and (Get-ItemProperty -LiteralPath $menuKey).Owner -ne $owner) {
        throw 'An unrelated menu entry already uses this registry key.'
    }
    if ($Action -eq 'Uninstall') {
        Stop-Helper
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        if ($hasShell) {
            $text = [IO.File]::ReadAllText($config)
            $updated = [regex]::Replace($text, '(?m)^\s*import [\x27\x22]imports/hdr-context-menu\.nss[\x27\x22]\s*\r?\n?', '')
            if ($updated -ne $text) { Backup-File $config; Write-Text $config $updated }
        }
        if ((Test-Path -LiteralPath $importFile) -and [IO.File]::ReadAllText($importFile).StartsWith('// HDR Context Menu - managed by Setup.ps1')) {
            Remove-Item -LiteralPath $importFile
        }
        if (Test-Path -LiteralPath $menuKey) { Remove-Item -LiteralPath $menuKey -Recurse }
        foreach ($name in @('HdrSdrMenu.ps1','HdrTray.ps1','TrayTheme.cs','Start-Tray.vbs','Toggle-HdrSdr.vbs','HdrSdrMenu.ico','MenuLabel.txt','Setup.ps1','hdr-context-menu.nss','package.commit')) {
            $path = Join-Path $installDir $name
            if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path }
        }
        Refresh-Shell
        Write-Output 'HDR Context Menu removed. Configuration backups were retained.'
        return
    }
    foreach ($name in @('HdrSdrMenu.ps1','HdrTray.ps1','TrayTheme.cs','Start-Tray.vbs','Toggle-HdrSdr.vbs','HdrSdrMenu.ico','hdr-context-menu.nss')) {
        if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $name))) { throw "Package file missing: $name" }
    }
    if ($installDir.Contains("'") -or $env:SystemRoot.Contains("'")) { throw 'Installation paths cannot contain apostrophes.' }
    if ((Test-Path -LiteralPath $importFile) -and -not [IO.File]::ReadAllText($importFile).StartsWith('// HDR Context Menu - managed by Setup.ps1')) {
        throw 'An unrelated Nilesoft import already uses hdr-context-menu.nss.'
    }
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null
    # The limited logon helper needs to update its state file after elevated setup.
    $acl = Get-Acl -LiteralPath $installDir
    $rule = New-Object Security.AccessControl.FileSystemAccessRule($identity.User,'Modify','ContainerInherit,ObjectInherit','None','Allow')
    $acl.SetAccessRule($rule)
    Set-Acl -LiteralPath $installDir -AclObject $acl
    Stop-Helper
    foreach ($name in @('HdrSdrMenu.ps1','HdrTray.ps1','TrayTheme.cs','Start-Tray.vbs','Toggle-HdrSdr.vbs','HdrSdrMenu.ico','Setup.ps1','hdr-context-menu.nss','package.commit')) {
        $source = Join-Path $PSScriptRoot $name
        $destination = Join-Path $installDir $name
        if ((Test-Path -LiteralPath $source) -and [IO.Path]::GetFullPath($source) -ne [IO.Path]::GetFullPath($destination)) {
            Backup-File $destination
            Copy-Item -LiteralPath $source -Destination $destination -Force
        }
    }
    New-Item -Path ($menuKey+'\command') -Force | Out-Null
    New-ItemProperty -LiteralPath $menuKey -Name Owner -Value $owner -PropertyType String -Force | Out-Null
    New-ItemProperty -LiteralPath $menuKey -Name Icon -Value (Join-Path $installDir 'HdrSdrMenu.ico') -PropertyType String -Force | Out-Null
    & $runtime -Action Sync
    if (-not $?) { throw 'Could not read the current HDR state.' }
    $oldKey = 'HKCU:\Software\Classes\DesktopBackground\Shell\HdrSdrToggle.LocalScript'
    if ((Test-Path -LiteralPath $oldKey) -and (Get-ItemProperty -LiteralPath $oldKey).Owner -eq $owner) {
        Remove-Item -LiteralPath $oldKey -Recurse
    }
    Remove-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name HdrSdrMenuLabel -ErrorAction SilentlyContinue
    if ($hasShell) {
        New-Item -ItemType Directory -Path (Split-Path $importFile) -Force | Out-Null
        $nss = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'hdr-context-menu.nss')).Replace('@@INSTALL@@',$installDir).Replace('@@WINDOWS@@',$env:SystemRoot)
        Backup-File $importFile
        Write-Text $importFile ("// HDR Context Menu - managed by Setup.ps1`r`n"+$nss)
        # Migrate only the exact inline block used by the original local version.
        $modify = Join-Path $NilesoftPath 'imports\modify.nss'
        if (Test-Path -LiteralPath $modify) {
            $text = [IO.File]::ReadAllText($modify)
            $pattern = '(?ms)^// HDR: build one live item from the Windows display helper\x27s current state\.\r?\nremove\(type="desktop".*?args=.*?\x27Off\x27 : \x27On\x27\)\)\r?\n?'
            $updated = [regex]::Replace($text,$pattern,'')
            if ($updated -ne $text) { Backup-File $modify; Write-Text $modify $updated }
        }
        $text = [IO.File]::ReadAllText($config)
        if ($text -notmatch '(?m)^\s*import [\x27\x22]imports/hdr-context-menu\.nss[\x27\x22]') {
            Backup-File $config
            Write-Text $config ($text.TrimEnd()+"`r`n"+$importLine+"`r`n")
        }
    }
    $taskAction = New-ScheduledTaskAction -Execute (Join-Path $env:SystemRoot 'System32\wscript.exe') -Argument ('//NoLogo "{0}" Watch' -f $launcher)
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $identity.User.Value
    $principal = New-ScheduledTaskPrincipal -UserId $identity.User.Value -LogonType Interactive -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
    Register-ScheduledTask -TaskName $taskName -Action $taskAction -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
    Start-ScheduledTask -TaskName $taskName
    Refresh-Shell
    Write-Output 'HDR Context Menu installed. Reopen the desktop right-click menu.'
} catch {
    # If an upgrade fails, resume the existing helper where possible.
    if (Test-Path -LiteralPath $runtime) { Start-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue }
    Write-Error $_ -ErrorAction Continue
    exit 1
}
