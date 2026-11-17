@echo off
rem Run INSIDE the OSS CAD Suite terminal. R8064 core (uop.mem, Z80 microcode) against the reference model, instruction by instruction.
rem Uses the vectors already generated in vec\ (2 random programs with all pages + start of ZEXDOC). To generate others: gerar_vetores.sh (needs gcc and python3).
cd /d "%~dp0"
set S=..\sim
set R=..\rtl
for %%F in (uop.mem mainctrl.mem rom_ed_a.mem rom_ed_b.mem amb_idx.mem ctrl.mem ctrl_b.mem) do copy /y %S%\%%F . >nul
iverilog -g2012 -o z80core.vvp tb_z80core.v %R%\r8064_core_min.v %R%\r8064_decode.v %R%\r8064_decode_rom.v %R%\regfile64.v %R%\regmap_b.v %R%\regmerge.v %R%\alu_prep.v %R%\alu_core_s.v ..\..\03_muldiv\rtl\mul_unit.v ..\..\03_muldiv\rtl\div_unit.v ..\..\08_fpu\rtl\fpu_unit.v ..\..\08_fpu\rtl\fpu_seq.v
if errorlevel 1 (echo COMPILATION FAILED & exit /b 1)
del resultado_z80core.txt 2>nul
for %%V in (r53 r56 zex) do (
  echo --- %%V >> resultado_z80core.txt
  vvp -n z80core.vvp +hex=vec/%%V_mem.hex +trace=vec/%%V_trace.txt +fim=vec/%%V_fim.hex >> resultado_z80core.txt 2>&1
)
type resultado_z80core.txt
