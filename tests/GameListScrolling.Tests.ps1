# Exercise the embedded settings lists with separate data for each tab.
param([switch]$OnScreen)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
Add-Type -Path @((Join-Path $repo 'TrayTheme.cs'),(Join-Path $repo 'ProfilesUi.cs')) -ReferencedAssemblies System.Windows.Forms,System.Drawing,UIAutomationProvider,UIAutomationTypes,WindowsBase
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class GameScrollInput {
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hwnd,int message,IntPtr wParam,IntPtr lParam);
}
"@
[Windows.Forms.Application]::EnableVisualStyles()
function Assert($condition,$message) { if(-not $condition) { throw $message } }
$window=[Activator]::CreateInstance([LocalHdrMenu.SettingsForm],[Reflection.BindingFlags]'Instance,NonPublic',$null,@($null),$null)
try {
    $window.Sections.SelectedIndex=1
    $window.StartPosition='Manual'; $window.ShowInTaskbar=$false
    $window.Location=if($OnScreen){[Drawing.Point]::new(80,80)}else{[Drawing.Point]::new(-30000,-30000)}
    $form=$window.Games
    $tabs=@($form.Controls | Where-Object { $_ -is [LocalHdrMenu.DialogTabs] })[0]
    $sections=@('Auto-detected','Installed','Custom')
    $form.ClearRows()
    foreach($section in $sections) {
        for($i=1599;$i -ge 0;$i--) {
            $form.AddRow($section,('{0}-{1:D4}.exe' -f $section,$i),'Watching','11/03/2026')
        }
    }
    $lists=@($tabs.TabPages | ForEach-Object { $_.Controls | Where-Object { $_ -is [Windows.Forms.ListView] } })
    $initial=@{}
    $counter=[Windows.Forms.RetrieveVirtualItemEventHandler]{
        param($sender,$eventArgs)
        [void]$initial[$sender].Add($eventArgs.ItemIndex)
    }
    foreach($list in $lists) {
        $initial[$list]=[Collections.Generic.HashSet[int]]::new()
        $list.add_RetrieveVirtualItem($counter)
    }
    $form.FinishRows(); $window.Show(); [Windows.Forms.Application]::DoEvents()
    foreach($index in 0..2) {
        $section=$sections[$index]; $tabs.SelectedIndex=$index
        $list=$lists[$index]
        [Windows.Forms.Application]::DoEvents()
        $list.remove_RetrieveVirtualItem($counter)
        Assert (-not $initial[$list].Contains(800)) "$section fetched a distant game before scrolling"
        Assert ($list.Items.Count -eq 1600) "$section lost games"
        $list.EnsureVisible(800)
        $top=$list.TopItem.Index
        # Count distinct rows in one forced paint, even when the test window is offscreen.
        $requested=[Collections.Generic.HashSet[int]]::new()
        $paintCounter=[Windows.Forms.RetrieveVirtualItemEventHandler]{param($sender,$eventArgs) [void]$requested.Add($eventArgs.ItemIndex)}
        $bitmap=[Drawing.Bitmap]::new($list.Width,$list.Height)
        $list.add_RetrieveVirtualItem($paintCounter)
        try { $list.DrawToBitmap($bitmap,$list.ClientRectangle) }
        finally { $list.remove_RetrieveVirtualItem($paintCounter); $bitmap.Dispose() }
        $visible=[Math]::Ceiling($list.ClientSize.Height/$list.GetItemRect($top).Height)
        Assert ($requested.Contains($top) -and $requested.Contains(800) -and $requested.Count -le $visible+2) "$section painted $($requested.Count) distinct rows for a $visible-row viewport"
        $samples=@()
        if ([Windows.Forms.SystemInformation]::MouseWheelScrollLines -ne 0) {
            foreach($direction in @(-120,120)) {
                $before=$list.TopItem.Index
                foreach($tick in 1..32) {
                    $watch=[Diagnostics.Stopwatch]::StartNew()
                    [void][GameScrollInput]::SendMessage($list.Handle,0x020a,[IntPtr]($direction -shl 16),[IntPtr]0)
                    $list.Update()
                    $samples+=$watch.Elapsed.TotalMilliseconds
                }
                Assert ((($before-$list.TopItem.Index)*$direction) -gt 0) "$section wheel did not move in the requested direction"
            }
            $sorted=@($samples | Sort-Object)
            "$section wheel + Update (64 samples): median {0:N1} ms, p95 {1:N1} ms" -f $sorted[31],$sorted[60]
        }
        $last=$list.FindItemWithText("$section-1599.exe",$false,0,$true)
        Assert ($null -ne $last -and $last.Index -eq 1599) "$section search missed the final game"
        [void]$list.SelectedIndices.Add($last.Index); $list.EnsureVisible($last.Index)
        $savedTop=$list.TopItem.Index
        $tabs.SelectedIndex=($index+1)%3; $tabs.SelectedIndex=$index
        Assert ($list.TopItem.Index -eq $savedTop -and $savedTop -gt 1500 -and $form.SelectedExecutable -eq "$section-1599.exe") "$section lost scroll position or selection"
    }
    'PASS: virtual painting, scrolling, tail search and tab restoration with 1,600 games per list.'
} finally { $window.Dispose() }
