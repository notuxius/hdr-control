# Large hidden lists must switch quickly without changing selection or actions.
param([string]$OutputDirectory)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
Add-Type -Path @((Join-Path $repo 'TrayTheme.cs'),(Join-Path $repo 'ProfilesUi.cs')) -ReferencedAssemblies System.Windows.Forms,System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class GameListInput { [DllImport("user32")] public static extern IntPtr SendMessage(IntPtr h,int m,IntPtr w,IntPtr l); [DllImport("user32")] public static extern bool PostMessage(IntPtr h,int m,IntPtr w,IntPtr l); }'
function Send-ListMouse($List,$Point,$Down,$Up,$Button) {
    $pos=[IntPtr]($Point.X -bor ($Point.Y -shl 16))
    [void][GameListInput]::PostMessage($List.Handle,$Down,[IntPtr]$Button,$pos)
    [void][GameListInput]::PostMessage($List.Handle,$Up,[IntPtr]0,$pos)
    [Windows.Forms.Application]::DoEvents()
}
function Assert($Condition,$Message) { if(-not $Condition){throw $Message} }
function Wait-ForSingleClick {
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while ($watch.ElapsedMilliseconds -lt [Windows.Forms.SystemInformation]::DoubleClickTime+80) {
        [Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 10
    }
}
$form=[LocalHdrMenu.GameListsForm]::new()
try {
    $form.ShowInTaskbar=$false; $form.StartPosition='Manual'; $form.Location=[Drawing.Point]::new(-30000,-30000)
    $form.ClearRows()
    for($i=0;$i -lt 800;$i++) {$form.AddRow('Defaults',('Game{0:D4}.exe' -f $i),'Watching','')}
    $form.AddRow('Auto-detected','Detected.exe','Watching','2026-11-01')
    $form.AddRow('Custom','Custom.exe','Watching','',$true,$true)
    $form.AddRow('Custom','Other.exe','Excluded','',$false,$true)
    $form.FinishRows(); $form.Show(); [Windows.Forms.Application]::DoEvents()
    $tabs=@($form.Controls | Where-Object {$_ -is [LocalHdrMenu.DialogTabs]})[0]
    $lists=@($tabs.TabPages | ForEach-Object { @($_.Controls | Where-Object {$_ -is [Windows.Forms.ListView]})[0] })
    $times=@()
    foreach($index in @(1,2,0,1,2,0,1)) {
        $watch=[Diagnostics.Stopwatch]::StartNew(); $tabs.SelectedIndex=$index; $form.Update(); [Windows.Forms.Application]::DoEvents()
        $times+=$watch.Elapsed.TotalMilliseconds
        Assert (@($tabs.TabPages | Where-Object Visible).Count -eq 1) 'Tab switch must show exactly one page'
    }
    $maximum=($times | Measure-Object -Maximum).Maximum
    Assert ($maximum -lt 750) ('Tab switch stalled for '+[Math]::Round($maximum)+' ms')
    $defaults=$lists[1]
    Assert ($defaults.Items.Count -eq 800) 'Default game count changed'
    Assert ($tabs.TabPages[1].Text -eq 'Defaults (800/800)' -and $tabs.TabPages[2].Text -eq 'Custom (1/2)') 'Tab captions must show enabled games over total games'
    if([Windows.Forms.SystemInformation]::MouseWheelScrollLines -ne 0) {
        foreach($step in 1..6) {
            [void][GameListInput]::SendMessage($defaults.Handle,0x20a,[IntPtr](-120 -shl 16),[IntPtr]0)
        }
        Assert ($defaults.TopItem.Index -gt 0 -and $defaults.SelectedIndices.Count -eq 0) 'Wheel scrolling must advance the viewport without selecting a game'
    }
    if($defaults.OwnerDraw) {
        # Offscreen windows may skip WM_PAINT. Force one viewport to be drawn.
        $script:retrievals=0
        $counter=[Windows.Forms.RetrieveVirtualItemEventHandler]{ $script:retrievals++ }
        $defaults.add_RetrieveVirtualItem($counter)
        $bitmap=[Drawing.Bitmap]::new($defaults.Width,$defaults.Height)
        try { $defaults.DrawToBitmap($bitmap,$defaults.ClientRectangle) }
        finally { $bitmap.Dispose(); $defaults.remove_RetrieveVirtualItem($counter) }
        $visibleRows=[Math]::Ceiling($defaults.ClientSize.Height/$defaults.GetItemRect(0).Height)
        Assert ($script:retrievals -gt 0 -and $script:retrievals -le 5*$visibleRows) "Painting a viewport requested $script:retrievals virtual items for at most $visibleRows rows"
    }
    $match=$defaults.FindItemWithText('game0799.exe',$false,0,$true)
    Assert ($null -ne $match -and $match.Index -eq 799) 'Keyboard/text search cannot find offscreen game'
    $defaults.SelectedIndices.Add(799); $defaults.EnsureVisible(799)
    [Windows.Forms.Application]::DoEvents()
    Assert ($form.SelectedExecutable -eq 'Game0799.exe' -and $form.LaunchButton.Enabled -and $form.ShortcutButton.Enabled) 'Selected offscreen game is not available to actions'
    $tabs.SelectedIndex=2
    Assert ($form.SelectedExecutable -eq '' -and -not $form.LaunchButton.Enabled) 'A different tab reused the previous tab selection'
    $lists[2].SelectedIndices.Add(0)
    Assert ($form.SelectedExecutable -eq 'Custom.exe') 'Custom tab selection is incorrect'
    $list=$lists[2]
    Assert (($list.Columns | Measure-Object Width -Sum).Sum -eq $list.ClientSize.Width) 'Unused header area on a short list'
    $script:toggle=''; $form.add_EnableRequested({param($exe,$enable) $script:toggle="$exe=$enable"})
    $script:edits=@(); $form.EditRuleButton.add_Click({$script:edits+=@($form.SelectedExecutable)})
    foreach ($i in 0,1) {
        $row=$list.GetItemRect($i)
        $label=[Drawing.Point]::new(64,$row.Top+($row.Height -shr 1))
        $before=$list.Items[$i].Checked
        Send-ListMouse $list $label 0x201 0x202 1
        Send-ListMouse $list $label 0x203 0x202 1
        Assert ($script:edits.Count -eq $i+1 -and $script:edits[-1] -eq $list.Items[$i].Text) 'Row double-click must open settings once for the clicked game'
        Assert ($script:toggle -eq '' -and $list.Items[$i].Checked -eq $before) 'Row double-click changed the checkbox'
    }
    $row=$list.GetItemRect(1)
    $point=[Drawing.Point]::new(8,$row.Top+($row.Height -shr 1))
    Send-ListMouse $list $point 0x201 0x202 1
    Send-ListMouse $list $point 0x203 0x202 1
    Wait-ForSingleClick
    Assert ($script:toggle -eq '' -and -not $list.Items[1].Checked -and $script:edits.Count -eq 2) 'Double-clicking the checkbox must leave the rule alone'
    Send-ListMouse $list $point 0x201 0x202 1
    Wait-ForSingleClick
    Assert ($script:toggle -eq 'Other.exe=True' -and $form.SelectedExecutable -eq 'Other.exe') 'Checkbox click did not request enabling the clicked game'
    Assert ($tabs.TabPages[2].Text -eq 'Custom (2/2)') 'Checking a game must increase the enabled count'
    $row=$list.GetItemRect(0); $point=[Drawing.Point]::new(64,$row.Top+($row.Height -shr 1))
    Send-ListMouse $list $point 0x204 0x205 2
    $menu=$form.GetType().GetField('itemMenu','Instance,NonPublic').GetValue($form)
    Assert ($menu.Visible -and $form.SelectedExecutable -eq 'Custom.exe' -and $menu.Items[0].Text -eq 'Disable game') 'Right-click did not open actions for the clicked game'
    $script:removed=''; $form.RemoveButton.add_Click({$script:removed=$form.SelectedExecutable})
    $menu.Items[$menu.Items.Count-1].PerformClick()
    Assert ($script:removed -eq 'Custom.exe') 'Menu remove acted on the wrong game'
    $menu.Close()
    [void][GameListInput]::SendMessage($list.Handle,0x100,[IntPtr]32,[IntPtr]0)
    Assert ($script:toggle -eq 'Custom.exe=False') 'Space did not request disabling the selected game'
    Assert ($tabs.TabPages[2].Text -eq 'Custom (1/2)') 'Unchecking a game must decrease the enabled count'
    $tabs.SelectedIndex=1
    Assert ($form.SelectedExecutable -eq 'Game0799.exe' -and $defaults.TopItem.Index -gt 0) 'Returning to a tab lost selection or scroll position'
    if($OutputDirectory) {
        [void][IO.Directory]::CreateDirectory($OutputDirectory)
        foreach($index in @(0,1,2)) {
            $tabs.SelectedIndex=$index; $form.Update(); [Windows.Forms.Application]::DoEvents()
            $bitmap=[Drawing.Bitmap]::new($form.Width,$form.Height)
            try {$form.DrawToBitmap($bitmap,[Drawing.Rectangle]::new(0,0,$form.Width,$form.Height)); $bitmap.Save((Join-Path $OutputDirectory ('tab-'+$index+'.png')))}
            finally {$bitmap.Dispose()}
        }
    }
    $form.ClearRows(); $form.AddRow('Custom','Replacement.exe','Watching',''); $form.FinishRows()
    Assert ($lists[1].Items.Count -eq 0 -and $tabs.TabPages[1].Text -eq 'Defaults (0/0)' -and $tabs.TabPages[2].Text -eq 'Custom (1/1)') 'Refresh retained removed games'
    Assert (-not $form.LaunchButton.Enabled -and $form.SelectedExecutable -eq '') 'Refresh retained a stale selection'
    $tabs.SelectedIndex=2; $lists[2].SelectedIndices.Add(0)
    Assert ($form.SelectedExecutable -eq 'Replacement.exe') 'Refreshed selection refers to the old data'
    'PASS: 800-game tab switching (max '+[Math]::Round($maximum,1)+' ms), search, per-tab selection/scroll, actions, empty tabs, and refresh.'
} finally {$form.Dispose()}
