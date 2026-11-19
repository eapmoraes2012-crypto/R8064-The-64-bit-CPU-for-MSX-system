# verify_z80.py - checks the Z80 base forms of r8isa.py (every operand combination) against sjasmplus.
# Usage: python3 verify_z80.py [path/to/sjasmplus] ; writes z80_all.asm (the test source, also used by the MSX cross-test)
import itertools, subprocess, sys, os, tempfile
from isacore import COMPILED, C_KW, C_IND, C_R8, C_XH, C_SS, C_QQ, C_XY, C_CC, C_IMM, C_MEM, C_REL, C_IDX8, C_BIT, C_RST, C_VAL, KWIDS, KWNUM
from asmref import Asm
SJ = sys.argv[1] if len(sys.argv) > 1 else 'sjasmplus'
NAME = {v: k for k, v in KWNUM.items()}
R8N = 'B C D E H L ? A'.split()
def values(c, a):
    if c == C_KW: return [NAME[a]]
    if c == C_IND: return ['(%s)' % NAME[a]] if NAME[a] != 'IX' else ['(IX)', '(IY)']
    if c == C_R8: return [R8N[i] for i in range(8) if a >> i & 1]
    if c == C_XH: return ['IXH', 'IXL', 'IYH', 'IYL']
    if c == C_SS: return ['BC', 'DE', 'HL', 'SP']
    if c == C_QQ: return ['BC', 'DE', 'HL', 'AF']
    if c == C_XY: return ['IX', 'IY']
    if c == C_CC: return [x for i, x in enumerate('NZ Z NC C PO PE P M'.split()) if a >> i & 1]
    if c == C_IMM: return {1: ['12h', '0FFh', '-1'], 2: ['1234h', '0FFFEh']}[a]
    if c == C_MEM: return {1: ['(34h)'], 2: ['(5678h)']}[a]
    if c == C_REL: return ['$+20', '$-30']
    if c == C_IDX8: return ['(IX+5)', '(IY-3)', '(IX)']
    if c == C_BIT: return [str(i) for i in range(a + 1)]
    if c == C_RST: return ['%02Xh' % i for i in range(0, 0x40, 8)]
    if c == C_VAL: return [str(a)]
    raise KeyError(c)
lines = []
for f in COMPILED:
    if f.id is not None or f.mn in ('MULUB', 'MLTUB', 'MULUW', 'MLTUW'): continue
    try: vs = [values(*p) for p in f.pats]
    except KeyError: continue
    if f.mn in ('SUB', 'AND', 'XOR', 'OR', 'CP') and f.src[0] == 'A' and len(f.src) == 2: continue   # sjasmplus reads "SUB A,B" as two instructions
    for combo in itertools.product(*vs):
        if f.same and len(set(x[:2] for x in combo if x.startswith('I'))) > 1: continue
        lines.append('        %s %s' % (f.mn, ','.join(combo)))
src = '        org 8000h\n' + '\n'.join(lines) + '\n'
here = os.path.dirname(os.path.abspath(__file__))
open(os.path.join(here, 'z80_all.asm'), 'w').write(src)
d = tempfile.mkdtemp(); p = os.path.join(d, 't.asm'); open(p, 'w').write(src)
a = Asm(p); mine = a.run()
for e in a.errors[:20]: print('asmref:', e)
r = subprocess.run([SJ, '--nologo', '--raw=' + os.path.join(d, 't.bin'), p], capture_output=True, text=True)
if r.returncode: print(r.stdout[-3000:], r.stderr[-2000:])
ref = open(os.path.join(d, 't.bin'), 'rb').read()
print('lines:', len(lines), ' bytes asmref:', len(mine), ' sjasmplus:', len(ref))
if mine == ref: print('Z80 BASE SET IDENTICAL TO SJASMPLUS'); sys.exit(0)
# locate the first differences line by line
bad = 0
for ln in lines:
    open(p, 'w').write('        org 8000h\n' + ln + '\n')
    a = Asm(p); m = a.run()
    subprocess.run([SJ, '--nologo', '--raw=' + os.path.join(d, 't.bin'), p], capture_output=True)
    r2 = open(os.path.join(d, 't.bin'), 'rb').read()
    if m != r2:
        print('DIFF %-30s asmref %s  sjasmplus %s  %s' % (ln.strip(), m.hex(' '), r2.hex(' '), a.errors)); bad += 1
        if bad > 30: break
sys.exit(1)
