@echo off
REM One-time setup. Double-click this file, or run it from a terminal.
REM Extra arguments are passed to setup.ps1, for example:  SETUP.bat -SkipBacktest
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1" %*
echo.
pause
