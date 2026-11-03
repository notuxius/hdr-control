# Windows PowerShell 5.1 -STA. Tests the built-in grid boundary without saving rules.
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$probePath=Join-Path $env:TEMP ('hdr-standard-picker-'+[Guid]::NewGuid().ToString('N')+'.cs')
@"
using System;
using System.Runtime.InteropServices;
using LocalHdrMenu;
public static class StandardPickerProbe {
    public static RunningAppsPicker Create(string script) {return new RunningAppsPicker(script);}
    [StructLayout(LayoutKind.Sequential)] struct RawDevice {public ushort Page,Usage;public uint Flags;public IntPtr Target;}
    [DllImport("user32.dll")] static extern uint GetRegisteredRawInputDevices([Out] RawDevice[] devices,ref uint count,uint size);
    public static bool HasMouseRegistration() {
        uint count=0,size=(uint)Marshal.SizeOf(typeof(RawDevice));
        GetRegisteredRawInputDevices(null,ref count,size); if(count==0) return false;
        var devices=new RawDevice[count];
        if(GetRegisteredRawInputDevices(devices,ref count,size)==UInt32.MaxValue) throw new Exception("Cannot inspect raw input registration");
        foreach(var device in devices) if(device.Page==1 && device.Usage==2 && device.Target!=IntPtr.Zero && device.Flags==0x100) return true;
        return false;
    }
}
"@ | Set-Content -LiteralPath $probePath -Encoding UTF8
try {Add-Type -Path @((Join-Path $repo 'TrayTheme.cs'),(Join-Path $repo 'ProfilesUi.cs'),$probePath) -ReferencedAssemblies System.Windows.Forms,System.Drawing,UIAutomationProvider,UIAutomationTypes,WindowsBase}
finally {Remove-Item -LiteralPath $probePath}
function Assert($condition,$message) {if(-not $condition){throw $message}}
function Pump($milliseconds) {$watch=[Diagnostics.Stopwatch]::StartNew();while($watch.ElapsedMilliseconds -lt $milliseconds){[Windows.Forms.Application]::DoEvents();Start-Sleep -Milliseconds 5}}
function Complete($picker) {
    $script:completed=0;$script:callbackThread=0
    $picker.add_Completed({$script:completed++;$script:callbackThread=[Threading.Thread]::CurrentThread.ManagedThreadId})
    $picker.Start();$deadline=[Diagnostics.Stopwatch]::StartNew()
    while($script:completed -eq 0 -and $deadline.ElapsedMilliseconds -lt 15000){Pump 20}
    Assert ($script:completed -eq 1 -and $script:callbackThread -eq [Threading.Thread]::CurrentThread.ManagedThreadId) 'Grid completion must be delivered once on the tray thread'
}
$production=[LocalHdrMenu.RunningAppsPicker]::new()
$code=$production.GetType().GetField('childScript',[Reflection.BindingFlags]'Instance,NonPublic').GetValue($production);$production.Dispose()
Assert ($code -match 'Out-GridView' -and $code -match 'Get-Process' -and $code -notmatch 'RunningAppsForm') 'Production must use the built-in process grid without creating custom UI'
# Replace only the interactive grid; exercise real process enumeration and result serialization.
$gridStub=@"
function Out-GridView {
    [CmdletBinding()] param([Parameter(ValueFromPipeline)]`$InputObject,[string]`$Title,[string]`$OutputMode)
    begin {`$items=[Collections.Generic.List[object]]::new()}
    process {`$items.Add(`$InputObject)}
    end {
        if(`$Title -ne 'Add running game' -or `$OutputMode -ne 'Single'){throw 'Wrong grid contract'}
        if(`$items.Count -eq 0){throw 'No process rows'}
        if(@(`$items | Group-Object Executable,Path | Where-Object Count -gt 1).Count){throw 'Duplicate rows'}
        `$self=@(`$items | Where-Object {`$_.Executable -ieq 'powershell.exe' -and `$_.Path})
        if(!`$self.Count){throw 'Current executable/path missing'}
        `$self[0]
    }
}
"@
foreach($theme in @((Join-Path $repo 'ProcessGridTheme.cs'),(Join-Path $repo 'missing-theme.cs'))) {
    $picker=[StandardPickerProbe]::Create($gridStub+[Environment]::NewLine+$code)
    $picker.ThemePath=$theme
    try {Complete $picker;Assert ($picker.SelectedExecutable -eq 'powershell.exe' -and $picker.SelectedPath -and $null -eq $picker.Error) ('Process grid selection failed: '+$picker.Error)} finally {$picker.Dispose()}
}
foreach($case in @('selection','unreadable','cancel','failure','malformed')) {
    $path=if($case -eq 'unreadable'){''}else{'C:\Games\Grüße\Game.exe'}
    $payload=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("Game.exe$([char]0)$path"))
    $script=switch($case){
        'cancel' {'exit 0'}
        'failure' {"[Console]::Error.WriteLine('Test grid failure'); exit 1"}
        'malformed' {"[Console]::WriteLine('bad payload')"}
        default {"[Console]::WriteLine('$payload')"}
    }
    $picker=[StandardPickerProbe]::Create($script)
    try {
        Complete $picker
        switch($case){
            {$_ -in @('selection','unreadable')} {Assert ($picker.SelectedExecutable -eq 'Game.exe' -and $picker.SelectedPath -eq $path -and $null -eq $picker.Error) 'Executable/path transport failed'}
            'cancel' {Assert (-not $picker.SelectedExecutable -and $null -eq $picker.Error) 'Cancel must not create a selection'}
            'failure' {Assert ($picker.Error.Message -eq 'Test grid failure') 'Grid failure was lost'}
            'malformed' {Assert ($null -ne $picker.Error -and -not $picker.SelectedExecutable) 'Malformed selection was accepted'}
        }
    } finally {$picker.Dispose()}
}
$picker=[StandardPickerProbe]::Create('Start-Sleep -Seconds 60')
try {
    $picker.Start();$child=$picker.GetType().GetField('child',[Reflection.BindingFlags]'Instance,NonPublic').GetValue($picker)
    $childId=$child.Id;$picker.Dispose();$deadline=[Diagnostics.Stopwatch]::StartNew()
    while((Get-Process -Id $childId -ErrorAction SilentlyContinue) -and $deadline.ElapsedMilliseconds -lt 3000){Start-Sleep -Milliseconds 10}
    Assert (-not (Get-Process -Id $childId -ErrorAction SilentlyContinue)) 'Tray shutdown left its grid process running'
} finally {$picker.Dispose()}
$icon=[Windows.Forms.NotifyIcon]::new();$left=[Windows.Forms.ContextMenuStrip]::new();$right=[Windows.Forms.ContextMenuStrip]::new()
try {
    $tracker=[LocalHdrMenu.TrayPressTracker]::new($icon,$left,$right)
    $thread=$tracker.GetType().GetField('inputThread',[Reflection.BindingFlags]'Instance,NonPublic').GetValue($tracker)
    Assert ($tracker.IsListening -and [StandardPickerProbe]::HasMouseRegistration()) 'Asynchronous mouse registration missing'
    $tracker.Dispose();$tracker.Dispose()
    Assert (-not $thread.IsAlive -and -not [StandardPickerProbe]::HasMouseRegistration()) 'Mouse observer shutdown failed'
} finally {if($tracker){$tracker.Dispose()};$icon.Dispose();$left.Dispose();$right.Dispose()}
'PASS: built-in grid contract, real process snapshot, selection/path transport, cancel, errors, child cleanup, and asynchronous mouse observer.'
