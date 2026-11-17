@echo off
rem Area por modulo (hierarquia preservada). Rode no terminal do OSS CAD Suite.
cd /d "%~dp0"
yosys -q -l yosys_modulos.log ys_modulos.ys
findstr /b /c:"ERROR" yosys_modulos.log && (echo SINTESE FALHOU & exit /b 1)
echo Pronto. Mande stat_modulos.txt.
