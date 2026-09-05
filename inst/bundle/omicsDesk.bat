@echo off
setlocal
set "HERE=%~dp0"
set "RSCRIPT="
where Rscript >nul 2>nul && set "RSCRIPT=Rscript"
if not defined RSCRIPT (
  for /d %%D in ("%ProgramFiles%\R\R-*") do if exist "%%D\bin\Rscript.exe" set "RSCRIPT=%%D\bin\Rscript.exe"
)
if not defined RSCRIPT (
  for /d %%D in ("%LocalAppData%\Programs\R\R-*") do if exist "%%D\bin\Rscript.exe" set "RSCRIPT=%%D\bin\Rscript.exe"
)
if not defined RSCRIPT (
  echo Could not find R. Install R first - see README.md - then run this file again.
  pause
  exit /b 1
)
echo Starting omicsDesk. Keep this window open while you work; close it to stop.
"%RSCRIPT%" "%HERE%START.R"
pause
