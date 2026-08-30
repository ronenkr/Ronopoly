@echo off
rem Ronopoly launcher.
rem
rem -ExecutionPolicy Bypass because this machine ships with LocalMachine set to
rem Restricted, which blocks .ps1 files outright. -STA because WPF cannot create
rem a window on an MTA thread. -NoProfile so a user profile cannot change how
rem the game behaves.
setlocal
powershell.exe -NoProfile -NoLogo -ExecutionPolicy Bypass -STA -File "%~dp0Start-Ronopoly.ps1" %*
exit /b %ERRORLEVEL%
