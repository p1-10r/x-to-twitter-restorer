@echo off
setlocal
cd /d "%~dp0"
echo Twitter Blue Bird Restorer - Complete Uninstall
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Uninstall-Twitter.ps1"
set "EXIT_CODE=%ERRORLEVEL%"
echo.
if not "%EXIT_CODE%"=="0" echo Uninstall paused or failed. Read the message above and try again.
pause
exit /b %EXIT_CODE%
