# build_fpu.py - generates 08_fpu/rtl/fpu_top.v (with the firmware ROMs) and reincorporates the FPU modules into the core file
import os, subprocess, shutil
H = os.path.dirname(os.path.abspath(__file__)); M = os.path.join(H, '..', '..')
import fpu_macro
open(os.path.join(H, 'fpu_macro_rom.vh'), 'w').write(fpu_macro.verilog())
tpl = open(os.path.join(H, 'fpu_top_tpl.v')).read().replace('//@ROM@', fpu_macro.verilog())
open(os.path.join(M, '08_fpu/rtl/fpu_top.v'), 'w').write(tpl)
core = os.path.join(M, '10_mode_gov/rtl/r8064_core_min.v'); s = open(core).read()
s = s[:s.index('\n// ---- (incorporado de')].rstrip('\n') + '\n'
for f in ('11_fpu_stk/rtl/fpu_stk.v', '08_fpu/rtl/mul_unit.v', '08_fpu/rtl/div_unit.v', '08_fpu/rtl/fpu_alu.v', '08_fpu/rtl/fpu_half.v', '08_fpu/rtl/fpu_frem.v', '08_fpu/rtl/fpu_top.v'):
    s += '\n// ---- (incorporado de %s) ----\n' % f + open(os.path.join(M, f)).read()
open(core, 'w').write(s); shutil.copy(core, os.path.join(M, '09_core_min/rtl/r8064_core_min.v'))
print('ok', len(s))
