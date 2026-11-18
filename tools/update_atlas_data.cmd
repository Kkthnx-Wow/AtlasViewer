@echo off
REM Refresh AtlasViewer's bundled atlas data.
REM   update_atlas_data.cmd                   use a fresh in-game /av dump, else show build status
REM   update_atlas_data.cmd --check           show current vs latest, change nothing
REM   update_atlas_data.cmd --from-client     build from the in-game /av dump
REM   update_atlas_data.cmd --web             try the web download (the site may block it)
REM Any other update_atlas_data.py option can be added after the command.
cd /d "%~dp0"
python update_atlas_data.py %*
echo.
pause
