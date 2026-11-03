# Uses only Windows PowerShell and Windows display APIs. No downloads.
param(
    [ValidateSet('Status','Toggle','On','Off','Sync','Watch','Brightness','Launch')]
    [string]$Action = 'Status',
    [ValidatePattern('^[A-Za-z0-9+/=]+$')]
    [string]$DisplayId,
    [ValidateRange(1000,6000)]
    [uint32]$SdrWhiteLevel = 1000,
    [ValidatePattern('^[a-f0-9]{32}$')][string]$LaunchId,
    [switch]$FromHelper,
    [switch]$OpenAbout,
    [switch]$UpdateComplete,
    [ValidatePattern('^[a-f0-9]{32}$')][string]$InstallOffer,
    [switch]$ShowError
)
$ErrorActionPreference = 'Stop'
$installDir = $PSScriptRoot
$installedScript = Join-Path $installDir 'HdrSdrMenu.ps1'
$installedIcon = Join-Path $installDir 'HdrSdrMenu.ico'
$installedLauncher = Join-Path $installDir 'Toggle-HdrSdr.vbs'
$menuKey = 'HKCU:\Software\Classes\DesktopBackground\Shell\HdrToggle.LocalScript'
$owner = 'HdrSdrMenu.LocalScript.v1'

function Sync-HdrMenu($Displays) {
    $capable = @($Displays | Where-Object HdrSupported)
    $unavailable = $capable.Count -eq 0
    $enableNext = @($capable | Where-Object { -not $_.HdrEnabled }).Count -gt 0
    $label = if ($enableNext) { 'Enable HDR' } else { 'Disable HDR' }
    $nextAction = if ($enableNext) { 'On' } else { 'Off' }
    # Shared storage avoids packaged-app redirection of AppData and HKCU.
    # Nilesoft reads this file each time it opens the menu.
    $iconName = if ($unavailable) { 'HdrUnavailableAction.ico' }
        elseif ($enableNext) { 'HdrEnableAction.ico' }
        else { 'HdrDisableAction.ico' }
    $stateFiles = [ordered]@{
        'MenuIcon.txt' = $iconName
        'MenuLabel.txt' = $(if ($unavailable) { 'HDR: Unavailable' } else { $label })
    }
    foreach ($name in $stateFiles.Keys) {
        $stateFile = Join-Path $installDir $name
        $stateLabel = $stateFiles[$name]
        if ([IO.File]::Exists($stateFile) -and [IO.File]::ReadAllText($stateFile) -eq $stateLabel) { continue }
        $pendingFile = Join-Path $installDir ('MenuLabel.' + [guid]::NewGuid().ToString('N') + '.tmp')
        [IO.File]::WriteAllText($pendingFile, $stateLabel, [Text.Encoding]::ASCII)
        try {
            if ([IO.File]::Exists($stateFile)) { [IO.File]::Replace($pendingFile, $stateFile, ($pendingFile + '.previous')) }
            else { [IO.File]::Move($pendingFile, $stateFile) }
        } finally {
            if ([IO.File]::Exists($pendingFile)) { [IO.File]::Delete($pendingFile) }
            if ([IO.File]::Exists($pendingFile + '.previous')) { [IO.File]::Delete($pendingFile + '.previous') }
        }
    }
    if (-not (Test-Path -LiteralPath $menuKey)) { return }
    $entry = Get-ItemProperty -LiteralPath $menuKey
    if ($entry.Owner -ne $owner) { return }
    $iconPath = Join-Path $installDir $iconName
    if ($entry.Icon -ne $iconPath) {
        Set-ItemProperty -LiteralPath $menuKey -Name Icon -Value $iconPath
    }
    $command = '"{0}" //NoLogo "{1}" {2}' -f (Join-Path $env:SystemRoot 'System32\wscript.exe'), $installedLauncher, $nextAction
    if ($unavailable) {
        if ($null -eq $entry.LegacyDisable) {
            New-ItemProperty -LiteralPath $menuKey -Name LegacyDisable -Value '' -PropertyType String -Force | Out-Null
        }
        return
    }
    if ($null -ne $entry.LegacyDisable) {
        Remove-ItemProperty -LiteralPath $menuKey -Name LegacyDisable
    }
    if ((Get-Item -LiteralPath ($menuKey + '\command')).GetValue('') -ne $command) {
        Set-Item -LiteralPath ($menuKey + '\command') -Value $command
    }
    if ($entry.MUIVerb -ne $label) {
        Set-ItemProperty -LiteralPath $menuKey -Name MUIVerb -Value $label
    }
}

function Invoke-HdrChange([string]$Action, $Displays, [string]$DisplayId) {
    $selected = @($Displays)
    if ($DisplayId) {
        $selected = @($Displays | Where-Object { $_.DisplayId -ceq $DisplayId })
        if ($selected.Count -ne 1) { throw 'The selected monitor is no longer available. Refresh displays and try again.' }
    }
    $supported = @($selected | Where-Object HdrSupported)
    if ($supported.Count -eq 0) { throw 'No active HDR-capable display was found.' }
    $enable = if ($Action -eq 'Toggle') { @($supported | Where-Object { -not $_.HdrEnabled }).Count -gt 0 } else { $Action -eq 'On' }
    $changed = @()
    try {
        foreach ($display in $supported) {
            if ($display.HdrEnabled -ne $enable) {
                [LocalHdrMenu.DisplayApi]::Set($display, $enable)
                $changed += $display
            }
        }
        $verified = $false
        for ($attempt=0; $attempt -lt 10; $attempt++) {
            Start-Sleep -Milliseconds 500
            $after = @([LocalHdrMenu.DisplayApi]::Read())
            $verified = $true
            foreach ($display in $supported) {
                $id = [LocalHdrMenu.DisplayApi]::Identity($display)
                $current = @($after | Where-Object { [LocalHdrMenu.DisplayApi]::Identity($_) -ceq $id })
                if ($current.Count -ne 1 -or $current[0].HdrEnabled -ne $enable) { $verified = $false }
            }
            if ($verified) { break }
        }
        if (-not $verified) { throw 'Windows did not confirm the requested HDR setting.' }
    } catch {
        $originalError = $_
        foreach ($display in $changed) {
            try {
                # Do not restore an old target after a disconnect/replacement.
                $current = @([LocalHdrMenu.DisplayApi]::Read() | Where-Object { $_.DisplayId -ceq $display.DisplayId })
                if ($current.Count -eq 1) { [LocalHdrMenu.DisplayApi]::Set($current[0], $display.HdrEnabled) }
            } catch { Write-Warning $_ }
        }
        throw $originalError
    }
    return $after
}

function Invoke-HdrBrightness([string]$DisplayId, [uint32]$Level) {
    if (-not $DisplayId -or $Level -lt 1000 -or $Level -gt 6000) { throw 'Invalid brightness request.' }
    # Resolve again immediately before writing; never redirect a stale command.
    $selected = @([LocalHdrMenu.DisplayApi]::Read() | Where-Object { $_.DisplayId -ceq $DisplayId })
    if ($selected.Count -ne 1) { throw 'The selected monitor is no longer available.' }
    $display = $selected[0]
    if (-not $display.HdrEnabled -or -not $display.HdrActive -or $null -eq $display.SdrWhiteLevel) {
        throw 'SDR brightness is unavailable. Enable HDR on this monitor first.'
    }
    if ($display.SdrWhiteLevel -ne $Level) { [LocalHdrMenu.DisplayApi]::SetBrightness($display, $Level) }
    for ($attempt = 0; $attempt -lt 8; $attempt++) {
        $current = @([LocalHdrMenu.DisplayApi]::Read() | Where-Object { $_.DisplayId -ceq $DisplayId })
        if ($current.Count -ne 1 -or -not $current[0].HdrEnabled -or -not $current[0].HdrActive) {
            throw 'The monitor disconnected or HDR was disabled during the brightness change.'
        }
        if ($null -ne $current[0].SdrWhiteLevel -and $current[0].SdrWhiteLevel -eq $Level) { return }
        Start-Sleep -Milliseconds 200
    }
    throw 'Windows did not confirm the requested SDR brightness.'
}

$changeMutex=$null
$ownsChangeMutex=$false
try {
    if ($DisplayId -and $Action -notin @('On','Off','Toggle','Brightness')) { throw '-DisplayId requires On, Off, Toggle, or Brightness.' }
    if ($Action -eq 'Brightness' -and -not $DisplayId) { throw 'Brightness requires a selected display.' }
    # Layouts and constants follow Microsoft's Windows SDK wingdi.h:
    # https://github.com/microsoft/win32metadata/blob/main/generation/WinSDK/RecompiledIdlHeaders/um/wingdi.h
    if (-not ('LocalHdrMenu.DisplayApi' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace LocalHdrMenu {
    [StructLayout(LayoutKind.Sequential)] public struct Luid { public uint Low; public int High; }
    // QueryDisplayConfig fills the full structures; only target identity is read.
    [StructLayout(LayoutKind.Explicit, Size=72)] public struct PathInfo {
        [FieldOffset(20)] public Luid Adapter;
        [FieldOffset(28)] public uint Target;
    }
    [StructLayout(LayoutKind.Explicit, Size=64)] public struct ModeInfo {
        [FieldOffset(0)] public uint Type;
    }
    [StructLayout(LayoutKind.Sequential)] public struct Header {
        public uint Type, Size; public Luid Adapter; public uint Id;
    }
    [StructLayout(LayoutKind.Sequential)] public struct ColorInfo2 {
        public Header Header; public uint Flags, Encoding, Bits, ActiveMode;
    }
    [StructLayout(LayoutKind.Sequential)] public struct ColorInfo {
        public Header Header; public uint Flags, Encoding, Bits;
    }
    [StructLayout(LayoutKind.Sequential)] public struct SetColor {
        public Header Header; public uint Enabled;
    }
    [StructLayout(LayoutKind.Sequential)] public struct SdrLevel {
        public Header Header; public uint Level;
    }
    [StructLayout(LayoutKind.Sequential)] public struct SetSdrLevel {
        public Header Header; public uint Level; public byte FinalValue;
    }
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] public struct TargetName {
        public Header Header; public uint Flags, Technology;
        public ushort Manufacturer, Product; public uint Connector;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=64)] public string FriendlyName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string DevicePath;
    }
    public class Display {
        public string Name { get; set; }
        public string DisplayId { get; set; }
        public string DevicePath { get; set; }
        public uint? SdrWhiteLevel { get; set; }
        public bool HdrSupported { get; set; }
        public bool HdrEnabled { get; set; }
        public bool HdrActive { get; set; }
        public string Api { get; set; }
        internal Luid Adapter;
        internal uint Id;
        internal bool Modern;
        internal string Key { get { return Adapter.High + ":" + Adapter.Low + ":" + Id; } }
    }
    public static class DisplayApi {
        [DllImport("user32.dll")] static extern int GetDisplayConfigBufferSizes(uint flags, out uint paths, out uint modes);
        [DllImport("user32.dll")] static extern int QueryDisplayConfig(uint flags, ref uint paths, [Out] PathInfo[] pathArray, ref uint modes, [Out] ModeInfo[] modeArray, IntPtr topology);
        [DllImport("user32.dll", EntryPoint="DisplayConfigGetDeviceInfo")] static extern int GetColor2(ref ColorInfo2 info);
        [DllImport("user32.dll", EntryPoint="DisplayConfigGetDeviceInfo")] static extern int GetColor(ref ColorInfo info);
        [DllImport("user32.dll", EntryPoint="DisplayConfigGetDeviceInfo")] static extern int GetName(ref TargetName info);
        [DllImport("user32.dll", EntryPoint="DisplayConfigSetDeviceInfo")] static extern int SetState(ref SetColor info);
        [DllImport("user32.dll", EntryPoint="DisplayConfigGetDeviceInfo")] static extern int GetSdrLevel(ref SdrLevel info);
        [DllImport("user32.dll", EntryPoint="DisplayConfigSetDeviceInfo")] static extern int SetSdrLevelNative(ref SetSdrLevel info);
        static Header MakeHeader(uint type, Type structure, Luid adapter, uint id) {
            return new Header { Type=type, Size=(uint)Marshal.SizeOf(structure), Adapter=adapter, Id=id };
        }
        static void Check(int result, string operation) {
            if (result != 0) throw new Win32Exception(result, operation + ": " + new Win32Exception(result).Message);
        }
        public static Display[] Read() {
            for (int attempt=0; attempt<5; attempt++) {
                uint pc, mc;
                Check(GetDisplayConfigBufferSizes(2, out pc, out mc), "Read display buffer sizes");
                PathInfo[] paths = new PathInfo[Math.Max(pc,1)];
                ModeInfo[] modes = new ModeInfo[Math.Max(mc,1)];
                int result = QueryDisplayConfig(2, ref pc, paths, ref mc, modes, IntPtr.Zero);
                if (result == 122) continue;
                Check(result, "Read active displays");
                var displays = new List<Display>();
                var seen = new HashSet<string>();
                for (int i=0; i<pc; i++) {
                    PathInfo p = paths[i];
                    var d = new Display { Adapter=p.Adapter, Id=p.Target };
                    if (!seen.Add(d.Key)) continue;
                    var name = new TargetName { Header=MakeHeader(2,typeof(TargetName),p.Adapter,p.Target) };
                    d.Name = GetName(ref name)==0 && !String.IsNullOrEmpty(name.FriendlyName) ? name.FriendlyName : "Display " + p.Target;
                    // Include the device path so another monitor on a reused target
                    // cannot receive a command from a stale menu. Base64 is safe to
                    // pass as a quoted process argument, even with unusual names.
                    d.DisplayId = Convert.ToBase64String(System.Text.Encoding.Unicode.GetBytes(d.Key + "\n" + name.DevicePath));
                    d.DevicePath = name.DevicePath;
                    var modern = new ColorInfo2 { Header=MakeHeader(15,typeof(ColorInfo2),p.Adapter,p.Target) };
                    int status = GetColor2(ref modern);
                    if (status == 0) {
                        d.Modern=true; d.Api="Windows HDR";
                        d.HdrSupported=(modern.Flags & 16)!=0;
                        d.HdrEnabled=(modern.Flags & 32)!=0;
                        d.HdrActive=modern.ActiveMode==2;
                    } else if (status == 87 || status == 50) {
                        var legacy = new ColorInfo { Header=MakeHeader(9,typeof(ColorInfo),p.Adapter,p.Target) };
                        Check(GetColor(ref legacy), "Read HDR for " + d.Name);
                        d.Api="Windows advanced color";
                        d.HdrSupported=(legacy.Flags & 1)!=0 && (legacy.Flags & 4)==0;
                        d.HdrEnabled=(legacy.Flags & 2)!=0 && d.HdrSupported;
                        d.HdrActive=d.HdrEnabled;
                    } else { Check(status, "Read HDR for " + d.Name); }
                    // Brightness failure is isolated: HDR controls must remain usable.
                    if (d.HdrEnabled && d.HdrActive) {
                        var level = new SdrLevel { Header=MakeHeader(11,typeof(SdrLevel),p.Adapter,p.Target) };
                        if (GetSdrLevel(ref level)==0) d.SdrWhiteLevel=level.Level;
                    }
                    displays.Add(d);
                }
                return displays.ToArray();
            }
            throw new Exception("Display configuration kept changing. Please try again.");
        }
        public static void Set(Display display, bool enabled) {
            if (!display.HdrSupported) throw new Exception("HDR is not supported on " + display.Name);
            var state = new SetColor {
                Header=MakeHeader(display.Modern ? 16u : 10u,typeof(SetColor),display.Adapter,display.Id),
                Enabled=enabled ? 1u : 0u
            };
            Check(SetState(ref state), "Set HDR for " + display.Name);
        }
        public static string Identity(Display display) { return display.DisplayId; }
        public static void SetBrightness(Display display, uint level) {
            if (!display.HdrEnabled || !display.HdrActive || level<1000 || level>6000)
                throw new ArgumentException("SDR brightness requires active HDR and a supported level.");
            // Private Windows operation, also used by hdr-sdr-brightness. Do not
            // fall back to a global DWM call: that could affect other monitors.
            var state = new SetSdrLevel {
                Header=MakeHeader(0xFFFFFFEEu,typeof(SetSdrLevel),display.Adapter,display.Id),
                Level=level, FinalValue=1
            };
            Check(SetSdrLevelNative(ref state), "Set SDR brightness for " + display.Name);
        }
    }
}
'@
    }
    if ($Action -eq 'Watch') {
        # One hidden helper per interactive session. Re-read state so changes from
        # Windows Settings, games, and Win+Alt+B are reflected in the menu too.
        $watchMutex = New-Object Threading.Mutex($false, 'Local\HdrSdrMenu.LabelWatcher.v1')
        $aboutRequest = [Threading.EventWaitHandle]::new($false,'AutoReset','Local\HdrSdrMenu.OpenAbout.v1')
        $ownsMutex = $false
        try {
            try { $ownsMutex = $watchMutex.WaitOne(0) }
            catch [Threading.AbandonedMutexException] { $ownsMutex = $true }
            if ($OpenAbout) { [void]$aboutRequest.Set() }
            if ($InstallOffer) {
                . (Join-Path $installDir 'HdrProfiles.ps1')
                $requests = Get-HdrRequestDirectory
                [void][IO.Directory]::CreateDirectory($requests)
                Write-HdrAtomicText (Join-Path $requests ('update-'+[Guid]::NewGuid().ToString('N')+'.json')) (
                    @{Kind='InstallUpdate';Id=$InstallOffer;CreatedUtc=[DateTime]::UtcNow.ToString('o')} | ConvertTo-Json -Compress
                )
            }
            if (-not $ownsMutex -and -not $UpdateComplete) { return }
            . (Join-Path $installDir 'HdrTray.ps1')
            if ($UpdateComplete) { Show-HdrNotification ("Update complete`nHDR Control "+(Get-HdrInstalledVersion)+" is installed.") }
            if ($ownsMutex) { Start-HdrTray }
        } finally {
            $aboutRequest.Dispose()
            if ($ownsMutex) { $watchMutex.ReleaseMutex() }
            $watchMutex.Dispose()
        }
        return
    }
    if ($Action -eq 'Launch') {
        . (Join-Path $installDir 'HdrTray.ps1')
        Submit-HdrLaunch $LaunchId
        return
    }
    if ($Action -in @('On','Off','Toggle','Brightness')) {
        # Serialize native writes from the tray, desktop entry, and CLI. Read the
        # current state only after acquiring the lock; never use a queued snapshot.
        $changeMutex=New-Object Threading.Mutex($false,'Local\HdrSdrMenu.DisplayChange.v1')
        try { $ownsChangeMutex=$changeMutex.WaitOne(20000) }
        catch [Threading.AbandonedMutexException] { $ownsChangeMutex=$true }
        if (-not $ownsChangeMutex) { throw 'Another display change is still running. Try again shortly.' }
    }
    $displays = @([LocalHdrMenu.DisplayApi]::Read())
    if ($Action -eq 'Status') { $displays; return }
    if ($Action -eq 'Brightness') { Invoke-HdrBrightness $DisplayId $SdrWhiteLevel; return }
    if ($Action -eq 'Sync') { Sync-HdrMenu $displays; return }
    $after = @(Invoke-HdrChange $Action $displays $DisplayId)
    if (-not $FromHelper) {
        try {
            . (Join-Path $installDir 'HdrProfiles.ps1')
            Publish-HdrManualChange $DisplayId
        } catch { Write-Warning 'HDR changed, but the manual override notification could not be saved.' }
    }
    Sync-HdrMenu $after
    $after
} catch {
    if ($ShowError) {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'HDR Control') | Out-Null
    }
    Write-Error $_ -ErrorAction Continue
    exit 1
} finally {
    if ($ownsChangeMutex) { $changeMutex.ReleaseMutex() }
    if ($null -ne $changeMutex) { $changeMutex.Dispose() }
}
