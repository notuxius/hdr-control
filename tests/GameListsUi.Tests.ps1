# Large hidden lists must switch quickly without changing selection or actions.
param([string]$OutputDirectory)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
Add-Type -Path @((Join-Path $repo 'TrayTheme.cs'),(Join-Path $repo 'ProfilesUi.cs')) -ReferencedAssemblies System.Windows.Forms,System.Drawing,UIAutomationProvider,UIAutomationTypes,WindowsBase
[Windows.Forms.Application]::EnableVisualStyles()
Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class GameListInput { [DllImport("user32")] public static extern int GetWindowLong(IntPtr h,int index); [DllImport("user32")] public static extern IntPtr SendMessage(IntPtr h,int m,IntPtr w,IntPtr l); [DllImport("user32")] public static extern bool PostMessage(IntPtr h,int m,IntPtr w,IntPtr l); }'
function Send-ListMouse($List,$Point,$Down,$Up,$Button) {
    $pos=[IntPtr]($Point.X -bor ($Point.Y -shl 16))
    [void][GameListInput]::PostMessage($List.Handle,$Down,[IntPtr]$Button,$pos)
    [void][GameListInput]::PostMessage($List.Handle,$Up,[IntPtr]0,$pos)
    [Windows.Forms.Application]::DoEvents()
}
function Assert($Condition,$Message) { if(-not $Condition){throw $Message} }
function Assert-EmptyGamePage($Tabs,$Index) {
    $Tabs.SelectedIndex=$Index
    $visible=@($Tabs.TabPages[$Index].Controls | Where-Object Visible)
    $messages=@('No games detected yet.','No community games to show.','Your custom list is empty.')
    Assert ($visible.Count -eq 1 -and $visible[0] -is [Windows.Forms.Label] -and $visible[0].Text.StartsWith($messages[$Index])) "Empty game tab $Index must show only its message"
}
function Click-Header($List,$Column,[switch]$Checkbox) {
    $header=[GameListInput]::SendMessage($List.Handle,0x101f,[IntPtr]0,[IntPtr]0)
    $x=if($Checkbox) { 12 } elseif($Column -eq 0) { $List.Columns[0].Width-9 } else { $List.Columns[$Column].Width -shr 1 }
    for($i=0;$i -lt $Column;$i++) { $x+=$List.Columns[$i].Width }
    Send-ListMouse ([pscustomobject]@{Handle=$header}) ([Drawing.Point]::new($x,8)) 0x201 0x202 1
}
function Check-RowActionsFit($List) {
    Assert ($List.Columns[$List.Columns.Count-1].Text -eq 'More') 'Row actions must have a More column header'
    $style=[GameListInput]::GetWindowLong($List.Handle,-16)
    Assert (-not ($style -band 0x100000)) "Horizontal scrollbar on $($List.AccessibleName)"
    $dots=$List.TopItem.SubItems[$List.Columns.Count-1].Bounds
    Assert ($dots.Width -gt 0 -and $dots.Left -ge 0 -and $dots.Right -le $List.ClientSize.Width) "Row menu clipped on $($List.AccessibleName)"
}
function Wait-ForSingleClick {
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while ($watch.ElapsedMilliseconds -lt [Windows.Forms.SystemInformation]::DoubleClickTime+80) {
        [Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 10
    }
}
function Check-MenuCorners($Menu) {
    if ([Windows.Forms.SystemInformation]::HighContrast) { return }
    $region=$Menu.Region
    Assert ($null -ne $region) 'Game actions popup needs a rounded window region'
    $w=$Menu.ClientSize.Width; $h=$Menu.ClientSize.Height
    foreach($x in 0,($w-1)) {
        foreach($y in 0,($h-1)) {
            Assert (-not $region.IsVisible($x,$y)) 'Square popup corner extends beyond the rounded border'
        }
        Assert ($region.IsVisible($x,($h -shr 1))) 'Popup side is clipped'
    }
    foreach($y in 0,($h-1)) {
        Assert ($region.IsVisible(($w -shr 1),$y)) 'Popup top or bottom is clipped'
    }
}
$form=[LocalHdrMenu.GameListsForm]::new()
try {
    $form.ShowInTaskbar=$false; $form.StartPosition='Manual'; $form.Location=[Drawing.Point]::new(-30000,-30000)
    $form.Show(); [Windows.Forms.Application]::DoEvents()
    $tabs=@($form.Controls | Where-Object {$_ -is [LocalHdrMenu.DialogTabs]})[0]
    foreach($index in 0..2) { Assert-EmptyGamePage $tabs $index }
    $form.ClearRows()
    for($i=799;$i -ge 0;$i--) {$form.AddRow('Installed',('Game{0:D4}.exe' -f $i),'Watching','')}
    $form.AddRow('Auto-detected','Detected.exe','Watching','2026-11-01')
    $form.AddRow('Custom','Custom.exe','Watching','',$true,$true)
    $form.AddRow('Custom','Other.exe','Excluded','',$false,$true)
    $form.FinishRows(); [Windows.Forms.Application]::DoEvents()
    $lists=@($tabs.TabPages | ForEach-Object { @($_.Controls | Where-Object {$_ -is [Windows.Forms.ListView]})[0] })
    $times=@()
    # Check the handoff itself as well as the final visible page.
    $blankTransitions=[Collections.Generic.List[int]]::new()
    foreach($page in $tabs.TabPages) {
        $page.add_VisibleChanged({
            if($form.Visible -and -not $tabs.TabPages[$tabs.SelectedIndex].Visible) {
                $blankTransitions.Add($tabs.SelectedIndex)
            }
        })
    }
    foreach($index in @(1,2,0,1,2,0,1)) {
        $watch=[Diagnostics.Stopwatch]::StartNew(); $tabs.SelectedIndex=$index; $form.Update(); [Windows.Forms.Application]::DoEvents()
        $times+=$watch.Elapsed.TotalMilliseconds
        Assert (@($tabs.TabPages | Where-Object Visible).Count -eq 1) 'Tab switch must show exactly one page'
        Assert ($lists[$index].Visible -and -not @($tabs.TabPages[$index].Controls | Where-Object {$_ -is [Windows.Forms.Label] -and $_.Visible}).Count) 'Populated tab must show its table without the empty hint'
        Check-RowActionsFit $lists[$index]
        $widths=($lists[$index].Columns.Width -join ',')
        if($times.Count -eq 1) { $expectedWidths=$widths }
        Assert ($widths -eq $expectedWidths) "Column widths changed on tab $index ($widths vs $expectedWidths)"
    }
    $maximum=($times | Measure-Object -Maximum).Maximum
    Assert ($blankTransitions.Count -eq 0) 'Previous page disappeared before the selected page was visible'
    Assert ($maximum -lt 750) ('Tab switch stalled for '+[Math]::Round($maximum)+' ms')
    $defaults=$lists[1]
    Assert ($defaults.Columns[0].Text -eq [char]0x2611 -and $defaults.Columns[0].Width -le 3*$defaults.Font.Height) 'Checkbox header should fit its two icons without a text label'
    Assert ($defaults.Items.Count -eq 800) 'All games must be reachable in a single scroll range'
    $initialHeight=$form.Height
    foreach($height in @($initialHeight,($initialHeight+17),$initialHeight)) {
        $form.Height=$height
        [Windows.Forms.Application]::DoEvents()
        $defaults.TopItem=$defaults.Items[799]
        $lastRow=$defaults.GetItemRect(799)
        Assert ($lastRow.Bottom -eq $defaults.ClientSize.Height) "Scrollbar extends past the last game at window height $height ($($lastRow.Bottom) vs $($defaults.ClientSize.Height))"
        Assert (($defaults.Parent.ClientSize.Height-$defaults.Bottom) -ge $lastRow.Height) 'Expected at least one row of space below the scrollbar'
    }
    $defaults.TopItem=$defaults.Items[0]
    $defaults.EnsureVisible(25)
    Assert ($defaults.TopItem.Index -gt 0 -and $defaults.Items[25].SubItems[1].Text -eq 'Game0025.exe') 'Could not scroll past the former page boundary'
    $defaults.TopItem=$defaults.Items[0]
    Assert ($defaults.Items[0].SubItems[1].Text -eq 'Game0000.exe' -and $defaults.Columns[1].Text.EndsWith([char]0x25b2)) 'Initial data and arrow must indicate executable A-Z'
    if(-not [Windows.Forms.SystemInformation]::HighContrast) {
        $bitmap=[Drawing.Bitmap]::new($defaults.Width,$defaults.Height)
        try {
            $defaults.DrawToBitmap($bitmap,$defaults.ClientRectangle)
            $right=$defaults.Columns[0].Width+$defaults.Columns[1].Width
            $headerHeight=$defaults.GetItemRect(0).Top
            $edge=[LocalHdrMenu.DialogTheme]::Border.ToArgb()
            for($y=0;$y -lt $defaults.GetItemRect(1).Bottom;$y++) {
                Assert ($bitmap.GetPixel($right-2,$y).ToArgb() -eq $edge) "Gap in the column divider at y=$y"
            }
            $arrow=0
            for($x=$right-28;$x -lt $right-3;$x++) {
                for($y=3;$y -lt $headerHeight-3;$y++) {
                    if($bitmap.GetPixel($x,$y).ToArgb() -eq [LocalHdrMenu.DialogTheme]::Muted.ToArgb()) { $arrow++ }
                }
            }
            Assert ($arrow -gt 5) 'Default sort arrow is missing from the right edge of the executable header'
        } finally { $bitmap.Dispose() }
    }
    Click-Header $defaults 1
    Assert ($defaults.Items[0].SubItems[1].Text -eq 'Game0799.exe' -and $defaults.Columns[1].Text.EndsWith([char]0x25bc)) 'Clicking the default sort must reverse it'
    Click-Header $defaults 1
    $originalWidth=$form.Width
    foreach($width in @(($originalWidth+160),$originalWidth)) {
        $form.Width=$width; [Windows.Forms.Application]::DoEvents()
        Check-RowActionsFit $defaults
    }
    Assert ($tabs.TabPages[1].Text -eq 'Installed (800/800)' -and $tabs.TabPages[2].Text -eq 'Custom (1/2)') 'Tab captions must show enabled games over total games'
    if([Windows.Forms.SystemInformation]::MouseWheelScrollLines -ne 0) {
        foreach($step in 1..6) {
            [void][GameListInput]::SendMessage($defaults.Handle,0x20a,[IntPtr](-120 -shl 16),[IntPtr]0)
        }
        Assert ($defaults.TopItem.Index -gt 0 -and $defaults.SelectedIndices.Count -eq 0) 'Wheel scrolling must advance the viewport without selecting a game'
    }
    if($defaults.OwnerDraw -and -not [Windows.Forms.SystemInformation]::HighContrast) {
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
    Assert ($null -ne $match -and $match.Index -eq 799) 'Keyboard/text search must find the last game'
    $defaults.SelectedIndices.Add($match.Index); $defaults.EnsureVisible($match.Index)
    [Windows.Forms.Application]::DoEvents()
    Assert ($form.SelectedExecutable -eq 'Game0799.exe' -and $form.LaunchButton.Enabled -and $form.ShortcutButton.Enabled) 'Selected offscreen game is not available to actions'
    $tabs.SelectedIndex=2
    Assert ($form.SelectedExecutable -eq '' -and -not $form.LaunchButton.Enabled) 'A different tab reused the previous tab selection'
    $lists[2].SelectedIndices.Add(0)
    Assert ($form.SelectedExecutable -eq 'Custom.exe') 'Custom tab selection is incorrect'
    $list=$lists[2]
    if(-not [Windows.Forms.SystemInformation]::HighContrast) {
        [void]$list.Focus()
        $list.Items[0].Focused=$true
        $row=$list.GetItemRect(0)
        $bitmap=[Drawing.Bitmap]::new($list.Width,$list.Height)
        try {
            $list.DrawToBitmap($bitmap,$list.ClientRectangle)
            $selection=[LocalHdrMenu.DialogTheme]::Selection.ToArgb()
            $pageColor=$list.Parent.BackColor.ToArgb()
            $actionsLeft=$list.Items[0].SubItems[4].Bounds.Left
            $edge=[LocalHdrMenu.DialogTheme]::Border.ToArgb()
            for($y=0;$y -lt $list.GetItemRect(1).Bottom;$y++) {
                Assert ($bitmap.GetPixel($actionsLeft-2,$y).ToArgb() -eq $edge) "Gap in the More column divider at y=$y"
            }
            foreach($y in $list.GetItemRect(1).Bottom,($list.ClientSize.Height-1)) {
                for($x=0;$x -lt $list.ClientSize.Width;$x++) {
                    Assert ($bitmap.GetPixel($x,$y).ToArgb() -eq $pageColor) "Area below the last row differs from the page at ($x,$y)"
                }
            }
            foreach($column in $list.Columns) {
                $cell=$list.Items[0].SubItems[$column.Index].Bounds
                foreach($offset in 8,9) {
                    Assert ($bitmap.GetPixel($cell.Left+$offset,$row.Top).ToArgb() -eq $selection) 'Focused game must show only the row selection across all columns'
                }
            }
        } finally { $bitmap.Dispose() }
    }
    Assert (($list.Columns.Width -join ',') -eq ($defaults.Columns.Width -join ',')) 'Tab layouts diverged after resize'
    $script:toggle=''; $form.add_EnableRequested({param($exe,$enable) $script:toggle="$exe=$enable"})
    $script:edits=@(); $form.EditRuleButton.add_Click({$script:edits+=@($form.SelectedExecutable)})
    foreach ($i in 0,1) {
        $row=$list.GetItemRect($i)
        $label=[Drawing.Point]::new(64,$row.Top+($row.Height -shr 1))
        $before=$list.Items[$i].Checked
        Send-ListMouse $list $label 0x201 0x202 1
        Send-ListMouse $list $label 0x203 0x202 1
        Assert ($script:edits.Count -eq $i+1 -and $script:edits[-1] -eq $list.Items[$i].SubItems[1].Text) 'Row double-click must open settings once for the clicked game'
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
    Check-MenuCorners $menu
    $script:removed=''; $form.RemoveButton.add_Click({$script:removed=$form.SelectedExecutable})
    $menu.Items[$menu.Items.Count-1].PerformClick()
    Assert ($script:removed -eq 'Custom.exe') 'Menu remove acted on the wrong game'
    $menu.Close()
    $dots=$list.Items[1].SubItems[$list.Columns.Count-1].Bounds
    $point=[Drawing.Point]::new($dots.Left+($dots.Width -shr 1),$dots.Top+($dots.Height -shr 1))
    Send-ListMouse $list $point 0x201 0x202 1
    Assert ($menu.Visible -and $form.SelectedExecutable -eq 'Other.exe') 'Row menu did not open for the clicked game'
    Check-MenuCorners $menu
    $commands=@($menu.Items | Where-Object { $_.Available -and $_ -is [Windows.Forms.ToolStripMenuItem] } | ForEach-Object Text)
    Assert (($commands -join '|') -eq 'Disable game|Game settings|Launch with HDR|Create shortcut|Remove game') 'Unexpected three-dot menu actions'
    $form.RemoveButton.PerformClick()
    Assert ($script:removed -eq 'Other.exe') 'Row menu acted on the previously selected game'
    $menu.Close()
    Send-ListMouse $list $point 0x201 0x202 1
    $menu.Items[0].PerformClick()
    Assert ($script:toggle -eq 'Other.exe=False' -and -not $list.Items[1].Checked) 'Three-dot menu did not disable the clicked game'
    $menu.Close()
    Send-ListMouse $list $point 0x201 0x202 1
    Assert ($menu.Visible -and $menu.Items[0].Text -eq 'Enable game') 'Disabled game must offer Enable game'
    $menu.Items[0].PerformClick()
    Assert ($script:toggle -eq 'Other.exe=True' -and $list.Items[1].Checked) 'Three-dot menu did not re-enable the clicked game'
    $menu.Close()
    $list.Items[0].Selected=$true
    [void][GameListInput]::SendMessage($list.Handle,0x100,[IntPtr]32,[IntPtr]0)
    Assert ($script:toggle -eq 'Custom.exe=False') 'Space did not request disabling the selected game'
    Assert ($tabs.TabPages[2].Text -eq 'Custom (1/2)') 'Unchecking a game must decrease the enabled count'
    Click-Header $list 0
    Assert ($list.Items[0].Checked -and $list.Items[0].SubItems[1].Text -eq 'Other.exe' -and $form.SelectedExecutable -eq 'Custom.exe') 'Enabled heading must sort checked games first and retain selection'
    Assert ($script:toggle -eq 'Custom.exe=False' -and $tabs.TabPages[2].Text -eq 'Custom (1/2)') 'Sorting Enabled changed the rules'
    Click-Header $list 0
    Assert (-not $list.Items[0].Checked -and $list.Items[0].SubItems[1].Text -eq 'Custom.exe') 'Second Enabled click must sort unchecked games first'
    Click-Header $list 0 -Checkbox
    Assert ($tabs.TabPages[2].Text -eq 'Custom (2/2)' -and $script:toggle -eq 'Custom.exe=True') 'Mixed header must enable the unchecked games'
    Click-Header $list 0 -Checkbox
    Assert ($tabs.TabPages[2].Text -eq 'Custom (0/2)' -and $script:toggle -eq 'Other.exe Custom.exe=False') 'Checked header must disable the tab in one request'
    Click-Header $list 2
    Assert ($list.Items[0].SubItems[1].Text -eq 'Other.exe' -and $form.SelectedExecutable -eq 'Custom.exe') 'Sorting by status lost the selected game'
    Click-Header $list 2
    Assert ($list.Items[0].SubItems[1].Text -eq 'Custom.exe') 'Second header click must reverse the sort'
    $tabs.SelectedIndex=1
    Assert ($tabs.TabPages[1].Text -eq 'Installed (800/800)') 'Custom bulk edit affected Defaults'
    Assert ($form.SelectedExecutable -eq 'Game0799.exe' -and $defaults.TopItem.Index -gt 0) 'Returning to a tab lost selection or scroll position'
    Click-Header $defaults 0
    Assert ($defaults.TopItem.Index -eq 0 -and $form.SelectedExecutable -eq 'Game0799.exe') 'Sorting must show the first group even when the selected game was far down the list'
    if($OutputDirectory) {
        [void][IO.Directory]::CreateDirectory($OutputDirectory)
        foreach($index in @(0,1,2)) {
            $tabs.SelectedIndex=$index; $form.Update(); [Windows.Forms.Application]::DoEvents()
            $bitmap=[Drawing.Bitmap]::new($form.Width,$form.Height)
            try {$form.DrawToBitmap($bitmap,[Drawing.Rectangle]::new(0,0,$form.Width,$form.Height)); $bitmap.Save((Join-Path $OutputDirectory ('tab-'+$index+'.png')))}
            finally {$bitmap.Dispose()}
        }
    }
    # A header toggle covers the full tab including offscreen games.
    $tabs.SelectedIndex=1
    Click-Header $defaults 0 -Checkbox
    Assert ($tabs.TabPages[1].Text -eq 'Installed (0/800)' -and $script:toggle -match 'Game0000\.exe' -and $script:toggle -match 'Game0799\.exe') 'Installed header changed only the visible rows'
    $form.ClearRows()
    foreach($i in 0..22) { $form.AddRow('Installed',('Game{0:D4}.exe' -f $i),'Watching','') }
    $form.FinishRows()
    Assert ($defaults.Items.Count -eq 23 -and $defaults.Items[22].SubItems[1].Text -eq 'Game0022.exe') 'Refresh must expose the entire shortened list'
    $defaults.SelectedIndices.Add(22)
    [void][GameListInput]::SendMessage($defaults.Handle,0x100,[IntPtr]32,[IntPtr]0)
    Assert ($script:toggle -eq 'Game0022.exe=False' -and $form.SelectedExecutable -eq 'Game0022.exe') 'Checkbox on a later row changed the wrong game'
    $tabs.SelectedIndex=0; Click-Header $lists[0] 0
    $form.ClearRows(); $form.AddRow('Custom','Replacement.exe','Watching',''); $form.FinishRows()
    Assert ($lists[1].Items.Count -eq 0 -and $tabs.TabPages[1].Text -eq 'Installed (0/0)' -and $tabs.TabPages[2].Text -eq 'Custom (1/1)') 'Refresh retained removed games'
    Assert (-not $form.LaunchButton.Enabled -and $form.SelectedExecutable -eq '') 'Refresh retained a stale selection'
    $tabs.SelectedIndex=2; $lists[2].SelectedIndices.Add(0)
    Assert ($form.SelectedExecutable -eq 'Replacement.exe') 'Refreshed selection refers to the old data'
    Assert-EmptyGamePage $tabs 1
    Assert-EmptyGamePage $tabs 0
    $form.ClearRows()
    $form.AddRow('Auto-detected','A.exe','Excluded','',$false,$true)
    $form.AddRow('Auto-detected','B.exe','Watching','',$true,$true)
    $form.AddRow('Auto-detected','C.exe','Watching','',$true,$true)
    $form.FinishRows()
    Assert ($lists[0].Visible -and $lists[0].Columns[0].Text.EndsWith([char]0x25b2)) 'Repopulated tab did not restore the table and sort arrow'
    Assert ($lists[0].Items[0].SubItems[1].Text -eq 'B.exe') 'Refresh lost enabled-first sorting'
    $lists[0].SelectedIndices.Add(0)
    [void][GameListInput]::SendMessage($lists[0].Handle,0x100,[IntPtr]32,[IntPtr]0)
    Assert ($lists[0].Items[0].SubItems[1].Text -eq 'C.exe' -and $form.SelectedExecutable -eq 'B.exe' -and $script:toggle -eq 'B.exe=False') 'Unchecking a sorted game must move it to its new group and preserve its selection'
    Click-Header $lists[0] 3
    $form.ClearRows()
    $form.AddRow('Auto-detected','A.exe','Watching',([datetime]'2026-01-01').ToString('g'))
    $form.AddRow('Auto-detected','Z.exe','Watching',([datetime]'2025-12-31').ToString('g'))
    $form.FinishRows()
    Assert ($lists[0].Items[0].SubItems[1].Text -eq 'Z.exe') 'Refresh must retain chronological date sorting'
    'PASS: 800-game tab switching (max '+[Math]::Round($maximum,1)+' ms), search, per-tab selection/scroll, actions, empty tabs, and refresh.'
} finally {$form.Dispose()}

# Reopen the real settings form against an isolated per-user preferences key.
$subkey='Software\HdrGameSortTest-'+[guid]::NewGuid().ToString('N')
$settingsKey='HKEY_CURRENT_USER\'+$subkey
try {
    [Microsoft.Win32.Registry]::SetValue($settingsKey,'GameListSort.Custom',[string[]]@('Obsolete','Descending'),'MultiString')
    foreach($reopen in @($false,$true)) {
        $window=[Activator]::CreateInstance([LocalHdrMenu.SettingsForm],[Reflection.BindingFlags]'Instance,NonPublic',$null,@($settingsKey),$null)
        try {
            $tabs=@($window.Games.Controls | Where-Object {$_ -is [LocalHdrMenu.DialogTabs]})[0]
            $lists=@($tabs.TabPages | ForEach-Object { $_.Controls | Where-Object {$_ -is [Windows.Forms.ListView]} })
            $columns=@(3,0,2)
            $arrows=@([char]0x25bc,[char]0x25b2,[char]0x25bc)
            foreach($i in 0..2) {
                if($reopen) {
                    Assert ($lists[$i].Columns[$columns[$i]].Text.EndsWith($arrows[$i])) "Tab $i initially displayed the wrong saved sort arrow"
                    Assert (-not $lists[$i].Columns[1].Text.EndsWith([char]0x25b2)) "Tab $i retained the default arrow"
                } else {
                    Assert ($lists[$i].Columns[1].Text.EndsWith([char]0x25b2)) 'An absent or invalid preference must fall back to executable A-Z'
                }
            }
            foreach($section in 'Auto-detected','Installed','Custom') {
                $window.Games.AddRow($section,'A.exe','Alpha','2025-01-01',$false,$true)
                $window.Games.AddRow($section,'B.exe','Zulu','2026-01-01',$true,$true)
            }
            $window.Games.FinishRows()
            $window.ShowInTaskbar=$false; $window.StartPosition='Manual'; $window.Location=[Drawing.Point]::new(-30000,-30000)
            $window.Sections.SelectedIndex=1; $window.Show()
            foreach($i in 0..2) {
                $tabs.SelectedIndex=$i; [Windows.Forms.Application]::DoEvents()
                if(-not $reopen) {
                    Click-Header $lists[$i] $columns[$i]
                    if($i -ne 1) { Click-Header $lists[$i] $columns[$i] }
                }
                Assert ($lists[$i].Items[0].SubItems[1].Text -eq 'B.exe') "Tab $i rows disagree with the chosen sort"
            }
            $window.Close()
        } finally { $window.Dispose() }
    }
    'PASS: distinct per-tab sort columns, directions and arrows survive closing and reopening Settings.'
} finally { [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKey($subkey,$false) }
