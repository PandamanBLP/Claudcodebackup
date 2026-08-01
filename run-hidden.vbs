' run-hidden.vbs — launches a PowerShell script with NO visible window.
' Scheduled tasks call this instead of powershell.exe directly, so there is
' no split-second console flash on screen. Arg 0 = full path to the .ps1.
Option Explicit
Dim shell, ps1, cmd
Set shell = CreateObject("WScript.Shell")
If WScript.Arguments.Count < 1 Then WScript.Quit 1
ps1 = WScript.Arguments(0)
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & ps1 & """"
' Second arg 0 = hidden window; third arg False = don't wait.
shell.Run cmd, 0, False
