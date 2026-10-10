@echo off
setlocal
cd /d "%~dp0"
echo Downloading latest Twitter Restorer from p1-10r/x-to-twitter-restorer...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Bootstrap-Twitter.ps1" -Repository "p1-10r/x-to-twitter-restorer"
set "EXIT_CODE=%ERRORLEVEL%"
echo.
if not "%EXIT_CODE%"=="0" echo Bootstrap failed: error code %EXIT_CODE%.
pause
exit /b %EXIT_CODE%
