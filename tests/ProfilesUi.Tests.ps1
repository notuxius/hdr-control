param([string]$OutputDirectory)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
Add-Type -Path @((Join-Path $repo 'TrayTheme.cs'),(Join-Path $repo 'ProfilesUi.cs')) -ReferencedAssemblies System.Windows.Forms,System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
function Assert($Condition,$Message) { if (-not $Condition) { throw $Message } }
function Get-AliasTextBounds($Grid,$Color) {
    $bounds=$Grid.GetCellDisplayRectangle($Grid.CurrentCell.ColumnIndex,$Grid.CurrentCell.RowIndex,$true)
    $bitmap=[Drawing.Bitmap]::new($Grid.Width,$Grid.Height)
    try {
        $Grid.DrawToBitmap($bitmap,$Grid.ClientRectangle)
        $left=$bounds.Right; $right=-1; $top=$bounds.Bottom; $bottom=-1
        $ink=$Color.ToArgb()
        for($y=$bounds.Top+2;$y -lt $bounds.Bottom-2;$y++) {
            for($x=$bounds.Left+2;$x -lt $bounds.Right-2;$x++) {
                if($bitmap.GetPixel($x,$y).ToArgb() -ne $ink) { continue }
                $left=[Math]::Min($left,$x); $right=[Math]::Max($right,$x)
                $top=[Math]::Min($top,$y); $bottom=[Math]::Max($bottom,$y)
            }
        }
        Assert ($right -ge $left) 'Alias text was not rendered'
        return [Drawing.Rectangle]::FromLTRB($left,$top,$right+1,$bottom+1)
    } finally { $bitmap.Dispose() }
}
function Check-Controls($Parent,$Name) {
    foreach($control in $Parent.Controls) {
        if ($control.Visible -and $Parent -isnot [Windows.Forms.TabControl]) {
            Assert ($control.Left -ge 0 -and $control.Top -ge 0 -and $control.Right -le $Parent.ClientSize.Width+2 -and $control.Bottom -le $Parent.ClientSize.Height+2) ('Control outside '+$Name+': '+$control.GetType().Name+' '+$control.Text)
        }
        if ($control -is [Windows.Forms.DataGridView] -or $control -is [Windows.Forms.ListView] -or $control -is [Windows.Forms.NumericUpDown]) { continue }
        Check-Controls $control $Name
    }
}
if ($OutputDirectory) { [void][IO.Directory]::CreateDirectory($OutputDirectory) }
foreach ($scale in @(1.0,1.25,1.5,2.0)) {
    foreach ($name in @('GameRuleForm','PresetForm','ShortcutForm','ProfileSettingsForm','GameListsForm')) {
        $form=New-Object ('LocalHdrMenu.'+$name)
        try {
            switch ($name) {
                'GameRuleForm' { $form.Executable.Text='ExampleGame.exe'; $form.RuleEnabled.Checked=$true; $form.AddTarget(('A'*64),'Main OLED',$true); $form.AddTarget(('B'*64),'Secondary HDR display',$false) }
                'PresetForm' { $form.PresetName.Text='Gaming'; $form.AddDisplay(('A'*64),'Main OLED',$true,$true,'35'); $form.AddDisplay(('B'*64),'Secondary HDR display',$true,$false,'') }
                'ShortcutForm' { $form.Modifiers=3; $form.Key.SelectedItem=[Windows.Forms.Keys]::H; $form.AddTarget(('A'*64),'Main OLED',$true) }
                'ProfileSettingsForm' {
                    $form.ExitPolicy.SelectedIndex=1
                    $form.AddMonitor([LocalHdrMenu.MonitorAlias]@{Key='A'*64;ModelName='Example OLED monitor';Alias='Main'})
                    $form.AddMonitor([LocalHdrMenu.MonitorAlias]@{Key='B'*64;ModelName='Second monitor';Alias='Side'})
                    $form.AddPreset('example','Gaming'); $form.AddShortcut('example','Ctrl+Alt+H - Gaming')
                }
                'GameListsForm' { $form.AddRow('Defaults','ExampleGame.exe','Watching',''); $form.FinishRows() }
            }
            $form.Scale([Drawing.SizeF]::new($scale,$scale)); $form.Font=[Drawing.Font]::new('Segoe UI',[single](10*$scale))
            $form.ShowInTaskbar=$false; $form.StartPosition='Manual'; $form.Location=[Drawing.Point]::new(-30000,-30000)
            $form.Show(); [Windows.Forms.Application]::DoEvents(); $form.PerformLayout()
            Check-Controls $form ($name+' at '+$scale)
            foreach($tabs in @($form.Controls | Where-Object { $_ -is [LocalHdrMenu.DialogTabs] })) {
                for($page=0;$page -lt $tabs.TabPages.Count;$page++) {
                    $tabs.SelectedIndex=$page
                    [Windows.Forms.Application]::DoEvents(); $form.PerformLayout()
                    Check-Controls $form ($name+' page '+$page+' at '+$scale)
                    Assert (@($tabs.TabPages | Where-Object Visible).Count -eq 1) 'Navigation must show exactly one page'
                    if($name -eq 'ProfileSettingsForm' -and $page -eq 0) {
                        $grid=$form.Monitors
                        $grid.CurrentCell=$grid.Rows[0].Cells['Alias']
                        [void]$grid.Focus()
                        $savedBounds=Get-AliasTextBounds $grid $grid.CurrentCell.InheritedStyle.SelectionForeColor
                        Assert ($grid.BeginEdit($false)) 'Alias editor did not open'
                        $grid.EditingControl.Select($grid.EditingControl.TextLength,0)
                        $editingBounds=Get-AliasTextBounds $grid $grid.EditingControl.ForeColor
                        Assert ($savedBounds -eq $editingBounds) "Alias text moved from $savedBounds to $editingBounds on entering edit mode at scale $scale"
                        $grid.EditingControl.Text='Gaming display'
                        $editedBounds=Get-AliasTextBounds $grid $grid.EditingControl.ForeColor
                        Assert ($grid.EndEdit()) 'Alias edit did not commit'
                        $committedBounds=Get-AliasTextBounds $grid $grid.CurrentCell.InheritedStyle.SelectionForeColor
                        Assert ($editedBounds -eq $committedBounds) "Alias text moved from $editedBounds to $committedBounds on saving at scale $scale"
                    }
                    if($name -eq 'ProfileSettingsForm' -and $page -gt 0) {
                        $list=if($page -eq 1) { $form.Presets } else { $form.Shortcuts }
                        $listName=$tabs.TabPages[$page].Text
                        foreach($count in @(1,80,0)) {
                            $list.BeginUpdate()
                            $list.Items.Clear()
                            for($i=0;$i -lt $count;$i++) { [void]$list.Items.Add("Example $i") }
                            $list.EndUpdate()
                            [Windows.Forms.Application]::DoEvents()
                            Assert ($list.Columns[0].Width -eq $list.ClientSize.Width) "$listName header leaves unused space or overflows with $count rows at scale $scale"
                        }
                    }
                    if($name -eq 'GameListsForm') {
                        $list=@($tabs.TabPages[$page].Controls | Where-Object { $_ -is [Windows.Forms.ListView] })[0]
                        if($list.Items.Count) {
                            $list.Items[0].Selected=$true; [Windows.Forms.Application]::DoEvents()
                            Assert ($form.SelectedExecutable -eq 'ExampleGame.exe' -and $form.LaunchButton.Enabled) 'Selected game action unavailable'
                        } else { Assert (-not $form.LaunchButton.Enabled) 'Empty page must disable game actions' }
                    }
                }
                $tabs.SelectedIndex=0
            }
            if ($OutputDirectory -and $scale -eq 1.0) {
                $bitmap=[Drawing.Bitmap]::new($form.Width,$form.Height)
                try { $form.DrawToBitmap($bitmap,[Drawing.Rectangle]::new(0,0,$form.Width,$form.Height)); $bitmap.Save((Join-Path $OutputDirectory ($name+'.png')),[Drawing.Imaging.ImageFormat]::Png) }
                finally { $bitmap.Dispose() }
            }
        } finally { $form.Dispose() }
    }
}
'PASS: five editor layouts at 100%, 125%, 150%, and 200% scale.'
