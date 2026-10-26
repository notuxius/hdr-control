# Loaded by the existing Watch action after the display API is initialized.
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

function Get-HdrTrayState($Displays) {
    $capable = @($Displays | Where-Object HdrSupported)
    $enabled = @($capable | Where-Object HdrEnabled).Count
    $status = if (-not $capable.Count) { 'HDR unavailable' }
        elseif ($enabled -eq $capable.Count) { 'HDR: On' }
        elseif ($enabled -eq 0) { 'HDR: Off' }
        else { 'HDR: Mixed' }
    $enableNext = $enabled -lt $capable.Count
    [pscustomobject]@{
        Status = $status
        Command = if ($enableNext) { 'Enable HDR' } else { 'Disable HDR' }
        Action = if ($enableNext) { 'On' } else { 'Off' }
        Available = $capable.Count -gt 0
        Details = @($Displays | ForEach-Object {
            $mode = if (-not $_.HdrSupported) { 'HDR unsupported' }
                elseif ($_.HdrEnabled) { 'HDR on' } else { 'HDR off' }
            $_.Name + ': ' + $mode
        })
    }
}

function Set-HdrTrayState($State) {
    $script:hdrTray.Status.Text = $State.Status
    $script:hdrTray.Icon.Text = 'HDR Context Menu - ' + $State.Status
    $script:hdrTray.Command.Text = if ($State.Available) { $State.Command } else { 'Enable HDR' }
    $script:hdrTray.Command.Tag = $State.Action
    $script:hdrTray.Command.Enabled = $State.Available -and $null -eq $script:hdrTray.Pending
    $details = $State.Details -join "`n"
    if ($details -ne $script:hdrTray.DetailsText) {
        foreach ($item in @($script:hdrTray.Displays.DropDownItems)) { $item.Dispose() }
        $script:hdrTray.Displays.DropDownItems.Clear()
        foreach ($line in $State.Details) {
            $item = New-Object Windows.Forms.ToolStripMenuItem
            $item.Text = $line
            $item.Enabled = $false
            [void]$script:hdrTray.Displays.DropDownItems.Add($item)
        }
        $script:hdrTray.DetailsText = $details
    }
    $script:hdrTray.Displays.Enabled = $State.Details.Count -gt 0
    if ($null -ne $script:hdrTray.Pending) { $script:hdrTray.Command.Text = 'Changing HDR...' }
}

function Update-HdrTray {
    try {
        if ($null -ne $script:hdrTray.Pending -and $script:hdrTray.Pending.HasExited) {
            if ($script:hdrTray.Pending.ExitCode -ne 0) {
                $script:hdrTray.Icon.ShowBalloonTip(5000, 'HDR Context Menu', 'Windows could not change HDR. Check HDR settings and try again.', [Windows.Forms.ToolTipIcon]::Warning)
            }
            $script:hdrTray.Pending.Dispose()
            $script:hdrTray.Pending = $null
        }
        $displays = @([LocalHdrMenu.DisplayApi]::Read())
        Set-HdrTrayState (Get-HdrTrayState $displays)
        # A transient file/registry failure must not stop the tray or its timer.
        try { Sync-HdrMenu $displays } catch { }
    } catch {
        Set-HdrTrayState ([pscustomobject]@{
            Status='HDR: Status unavailable'; Available=$false; Action='On'; Command='Enable HDR'; Details=@()
        })
    }
}

function Open-HdrSettings([string]$Uri) {
    try { Start-Process -FilePath $Uri | Out-Null }
    catch { $script:hdrTray.Icon.ShowBalloonTip(5000, 'HDR Context Menu', 'Windows Settings could not be opened.', [Windows.Forms.ToolTipIcon]::Warning) }
}

function Start-HdrChange([string]$NextAction) {
    if ($null -ne $script:hdrTray.Pending -or $NextAction -notin @('On','Off')) { return }
    try {
        # Keep the menu responsive while Windows changes display mode. Use the
        # explicit action offered by the menu, never a possibly stale toggle.
        $script:hdrTray.Pending = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList (
            '-NoLogo -NoProfile -NonInteractive -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" -Action {1}' -f $installedScript,$NextAction
        ) -WindowStyle Hidden -PassThru
        $script:hdrTray.Command.Enabled = $false
        $script:hdrTray.Command.Text = 'Changing HDR...'
    } catch {
        $script:hdrTray.Icon.ShowBalloonTip(5000, 'HDR Context Menu', 'The HDR command could not be started.', [Windows.Forms.ToolTipIcon]::Warning)
    }
}

function Initialize-HdrTray {
    [Windows.Forms.Application]::EnableVisualStyles()
    $script:hdrTray = @{
        Icon = New-Object Windows.Forms.NotifyIcon
        Menu = New-Object Windows.Forms.ContextMenuStrip
        Status = New-Object Windows.Forms.ToolStripMenuItem
        Command = New-Object Windows.Forms.ToolStripMenuItem
        Displays = New-Object Windows.Forms.ToolStripMenuItem('Displays')
        HdrSettings = New-Object Windows.Forms.ToolStripMenuItem('HDR settings')
        DisplaySettings = New-Object Windows.Forms.ToolStripMenuItem('Display settings')
        Exit = New-Object Windows.Forms.ToolStripMenuItem('Exit')
        Timer = New-Object Windows.Forms.Timer
        IconResource = New-Object Drawing.Icon($installedIcon)
        Pending = $null
        DetailsText = $null
    }
    $script:hdrTray.Status.Enabled = $false
    $script:hdrTray.Icon.Icon = $script:hdrTray.IconResource
    $script:hdrTray.Icon.ContextMenuStrip = $script:hdrTray.Menu
    $script:hdrTray.Icon.Text = 'HDR Context Menu'
    $script:hdrTray.Menu.ShowImageMargin = $false
    [void]$script:hdrTray.Menu.Items.Add($script:hdrTray.Status)
    [void]$script:hdrTray.Menu.Items.Add($script:hdrTray.Displays)
    [void]$script:hdrTray.Menu.Items.Add((New-Object Windows.Forms.ToolStripSeparator))
    [void]$script:hdrTray.Menu.Items.Add($script:hdrTray.Command)
    [void]$script:hdrTray.Menu.Items.Add((New-Object Windows.Forms.ToolStripSeparator))
    [void]$script:hdrTray.Menu.Items.Add($script:hdrTray.HdrSettings)
    [void]$script:hdrTray.Menu.Items.Add($script:hdrTray.DisplaySettings)
    [void]$script:hdrTray.Menu.Items.Add((New-Object Windows.Forms.ToolStripSeparator))
    [void]$script:hdrTray.Menu.Items.Add($script:hdrTray.Exit)
    $script:hdrTray.Command.add_Click({ Start-HdrChange ([string]$script:hdrTray.Command.Tag) })
    $script:hdrTray.HdrSettings.add_Click({ Open-HdrSettings 'ms-settings:display-advancedcolor' })
    $script:hdrTray.DisplaySettings.add_Click({ Open-HdrSettings 'ms-settings:display' })
    $script:hdrTray.Icon.add_DoubleClick({ Open-HdrSettings 'ms-settings:display-advancedcolor' })
    $script:hdrTray.Menu.add_Opening({ Update-HdrTray })
    $script:hdrTray.Exit.add_Click({ [Windows.Forms.Application]::ExitThread() })
    $script:hdrTray.Timer.Interval = 2000
    $script:hdrTray.Timer.add_Tick({
        if (-not (Test-Path -LiteralPath $installedScript)) { [Windows.Forms.Application]::ExitThread(); return }
        Update-HdrTray
    })
}

function Close-HdrTray {
    $script:hdrTray.Timer.Stop()
    $script:hdrTray.Icon.Visible = $false
    $script:hdrTray.Timer.Dispose()
    $script:hdrTray.Icon.Dispose()
    $script:hdrTray.Menu.Dispose()
    $script:hdrTray.IconResource.Dispose()
    if ($null -ne $script:hdrTray.Pending) { $script:hdrTray.Pending.Dispose() }
}

function Start-HdrTray {
    Initialize-HdrTray
    try {
        Update-HdrTray
        $script:hdrTray.Icon.Visible = $true
        $script:hdrTray.Timer.Start()
        [Windows.Forms.Application]::Run()
    } finally { Close-HdrTray }
}
