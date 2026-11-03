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
$locationExe = Join-Path $installDir 'HDR Control.exe'
$locationBuild = $null
$launcher = Join-Path $installDir 'Toggle-HdrSdr.vbs'
$shortcutPath = Join-Path ([Environment]::GetFolderPath('Programs')) 'HDR Control.lnk'
$legacyShortcutPath = Join-Path ([Environment]::GetFolderPath('Programs')) 'HDR Context Menu.lnk'
$shortcutTarget = Join-Path $env:SystemRoot 'System32\wscript.exe'
$shortcutArguments = '//NoLogo "{0}"' -f (Join-Path $installDir 'Start-Tray.vbs')
$taskName = 'HdrSdrMenu-Label-' + $env:USERNAME
$menuKey = 'HKCU:\Software\Classes\DesktopBackground\Shell\HdrToggle.LocalScript'
$owner = 'HdrSdrMenu.LocalScript.v1'
$aboutProtocol = 'HKCU:\Software\Classes\notuxius-hdr-control'
$config = Join-Path $NilesoftPath 'shell.nss'
$importFile = Join-Path $NilesoftPath 'imports\hdr-context-menu.nss'
$importLine = "import 'imports/hdr-context-menu.nss'"
$utf8 = New-Object Text.UTF8Encoding($true)
$hasShell = Test-Path -LiteralPath $config

function Write-Text([string]$Path, [string]$Text) {
    [IO.File]::WriteAllText($Path,$Text,$utf8)
}
function Set-HdrShortcutNotificationIdentity([string]$Path) {
    # Windows resolves the toast sender's name from the Start shortcut with this ID.
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    $fileType=[Windows.Storage.StorageFile,Windows.Storage,ContentType=WindowsRuntime]
    # PowerShell 5.1 needs the concrete AsTask<StorageFile> overload for this read.
    $methods=[System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 }
    $asTask=$methods | Where-Object { $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' }
    $read=$asTask.MakeGenericMethod($fileType).Invoke($null,@($fileType::GetFileFromPathAsync($Path)))
    $file=$read.GetAwaiter().GetResult()
    $properties=[Collections.Generic.Dictionary[string,object]]::new()
    $properties.Add('System.AppUserModel.ID','Notuxius.HdrControl')
    $asAction=$methods | Where-Object { $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncAction' }
    $write=$asAction.Invoke($null,@($file.Properties.SavePropertiesAsync($properties)))
    [void]$write.GetAwaiter().GetResult()
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
        ('(?i)"' + [regex]::Escape($launcher) + '"\s+(?:Watch|Startup)(?:\s|$)')
    )
    Get-CimInstance Win32_Process | Where-Object {
        $_.SessionId -eq $session -and $_.Name -in @('powershell.exe','wscript.exe') -and
        ($_.CommandLine -match $patterns[0] -or $_.CommandLine -match $patterns[1])
    } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Get-Process -Name 'HDR Control' -ErrorAction SilentlyContinue | Where-Object {
        $_.SessionId -eq $session -and $_.Path -eq $locationExe
    } | Stop-Process -Force -ErrorAction SilentlyContinue
}
function Refresh-Shell {
    if ($hasShell -and -not $NoRestart) {
        Start-Process -FilePath (Join-Path $NilesoftPath 'shell.exe') -ArgumentList '-restart','-silent' -WindowStyle Hidden -Wait
    }
}

try {
    $ownsProtocol = (Test-Path -LiteralPath $aboutProtocol) -and (Get-ItemProperty -LiteralPath $aboutProtocol).Owner -eq $owner
    if ($Action -eq 'Install' -and (Test-Path -LiteralPath $aboutProtocol) -and -not $ownsProtocol) { throw 'The HDR Control notification protocol is already registered by another app.' }
    if ((Test-Path -LiteralPath $menuKey) -and (Get-ItemProperty -LiteralPath $menuKey).Owner -ne $owner) {
        throw 'An unrelated menu entry already uses this registry key.'
    }
    $shortcutShell = New-Object -ComObject WScript.Shell
    $ownsShortcut = $false
    if (Test-Path -LiteralPath $shortcutPath) {
        $existingShortcut = $shortcutShell.CreateShortcut($shortcutPath)
        $ownsShortcut = $existingShortcut.TargetPath -eq $shortcutTarget -and $existingShortcut.Arguments -eq $shortcutArguments
        if ($Action -eq 'Install' -and -not $ownsShortcut) {
            throw 'An unrelated Start menu shortcut already uses HDR Control.lnk.'
        }
    }
    $ownsLegacyShortcut = $false
    if (Test-Path -LiteralPath $legacyShortcutPath) {
        $legacyShortcut = $shortcutShell.CreateShortcut($legacyShortcutPath)
        $ownsLegacyShortcut = $legacyShortcut.TargetPath -eq $shortcutTarget -and $legacyShortcut.Arguments -eq $shortcutArguments
    }
    if ($Action -eq 'Uninstall') {
        Stop-Helper
        if ($ownsProtocol) { Remove-Item -LiteralPath $aboutProtocol -Recurse }
        . (Join-Path $PSScriptRoot 'HdrStartup.ps1')
        Set-HdrStartupEnabled $false
        if (Test-Path -LiteralPath $locationExe) { Remove-Item -LiteralPath $locationExe }
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath 'HKCU:\Software\Classes\AppUserModelId\Notuxius.HdrControl' -ErrorAction SilentlyContinue
        Remove-ItemProperty -LiteralPath 'HKCU:\Software\HdrContextMenu' -Name StartWithWindows,StartupMigrated,UpdateOffer -ErrorAction SilentlyContinue
        Remove-ItemProperty -LiteralPath 'HKCU:\Software\HdrContextMenu' -Name AutomaticHdr,UseCommunityApps,SettingsWindowPlacement -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath 'HKCU:\Software\HdrContextMenu\SdrBrightness' -Recurse -ErrorAction SilentlyContinue
        if ($ownsShortcut) { Remove-Item -LiteralPath $shortcutPath }
        if ($ownsLegacyShortcut) { Remove-Item -LiteralPath $legacyShortcutPath }
        if ($hasShell) {
            $text = [IO.File]::ReadAllText($config)
            $updated = [regex]::Replace($text, '(?m)^\s*import [\x27\x22]imports/hdr-context-menu\.nss[\x27\x22]\s*\r?\n?', '')
            if ($updated -ne $text) { Backup-File $config; Write-Text $config $updated }
        }
        if ((Test-Path -LiteralPath $importFile) -and [IO.File]::ReadAllText($importFile).StartsWith('// HDR Context Menu - managed by Setup.ps1')) {
            Remove-Item -LiteralPath $importFile
        }
        if (Test-Path -LiteralPath $menuKey) { Remove-Item -LiteralPath $menuKey -Recurse }
        foreach ($name in @('HdrSdrMenu.ps1','HdrTray.ps1','HdrProfiles.ps1','HdrStartup.ps1','ProfilesUi.cs','ProcessGridTheme.cs','TrayTheme.cs','HdrLocation.cs','Update-HdrApp.ps1','HdrApps.community.txt','VERSION','Start-Tray.vbs','Toggle-HdrSdr.vbs','HdrSdrMenu.ico','HdrEnabled.ico','HdrAutoEnabled.ico','HdrEnabledPaused.ico','HdrAutoIdle.ico','HdrDisabled.ico','HdrUnavailable.ico','HdrEnableAction.ico','HdrDisableAction.ico','HdrUnavailableAction.ico','MenuLabel.txt','MenuIcon.txt','Setup.ps1','hdr-context-menu.nss','package.commit')) {
            $path = Join-Path $installDir $name
            if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path }
        }
        Refresh-Shell
        Write-Output 'HDR Control removed. Configuration backups were retained.'
        return
    }
    . (Join-Path $PSScriptRoot 'Update-HdrApp.ps1') -FunctionsOnly
    Restore-HdrCommunityBundle $PSScriptRoot
    foreach ($name in @('HdrSdrMenu.ps1','HdrTray.ps1','HdrProfiles.ps1','HdrStartup.ps1','ProfilesUi.cs','ProcessGridTheme.cs','TrayTheme.cs','HdrLocation.cs','Update-HdrApp.ps1','HdrApps.community.txt','VERSION','Start-Tray.vbs','Toggle-HdrSdr.vbs','HdrSdrMenu.ico','HdrEnabled.ico','HdrAutoEnabled.ico','HdrEnabledPaused.ico','HdrAutoIdle.ico','HdrDisabled.ico','HdrUnavailable.ico','HdrEnableAction.ico','HdrDisableAction.ico','HdrUnavailableAction.ico','hdr-context-menu.nss')) {
        if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $name))) { throw "Package file missing: $name" }
    }
    if ($installDir.Contains("'") -or $env:SystemRoot.Contains("'")) { throw 'Installation paths cannot contain apostrophes.' }
    if ((Test-Path -LiteralPath $importFile) -and -not [IO.File]::ReadAllText($importFile).StartsWith('// HDR Context Menu - managed by Setup.ps1')) {
        throw 'An unrelated Nilesoft import already uses hdr-context-menu.nss.'
    }
    # Windows attributes desktop location access to the executable that requests it.
    $buildDir = Join-Path ([IO.Path]::GetTempPath()) ('hdr-location-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $buildDir | Out-Null
    $locationBuild = Join-Path $buildDir 'HDR Control.exe'
    $compiler = Join-Path $env:SystemRoot 'Microsoft.NET\Framework\v4.0.30319\csc.exe'
    & $compiler /nologo /target:winexe /optimize+ /reference:System.Device.dll "/out:$locationBuild" ("/win32icon:" + (Join-Path $PSScriptRoot 'HdrSdrMenu.ico')) (Join-Path $PSScriptRoot 'HdrLocation.cs')
    if ($LASTEXITCODE -ne 0) { throw 'Could not build the HDR Control location reader.' }
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null
    # The limited logon helper needs to update its state file after elevated setup.
    $acl = Get-Acl -LiteralPath $installDir
    $rule = New-Object Security.AccessControl.FileSystemAccessRule($identity.User,'Modify','ContainerInherit,ObjectInherit','None','Allow')
    $acl.SetAccessRule($rule)
    Set-Acl -LiteralPath $installDir -AclObject $acl
    Stop-Helper
    Copy-Item -LiteralPath $locationBuild -Destination $locationExe -Force
    foreach ($name in @('HdrSdrMenu.ps1','HdrTray.ps1','HdrProfiles.ps1','HdrStartup.ps1','ProfilesUi.cs','ProcessGridTheme.cs','TrayTheme.cs','HdrLocation.cs','Update-HdrApp.ps1','HdrApps.community.txt','VERSION','Start-Tray.vbs','Toggle-HdrSdr.vbs','HdrSdrMenu.ico','HdrEnabled.ico','HdrAutoEnabled.ico','HdrEnabledPaused.ico','HdrAutoIdle.ico','HdrDisabled.ico','HdrUnavailable.ico','HdrEnableAction.ico','HdrDisableAction.ico','HdrUnavailableAction.ico','Setup.ps1','hdr-context-menu.nss','package.commit')) {
        $source = Join-Path $PSScriptRoot $name
        $destination = Join-Path $installDir $name
        if ((Test-Path -LiteralPath $source) -and [IO.Path]::GetFullPath($source) -ne [IO.Path]::GetFullPath($destination)) {
            Backup-File $destination
            Copy-Item -LiteralPath $source -Destination $destination -Force
        }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'package.commit')) -and $PSScriptRoot -ne $installDir) {
        Remove-Item -LiteralPath (Join-Path $installDir 'package.commit') -ErrorAction SilentlyContinue
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
    $taskAction = New-ScheduledTaskAction -Execute (Join-Path $env:SystemRoot 'System32\wscript.exe') -Argument ('//NoLogo "{0}" Startup "$(Arg0)"' -f $launcher)
    # Keep the task for on-demand limited-user launches from elevated setup only.
    $principal = New-ScheduledTaskPrincipal -UserId $identity.User.Value -LogonType Interactive -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
    . (Join-Path $installDir 'HdrStartup.ps1')
    Register-HdrNotificationProtocol -RefreshShell
    $startupPrefs=Get-ItemProperty -LiteralPath 'HKCU:\Software\HdrContextMenu' -ErrorAction SilentlyContinue
    if (-not $startupPrefs.StartupMigrated) {
        Set-HdrStartupEnabled ($null -eq $startupPrefs.StartWithWindows -or $startupPrefs.StartWithWindows -ne 0)
        if (-not $startupPrefs) { New-Item -Path 'HKCU:\Software\HdrContextMenu' -Force | Out-Null }
        New-ItemProperty -LiteralPath 'HKCU:\Software\HdrContextMenu' -Name StartupMigrated -Value 1 -PropertyType DWord -Force | Out-Null
    } elseif (Test-HdrStartupShortcut -Legacy) {
        Set-HdrStartupEnabled $true
    }
    Register-ScheduledTask -TaskName $taskName -Action $taskAction -Principal $principal -Settings $settings -Force | Out-Null
    New-Item -ItemType Directory -Path (Split-Path $shortcutPath) -Force | Out-Null
    # StorageFile cannot edit a link directly inside the protected Start menu folder.
    $stagedShortcut = Join-Path $buildDir 'HDR Control.lnk'
    $shortcut = $shortcutShell.CreateShortcut($stagedShortcut)
    $shortcut.TargetPath = $shortcutTarget
    $shortcut.Arguments = $shortcutArguments
    $shortcut.WorkingDirectory = $installDir
    $shortcut.IconLocation = (Join-Path $installDir 'HdrEnabled.ico') + ',0'
    $shortcut.Description = 'HDR Control - HDR controls, automatic switching, and SDR brightness'
    $shortcut.WindowStyle = 7
    $shortcut.Save()
    Set-HdrShortcutNotificationIdentity $stagedShortcut
    Copy-Item -LiteralPath $stagedShortcut -Destination $shortcutPath -Force
    if ($ownsLegacyShortcut) { Remove-Item -LiteralPath $legacyShortcutPath }
    # Pass a one-time argument through Task Scheduler so explicit installation
    # starts the limited-user tray even when the saved logon preference is off.
    $scheduler = New-Object -ComObject Schedule.Service
    $scheduler.Connect()
    [void]$scheduler.GetFolder('\').GetTask($taskName).Run('LaunchNow')
    Refresh-Shell
    Write-Output 'HDR Control installed. Open HDR Control from the Start menu or use the tray icon.'
} catch {
    # If an upgrade fails, resume the existing helper where possible.
    if (Test-Path -LiteralPath $runtime) { Start-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue }
    Write-Error $_ -ErrorAction Continue
    exit 1
} finally {
    if ($locationBuild) {
        if ($stagedShortcut -and (Test-Path -LiteralPath $stagedShortcut)) { Remove-Item -LiteralPath $stagedShortcut -Force }
        if (Test-Path -LiteralPath $locationBuild) { Remove-Item -LiteralPath $locationBuild -Force }
        [IO.Directory]::Delete($buildDir)
    }
}
