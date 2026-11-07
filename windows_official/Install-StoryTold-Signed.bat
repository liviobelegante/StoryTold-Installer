@echo off
setlocal
rem Prefer native PowerShell when this BAT is launched from a 32-bit application.
set "ST_POWERSHELL=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "ST_POWERSHELL=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%ST_POWERSHELL%" goto host_error
"%ST_POWERSHELL%" -NoLogo -NoProfile -Command "if ($PSVersionTable.PSVersion -lt [version]'5.1') {exit 1}" >nul 2>&1
if errorlevel 1 goto host_error
for %%F in (Start-StoryTold.ps1 StoryTold-Installer.ps1 Installer-Storage.ps1 Installer-Prerequisites.ps1 Installer-Progress.ps1 SolidCraft-Source.ps1) do if not exist "%~dp0%%F" goto files_error
start "" "%ST_POWERSHELL%" -NoLogo -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0Start-StoryTold.ps1"
exit /b

:host_error
echo Windows PowerShell 5.1 could not start. Restore Windows PowerShell and .NET Framework using Windows Update or Windows component repair, then retry.
pause
exit /b 1

:files_error
echo Installer files are missing. Extract the entire windows_official folder, then retry.
pause
exit /b 1
