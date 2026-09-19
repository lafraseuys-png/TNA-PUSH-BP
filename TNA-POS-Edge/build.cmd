@echo off
REM ===================================================================
REM  BUILD TNA-POS-Edge.exe   (run on your development PC, with internet)
REM
REM  1. Install Node.js 18 or newer
REM  2. Put a copy of the POS web files in .\web  (optional fallback):
REM       POS.html, pos.js, POSSlips.js, theme.js, css\assets.css
REM     The till downloads the current ones from the server anyway.
REM  3. Run this file. The result is dist\TNA-POS-Edge.exe
REM  4. Copy that exe to the server:  <app folder>\downloads\pos-edge\TNA-POS-Edge.exe
REM     (or set POS_EDGE_INSTALLER in .env to its path)
REM     The "Install App" button in the POS then hands it out, set up per company and till.
REM ===================================================================
setlocal
cd /d "%~dp0"

echo Installing dependencies...
call npm install || goto :fail

echo Building TNA-POS-Edge.exe...
call npx pkg . --targets node18-win-x64 --output dist\TNA-POS-Edge.exe || goto :fail

echo.
echo DONE:  %~dp0dist\TNA-POS-Edge.exe
echo Copy it to the server under downloads\pos-edge\
echo.
pause
exit /b 0

:fail
echo.
echo BUILD FAILED. Check the messages above.
pause
exit /b 1
