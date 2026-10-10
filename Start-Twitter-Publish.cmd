@echo off
setlocal
cd /d "%~dp0"
echo GitHub destination: p1-10r/x-to-twitter-restorer
echo Press ENTER to accept the default, or type the repository name.
set /p "REPO=Repository [p1-10r/x-to-twitter-restorer]: "
if "%REPO%"=="" set "REPO=p1-10r/x-to-twitter-restorer"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Publish-Twitter-GitHub.ps1" -Repository "%REPO%"
set "EXIT_CODE=%ERRORLEVEL%"
echo.
if not "%EXIT_CODE%"=="0" echo Publishing failed: error code %EXIT_CODE%.
pause
exit /b %EXIT_CODE%
