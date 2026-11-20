@echo off
setlocal
title WALLSTREETPRO - System start
color 0A

REM ================================================================
REM  Configuration. Set either variable in your environment before
REM  running this file to override the default.
REM ================================================================
REM Folder where the TradingView MCP server lives. setup.ps1 clones it here.
if not defined TV_MCP_REPO set "TV_MCP_REPO=%USERPROFILE%\tradingview-mcp-jackson"
REM Chrome DevTools Protocol port. The MCP server expects 9222.
set "PORT=9222"
REM This folder, wherever the repo was cloned.
set "WSP_HOME=%~dp0"

echo.
echo  ============================================================
echo   W A L L S T R E E T P R O  -  Trading analysis system
echo   Starts TradingView with the MCP bridge, runs the screener
echo   and opens Claude Code with the weekly check loaded
echo  ============================================================
echo.

REM -- 0. Preflight ------------------------------------------------
if not exist "%TV_MCP_REPO%\src\server.js" goto no_mcp
where claude >nul 2>&1
if errorlevel 1 goto no_claude
if not exist "%WSP_HOME%wiki\context.md" copy /Y "%WSP_HOME%wiki\context.example.md" "%WSP_HOME%wiki\context.md" >nul
if not exist "%WSP_HOME%wiki\index.md" copy /Y "%WSP_HOME%wiki\index.example.md" "%WSP_HOME%wiki\index.md" >nul
if not exist "%WSP_HOME%wiki\log.md" copy /Y "%WSP_HOME%wiki\log.example.md" "%WSP_HOME%wiki\log.md" >nul
if not exist "%WSP_HOME%trade_log.md" copy /Y "%WSP_HOME%trade_log.example.md" "%WSP_HOME%trade_log.md" >nul

REM -- 1. Close previous TradingView instances ---------------------
REM TradingView only exposes CDP when it is started with the debug flag,
REM so a window that is already open has to be closed first.
echo [1/5] Closing previous TradingView instances...
taskkill /F /IM TradingView.exe >nul 2>&1
timeout /t 2 /nobreak >nul

REM -- 2. Find TradingView Desktop ---------------------------------
echo [2/5] Looking for TradingView Desktop...
set "TV_EXE="

if exist "%LOCALAPPDATA%\TradingView\TradingView.exe"      set "TV_EXE=%LOCALAPPDATA%\TradingView\TradingView.exe"
if exist "%PROGRAMFILES%\TradingView\TradingView.exe"       set "TV_EXE=%PROGRAMFILES%\TradingView\TradingView.exe"
if exist "%PROGRAMFILES(x86)%\TradingView\TradingView.exe"  set "TV_EXE=%PROGRAMFILES(x86)%\TradingView\TradingView.exe"

if "%TV_EXE%"=="" (
    for /f "tokens=*" %%i in ('dir /s /b "%PROGRAMFILES%\WindowsApps\TradingView*\TradingView.exe" 2^>nul') do set "TV_EXE=%%i"
)
if "%TV_EXE%"=="" (
    for /f "tokens=*" %%i in ('where TradingView.exe 2^>nul') do set "TV_EXE=%%i"
)
if "%TV_EXE%"=="" (
    for /f "tokens=*" %%i in ('powershell -NoProfile -Command "try { $p = Get-AppxPackage -Name '*TradingView*' -EA Stop; Join-Path $p.InstallLocation 'TradingView.exe' } catch { }"') do set "TV_EXE=%%i"
)
if "%TV_EXE%"=="" goto no_tradingview

echo  Found: %TV_EXE%

REM -- 3. Launch TradingView with CDP enabled ----------------------
echo [3/5] Starting TradingView with --remote-debugging-port=%PORT%...
start "" "%TV_EXE%" --remote-debugging-port=%PORT%

echo  Waiting for CDP on localhost:%PORT%...
timeout /t 5 /nobreak >nul
set /a TRIES=0

:check
curl -s http://localhost:%PORT%/json/version >nul 2>&1
if not errorlevel 1 goto cdp_ready
set /a TRIES+=1
if %TRIES% geq 45 goto cdp_timeout
echo  Still starting...
timeout /t 2 /nobreak >nul
goto check

:cdp_ready
echo.
echo  CDP ready on http://localhost:%PORT%
echo.

REM -- 4. Wide-funnel screener -------------------------------------
echo [4/5] Running the screener against the TradingView scanner API...
cd /d "%WSP_HOME%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%WSP_HOME%screener.ps1"
echo.

REM -- 5. Open Claude Code with the weekly check as the first message
echo [5/5] Opening Claude Code in %WSP_HOME%
start "" cmd /k claude "Read daily_brief.md and run it end to end"

exit /b 0

:no_mcp
echo.
echo  [ERROR] TradingView MCP server not found at:
echo    %TV_MCP_REPO%\src\server.js
echo  Run SETUP.bat once, or set TV_MCP_REPO to the folder where you cloned it.
echo.
pause
exit /b 1

:no_claude
echo.
echo  [ERROR] The "claude" command is not on PATH.
echo  Install Claude Code, open a new terminal and run SETUP.bat again.
echo.
pause
exit /b 1

:no_tradingview
echo.
echo  [ERROR] TradingView Desktop not found.
echo  Install it from https://www.tradingview.com/desktop/
echo  or start it by hand with:
echo    "C:\path\to\TradingView.exe" --remote-debugging-port=%PORT%
echo.
pause
exit /b 1

:cdp_timeout
echo.
echo  [ERROR] TradingView did not open the CDP port after 90 seconds.
echo  Close every TradingView window and run this file again.
echo.
pause
exit /b 1
