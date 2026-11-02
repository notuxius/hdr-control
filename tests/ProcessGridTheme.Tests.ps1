# Run with Windows PowerShell 5.1 -STA; exercises the actual Microsoft grid.
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
Add-Type -Path (Join-Path $repo 'ProcessGridTheme.cs') -ReferencedAssemblies PresentationFramework,PresentationCore,WindowsBase,System.Xaml
$source=@"
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;
using System.Windows.Input;
using System.Windows.Threading;
public static class GridThemeTest {
    public static string Failure;
    public static bool Cancel;
    public static bool DoubleClick;
    public static int Samples;
    public static long MaxGap;
    public static void Install() {EventManager.RegisterClassHandler(typeof(Window),FrameworkElement.LoadedEvent,new RoutedEventHandler(Loaded));}
    static T Find<T>(DependencyObject root,Predicate<T> predicate) where T:DependencyObject {
        var item=root as T;if(item!=null && predicate(item)) return item;
        for(int i=0;i<VisualTreeHelper.GetChildrenCount(root);i++) {var result=Find<T>(VisualTreeHelper.GetChild(root,i),predicate);if(result!=null)return result;}
        return null;
    }
    static void Check(bool value,string message) {if(!value) throw new Exception(message);}
    static void Loaded(object sender,RoutedEventArgs args) {
        var window=sender as Window;if(window==null || window.Title!="Add running game")return;
        int stage=0;var watch=Stopwatch.StartNew();long last=0;
        var heartbeat=new DispatcherTimer {Interval=TimeSpan.FromMilliseconds(50)};
        heartbeat.Tick+=delegate {long now=watch.ElapsedMilliseconds;if(last>0) {MaxGap=Math.Max(MaxGap,now-last);Samples++;}last=now;};
        var timer=new DispatcherTimer {Interval=TimeSpan.FromMilliseconds(800)};
        window.Closed+=delegate {timer.Stop();heartbeat.Stop();};
        timer.Tick+=delegate {
            try {
                var list=Find<ListView>(window,x=>true);
                Check(list!=null,"Microsoft list missing");
                if(stage==0) {
                    Check(window.Resources.Contains("HdrGridTheme"),"Theme not installed");
                    Check(list.Background.ToString()=="#FF222529","List background is not dark");
                    Check(list.ItemContainerStyle!=null,"Row style missing");
                    if(Cancel) {window.Close();return;}
                    Check(list.Items.Count==1000,"Initial rows missing");
                    var header=Find<GridViewColumnHeader>(window,x=>x.Content!=null && x.Content.ToString()=="Executable");
                    Check(header!=null,"Executable header missing");
                    Check(header.Template.FindName("PART_HeaderGripper",header)!=null,"Native resizable column template was replaced");
                    header.RaiseEvent(new RoutedEventArgs(ButtonBase.ClickEvent));
                    list.ScrollIntoView(list.Items[950]);
                } else if(stage==1) {
                    var row=Find<ListViewItem>(list,x=>true);
                    Check(row!=null && row.ActualHeight>=34,"Scrolled rows lost their theme");
                    var filter=Find<TextBox>(window,x=>x.Name=="PART_SearchBox");
                    Check(filter!=null,"Native filter missing");filter.Text="Game0987.exe";
                } else if(stage==2) {
                    Check(list.Items.Count==1,"Native filter failed");
                    list.SelectedIndex=0;list.Focus();
                } else {
                    var ok=Find<Button>(window,x=>x.IsDefault);
                    Check(ok!=null && ok.IsEnabled,"OK button unavailable");
                    if(DoubleClick) {
                        var row=(ListViewItem)list.ItemContainerGenerator.ContainerFromIndex(0);
                        Check(row!=null,"Selected row was not realized");
                        row.RaiseEvent(new MouseButtonEventArgs(Mouse.PrimaryDevice,Environment.TickCount,MouseButton.Right) {RoutedEvent=Control.MouseDoubleClickEvent});
                        Check(window.IsVisible,"Right double-click accepted a game");
                        list.RaiseEvent(new MouseButtonEventArgs(Mouse.PrimaryDevice,Environment.TickCount,MouseButton.Left) {RoutedEvent=Control.MouseDoubleClickEvent});
                        Check(window.IsVisible,"Double-click outside a row accepted a game");
                        row.RaiseEvent(new MouseButtonEventArgs(Mouse.PrimaryDevice,Environment.TickCount,MouseButton.Left) {RoutedEvent=Control.MouseDoubleClickEvent});
                        Check(!window.IsVisible,"Double-click did not accept the selected row");
                    } else ok.RaiseEvent(new RoutedEventArgs(ButtonBase.ClickEvent));
                    timer.Stop();
                }
                stage++;
            } catch(Exception error) {Failure=error.ToString();window.Close();}
        };
        heartbeat.Start();timer.Start();
    }
}
"@
Add-Type -TypeDefinition $source -ReferencedAssemblies PresentationFramework,PresentationCore,WindowsBase,System.Xaml
[LocalHdrMenu.ProcessGridTheme]::Install()
[GridThemeTest]::Install()
$rows=@(1..1000 | ForEach-Object {[pscustomobject]@{Executable=('Game{0:0000}.exe' -f $_);Path=('C:\Games\Game{0:0000}\Game.exe' -f $_)}})
$result=$rows | Out-GridView -Title 'Add running game' -OutputMode Single
if([GridThemeTest]::Failure){throw [GridThemeTest]::Failure}
if($result.Executable -ne 'Game0987.exe' -or $result.Path -ne 'C:\Games\Game0987\Game.exe'){throw 'Selected game did not survive the native grid pipeline'}
[GridThemeTest]::DoubleClick=$true
$result=$rows | Out-GridView -Title 'Add running game' -OutputMode Single
if([GridThemeTest]::Failure){throw [GridThemeTest]::Failure}
if($result.Executable -ne 'Game0987.exe' -or $result.Path -ne 'C:\Games\Game0987\Game.exe'){throw 'Double-click did not return the selected game'}
[GridThemeTest]::Cancel=$true
$result=$rows | Out-GridView -Title 'Add running game' -OutputMode Single
if([GridThemeTest]::Failure){throw [GridThemeTest]::Failure}
if($null -ne $result){throw 'Closing the grid returned a game'}
Write-Host ('PASS: dark built-in grid, 1,000 rows, sort, virtual scrolling, filter, OK, double-click and cancel. Dispatcher samples: {0}; max gap: {1} ms.' -f [GridThemeTest]::Samples,[GridThemeTest]::MaxGap)
