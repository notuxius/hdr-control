param([string]$OutputDirectory)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
Add-Type -Path (Join-Path $repo 'TrayTheme.cs') -ReferencedAssemblies System.Windows.Forms,System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
function Assert($condition,$message) { if(-not $condition) {throw $message} }
if($OutputDirectory) {[void][IO.Directory]::CreateDirectory($OutputDirectory)}
foreach($scale in @(1.0,1.25,1.5,2.0)) {
    foreach($kind in @('OK','YesNo','OKCancel','YesNoCancel','RetryCancel')) {
        $message="HDR Control`r`nVersion: 1.1.0`r`n`r`nLeft click: HDR controls`r`nRight click: Settings and app options`r`nMiddle click: Toggle HDR`r`n`r`nBy notuxius"
        $form=[LocalHdrMenu.DialogMessageForm]::new($message,[Windows.Forms.MessageBoxButtons]$kind)
        try {
            $form.ShowInTaskbar=$false; $form.StartPosition='Manual'; $form.Location=[Drawing.Point]::new(-30000,-30000)
            $form.Scale([Drawing.SizeF]::new($scale,$scale)); $form.Font=[Drawing.Font]::new('Segoe UI',[single](10*$scale))
            $form.Show(); [Windows.Forms.Application]::DoEvents()
            Assert ($form.MessageText.Text -eq $message) 'Message content changed'
            $footer=$form.AcceptButton.Parent
            foreach($button in $footer.Controls) {
                Assert ($button.Right -le $footer.ClientSize.Width -and $button.Bottom -le $footer.ClientSize.Height) 'Message button clipped at scaled size'
            }
            Assert ($form.MessageText.Width -le $form.MessageText.Parent.ClientSize.Width) 'Message text exceeds body width'
            if($OutputDirectory -and $scale -eq 1.0 -and $kind -eq 'OK') {
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
