# Shared by setup and the tray. Windows manages sign-in through this user's Startup folder.
$hdrStartupLink = Join-Path ([Environment]::GetFolderPath('Startup')) 'HDR Control.lnk'
$hdrStartupTarget = Join-Path $env:ProgramData 'HdrSdrMenu\HDR Control.exe'
$hdrStartupArguments = '--startup'
$hdrStartupApproval = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'
$hdrProtocolPath = 'HKCU:\Software\Classes\notuxius-hdr-control'

function Register-HdrNotificationProtocol([switch]$RefreshShell) {
    $owner = 'HdrSdrMenu.LocalScript.v1'
    $command = '"{0}" //NoLogo "{1}" Notification "%1"' -f (Join-Path $env:SystemRoot 'System32\wscript.exe'),(Join-Path $env:ProgramData 'HdrSdrMenu\Toggle-HdrSdr.vbs')
    $key = Get-Item -LiteralPath $hdrProtocolPath -ErrorAction SilentlyContinue
    if ($key -and $key.GetValue('Owner') -ne $owner) { throw 'The notification protocol is registered by another app.' }
    $commandPath = Join-Path $hdrProtocolPath 'shell\open\command'
    $open = Get-Item -LiteralPath $commandPath -ErrorAction SilentlyContinue
    if (-not $key -or $null -eq $key.GetValue('URL Protocol') -or -not $open -or $open.GetValue('') -ne $command) {
        New-Item -Path $commandPath -Force | Out-Null
        Set-Item -LiteralPath $hdrProtocolPath -Value 'URL:HDR Control'
        New-ItemProperty -LiteralPath $hdrProtocolPath -Name Owner -Value $owner -Force | Out-Null
        Set-Item -LiteralPath $commandPath -Value $command
        New-ItemProperty -LiteralPath $hdrProtocolPath -Name 'URL Protocol' -Value '' -PropertyType String -Force | Out-Null
        $RefreshShell = $true
    }
    if ($RefreshShell) {
        if (-not ('LocalHdrMenu.ShellAssociations' -as [type])) {
            Add-Type -Namespace LocalHdrMenu -Name ShellAssociations -MemberDefinition '[System.Runtime.InteropServices.DllImport("shell32.dll")] public static extern void SHChangeNotify(int change, uint flags, System.IntPtr item1, System.IntPtr item2);'
        }
        [LocalHdrMenu.ShellAssociations]::SHChangeNotify(0x08000000,0,[IntPtr]::Zero,[IntPtr]::Zero)
    }
}

function Test-HdrStartupShortcut([switch]$Legacy) {
    if (-not (Test-Path -LiteralPath $hdrStartupLink -PathType Leaf)) { return $false }
    $link=(New-Object -ComObject WScript.Shell).CreateShortcut($hdrStartupLink)
    if ($Legacy) {
        $arguments='//NoLogo "{0}"' -f (Join-Path $env:ProgramData 'HdrSdrMenu\Start-Tray.vbs')
        return $link.TargetPath -eq (Join-Path $env:SystemRoot 'System32\wscript.exe') -and $link.Arguments -eq $arguments
    }
    return $link.TargetPath -eq $hdrStartupTarget -and $link.Arguments -eq $hdrStartupArguments
}

function Get-HdrStartupEnabled {
    if (-not (Test-HdrStartupShortcut)) { return $false }
    # Respect a separate disable in Windows Startup Apps. Never write its approval data.
    $approval=Get-ItemProperty -LiteralPath $hdrStartupApproval -Name 'HDR Control.lnk' -ErrorAction SilentlyContinue
    $bytes=$approval.'HDR Control.lnk'
    return -not $bytes -or ($bytes[0] -band 1) -eq 0
}

function Set-HdrStartupEnabled([bool]$Enabled) {
    $owned=Test-HdrStartupShortcut
    if ($Enabled -and -not $owned) {
        if ((Test-Path -LiteralPath $hdrStartupLink) -and -not (Test-HdrStartupShortcut -Legacy)) { throw 'An unrelated shortcut already uses HDR Control.lnk in Startup.' }
        $directory=Join-Path $env:ProgramData 'HdrSdrMenu'
        $link=(New-Object -ComObject WScript.Shell).CreateShortcut($hdrStartupLink)
        $link.TargetPath=$hdrStartupTarget
        $link.Arguments=$hdrStartupArguments
        $link.WorkingDirectory=$directory
        $link.IconLocation=(Join-Path $directory 'HdrEnabled.ico')+',0'
        $link.Save()
    } elseif (-not $Enabled -and ($owned -or (Test-HdrStartupShortcut -Legacy))) {
        Remove-Item -LiteralPath $hdrStartupLink -ErrorAction Stop
    }
}
