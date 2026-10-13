@echo off
rem Compatibility: the old Remove command now launches the complete uninstaller.
call "%~dp0Start-Twitter-Uninstall-All.cmd"
exit /b %ERRORLEVEL%
