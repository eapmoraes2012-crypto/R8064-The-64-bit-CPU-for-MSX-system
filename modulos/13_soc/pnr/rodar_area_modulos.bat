@echo off
rem Area per module (hierarchy preserved). Run in the OSS CAD Suite terminal.
cd /d "%~dp0"
yosys -q -l yosys_modulos.log ys_modulos.ys
findstr /b /c:"ERROR" yosys_modulos.log && (echo SYNTHESIS FAILED & exit /b 1)
echo Done. Send stat_modulos.txt.
