@echo off
rem Synthesis + place and route of the R8064 cartridge in Gowin EDA (Education is enough for the GW2AR-18).
rem Finds gw_sh.exe in C:\Gowin\*\IDE\bin; or set GWSH=full path of gw_sh.exe before running.
cd /d "%~dp0"
if not defined GWSH for /d %%D in ("C:\Gowin\*") do if exist "%%D\IDE\bin\gw_sh.exe" set "GWSH=%%D\IDE\bin\gw_sh.exe"
if not defined GWSH (echo gw_sh.exe not found: set GWSH=C:\...\IDE\bin\gw_sh.exe & exit /b 1)
echo Using %GWSH%
"%GWSH%" gowin_build.tcl > gowin_build.log 2>&1
echo Done (exit %errorlevel%). Send gowin_build.log and the proj\impl\pnr\*.rpt.txt and *timing*.rpt / *.tr files.
