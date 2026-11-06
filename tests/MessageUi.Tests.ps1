param([string]$OutputDirectory)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
Add-Type -Path @((Join-Path $repo 'TrayTheme.cs'),(Join-Path $repo 'ProfilesUi.cs')) -ReferencedAssemblies System.Windows.Forms,System.Drawing,UIAutomationProvider,UIAutomationTypes,WindowsBase
[Windows.Forms.Application]::EnableVisualStyles()
function Assert($condition,$message) { if(-not $condition) {throw $message} }
if($OutputDirectory) {[void][IO.Directory]::CreateDirectory($OutputDirectory)}
foreach($scale in @(1.0,1.25,1.5,2.0)) {
    foreach($kind in @('OK','YesNo','OKCancel','YesNoCancel','RetryCancel')) {
        $message="Left click: HDR controls`r`nRight click: Settings and app options`r`nMiddle click: Toggle HDR"
        $version=if($kind -eq 'OK') {'1.1.0'}
        $form=[LocalHdrMenu.DialogMessageForm]::new($message,[Windows.Forms.MessageBoxButtons]$kind,$version)
        try {
            $form.ShowInTaskbar=$false; $form.StartPosition='Manual'; $form.Location=[Drawing.Point]::new(-30000,-30000)
            $form.Scale([Drawing.SizeF]::new($scale,$scale)); $form.Font=[Drawing.Font]::new('Segoe UI',[single](10*$scale))
            $form.Show(); [Windows.Forms.Application]::DoEvents()
            Assert ($form.MessageText.Text -eq $message) 'Message content changed'
            $footer=$form.AcceptButton.Parent
            $links=$form.Controls.Find('GitHubLink',$true)
            if($kind -eq 'OK') {
                $label=$form.Controls.Find('VersionLabel',$true)[0]
                Assert ($label.Text -eq "Version: $version") 'About version is missing'
                $update=$form.CheckUpdates
                $daily=$form.AutoCheckUpdates
                Assert ($daily.Left -ge $update.Right -and $daily.Right -le $form.AcceptButton.Left -and $daily.Top -eq $update.Top -and
                    $daily.Width -ge ([Windows.Forms.TextRenderer]::MeasureText($daily.Text,$daily.Font).Width + 32*$scale)) 'Daily update checkbox must fit beside the update button'
                Assert ($update.Parent -eq $footer -and $footer.Bottom -eq $form.ClientSize.Height -and $update.Left -eq $footer.Padding.Left -and $update.Top -eq $form.AcceptButton.Top -and $update.Right -lt $form.AcceptButton.Left) 'Update button should sit at the bottom left, aligned with OK'
                $form.SetUpToDate($true)
                $status=$form.Controls.Find('UpdateStatus',$true)[0]
                Assert ($status.TextAlign -eq 'MiddleLeft') 'Update confirmation text must be left aligned'
                $size=$status.GetPreferredSize([Drawing.Size]::Empty)
                $lastCheck=$form.Controls.Find('LastUpdateCheck',$true)[0]
                Assert ($status.Parent -eq $footer -and $status.Left -eq $update.Left -and $status.Bottom -le $lastCheck.Top -and $status.Width -ge $size.Width -and $status.Height -ge $size.Height) 'Update confirmation must fit above Last checked, aligned to the update button'
                $form.SetUpToDate($false)
                Assert ($status.Text -eq '') 'A new check should clear the previous result'
                $lastCheck=$form.Controls.Find('LastUpdateCheck',$true)[0]
                Assert ($lastCheck.Text -eq 'Last checked: Never') 'An unknown check time must not invent a date'
                $checkedAt=[DateTimeOffset]::Parse('2026-11-04T09:15:00+00:00')
                $form.SetLastUpdateCheck($checkedAt.ToString('o'))
                Assert ($lastCheck.Text -eq ('Last checked: '+$checkedAt.ToLocalTime().ToString('g'))) 'Check timestamp must use the local date and time'
                $size=[Windows.Forms.TextRenderer]::MeasureText($lastCheck.Text,$lastCheck.Font)
                Assert ($lastCheck.Left -eq $update.Left -and $lastCheck.TextAlign -eq 'MiddleLeft' -and $lastCheck.Bottom -le $update.Top -and $lastCheck.Width -ge $size.Width -and $lastCheck.Height -ge $size.Height) 'Last check time must fit above the update button aligned to its left edge'
                $form.SetLastUpdateCheck('invalid')
                Assert ($lastCheck.Text -eq 'Last checked: Never') 'Invalid saved timestamps must be ignored'
                $form.SetLastUpdateCheck($checkedAt.ToString('o'))
                Assert ($links.Count -eq 1 -and $links[0].TabStop -and $links[0].AccessibleRole -eq 'Link') 'About needs a keyboard-accessible GitHub link'
                Assert ($links[0].Top -ge $form.MessageText.Bottom) 'GitHub link overlaps About text'
            } else { Assert ($links.Count -eq 0) 'Unexpected GitHub link outside About' }
            foreach($button in $footer.Controls) {
                Assert ($button.Right -le $footer.ClientSize.Width -and $button.Bottom -le $footer.ClientSize.Height) 'Message button clipped at scaled size'
            }
            Assert ($form.MessageText.Width -le $form.MessageText.Parent.ClientSize.Width) 'Message text exceeds body width'
            if($OutputDirectory -and $scale -eq 1.0 -and $kind -eq 'OK') {
                $form.SetUpToDate($true)
                $bitmap=[Drawing.Bitmap]::new($form.Width,$form.Height)
                try {$form.DrawToBitmap($bitmap,[Drawing.Rectangle]::new(0,0,$form.Width,$form.Height)); $bitmap.Save((Join-Path $OutputDirectory 'MessageForm.png'))}
                finally {$bitmap.Dispose()}
            }
            $expected=if($kind -like 'Yes*') {'Yes'} elseif($kind -eq 'RetryCancel') {'Retry'} else {'OK'}
            $form.AcceptButton.PerformClick()
            Assert ($form.DialogResult.ToString() -eq $expected) 'Message acceptance result changed'
            $form.CancelButton.PerformClick()
            $expected=if($kind -eq 'YesNo') {'No'} elseif($kind -eq 'OK') {'OK'} else {'Cancel'}
            Assert ($form.DialogResult.ToString() -eq $expected) 'Message cancellation result changed'
        } finally {$form.Dispose()}
    }
}
'PASS: message text, button results, keyboard defaults, and layout at 100-200% scale.'
