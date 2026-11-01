@echo off
setlocal
REM ----------- launch GUI ----------
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0StoryTold-GUI.ps1"
echo.
echo Installer window closed. If it closed unexpectedly, copy any error above.
pause
REM -----------------------------
