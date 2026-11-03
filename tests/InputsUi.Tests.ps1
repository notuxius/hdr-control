# Exercises local test windows only; no display changes or global input.
param([string]$OutputDirectory)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
Add-Type -Path @((Join-Path $repo 'TrayTheme.cs'),(Join-Path $repo 'ProfilesUi.cs')) -ReferencedAssemblies System.Windows.Forms,System.Drawing,UIAutomationProvider,UIAutomationTypes,WindowsBase
Add-Type @'
using System;
using System.Drawing;
using System.Runtime.InteropServices;
public static class InputProbe {
    [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left,Top,Right,Bottom; }
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr window,int message,IntPtr wparam,IntPtr lparam);
    [DllImport("user32.dll",EntryPoint="SendMessageW")] static extern IntPtr ReadRect(IntPtr window,int message,IntPtr wparam,ref Rect rect);
    public static void Key(IntPtr window,int key) {
        SendMessage(window,0x100,(IntPtr)key,IntPtr.Zero);
        if(key==32) SendMessage(window,0x102,(IntPtr)key,IntPtr.Zero);
        SendMessage(window,0x101,(IntPtr)key,IntPtr.Zero);
    }
    public static void Mouse(IntPtr window,int message,int x,int y,int buttons) {
        SendMessage(window,message,(IntPtr)buttons,(IntPtr)((y<<16)|(x&0xffff)));
    }
    public static void Drag(IntPtr window,double fraction) {
        var thumb=new Rect(); var channel=new Rect();
        ReadRect(window,0x419,IntPtr.Zero,ref thumb); ReadRect(window,0x41a,IntPtr.Zero,ref channel);
        int x=(thumb.Left+thumb.Right)/2,y=(thumb.Top+thumb.Bottom)/2;
        Mouse(window,0x201,x,y,1);
        x=channel.Left+(int)Math.Round(fraction*(channel.Right-channel.Left));
        Mouse(window,0x200,x,y,1); Mouse(window,0x202,x,y,0);
    }
    public static bool TrackSurvivesErase(IntPtr window,Bitmap frame,Color expected) {
        var thumb=new Rect(); var channel=new Rect();
        ReadRect(window,0x419,IntPtr.Zero,ref thumb); ReadRect(window,0x41a,IntPtr.Zero,ref channel);
        int x=(channel.Left+thumb.Left)/2,y=(thumb.Top+thumb.Bottom)/2;
        if(frame.GetPixel(x,y).ToArgb()!=expected.ToArgb()) return false;
        using(var g=Graphics.FromImage(frame)) {
            var dc=g.GetHdc();
            try { SendMessage(window,0x14,dc,IntPtr.Zero); } // WM_ERASEBKGND
            finally { g.ReleaseHdc(dc); }
        }
        return frame.GetPixel(x,y).ToArgb()==expected.ToArgb();
    }
}
'@ -ReferencedAssemblies System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
function Assert($condition,$message) { if(-not $condition) { throw $message } }
function Show-TestWindow($form,$scale) {
    $form.ShowInTaskbar=$false; $form.StartPosition='Manual'; $form.Location=[Drawing.Point]::new(-30000,-30000)
    $form.Scale([Drawing.SizeF]::new($scale,$scale)); $form.Font=[Drawing.Font]::new('Segoe UI',[single](10*$scale))
    $form.Show(); [Windows.Forms.Application]::DoEvents()
}
function Snapshot($form,$name) {
    if(-not $OutputDirectory) { return }
    [Windows.Forms.Application]::DoEvents()
    $bitmap=[Drawing.Bitmap]::new($form.Width,$form.Height)
    try {
        $form.DrawToBitmap($bitmap,[Drawing.Rectangle]::new(0,0,$form.Width,$form.Height))
        $bitmap.Save((Join-Path $OutputDirectory ($name+'.png')),[Drawing.Imaging.ImageFormat]::Png)
    } finally { $bitmap.Dispose() }
}
if($OutputDirectory) { [void][IO.Directory]::CreateDirectory($OutputDirectory) }
foreach($scale in @(1.0,1.25,1.5,2.0)) {
    $brightness=[LocalHdrMenu.SdrBrightnessForm]::new('Example HDR monitor','QQ==',('A'*64),2500,$false)
    $shortcut=[LocalHdrMenu.ShortcutForm]::new()
    $preset=[LocalHdrMenu.PresetForm]::new()
    $game=[LocalHdrMenu.GameRuleForm]::new()
    try {
        Show-TestWindow $game $scale
        $game.Executable.Text='ExampleGame.exe'
        Assert ($game.Executable.Editor.Text -eq 'ExampleGame.exe') 'Executable field did not load saved text'
        $game.Arguments.Editor.Text='--fullscreen --profile "HDR"'
        Assert ($game.Arguments.Text -eq '--fullscreen --profile "HDR"') 'Launch arguments changed during editing'
        $game.StartDelay.Value=10
        [void]$game.StartDelay.Editor.Focus()
        [InputProbe]::Key($game.StartDelay.Editor.Handle,38)
        Assert ($game.StartDelay.Value -eq 11) 'Up arrow did not increment the game delay'
        $game.StartDelay.Editor.Text='300'
        $game.StartDelay.Step(1)
        Assert ($game.StartDelay.Value -eq 300) 'Game delay exceeded its upper limit'
        $game.ExitDelay.Value=2; $game.ExitDelay.Step(-1)
        Assert ($game.ExitDelay.Value -eq 2) 'Exit delay fell below its safe minimum'
        $game.ExitDelay.Editor.Text='invalid'
        Assert ($game.ExitDelay.Value -eq 2 -and $game.ExitDelay.Editor.Text -eq '2') 'Invalid delay text was not restored'
        $game.StartDelay.Editor.Text='12'; $game.StartDelay.Step(1)
        Assert ($game.StartDelay.Value -eq 13) 'Stepper ignored the typed delay'
        Snapshot $game ('game-controls-'+[int]($scale*100))
        $brightness.RefreshAvailability($true,$false,'Changes save automatically.')
        Show-TestWindow $brightness $scale
        $slider=$brightness.Slider
        [void]$slider.Focus()
        [InputProbe]::Key($slider.Handle,39)
        Assert ($slider.Value -eq 31 -and $brightness.SelectedLevel -eq 2550 -and $brightness.LevelEdited) 'Arrow-key brightness mapping failed'
        [InputProbe]::Key($slider.Handle,35)
        Assert ($slider.Value -eq 100 -and $brightness.SelectedLevel -eq 6000) 'End must reach maximum brightness'
        [InputProbe]::Key($slider.Handle,36)
        Assert ($slider.Value -eq 0 -and $brightness.SelectedLevel -eq 1000) 'Home must reach minimum brightness'
        [InputProbe]::Key($slider.Handle,34)
        Assert ($slider.Value -eq 10) 'Page Down must use the configured large step'
        [InputProbe]::Drag($slider.Handle,0.8)
        Assert ([Math]::Abs($slider.Value-80) -le 1) 'Dragging the visible thumb did not reach the expected value'
        if(-not [Windows.Forms.SystemInformation]::HighContrast) {
            $frame=[Drawing.Bitmap]::new($slider.Width,$slider.Height)
            try {
                foreach($busy in @($false,$true)) {
                    $brightness.RefreshAvailability($true,$busy,'')
                    $slider.DrawToBitmap($frame,$slider.ClientRectangle)
                    $fill=if($busy) { [LocalHdrMenu.DialogTheme]::Muted } else { [LocalHdrMenu.DialogTheme]::Accent }
                    Assert ([InputProbe]::TrackSurvivesErase($slider.Handle,$frame,$fill)) "Slider track disappeared during repaint (busy=$busy, scale=$scale)"
                }
                $brightness.RefreshAvailability($true,$false,'Changes save automatically.')
            } finally { $frame.Dispose() }
        }
        [void]$brightness.Restore.Focus()
        [InputProbe]::Key($brightness.Restore.Handle,32)
        Assert $brightness.Restore.Checked 'Space did not toggle restore checkbox'
        Snapshot $brightness ('brightness-checked-'+[int]($scale*100))
        $brightness.RefreshAvailability($false,$true,'Waiting for the current operation to finish.')
        Assert (-not $slider.Enabled -and -not $brightness.Restore.Enabled) 'Busy controls must be disabled'
        Snapshot $brightness ('brightness-disabled-'+[int]($scale*100))
        $brightness.RefreshAvailability($true,$false,'Changes save automatically.')
        $brightness.LoadSettings(3000,1750,'Schedule',480,1080,$false)
        $time=$brightness.DayStart
        [void]$time.Editor.Focus(); $time.Editor.Select(0,2)
        [InputProbe]::Key($time.Editor.Handle,38)
        Assert ($time.Value.Hour -eq 9 -and $time.Value.Minute -eq 0) 'Up arrow must increment the selected hour'
        $time.Value=[DateTime]'2026-11-01T23:59:00'; $time.Editor.Select(3,2)
        [InputProbe]::Key($time.Editor.Handle,38)
        Assert ($time.Value.Hour -eq 0 -and $time.Value.Minute -eq 0) 'Minute increment must wrap midnight'
        [InputProbe]::Key($time.Editor.Handle,40)
        Assert ($time.Value.Hour -eq 23 -and $time.Value.Minute -eq 59) 'Minute decrement must wrap midnight'
        $time.Value=[DateTime]'2026-11-01T08:00:00'
        Snapshot $brightness ('brightness-schedule-'+[int]($scale*100))

        $shortcut.AddTarget(('A'*64),'Main OLED',$true); $shortcut.AddTarget(('B'*64),'Second display',$false)
        Show-TestWindow $shortcut $scale
        [void]$shortcut.Ctrl.Focus(); [InputProbe]::Key($shortcut.Ctrl.Handle,32)
        Assert ($shortcut.Modifiers -eq 2) 'Modern Ctrl checkbox changed the modifier mapping'
        [void]$shortcut.Targets.Focus(); $shortcut.Targets.SelectedIndex=1
        [InputProbe]::Key($shortcut.Targets.Handle,32)
        Assert (@($shortcut.SelectedTargets()).Count -eq 2) 'Space did not toggle the selected monitor'
        $row=$shortcut.Targets.GetItemRectangle(0)
        [InputProbe]::Mouse($shortcut.Targets.Handle,0x201,15,[int]($row.Top+$row.Height/2),1)
        [InputProbe]::Mouse($shortcut.Targets.Handle,0x202,15,[int]($row.Top+$row.Height/2),0)
        Assert (@($shortcut.SelectedTargets()).Count -eq 1 -and $shortcut.SelectedTargets()[0] -eq ('B'*64)) 'Monitor row click changed the wrong target'
        Snapshot $shortcut ('shortcut-'+[int]($scale*100))

        $preset.AddDisplay(('A'*64),'Main OLED',$true,$true,'35')
        Show-TestWindow $preset $scale
        $grid=$preset.Displays; [void]$grid.Focus(); $grid.CurrentCell=$grid.Rows[0].Cells['Enabled']
        [InputProbe]::Key($grid.Handle,32); [void]$grid.EndEdit()
        Assert (-not [bool]$grid.Rows[0].Cells['Enabled'].Value) 'Space did not toggle the preset HDR checkbox'
        $cell=$grid.GetCellDisplayRectangle(0,0,$false)
        $x=[int]($cell.Left+$cell.Width/2); $y=[int]($cell.Top+$cell.Height/2)
        [InputProbe]::Mouse($grid.Handle,0x201,$x,$y,1); [InputProbe]::Mouse($grid.Handle,0x202,$x,$y,0)
        [void]$grid.EndEdit()
        Assert (-not [bool]$grid.Rows[0].Cells['Include'].Value) 'Click did not toggle the preset include checkbox'
        Snapshot $preset ('preset-'+[int]($scale*100))
    } finally { $brightness.Dispose(); $shortcut.Dispose(); $preset.Dispose(); $game.Dispose() }
}
'PASS: slider dragging and keyboard steps, checkbox toggles, monitor selection, preset grid editing, disabled states, and values at 100-200% scale.'
