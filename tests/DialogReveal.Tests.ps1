param([string]$SourceDirectory=(Split-Path $PSScriptRoot))
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
Add-Type -Path @((Join-Path $SourceDirectory 'TrayTheme.cs'),(Join-Path $SourceDirectory 'ProfilesUi.cs')) -ReferencedAssemblies System.Windows.Forms,System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;
public sealed class RevealPaintProbe : Panel {
    [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr window,int attribute,out int value,int size);
    public bool Painted, FirstPaintHidden;
    public static bool Hidden(Form form) {
        int value;
        if(DwmGetWindowAttribute(form.Handle,14,out value,4)<0) throw new Exception("Cannot query window cloak");
        return (value&1)!=0;
    }
    protected override void OnPaint(PaintEventArgs e) {
        if(!Painted) {
            FirstPaintHidden=Hidden((Form)TopLevelControl);
            // Reproduce a slow child without changing a display or saved settings.
            System.Threading.Thread.Sleep(100);
            Painted=true;
        }
        base.OnPaint(e);
    }
}
'@ -ReferencedAssemblies System.Windows.Forms,System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
function Assert($Condition,$Message) { if(-not $Condition) { throw $Message } }
function Prepare($Form) {
    $Form.ShowInTaskbar=$false; $Form.StartPosition='Manual'; $Form.Location=[Drawing.Point]::new(-30000,-30000)
    $probe=[RevealPaintProbe]::new(); $probe.SetBounds(0,0,20,20)
    $Form.Controls.Add($probe); $probe.BringToFront()
    return $probe
}
foreach($name in @('GameRuleForm','PresetForm','ShortcutForm','ProfileSettingsForm','GameListsForm','SdrBrightnessForm')) {
    $form=if($name -eq 'SdrBrightnessForm') { [LocalHdrMenu.SdrBrightnessForm]::new('Test display','QQ==',('A'*64),2500,$false) }
        else { New-Object ('LocalHdrMenu.'+$name) }
    try {
        $probe=Prepare $form
        $parameters=$form.GetType().GetProperty('CreateParams',[Reflection.BindingFlags]'Instance,NonPublic').GetValue($form)
        Assert (($parameters.ExStyle -band 0x02000000) -eq 0) "$name must not composite native child controls"
        foreach($attempt in 1..2) {
            $probe.Painted=$false
            $form.Show()
            Assert ([RevealPaintProbe]::Hidden($form)) "$name appeared before first paint on opening $attempt"
            [Windows.Forms.Application]::DoEvents()
            Assert ($probe.Painted -and $probe.FirstPaintHidden) "$name revealed before its slow child painted"
            Assert ($form.Visible -and -not [RevealPaintProbe]::Hidden($form)) "$name remained hidden"
            $form.Hide()
        }
    } finally { $form.Dispose() }
}
$form=[LocalHdrMenu.ShortcutForm]::new()
$timer=[Windows.Forms.Timer]::new(); $timer.Interval=250
try {
    $probe=Prepare $form
    $timer.add_Tick({ $timer.Stop(); $form.DialogResult=[Windows.Forms.DialogResult]::Cancel })
    foreach($attempt in 1..2) {
        $probe.Painted=$false; $timer.Start()
        Assert ($form.ShowDialog() -eq [Windows.Forms.DialogResult]::Cancel) 'Modal dialog did not close'
        Assert ($probe.Painted -and $probe.FirstPaintHidden) 'Modal child painted after reveal'
    }
} finally { $timer.Dispose(); $form.Dispose() }
$form=[LocalHdrMenu.ShortcutForm]::new()
try {
    $null=Prepare $form
    $form.add_Shown({ $form.Close() })
    $form.Show(); [Windows.Forms.Application]::DoEvents()
    Assert $form.IsDisposed 'Closing during Shown left an invisible window'
} finally { $form.Dispose() }
'PASS: all six dialogs stay cloaked through slow child painting, reveal, and reopen; modal reuse and early close work.'
