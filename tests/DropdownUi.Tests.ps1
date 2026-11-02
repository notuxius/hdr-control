param([string]$OutputDirectory)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
Add-Type -Path @((Join-Path $repo 'TrayTheme.cs'),(Join-Path $repo 'ProfilesUi.cs')) -ReferencedAssemblies System.Windows.Forms,System.Drawing
Add-Type @'
using System;
using System.Drawing;
using System.Runtime.InteropServices;
public static class DropdownProbe {
    [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left,Top,Right,Bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct Info { public int Size; public Rect Item,Button; public int State; public IntPtr Combo,Edit,List; }
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr window,int message,IntPtr wparam,IntPtr lparam);
    [DllImport("user32.dll")] static extern bool GetComboBoxInfo(IntPtr window,ref Info info);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr window,out Rect rect);
    public static void Key(IntPtr window,int key) {
        SendMessage(window,0x100,(IntPtr)key,IntPtr.Zero);
        SendMessage(window,0x101,(IntPtr)key,IntPtr.Zero);
    }
    static IntPtr Popup(IntPtr window) {
        var info=new Info {Size=Marshal.SizeOf(typeof(Info))};
        if(!GetComboBoxInfo(window,ref info)) throw new Exception("Cannot find dropdown");
        return info.List;
    }
    public static void PointAt(IntPtr window,int row,int height,bool click) {
        var list=Popup(window);
        var point=(IntPtr)(((row*height+height/2)<<16)|16);
        SendMessage(list,0x200,IntPtr.Zero,point);
        if(click) { SendMessage(list,0x201,(IntPtr)1,point); SendMessage(list,0x202,IntPtr.Zero,point); }
    }
    public static int CheckedRows(IntPtr window,int height,Color accent,string path) {
        var list=Popup(window);
        Rect rect; GetWindowRect(list,out rect);
        using(var bitmap=new Bitmap(rect.Right-rect.Left,rect.Bottom-rect.Top)) {
            using(var graphics=Graphics.FromImage(bitmap)) {
                IntPtr dc=graphics.GetHdc();
                try { SendMessage(list,0x317,dc,(IntPtr)30); } finally { graphics.ReleaseHdc(dc); }
            }
            if(!String.IsNullOrEmpty(path)) bitmap.Save(path,System.Drawing.Imaging.ImageFormat.Png);
            int rows=0;
            for(int y=0;y<bitmap.Height;y++) for(int x=bitmap.Width*3/4;x<bitmap.Width;x++) {
                if(bitmap.GetPixel(x,y).ToArgb()==accent.ToArgb()) { rows|=1<<(y/height); break; }
            }
            return rows;
        }
    }
}
'@ -ReferencedAssemblies System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
function Assert($condition,$message) { if(-not $condition) { throw $message } }
if($OutputDirectory) { [void][IO.Directory]::CreateDirectory($OutputDirectory) }
foreach($scale in @(1.0,1.25,1.5,2.0)) {
    $form=[LocalHdrMenu.ShortcutForm]::new()
    try {
        $form.ShowInTaskbar=$false; $form.StartPosition='Manual'; $form.Location=[Drawing.Point]::new(-30000,-30000)
        $form.Scale([Drawing.SizeF]::new($scale,$scale)); $form.Font=[Drawing.Font]::new('Segoe UI',[single](10*$scale))
        $form.AddPreset('sample','Gaming'); $form.Preset.SelectedIndex=0
        $form.Show(); [Windows.Forms.Application]::DoEvents()
        $form.Action.Focus() | Out-Null
        [DropdownProbe]::Key($form.Action.Handle,40)
        Assert ($form.Action.SelectedIndex -eq 1) 'Arrow-key selection failed'
        $form.Action.DroppedDown=$true; [Windows.Forms.Application]::DoEvents()
        Assert $form.Action.DroppedDown 'Dropdown did not open'
        $path=if($OutputDirectory) { Join-Path $OutputDirectory ('dropdown-'+[int]($scale*100)+'.png') }
        foreach($row in @(0,2,3,1,0)) {
            [DropdownProbe]::PointAt($form.Action.Handle,$row,$form.Action.ItemHeight,$false)
            [Windows.Forms.Application]::DoEvents()
            if(-not [Windows.Forms.SystemInformation]::HighContrast) {
                $checks=[DropdownProbe]::CheckedRows($form.Action.Handle,$form.Action.ItemHeight,[LocalHdrMenu.DialogTheme]::Accent,$path)
                Assert ($checks -eq (1 -shl 1)) "Hovering row $row moved the checkmark at scale $scale (row mask $checks)"
            }
        }
        [DropdownProbe]::Key($form.Action.Handle,27); [Windows.Forms.Application]::DoEvents()
        Assert (-not $form.Action.DroppedDown -and $form.Action.SelectedIndex -eq 1) 'Escape must keep the original selection after hover'
        $form.Action.DroppedDown=$true; [Windows.Forms.Application]::DoEvents()
        [DropdownProbe]::PointAt($form.Action.Handle,3,$form.Action.ItemHeight,$true)
        Assert ($form.Preset.Enabled -and -not $form.Targets.Enabled) 'Preset action did not update dependent controls'
        $form.Action.SelectedIndex=0
        Assert (-not $form.Preset.Enabled -and $form.Targets.Enabled) 'HDR action did not update dependent controls'
        $form.Key.SelectedItem=[Windows.Forms.Keys]::H
        Assert ($form.Key.SelectedItem -eq [Windows.Forms.Keys]::H) 'Key value was not preserved'
        Assert ($form.Action.ItemHeight -ge $form.Action.Font.Height+8) 'Dropdown rows clip scaled text'
    } finally { $form.Dispose() }
}
$form=[LocalHdrMenu.SdrBrightnessForm]::new('Example','QQ==',('A'*64),2500,$true)
try {
    $form.ShowInTaskbar=$false; $form.StartPosition='Manual'; $form.Location=[Drawing.Point]::new(-30000,-30000)
    $form.Show(); $form.Switching.SelectedIndex=2; $form.Switching.DroppedDown=$true
    [DropdownProbe]::PointAt($form.Switching.Handle,0,$form.Switching.ItemHeight,$false)
    $form.RefreshAvailability($true,$false,'')
    Assert ($form.NightLightSettings.Visible -and [LocalHdrMenu.MonitorBrightness]::Capture($form).Mode -eq 'NightLight') 'Hovering changed the displayed or autosaved switching mode'
} finally { $form.Dispose() }
'PASS: dropdown hover, checkmarks, mouse and keyboard selection at 100-200% scale, and brightness mode during hover.'
