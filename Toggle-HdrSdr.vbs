Option Explicit
Dim shell, files, folder, script, powershell, command, result, action
Set shell = CreateObject("WScript.Shell")
Set files = CreateObject("Scripting.FileSystemObject")
folder = files.GetParentFolderName(WScript.ScriptFullName)
script = files.BuildPath(folder, "HdrSdrMenu.ps1")
powershell = shell.ExpandEnvironmentStrings("%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe")
action = "Toggle"
If WScript.Arguments.Count > 0 Then action = WScript.Arguments(0)
Select Case action
    Case "Toggle", "On", "Off", "Watch", "Sync"
    Case Else: WScript.Quit 2
End Select
command = Chr(34) & powershell & Chr(34) & " -NoLogo -NoProfile -NonInteractive -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File " & Chr(34) & script & Chr(34) & " -Action " & action
If action <> "Watch" Then command = command & " -ShowError"
result = shell.Run(command, 0, True)
WScript.Quit result
