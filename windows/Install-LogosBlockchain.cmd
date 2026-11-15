@echo off
rem Double-click to set up the Logos Blockchain node + UI in Logos Basecamp (unofficial Windows build).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-LogosBlockchain.ps1" %*
echo.
pause
