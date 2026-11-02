# Window interaction stays on its own STA; actions return to the tray thread.
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$probePath=Join-Path $env:TEMP ('hdr-game-window-probe-'+[Guid]::NewGuid().ToString('N')+'.cs')
@'
using System;
using System.Threading;
using System.Windows.Forms;
using LocalHdrMenu;
public static class GameWindowProbe {
    [System.Runtime.InteropServices.DllImport("user32.dll")]
    static extern bool PostMessage(IntPtr handle,int message,IntPtr wParam,IntPtr lParam);
    public static readonly ManualResetEvent Ready=new ManualResetEvent(false),Closed=new ManualResetEvent(false),Clicked=new ManualResetEvent(false);
    public static int Pulses,Command,DefaultsCount;
    public static string UiError="";
    public static SettingsWindow Create() {
        Ready.Reset(); Closed.Reset(); Clicked.Reset(); Pulses=0; Command=0;
        return new SettingsWindow(delegate {
            var window=new SettingsForm(); var form=window.Games; window.Sections.SelectedIndex=1; window.ShowInTaskbar=false; window.StartPosition=FormStartPosition.Manual; window.Location=new System.Drawing.Point(-30000,-30000);
            DialogTabs tabs=null; foreach(Control c in form.Controls) if(c is DialogTabs) tabs=(DialogTabs)c;
            ListView defaults=null,custom=null;
            foreach(Control c in tabs.TabPages[1].Controls) if(c is ListView) defaults=(ListView)c;
            foreach(Control c in tabs.TabPages[2].Controls) if(c is ListView) custom=(ListView)c;
            var timer=new System.Windows.Forms.Timer {Interval=15};
            timer.Tick+=delegate {
                try {
                Interlocked.Increment(ref Pulses); DefaultsCount=defaults.Items.Count;
                int command=Interlocked.Exchange(ref Command,0);
                if(command==1) tabs.SelectedIndex=(tabs.SelectedIndex+1)%3;
                if(command==2) {
                    tabs.SelectedIndex=1; defaults.SelectedIndices.Add(799); defaults.EnsureVisible(799);
                    form.LaunchButton.PerformClick(); Clicked.Set();
                    // Change selection before the tray gets around to dispatching.
                    tabs.SelectedIndex=2; custom.SelectedIndices.Add(0);
                }
                if(command==3) window.Close();
                if(command==4) {
                    tabs.SelectedIndex=2;
                    var list=(GameListsForm.GameListView)custom;
                    list.Toggle(list.Items[0]); list.Toggle(list.Items[0]);
                    tabs.SelectedIndex=1; Clicked.Set();
                }
                } catch(Exception error) {UiError=error.ToString();Clicked.Set();}
            };
            window.Shown+=delegate {timer.Start(); Ready.Set();};
            window.Disposed+=delegate {timer.Dispose(); Closed.Set();};
            return window;
        });
    }
    public static string Inspect(IntPtr handle,string action) {
        var window=(SettingsForm)Control.FromHandle(handle);
        return (string)window.Invoke(new Func<string>(delegate {
            if(action=="edit brightness") {
                window.Location=new System.Drawing.Point(-30000,-30000);
                window.Brightness.Slider.Value=67;
                window.Brightness.Slider.Value=68;
            }
            if(action=="open HDR settings") window.Brightness.HdrSettings.PerformClick();
            if(action=="toggle restore") window.Brightness.Restore.Checked=!window.Brightness.Restore.Checked;
            if(action=="invalid schedule") {
                window.Brightness.Switching.SelectedIndex=1;
                window.Brightness.DayStart.Text="25:00";
            }
            if(action=="change schedule") {
                window.Brightness.DayStart.Text="07:30";
                window.Brightness.DaySlider.Value=73;
                window.Brightness.NightSlider.Value=27;
                window.Brightness.Restore.Checked=true;
                window.Brightness.Enforce.Checked=true;
            }
            if(action=="edit before close") window.Brightness.DayStart.Step(1);
            if(action=="open profiles") window.Sections.SelectedIndex=2;
            if(action=="game save status") return window.GameSaveStatus.Text;
            if(action=="profile save status") return window.ProfileSaveStatus.Text;
            if(action=="brightness save status") return window.Brightness.Status.Text;
            if(action.EndsWith(" saving image")) {
                Label label=action=="game saving image" ? window.GameSaveStatus :
                    action=="profile saving image" ? window.ProfileSaveStatus : window.Brightness.Status;
                if(!label.Visible || label.Text!="\u2193 Saving\u2026") return "";
                using(var bitmap=new System.Drawing.Bitmap(label.Width,label.Height)) {
                    label.DrawToBitmap(bitmap,label.ClientRectangle);
                    int hash=0;
                    for(int y=0;y<label.Height;y++)
                        for(int x=0;x<label.Width;x++) hash=unchecked(hash*31+bitmap.GetPixel(x,y).ToArgb());
                    return hash.ToString();
                }
            }
            if(action=="read monitor") {
                var cells=window.Profiles.Monitors.Rows[0].Cells;
                return cells["Monitor"].Value+"|"+cells["Alias"].Value;
            }
            if(action=="click grid background" || action=="click profile heading") {
                Control target=window.Profiles.Monitors;
                if(action=="click profile heading") {
                    foreach(Control c in window.Profiles.Controls) if(c is Label && c.Text=="Profiles and shortcuts") target=c;
                    if(!(target is Label)) throw new Exception("Profile heading not found");
                }
                var point=new IntPtr(((target.ClientSize.Height-4)<<16)|4);
                PostMessage(target.Handle,0x201,new IntPtr(1),point);
                PostMessage(target.Handle,0x202,IntPtr.Zero,point);
            }
            if(action=="change exit policy") window.Profiles.ExitPolicy.SelectedIndex=1;
            if(action=="edit alias" || action=="clear alias" || action=="cancel alias") {
                var grid=window.Profiles.Monitors;
                grid.CurrentCell=grid.Rows[0].Cells["Alias"];
                grid.Focus();
                if(!grid.BeginEdit(true)) throw new Exception("Alias editor did not open");
                grid.EditingControl.Text=action=="clear alias" ? "" : "Gaming";
                if(action=="cancel alias") grid.CancelEdit();
            }
            if(action=="close profiles") { ((Button)window.CancelButton).PerformClick(); return ""; }
            if(action=="open games") window.Sections.SelectedIndex=1;
            if(action=="toggle community" || action=="read community") {
                var check=window.Games.UseCommunityApps;
                if(!check.Visible || !check.Enabled) throw new Exception("Community checkbox unavailable");
                if(action=="toggle community") typeof(CheckBox).GetMethod("OnClick",
                    System.Reflection.BindingFlags.Instance|System.Reflection.BindingFlags.NonPublic).Invoke(check,new object[]{EventArgs.Empty});
                return check.Checked.ToString();
            }
            if(action=="close") { ((Button)window.CancelButton).PerformClick(); return ""; }
            int visible=0; foreach(Panel page in window.Sections.TabPages) if(page.Visible) visible++;
            if(visible!=1 || window.Games.TopLevel || window.Profiles.TopLevel || window.Brightness.TopLevel)
                throw new Exception("Settings pages must share one top-level window");
            return window.Sections.SelectedIndex+"|"+window.Profiles.Enabled+"|"+window.Brightness.DisplayId+"|"+window.Brightness.SelectedLevel;
        }));
    }
    public static SettingsWindow Broken() {return new SettingsWindow(delegate {throw new Exception("Test window failure");});}
}
'@ | Set-Content -LiteralPath $probePath -Encoding UTF8
try {Add-Type -Path @((Join-Path $repo 'TrayTheme.cs'),(Join-Path $repo 'ProfilesUi.cs'),$probePath) -ReferencedAssemblies System.Windows.Forms,System.Drawing}
finally {Remove-Item -LiteralPath $probePath}
[Windows.Forms.Application]::EnableVisualStyles()
[Windows.Forms.Control]::CheckForIllegalCrossThreadCalls=$true
function Assert($Condition,$Message){if(-not $Condition){throw $Message}}
function Pump($Milliseconds){$watch=[Diagnostics.Stopwatch]::StartNew();while($watch.ElapsedMilliseconds -lt $Milliseconds){[Windows.Forms.Application]::DoEvents();Start-Sleep -Milliseconds 5}}
function Wait-Checkmark($Handle,$Tab) {
    $watch=[Diagnostics.Stopwatch]::StartNew()
    $saved=([string][char]0x2713)+' Saved'
    while ([GameWindowProbe]::Inspect($Handle,"$Tab save status") -cne $saved -and $watch.ElapsedMilliseconds -lt 3000) { Pump 25 }
    Assert ([GameWindowProbe]::Inspect($Handle,"$Tab save status") -ceq $saved) "Missing $Tab save confirmation"
}
function Check-StaticSavingIcon($Handle,$Tab) {
    $watch=[Diagnostics.Stopwatch]::StartNew()
    do {
        $first=[GameWindowProbe]::Inspect($Handle,"$Tab saving image")
        if ($first) { break }
        Pump 25
    } while ($watch.ElapsedMilliseconds -lt 2000)
    Assert $first "Missing saving arrow on $Tab"
    Pump 150
    Assert ([GameWindowProbe]::Inspect($Handle,"$Tab saving image") -ceq $first) "Saving icon changed during the $Tab save"
}
$window=[GameWindowProbe]::Create()
$script:launches=0;$script:selected='';$script:actionThread=0
$window.LaunchButton.add_Click({$script:launches++;$script:selected=$window.SelectedExecutable;$script:actionThread=[Threading.Thread]::CurrentThread.ManagedThreadId})
$changes=New-Object 'Collections.Generic.List[string]'
$toggleConfirmations=New-Object 'Collections.Generic.List[Action]'
$window.add_EnableRequested({param($exe,$enabled) $changes.Add("${exe}=$enabled"); $toggleConfirmations.Add($window.SaveConfirmation)})
try {
    $window.ClearRows()
    for($i=0;$i -lt 800;$i++){$window.AddRow('Defaults',('Game{0:D4}.exe' -f $i),'Watching','')}
    $window.AddRow('Custom','Custom.exe','Watching',''); $window.FinishRows()
    $window.Show()
    Assert ([GameWindowProbe]::Ready.WaitOne(3000)) 'Game lists did not open'
    for($i=0;$i -lt 6;$i++){[GameWindowProbe]::Command=1;[Threading.Thread]::Sleep(100)}
    Assert ([GameWindowProbe]::Pulses -ge 10 -and [GameWindowProbe]::DefaultsCount -eq 800) 'Tabs stalled while the tray thread was blocked'
    [GameWindowProbe]::Command=2
    Assert ([GameWindowProbe]::Clicked.WaitOne(2000)) 'Launch click did not reach the window'
    Assert ([GameWindowProbe]::UiError -eq '') ('Window test failed: '+[GameWindowProbe]::UiError)
    [Threading.Thread]::Sleep(100)
    Assert ($script:launches -eq 0) 'Action ran on the window thread'
    Pump 200
    Assert ($script:launches -eq 1 -and $script:selected -eq 'Game0799.exe' -and $script:actionThread -eq [Threading.Thread]::CurrentThread.ManagedThreadId) 'Action lost its captured selection or was dispatched on the wrong thread'
    [GameWindowProbe]::Clicked.Reset(); [GameWindowProbe]::Command=4
    Assert ([GameWindowProbe]::Clicked.WaitOne(2000)) 'Toggle clicks did not reach the window'
    Assert ([GameWindowProbe]::UiError -eq '') ([GameWindowProbe]::UiError)
    Pump 250
    Assert (($changes -join ',') -eq 'Custom.exe=False,Custom.exe=True') 'Rapid toggles lost their click-time game or desired state'
    $toggleConfirmations[0].Invoke(); Pump 90
    Assert ([GameWindowProbe]::Inspect($window.Handle,'game save status') -eq '') 'An older toggle confirmed a newer edit'
    $toggleConfirmations[1].Invoke(); Pump 90
    Wait-Checkmark $window.Handle 'game'
    Assert ([GameWindowProbe]::Inspect($window.Handle,'game save status') -ceq (([string][char]0x2713)+' Saved')) 'Latest game toggle did not show Saved'
    $window.ClearRows();$window.AddRow('Defaults','Replacement.exe','Watching','');$window.FinishRows()
    $deadline=[Diagnostics.Stopwatch]::StartNew()
    while([GameWindowProbe]::DefaultsCount -ne 1 -and $deadline.ElapsedMilliseconds -lt 2000) { [Threading.Thread]::Sleep(10) }
    Assert ([GameWindowProbe]::DefaultsCount -eq 1) 'Updated snapshot did not reach the window'
    $window.Activate(); $window.Show()
    $window.Dispose();$window.Dispose()
    Assert ([GameWindowProbe]::Closed.WaitOne(2000)) 'Tray shutdown failed to close the window independently'
    Assert ($window.IsDisposed) 'Disposed window still appears open'
} finally {$window.Dispose()}
$window=[GameWindowProbe]::Create()
try {
    $window.Show();Assert ([GameWindowProbe]::Ready.WaitOne(2000)) 'Empty window did not open'
    [GameWindowProbe]::Command=3;Assert ([GameWindowProbe]::Closed.WaitOne(2000)) 'Close button failed'
    Pump 150;Assert ($window.IsDisposed) 'User-closed window cannot be reopened'
} finally {$window.Dispose()}
$window=[GameWindowProbe]::Broken();$script:failures=0;$window.add_Failed({$script:failures++})
try {$window.Show();Pump 300;Assert ($window.IsDisposed -and $script:failures -eq 1 -and $window.Error.Message -eq 'Test window failure') 'Window error was not returned to the tray'}
finally {$window.Dispose()}
'PASS: independent tab responsiveness, immutable row updates, click-time selection, tray-thread action dispatch, closing, and error delivery.'

# Use the actual tray handlers and UI dispatcher, with simulated displays and storage.
. (Join-Path $repo 'HdrTray.ps1')
Add-Type 'namespace LocalHdrMenu { public static class DisplayApi { public static object[] Displays; public static object[] Read() { return Displays; } } }'
function Get-HdrGameListRows { $script:listReads++ }
function Open-HdrSettings([string]$Uri) { $script:requestedUri=$Uri }
function Get-HdrStartupEnabled { return $false }
function Get-HdrBrightnessPreference($Key) { return $null }
function Save-HdrBrightnessPreference { $script:preferenceWrites++ }
$script:communityEnabled=$true
function Get-HdrAutomationPreference($Name) { return $Name -eq 'UseCommunityApps' -and $script:communityEnabled }
function Set-HdrAutomationPreference($Name,[bool]$Enabled) {
    if ($Name -ne 'UseCommunityApps' -or $script:rejectSave) { throw 'Preference save failed' }
    $script:communityEnabled=$Enabled
}
function Read-HdrProfiles { return $script:config }
function Save-HdrProfiles($Profiles) { Test-HdrProfiles $Profiles; $script:config=$Profiles; $script:profileWrites++ }
function Update-HdrTray { }
function Write-HdrDiagnostic { }
function Show-HdrMessage($Text) { $script:failure=$Text }
function Get-HdrBrightnessTime { return [DateTime]'2026-11-01T12:00:00' }
function Start-HdrBrightnessChange($Display,$Level,$Restore,$Settings,$PreferenceKey) {
    $script:brightnessWrites++; $script:target=$Display.DisplayId; $script:level=$Level; $script:savedBrightness=$Settings
}
$script:config=New-HdrProfiles
[LocalHdrMenu.DisplayApi]::Displays=@(foreach ($id in @('QQ==','Qg==')) {
    [pscustomobject]@{Name='Same model';DisplayId=$id;DevicePath=$id;HdrEnabled=$true;HdrSupported=$true;HdrActive=$true;SdrWhiteLevel=2500}
})
$script:config.Monitors=@([pscustomobject]@{Key=(Get-HdrBrightnessKey ([LocalHdrMenu.DisplayApi]::Displays[0]));Alias='Old alias'})
Initialize-HdrTray
try {
    $script:hdrTray.LastDisplays=[LocalHdrMenu.DisplayApi]::Displays
    $script:hdrTray.AppSettings.PerformClick()
    $window=$script:hdrTray.SettingsWindow
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while (($window.Handle -eq [IntPtr]::Zero -or -not $window.ActiveBrightnessId) -and $watch.ElapsedMilliseconds -lt 5000) { Pump 30 }
    $handle=$window.Handle
    Assert ($handle -ne [IntPtr]::Zero) 'Settings command failed to open its window'
    [void][GameWindowProbe]::Inspect($handle,'toggle restore')
    Check-StaticSavingIcon $handle 'brightness'
    Wait-Checkmark $handle 'brightness'
    Assert ($script:preferenceWrites -eq 1 -and -not $script:brightnessWrites) 'Preference-only save unexpectedly wrote the display'
    [void][GameWindowProbe]::Inspect($handle,'open HDR settings'); Pump 160
    Assert ($script:requestedUri -eq 'ms-settings:display-hdr') 'Windows HDR settings button must open the HDR page'
    Assert ([GameWindowProbe]::Inspect($handle,'edit brightness') -eq '0|False|QQ==|4400') 'Wrong initial brightness monitor'
    [void][GameWindowProbe]::Inspect($handle,'open profiles')
    Pump 220
    $savedText=([string][char]0x2713)+' Saved'
    Assert ([GameWindowProbe]::Inspect($handle,'profile save status') -eq '') 'Loading settings showed a save confirmation'
    Assert ($script:target -eq 'QQ==' -and $script:level -eq 4400) 'Leaving the tab must flush the pending brightness edit'
    Assert ([GameWindowProbe]::Inspect($handle,'read') -eq '2|True|QQ==|4400' -and !$script:profileWrites) ('Loading Profiles must not write settings: '+$script:failure)
    Assert ([GameWindowProbe]::Inspect($handle,'read monitor') -eq 'Same model|Old alias') 'A saved alias must not replace the monitor model'
    [void][GameWindowProbe]::Inspect($handle,'change exit policy')
    Check-StaticSavingIcon $handle 'profile'
    Wait-Checkmark $handle 'profile'
    Assert ($script:profileWrites -eq 1 -and $script:config.ExitPolicy -eq 'Restore') ('Exit policy did not autosave: '+$script:failure)
    Assert ([GameWindowProbe]::Inspect($handle,'profile save status') -ceq $savedText) 'Saving an exit policy did not confirm on Profiles'
    [void][GameWindowProbe]::Inspect($handle,'cancel alias'); Pump 160
    Assert ($script:profileWrites -eq 1) 'Canceling an alias edit must not autosave'
    [void][GameWindowProbe]::Inspect($handle,'edit alias')
    [void][GameWindowProbe]::Inspect($handle,'click grid background'); Pump 160
    Assert ($script:profileWrites -eq 2 -and $script:config.Monitors[0].Alias -eq 'Gaming') ('Clicking empty grid space did not save the alias: '+$script:failure)
    [void][GameWindowProbe]::Inspect($handle,'clear alias')
    [void][GameWindowProbe]::Inspect($handle,'click profile heading'); Pump 160
    Assert ($script:profileWrites -eq 3 -and [GameWindowProbe]::Inspect($handle,'read monitor') -eq 'Same model|') 'Clicking a label must commit an edit and preserve the monitor model'
    [void][GameWindowProbe]::Inspect($handle,'edit alias')
    [void][GameWindowProbe]::Inspect($handle,'open games')
    Pump 160
    Assert ($script:profileWrites -eq 4 -and $script:config.Monitors[0].Alias -eq 'Gaming') ('Leaving Profiles did not save the alias: '+$script:failure)
    Wait-Checkmark $handle 'profile'
    Assert ([GameWindowProbe]::Inspect($handle,'game save status') -eq '' -and [GameWindowProbe]::Inspect($handle,'profile save status') -ceq $savedText) 'An alias acknowledgement appeared on the wrong tab'
    Assert ([GameWindowProbe]::Inspect($handle,'read community') -eq 'True') 'Game lists did not load the enabled preference'
    $reads=$script:listReads
    [void][GameWindowProbe]::Inspect($handle,'toggle community')
    Check-StaticSavingIcon $handle 'game'
    Wait-Checkmark $handle 'game'
    Assert (-not $script:communityEnabled -and $script:listReads -gt $reads) 'Changing the checkbox must save and refresh game statuses'
    Assert ([GameWindowProbe]::Inspect($handle,'game save status') -ceq $savedText) 'Successful community preference save did not show the checkmark'
    $script:rejectSave=$true
    [void][GameWindowProbe]::Inspect($handle,'toggle community'); Pump 180
    Assert ($script:failure -eq 'Preference save failed' -and [GameWindowProbe]::Inspect($handle,'read community') -eq 'False') 'A failed save must restore the checkbox and report the error'
    Assert ([GameWindowProbe]::Inspect($handle,'game save status') -eq '') 'A rejected save left a checkmark'
    $script:failure=$null; $script:rejectSave=$false
    $script:hdrTray.AppSettings.PerformClick()
    Assert ($script:hdrTray.SettingsWindow.Handle -eq $handle -and [GameWindowProbe]::Inspect($handle,'read').StartsWith('1|')) 'Reopening settings lost its active tab or opened a second window'
    Set-HdrTrayState (Get-HdrTrayState $script:hdrTray.LastDisplays)
    $shortcuts=@($script:hdrTray.Displays.DropDownItems | Where-Object Name -eq SdrBrightness)
    $shortcuts[0].PerformClick(); Pump 110
    Assert ([GameWindowProbe]::Inspect($handle,'read') -eq '0|True|QQ==|4400') 'Switching tabs lost the selected brightness'
    $shortcuts[1].PerformClick(); Pump 110
    Assert ([GameWindowProbe]::Inspect($handle,'read') -eq '0|True|Qg==|2500') 'Monitor shortcut did not select its own monitor in the existing window'
    [void][GameWindowProbe]::Inspect($handle,'edit brightness')
    Pump 550
    Assert ($script:brightnessWrites -eq 2 -and $script:target -eq 'Qg==' -and $script:level -eq 4400) ('Brightness autosave used the wrong target, level or write count: '+$script:failure)
    [void][GameWindowProbe]::Inspect($handle,'invalid schedule'); Pump 550
    $watch.Restart()
    while ([GameWindowProbe]::Inspect($handle,'profile save status') -and $watch.ElapsedMilliseconds -lt 2500) { Pump 40 }
    Assert ([GameWindowProbe]::Inspect($handle,'profile save status') -eq '') 'Profile confirmation did not expire'
    Assert ($script:brightnessWrites -eq 2) 'Invalid times must not autosave'
    [void][GameWindowProbe]::Inspect($handle,'change schedule'); Pump 550
    Assert ($script:brightnessWrites -eq 3 -and $script:level -eq 4650 -and $script:savedBrightness.NightLevel -eq 2350 -and $script:savedBrightness.DayStart -eq 450 -and $script:savedBrightness.Restore -and $script:savedBrightness.Enforce) 'Schedule or restoration options did not autosave'
    [void][GameWindowProbe]::Inspect($handle,'edit before close')
    [void][GameWindowProbe]::Inspect($handle,'close'); Pump 120
    Assert ($script:brightnessWrites -eq 4 -and $script:savedBrightness.DayStart -ne 450) 'Closing dropped the last time edit'
    Assert $window.IsDisposed 'Page Close must close the entire settings window'
    Show-HdrAppSettings
    Assert ($script:hdrTray.SettingsWindow -ne $window) 'Closed settings did not reopen'
    $reopened=$script:hdrTray.SettingsWindow
    $watch.Restart()
    while ($reopened.Handle -eq [IntPtr]::Zero -and $watch.ElapsedMilliseconds -lt 5000) { Pump 30 }
    [void][GameWindowProbe]::Inspect($reopened.Handle,'open games')
    Assert ([GameWindowProbe]::Inspect($reopened.Handle,'read community') -eq 'False') 'Reopening settings lost the saved community preference'
    [LocalHdrMenu.DisplayApi]::Displays=@()
    [void][GameWindowProbe]::Inspect($reopened.Handle,'open profiles'); Pump 200
    Assert ([GameWindowProbe]::Inspect($reopened.Handle,'read monitor') -eq 'Same model (disconnected)|Gaming') 'A disconnected monitor must retain its saved model and alias separately'
    [void][GameWindowProbe]::Inspect($reopened.Handle,'clear alias')
    [void][GameWindowProbe]::Inspect($reopened.Handle,'close profiles'); Pump 200
    Assert ($script:profileWrites -eq 5 -and $script:config.Monitors[0].Alias -ceq '' -and $script:config.Monitors[0].ModelName -eq 'Same model') ('Closing Profiles did not save the cleared alias and original model: '+$script:failure)
    Assert (-not $script:failure) $script:failure
} finally { Close-HdrTray }
'PASS: one settings window, profile saves, per-display tray shortcuts, brightness autosave, close and reopen.'
