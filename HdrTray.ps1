# Loaded by the existing Watch action after the display API is initialized.
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
if (-not ('LocalHdrMenu.TrayMenuTheme' -as [type])) {
    Add-Type -Path (Join-Path $PSScriptRoot 'TrayTheme.cs') -ReferencedAssemblies System.Windows.Forms,System.Drawing
}

function Get-HdrTrayState($Displays) {
    $capable = @($Displays | Where-Object HdrSupported)
    $enabled = @($capable | Where-Object HdrEnabled).Count
    $status = if (-not $capable.Count) { 'HDR: Unavailable' }
        elseif ($enabled -eq $capable.Count) { 'HDR: On' }
        elseif ($enabled -eq 0) { 'HDR: Off' }
        else { 'HDR: Mixed' }
    $enableNext = $enabled -lt $capable.Count
    [pscustomobject]@{
        Status = $status
        IconState = if (-not $capable.Count) { 'Unavailable' } elseif ($enabled -gt 0) { 'Enabled' } else { 'Disabled' }
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
    if ($script:hdrTray.CurrentIconState -ne $State.IconState) {
        $script:hdrTray.Icon.Icon = switch ($State.IconState) {
            'Enabled' { $script:hdrTray.EnabledIcon }
            'Disabled' { $script:hdrTray.DisabledIcon }
            default { $script:hdrTray.UnavailableIcon }
        }
        $script:hdrTray.CurrentIconState = $State.IconState
    }
    $script:hdrTray.Command.Text = if ($State.Available) { $State.Command } else { 'Enable HDR' }
    $script:hdrTray.Command.Tag = $State.Action
    $script:hdrTray.Command.Enabled = $State.Available -and $null -eq $script:hdrTray.Pending
    $script:hdrTray.ControlsMenu.SuspendLayout()
    $script:hdrTray.Command.Available = $State.Available
    $script:hdrTray.CommandSeparator.Available = $State.Available
    $script:hdrTray.ControlsMenu.ResumeLayout($true)
    $details = $State.Details -join "`n"
    if ($details -ne $script:hdrTray.DetailsText) {
        foreach ($item in @($script:hdrTray.Displays.DropDownItems)) { $item.Dispose() }
        $script:hdrTray.Displays.DropDownItems.Clear()
        foreach ($line in $State.Details) {
            $item = New-Object LocalHdrMenu.TrayStatusItem
            $item.Text = $line
            $item.Enabled = $false
            $item.Padding = $script:hdrTray.Displays.Padding
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
            Status='HDR: Unavailable'; IconState='Unavailable'; Available=$false; Action='On'; Command='Enable HDR'; Details=@()
        })
    }
}

function Open-HdrSettings([string]$Uri) {
    try { Start-Process -FilePath $Uri | Out-Null }
    catch { $script:hdrTray.Icon.ShowBalloonTip(5000, 'HDR Context Menu', 'Windows Settings could not be opened.', [Windows.Forms.ToolTipIcon]::Warning) }
}

function Start-HdrChange([string]$NextAction) {
    if ($null -ne $script:hdrTray.Pending -or $NextAction -notin @('On','Off','Toggle')) { return }
    try {
        # Keep the menu responsive while Windows changes display mode. Use the
        # explicit action offered by the menu. Middle-click uses Toggle, which
        # reads the current Windows state in the child before choosing On/Off.
        $script:hdrTray.Pending = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList (
            '-NoLogo -NoProfile -NonInteractive -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" -Action {1}' -f $installedScript,$NextAction
        ) -WindowStyle Hidden -PassThru
        $script:hdrTray.Command.Enabled = $false
        $script:hdrTray.Command.Text = 'Changing HDR...'
    } catch {
        $script:hdrTray.Icon.ShowBalloonTip(5000, 'HDR Context Menu', 'The HDR command could not be started.', [Windows.Forms.ToolTipIcon]::Warning)
    }
}

function Show-HdrControls {
    $script:hdrTray.Menu.Close()
    # Reuse NotifyIcon's native popup handling for focus, taskbar placement,
    # keyboard navigation, and dismissal when clicking elsewhere (.NET 4.x).
    $script:hdrTray.Icon.ContextMenuStrip = $script:hdrTray.ControlsMenu
    try {
        [void]$script:hdrTray.ShowMenuMethod.Invoke($script:hdrTray.Icon, $null)
    } finally {
        $script:hdrTray.Icon.ContextMenuStrip = $script:hdrTray.Menu
    }
}

function Initialize-HdrTray {
    [Windows.Forms.Application]::EnableVisualStyles()
    $script:hdrTray = @{
        Icon = New-Object Windows.Forms.NotifyIcon
        Menu = New-Object LocalHdrMenu.TrayPopupMenu
        ControlsMenu = New-Object LocalHdrMenu.TrayPopupMenu
        ShowMenuMethod = [Windows.Forms.NotifyIcon].GetMethod('ShowContextMenu', [Reflection.BindingFlags]'Instance,NonPublic')
        Status = New-Object LocalHdrMenu.TrayStatusItem
        Command = New-Object Windows.Forms.ToolStripMenuItem
        CommandSeparator = New-Object Windows.Forms.ToolStripSeparator
        Displays = New-Object Windows.Forms.ToolStripMenuItem('Displays')
        HdrSettings = New-Object Windows.Forms.ToolStripMenuItem('HDR settings')
        DisplaySettings = New-Object Windows.Forms.ToolStripMenuItem('Display settings')
        Exit = New-Object Windows.Forms.ToolStripMenuItem('Exit')
        Timer = New-Object Windows.Forms.Timer
        EnabledIcon = [Drawing.Icon]::new((Join-Path $PSScriptRoot 'HdrEnabled.ico'), [Windows.Forms.SystemInformation]::SmallIconSize)
        DisabledIcon = [Drawing.Icon]::new((Join-Path $PSScriptRoot 'HdrDisabled.ico'), [Windows.Forms.SystemInformation]::SmallIconSize)
        UnavailableIcon = [Drawing.Icon]::new((Join-Path $PSScriptRoot 'HdrUnavailable.ico'), [Windows.Forms.SystemInformation]::SmallIconSize)
        CurrentIconState = 'Unavailable'
        MenuFont = New-Object Drawing.Font('Segoe UI',10)
        ActionFont = New-Object Drawing.Font('Segoe UI Semibold',10)
        Pending = $null
        DetailsText = $null
    }
    $script:hdrTray.Status.Enabled = $false
    $script:hdrTray.Icon.Icon = $script:hdrTray.UnavailableIcon
    $script:hdrTray.Icon.ContextMenuStrip = $script:hdrTray.Menu
    $script:hdrTray.Icon.Text = 'HDR Context Menu'
    $script:hdrTray.Menu.ShowImageMargin = $false
    $script:hdrTray.ControlsMenu.ShowImageMargin = $false
    $script:hdrTray.Menu.CenterAboveCursor = $true
    $script:hdrTray.ControlsMenu.CenterAboveCursor = $true
    [void]$script:hdrTray.ControlsMenu.Items.Add($script:hdrTray.Status)
    [void]$script:hdrTray.ControlsMenu.Items.Add($script:hdrTray.Displays)
    [void]$script:hdrTray.ControlsMenu.Items.Add($script:hdrTray.CommandSeparator)
    [void]$script:hdrTray.ControlsMenu.Items.Add($script:hdrTray.Command)
    [void]$script:hdrTray.Menu.Items.Add($script:hdrTray.HdrSettings)
    [void]$script:hdrTray.Menu.Items.Add($script:hdrTray.DisplaySettings)
    [void]$script:hdrTray.Menu.Items.Add((New-Object Windows.Forms.ToolStripSeparator))
    [void]$script:hdrTray.Menu.Items.Add($script:hdrTray.Exit)
    $script:hdrTray.Command.Name = 'HdrAction'
    $script:hdrTray.Displays.DropDown = New-Object LocalHdrMenu.TrayPopupMenu
    $script:hdrTray.Command.Font = $script:hdrTray.ActionFont
    [LocalHdrMenu.TrayMenuTheme]::Apply($script:hdrTray.Menu, $script:hdrTray.MenuFont)
    [LocalHdrMenu.TrayMenuTheme]::Apply($script:hdrTray.ControlsMenu, $script:hdrTray.MenuFont)
    [LocalHdrMenu.TrayMenuTheme]::Apply($script:hdrTray.Displays.DropDown, $script:hdrTray.MenuFont)
    $script:hdrTray.Command.add_Click({ Start-HdrChange ([string]$script:hdrTray.Command.Tag) })
    $script:hdrTray.HdrSettings.add_Click({ Open-HdrSettings 'ms-settings:display-hdr' })
    $script:hdrTray.DisplaySettings.add_Click({ Open-HdrSettings 'ms-settings:display' })
    $script:hdrTray.Icon.add_MouseClick({
        param($sender, $eventArgs)
        if ($eventArgs.Button -eq [Windows.Forms.MouseButtons]::Left) { Show-HdrControls }
        elseif ($eventArgs.Button -eq [Windows.Forms.MouseButtons]::Middle) {
            Start-HdrChange 'Toggle'
        }
    })
    $script:hdrTray.ControlsMenu.add_Opening({ Update-HdrTray })
    $script:hdrTray.Menu.add_Opening({ $script:hdrTray.ControlsMenu.Close() })
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
    $script:hdrTray.ControlsMenu.Dispose()
    $script:hdrTray.EnabledIcon.Dispose()
    $script:hdrTray.DisabledIcon.Dispose()
    $script:hdrTray.UnavailableIcon.Dispose()
    $script:hdrTray.MenuFont.Dispose()
    $script:hdrTray.ActionFont.Dispose()
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
