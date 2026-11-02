param([string]$OutputDirectory)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
Add-Type -Path @((Join-Path $repo 'TrayTheme.cs'),(Join-Path $repo 'ProfilesUi.cs')) -ReferencedAssemblies System.Windows.Forms,System.Drawing
$source=[IO.File]::ReadAllText((Join-Path $repo 'HdrSdrMenu.ps1'))
$native=[regex]::Match($source,"(?s)Add-Type -TypeDefinition @'\r?\n(.*?)\r?\n'@").Groups[1].Value
Add-Type -TypeDefinition $native
function Assert($Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
function Check-PanelBounds($Parent,$Scale) {
    foreach ($child in $Parent.Controls) {
        if (-not $child.Visible) { continue }
        if ($Parent -isnot [Windows.Forms.ScrollableControl] -or -not $Parent.AutoScroll) {
            Assert ($child.Right -le $Parent.ClientSize.Width+2 -and $child.Bottom -le $Parent.ClientSize.Height+2) ("{0} '{1}' {2} outside {3} {4} at scale {5}" -f $child.GetType().Name,$child.Text,$child.Bounds,$Parent.GetType().Name,$Parent.ClientSize,$Scale)
        }
        if ($child -is [Windows.Forms.Panel]) { Check-PanelBounds $child $Scale }
    }
}
Assert ([Runtime.InteropServices.Marshal]::SizeOf([type][LocalHdrMenu.Header]) -eq 20) 'Unexpected native header size'
Assert ([Runtime.InteropServices.Marshal]::SizeOf([type][LocalHdrMenu.SdrLevel]) -eq 24) 'Unexpected white-level query size'
Assert ([Runtime.InteropServices.Marshal]::SizeOf([type][LocalHdrMenu.SetSdrLevel]) -eq 28) 'Unexpected white-level write size'
Assert ([Runtime.InteropServices.Marshal]::OffsetOf([type][LocalHdrMenu.SetSdrLevel],'FinalValue').ToInt32() -eq 24) 'Unexpected final-value flag offset'
[Windows.Forms.Application]::EnableVisualStyles()
# Seed a temporary in-process location; rendering must not request real location.
$locationType=[type][LocalHdrMenu.BrightnessLocation]
$privateStatic=[Reflection.BindingFlags]'NonPublic,Static'
$locationType.GetField('nextRead',$privateStatic).SetValue($null,[DateTime]::MaxValue)
$locationType.GetField('fix',$privateStatic).SetValue($null,[LocalHdrMenu.BrightnessLocationFix]::new(50.45,30.52,[DateTime]::UtcNow))
if ($OutputDirectory) { [void][IO.Directory]::CreateDirectory($OutputDirectory) }
foreach($scale in @(1.0,1.25,1.5,2.0)) {
    $form=[LocalHdrMenu.SdrBrightnessForm]::new('Example HDR monitor','QQ==',('A'*64),2500,$false)
    try {
        $form.RefreshAvailability($true,$false,'Current Windows level: 30%. Changes save automatically.')
        $form.CreateControl()
        $form.Scale([Drawing.SizeF]::new($scale,$scale))
        $form.Font=[Drawing.Font]::new('Segoe UI',[single](10*$scale))
        $form.PerformLayout()
        $form.ShowInTaskbar=$false
        $form.StartPosition=[Windows.Forms.FormStartPosition]::Manual
        $form.Location=[Drawing.Point]::new(-30000,-30000)
        $form.Show()
        [Windows.Forms.Application]::DoEvents()
        Check-PanelBounds $form $scale
        Assert ($form.Footer.Dock -eq 'Bottom' -and $form.Footer.Controls.Count -eq 1 -and $form.Footer.Controls[0].Text -eq 'Close') 'The brightness footer should contain only Close'
        # Windows can cap the scaled form height to the monitor height.
        if ($form.ClientSize.Height -ge [Math]::Floor(906*$scale)) {
            Assert (-not $form.Body.VerticalScroll.Visible -and -not $form.Body.HorizontalScroll.Visible) 'Brightness settings should fit without scrollbars'
            foreach ($control in $form.Body.Controls) {
                Assert ($control.Bottom -le $form.Body.ClientSize.Height -and $control.Right -le $form.Body.ClientSize.Width) 'Brightness settings must fit in the body'
            }
        } else {
            Assert $form.Body.AutoScroll 'Settings must stay reachable when Windows limits the window height'
        }
        Assert ($form.Slider.Minimum -eq 0 -and $form.Slider.Maximum -eq 100) 'Slider range changed'
        Assert ([Math]::Abs($form.DayStart.Editor.Font.Size-16*$scale) -lt 0.1) 'Time text must scale with display size'
        Assert (-not $form.Restore.Checked) 'Restore must default to off'
        Assert (-not $form.NightLightSettings.Visible) 'Manual mode must hide Night Light settings'
        $form.LoadSettings(2033,3500,'NightLight',480,1080,$false)
        Assert $form.NightLightSettings.Visible 'Loading Night Light mode must show its settings button'
        Assert ($form.DayLevel -eq 2033 -and $form.NightLevel -eq 3500) 'Loading settings must retain precise levels'
        Assert ($form.SwitchingMode -eq 'NightLight' -and $form.DaySlider.Enabled -and -not $form.Slider.Enabled -and $form.DaySlider.Visible -and -not $form.Slider.Visible) 'Scheduled UI availability is incorrect'
        Assert ($form.Calibrate.Text -match 'Calibration' -and $form.NightLightSettings.Text -match 'Night Light') 'Settings shortcuts missing'
        $form.RefreshAvailability($true,$true,'Waiting for display change...')
        Assert (-not $form.DaySlider.Enabled -and -not $form.Switching.Enabled -and -not $form.Enforce.Enabled) 'Busy panel still allows edits'
        $form.RefreshAvailability($true,$true,'Waiting for display change...',$true)
        Assert ($form.Status.Text -ceq (([string][char]0x2193)+' Saving'+[char]0x2026)) "Missing saving arrow at scale $scale"
        $size=[Windows.Forms.TextRenderer]::MeasureText($form.Status.Text,$form.Status.Font)
        Assert ($form.Status.Width -ge $size.Width -and $form.Status.Height -ge $size.Height) "Saving status clipped at scale $scale"
        $form.RefreshAvailability($true,$false,'Current Windows level: 30%. Changes save automatically.')
        $form.Runtime.Text='Saved mode: Day | Windows Night Light'
        if ($OutputDirectory) {
            $form.LoadSettings(3000,1750,'NightLight',480,1080,$false)
            # Native child controls are created only when the form becomes visible.
            # Keep this test window off screen and out of the taskbar.
            $form.ShowInTaskbar=$false
            $form.StartPosition=[Windows.Forms.FormStartPosition]::Manual
            $form.Location=[Drawing.Point]::new(-30000,-30000)
            $form.Show()
            [Windows.Forms.Application]::DoEvents()
            $bitmap=[Drawing.Bitmap]::new($form.Width,$form.Height)
            try {
                $form.DrawToBitmap($bitmap,[Drawing.Rectangle]::new(0,0,$form.Width,$form.Height))
                $bitmap.Save((Join-Path $OutputDirectory ('brightness-'+[int]($scale*100)+'.png')),[Drawing.Imaging.ImageFormat]::Png)
            } finally { $bitmap.Dispose() }
        }
        $originalHeight=$form.Switching.Parent.Height
        $form.LoadSettings(3000,1750,'SunriseSunset',480,1080,$false)
        $form.Runtime.Text='Saved mode: Day | Sunrise / sunset (Windows location)'
        $form.RefreshLocationStatus()
        [Windows.Forms.Application]::DoEvents()
        Check-PanelBounds $form $scale
        Assert ($form.SwitchingMode -eq 'SunriseSunset' -and $form.LocationSettings.Visible -and $form.RefreshLocation.Visible) 'Location mode controls missing'
        Assert ($form.LocationStatus.Text -match 'sunrise.*sunset' -and $form.DayStart.Enabled) 'Solar preview or editable fallback missing'
        if ($OutputDirectory) {
            $bitmap=[Drawing.Bitmap]::new($form.Width,$form.Height)
            try {
                $form.DrawToBitmap($bitmap,[Drawing.Rectangle]::new(0,0,$form.Width,$form.Height))
                $bitmap.Save((Join-Path $OutputDirectory ('brightness-location-'+[int]($scale*100)+'.png')),[Drawing.Imaging.ImageFormat]::Png)
            } finally { $bitmap.Dispose() }
        }
        $form.LoadSettings(3000,1750,'Schedule',480,1080,$false)
        Assert ($form.Switching.Parent.Height -eq $originalHeight -and -not $form.LocationSettings.Visible) 'Switching away from location mode must restore compact layout'
    } finally { $form.Dispose() }

    $settings=[LocalHdrMenu.SettingsForm]::new()
    try {
        $display=[LocalHdrMenu.MonitorBrightness]@{Name='Example HDR monitor'; DisplayId='QQ=='; Level=6000; CurrentLevel=6000}
        $settings.SetDisplays(@($display))
        $settings.Scale([Drawing.SizeF]::new($scale,$scale))
        $settings.ShowInTaskbar=$false
        $settings.StartPosition='Manual'
        $settings.Location=[Drawing.Point]::new(-30000,-30000)
        $settings.Show()
        $close=$settings.CancelButton
        $closeBounds=$close.RectangleToScreen($close.ClientRectangle)
        for($i=0;$i -lt $settings.Sections.TabPages.Count;$i++) {
            $settings.Sections.SelectedIndex=$i
            [Windows.Forms.Application]::DoEvents()
            $page=$settings.Sections.TabPages[$i]
            $header=if($i -eq 0) { $settings.DisplayPicker.Parent } elseif($i -eq 1) { $settings.Games } else { $settings.Profiles }
            $title=$header.Controls | Where-Object { $_ -is [Windows.Forms.Label] -and $_.Text -eq $page.Text }
            $caption=$header.Controls | Where-Object { $_ -is [Windows.Forms.Label] -and $_.Tag -eq 'muted' } | Sort-Object Top | Select-Object -First 1
            Assert ($title -and $caption) "Missing title or description on $($page.Text)"
            $titleBounds=$title.RectangleToScreen($title.ClientRectangle)
            $captionBounds=$caption.RectangleToScreen($caption.ClientRectangle)
            if($i -eq 0) { $firstTitle=$titleBounds; $firstCaption=$captionBounds }
            Assert ($titleBounds -eq $firstTitle -and $captionBounds -eq $firstCaption) "Header alignment differs on $($page.Text) at scale $scale"
            $measured=[Windows.Forms.TextRenderer]::MeasureText($caption.Text,$caption.Font)
            Assert ($measured.Width -le $caption.Width -and $measured.Height -le $caption.Height) "Description is clipped on $($page.Text) at scale $scale"
            $hit=$close.Parent.GetChildAtPoint([Drawing.Point]::new($close.Left+1,$close.Top+1))
            Assert ($close.Text -eq 'Close' -and $close.Visible -and $close.Enabled -and $hit -eq $close -and $close.RectangleToScreen($close.ClientRectangle) -eq $closeBounds) "Close moved or is unavailable on $($page.Text)"
        }
        $settings.Sections.SelectedIndex=0
        $editor=$settings.Brightness
        foreach ($mode in @('Custom schedule','Follow Windows Night Light','Sunrise & sunset (location)','Follow Windows Night Light','Manual')) {
            $editor.Switching.SelectedItem=$mode
            Assert ($editor.HdrSettings.Visible -and $editor.HdrSettings.Enabled -and $editor.HdrSettings.Text -eq 'Windows HDR settings') "Windows HDR settings missing in $mode"
            Assert ($editor.HdrSettings.Left -eq $editor.Calibrate.Left -and $editor.HdrSettings.Top -ge $editor.Calibrate.Bottom -and $editor.HdrSettings.Parent.GetRow($editor.HdrSettings) -eq 1+$editor.Calibrate.Parent.GetRow($editor.Calibrate)) 'Windows HDR settings must sit directly below Calibration'
            Assert ($editor.NightLightSettings.Visible -eq ($mode -eq 'Follow Windows Night Light')) "Unexpected Night Light settings visibility in $mode"
            if ($mode -eq 'Sunrise & sunset (location)' -and $scale -eq 1) {
                Assert (-not $editor.Body.VerticalScroll.Visible -and -not $editor.Body.HorizontalScroll.Visible) 'The expanded brightness tab should fit the preferred window size'
            }
        }
        Assert (@($editor.Restore.Parent.Controls | Where-Object { $_ -is [Windows.Forms.CheckBox] }).Count -eq 2) 'Restore brightness should only contain the two restoration options'
        Assert ($editor.Slider.Visible -and -not $editor.DaySlider.Visible) 'Manual mode should show one slider'
        $editor.LoadSettings(4100,2200,'Schedule',480,1080,$false)
        $day=$editor.DaySlider.Parent
        $night=$editor.NightSlider.Parent
        $readout=$editor.Runtime.Parent.Parent
        $value=$readout.Controls | Where-Object Text -eq '100%'
        Assert ($settings.FormBorderStyle -eq 'FixedDialog' -and -not $settings.MaximizeBox) 'Settings must have a fixed window size'
        $width=$settings.Width
        [Windows.Forms.Application]::DoEvents()
        Assert ($value -and $value.Right -le $editor.Runtime.Parent.Left -and $readout.ClientRectangle.Contains($value.Bounds)) "Readout overlaps at width $width and scale $scale"
        Assert ($day.Visible -and $night.Visible -and $day.Top -eq $night.Top -and $day.Right -lt $night.Left) 'Period cards must sit side by side'
        foreach ($card in @($day,$night)) { Check-PanelBounds $card $scale }
        Assert (-not $editor.Slider.Visible -and $day.Controls.Text -contains '62%' -and $night.Controls.Text -contains '24%') 'Scheduled level labels are incorrect'
        $settings.ClientSize=[Drawing.Size]::new(720,480)
        [Windows.Forms.Application]::DoEvents()
        $content=$settings.Sections.Parent
        Assert ($content.HorizontalScroll.Visible -and $content.VerticalScroll.Visible) 'Settings must scroll when constrained by a small working area'
        Assert ($settings.RectangleToScreen($settings.ClientRectangle).Contains($close.RectangleToScreen($close.ClientRectangle))) 'Close must stay within the window on a small working area'
        $unavailable=[LocalHdrMenu.MonitorBrightness]@{Name='HDR off';DisplayId='Qg==';PreferenceKey=('B'*64);HdrOff=$true;Runtime='Manual control';Status='Enable HDR on this monitor to adjust SDR brightness.'}
        $settings.SetDisplays(@($unavailable)); $settings.SelectDisplay($unavailable.DisplayId)
        $editor=$settings.Brightness
        Assert ($editor.Slider.Visible -and -not $editor.Slider.Enabled -and -not $editor.DaySlider.Visible) 'HDR off must keep the manual slider visible and disabled'
        Assert ($editor.Status.Text -eq $unavailable.Status -and $editor.Runtime.Text -eq $unavailable.Runtime) 'The enable-HDR instruction should appear only in the status line'
        $value=$editor.Runtime.Parent.Parent.GetControlFromPosition(0,0)
        Assert ($value.Text -eq [string][char]0x2014) 'Missing brightness history should show a dash'
        $editId=[LocalHdrMenu.MonitorBrightness]::Capture($editor).EditId
        $unavailable.LastUsedLevel=3033
        $settings.SetDisplays(@($unavailable))
        Assert ($value.Text -eq '41%' -and $editor.Slider.Value -eq 41 -and -not $editor.LevelEdited -and [LocalHdrMenu.MonitorBrightness]::Capture($editor).EditId -eq $editId) 'Showing the remembered level must align the thumb without generating an edit'
        $unavailable.LastUsedLevel=1000
        $settings.SetDisplays(@($unavailable))
        Assert ($value.AccessibleName -eq 'Last used brightness 0%' -and $editor.Slider.Value -eq 0 -and -not $editor.Slider.Enabled) 'A remembered 0% must be visible and read-only'
        $unavailable.CurrentLevel=4500
        $unavailable.HdrOff=$false
        $settings.SetDisplays(@($unavailable))
        Assert ($value.AccessibleName -eq 'Manual brightness 70%' -and $editor.Slider.Enabled) 'Re-enabling HDR must restore the live level'
        $editor.LoadSettings(4100,2200,'Manual',480,1080,$false)
        $unavailable.LastUsedLevel=3500
        foreach ($off in @($true,$false)) {
            $unavailable.HdrOff=$off
            $unavailable.CurrentLevel=if ($off) { 0 } else { 4500 }
            $settings.SetDisplays(@($unavailable))
            foreach ($mode in $editor.Switching.Items) {
                $editor.Switching.SelectedItem=$mode
                $scheduled=$mode -ne 'Manual'
                if (-not $scheduled) {
                    $statusTop=$editor.Status.Top
                    $restoreTop=$editor.Restore.Parent.Top
                    $manualTrack=$editor.Slider.RectangleToScreen($editor.Slider.ClientRectangle)
                }
                Assert ($editor.Status.Top -eq $statusTop -and $editor.Restore.Parent.Top -eq $restoreTop) "Brightness section height changes in $mode (HDR off=$off, scale=$scale)"
                if ($editor.Slider.Visible) {
                    Assert ($editor.Slider.Parent.ClientRectangle.Contains($editor.Slider.Bounds)) "Main slider clipped in $mode (HDR off=$off, scale=$scale)"
                    $strip=$editor.Slider.Parent
                    $readout=$editor.Runtime.Parent.Parent
                    Assert ($strip.Height -eq $editor.Slider.Height -and $strip.Width -eq $readout.Width -and $strip.Controls.Count -eq 1) "Expected one compact, full-width slider under the percentage in $mode"
                    Assert ($editor.Slider.RectangleToScreen($editor.Slider.ClientRectangle) -eq $manualTrack) "The shared slider moved or resized in $mode (HDR off=$off, scale=$scale)"
                    Check-PanelBounds $editor.Slider.Parent $scale
                }
                Assert $editor.Switching.Enabled "Switching dropdown disabled in $mode (HDR off=$off)"
                Assert ($editor.Slider.Visible -eq ($off -or -not $scheduled) -and $editor.Slider.Enabled -eq (-not $off -and -not $scheduled)) "Wrong main slider state in $mode (HDR off=$off)"
                $percent=if ($off) { 50 } else { 70 }
                Assert ($value.Text -eq "$percent%" -and $editor.Slider.Value -eq $percent) "Readout and slider disagree in $mode (HDR off=$off)"
                Assert ($editor.DaySlider.Visible -eq $scheduled -and $editor.NightSlider.Visible -eq $scheduled -and $editor.DaySlider.Value -eq 62 -and $editor.NightSlider.Value -eq 24) "Day or Night controls changed in $mode (HDR off=$off)"
                Assert ($editor.NightLightSettings.Visible -eq ($mode -eq 'Follow Windows Night Light') -and $editor.LocationSettings.Visible -eq ($mode -eq 'Sunrise & sunset (location)')) "Wrong settings shortcut in $mode (HDR off=$off)"
                Assert ($editor.Status.Text -ne $editor.Runtime.Text) "Duplicate status in $mode (HDR off=$off)"
            }
        }
        $settings.SetDisplays(@())
        Assert ($null -eq $settings.Brightness -and $close.Visible -and $close.Enabled) 'Close must be available without a display'
    } finally { $settings.Dispose() }
}
Write-Output 'PASS: native structure sizes and brightness panel layout at 100%, 125%, 150%, and 200% scale.'
