Option Explicit
Dim shell, files, launcher
Set shell = CreateObject("WScript.Shell")
Set files = CreateObject("Scripting.FileSystemObject")
launcher = files.BuildPath(shell.ExpandEnvironmentStrings("%ProgramData%\HdrSdrMenu"), "Toggle-HdrSdr.vbs")
If Not files.FileExists(launcher) Then
    MsgBox "Install HDR Context Menu first.", 48, "HDR Context Menu"
    WScript.Quit 1
End If
shell.Run Chr(34) & shell.ExpandEnvironmentStrings("%SystemRoot%\System32\wscript.exe") & Chr(34) & " //NoLogo " & Chr(34) & launcher & Chr(34) & " Watch", 0, False
