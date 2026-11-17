@echo off
rem Run INSIDE the OSS CAD Suite terminal. COMPACT arithmetic core of the FPU (rtl\fpu_seq.v, the one wired to the core since REV41),
rem against the 39,000 vectors of the exact model (ref\fpref.py): sim\vetores.txt.
cd /d "%~dp0sim"
iverilog -g2012 -o seq.vvp tb_seq.v ..\rtl\fpu_seq.v
if errorlevel 1 (echo COMPILATION FAILED & exit /b 1)
vvp -n seq.vvp
