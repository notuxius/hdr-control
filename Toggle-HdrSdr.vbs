Option Explicit
Dim shell, files, folder, script, powershell, command, result, action
Set shell = CreateObject("WScript.Shell")
Set files = CreateObject("Scripting.FileSystemObject")
folder = files.GetParentFolderName(WScript.ScriptFullName)
script = files.BuildPath(folder, "HdrSdrMenu.ps1")
powershell = shell.ExpandEnvironmentStrings("%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe")
action = "Toggle"
If WScript.Arguments.Count > 0 Then action = WScript.Arguments(0)
Dim updateComplete
If action = "Startup" Then
    If WScript.Arguments.Count = 2 Then updateComplete = (WScript.Arguments(1) = "UpdateComplete")
    ' Missing preference means enabled. Explicit launches always bypass it.
    Dim startupEnabled
    startupEnabled = 1
    On Error Resume Next
    startupEnabled = shell.RegRead("HKCU\Software\HdrContextMenu\StartWithWindows")
    On Error GoTo 0
    If startupEnabled = 0 Then
        If WScript.Arguments.Count < 2 Then WScript.Quit 0
        If WScript.Arguments(1) <> "LaunchNow" And Not updateComplete Then WScript.Quit 0
    End If
    action = "Watch"
End If
Dim openAbout, installOffer, pattern
If action = "Notification" Then
    If WScript.Arguments.Count <> 2 Then WScript.Quit 2
    If WScript.Arguments(1) = "notuxius-hdr-control:about" Then
        action = "OpenAbout"
    Else
        Set pattern = New RegExp
        pattern.Pattern = "^notuxius-hdr-control:install/([a-f0-9]{32})$"
        If Not pattern.Test(WScript.Arguments(1)) Then WScript.Quit 2
        installOffer = pattern.Execute(WScript.Arguments(1))(0).SubMatches(0)
        action = "Watch"
    End If
End If
openAbout = (action = "OpenAbout")
If openAbout Then action = "Watch"
Select Case action
    Case "Toggle", "On", "Off", "Watch", "Sync", "Launch"
    Case Else: WScript.Quit 2
End Select
command = Chr(34) & powershell & Chr(34) & " -NoLogo -NoProfile -NonInteractive -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File " & Chr(34) & script & Chr(34) & " -Action " & action
If openAbout Then command = command & " -OpenAbout"
If updateComplete Then command = command & " -UpdateComplete"
If Len(installOffer) > 0 Then command = command & " -InstallOffer " & installOffer
If action = "Launch" Then
    If WScript.Arguments.Count <> 2 Then WScript.Quit 2
    Set pattern = New RegExp
    pattern.Pattern = "^[a-f0-9]{32}$"
    If Not pattern.Test(WScript.Arguments(1)) Then WScript.Quit 2
    command = command & " -LaunchId " & WScript.Arguments(1)
End If
If action <> "Watch" Then command = command & " -ShowError"
result = shell.Run(command, 0, True)
WScript.Quit result
