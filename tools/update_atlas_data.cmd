@echo off
setlocal
REM Refresh AtlasViewer's bundled atlas data.
REM   update_atlas_data.cmd                   use a fresh in-game /av dump, else show build status
REM   update_atlas_data.cmd --check           show current vs latest, change nothing
REM   update_atlas_data.cmd --from-client     build from the in-game /av dump
REM   update_atlas_data.cmd --web             try the web download (the site may block it)
REM Any other update_atlas_data.py option can be added after the command.
REM Web requests are paced and cached by the script, so running this twice in a row
REM does not hit the site twice.
cd /d "%~dp0"
REM Prefer the py launcher, it skips the Microsoft Store python stub.
where py >nul 2>nul
if %errorlevel%==0 (
    py -3 update_atlas_data.py %*
) else (
    python update_atlas_data.py %*
)
set RESULT=%errorlevel%
echo.
pause
exit /b %RESULT%
