# Shared by setup and the tray. Windows manages sign-in through this user's Startup folder.
$hdrStartupLink = Join-Path ([Environment]::GetFolderPath('Startup')) 'HDR Control.lnk'
$hdrStartupTarget = Join-Path $env:ProgramData 'HdrSdrMenu\HDR Control.exe'
$hdrStartupArguments = '--startup'
$hdrStartupApproval = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'

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
