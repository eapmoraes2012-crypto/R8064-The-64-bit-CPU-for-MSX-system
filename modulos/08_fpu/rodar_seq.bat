@echo off
rem Rode DENTRO do terminal do OSS CAD Suite. Nucleo aritmetico COMPACTO da FPU (rtl\fpu_seq.v, o que esta ligado ao nucleo desde a REV41),
rem contra os 39.000 vetores do modelo exato (ref\fpref.py): sim\vetores.txt.
cd /d "%~dp0sim"
iverilog -g2012 -o seq.vvp tb_seq.v ..\rtl\fpu_seq.v
if errorlevel 1 (echo COMPILACAO FALHOU & exit /b 1)
vvp -n seq.vvp
