# crosstest.py - assembles test sources with R8064AS.COM (Z80 code, run in the msxsim MSX-DOS model) and with the
# host reference asmref.py, and compares the BIN files and the error lists line by line.
# Usage: python3 crosstest.py <msxsim> <R8064AS.COM> <work dir>
import sys, os, subprocess, shutil, itertools, re
from isacore import COMPILED, CANDS, C_KW, C_IND, C_R8, C_XH, C_SS, C_QQ, C_XY, C_RR, C_INDRR, C_U4, C_CC, C_IMM, C_MEM, C_REL, C_IDX8, C_IDXQ, C_BIT, C_ST, C_RST, C_VAL, KWNUM
from asmref import Asm
SIM, COM, W = sys.argv[1], sys.argv[2], sys.argv[3]
HERE = os.path.dirname(os.path.abspath(__file__))
os.makedirs(W, exist_ok=True); shutil.copy(COM, os.path.join(W, 'R8064AS.COM'))
NAME = {v: k for k, v in KWNUM.items()}
RRN = {0: ['BC', 'QBC', 'LBC'], 2: ['DE', 'QDE'], 3: ['IY', 'QIY'], 4: ['HL', 'QHL', 'LHL'], 5: ['IX', 'LIX'], 7: ['AX', 'QAX', 'LAX', 'EA', 'QA']}
BANKN = {1: {0: 'N0', 2: 'N1', 4: 'N2', 7: 'N3'}, 2: {0: 'N4', 2: 'N5', 4: 'N6', 7: 'N7'}, 3: {0: "BC'", 2: "DE'", 4: "HL'", 7: "AX'"}}
R8N = 'B C D E H L ? A'.split()

def ext_lines():
    out = []
    for f in COMPILED:
        if f.id is None: continue
        def vals(c, a, bank=0):
            if c == C_KW: return [NAME[a]]
            if c == C_IND: return ['(%s)' % NAME[a]]
            if c == C_R8: return [R8N[i] for i in range(8) if a >> i & 1]
            if c in (C_RR, C_INDRR):
                v = []
                for code in range(8):
                    if not a >> code & 1: continue
                    if bank and code not in (3, 5): v.append(BANKN[bank][code])
                    elif not bank: v += RRN[code][:2]
                    else: v.append(RRN[code][0])
                return ['(%s)' % x for x in v] if c == C_INDRR else v
            if c == C_U4: return ['(BC)', '(DE)', '(HL)', '(AX)']
            if c == C_CC: return [x for i, x in enumerate('NZ Z NC C PO PE P M'.split()) if a >> i & 1]
            if c == C_ST: return ['ST%d' % i for i in range(8)]
            if c == C_IMM: return {1: ['12h', '-5'], 2: ['1234h', '-2'], 4: ['12345678h', '-100000h'], 8: ['1122334455667788h', '-1', 'start']}[a]
            if c == C_MEM: return {8: ['(123456789ABCh)', '(start+8)']}[a]
            if c == C_REL: return ['start', '$+300h', '$-100h']
            if c == C_IDXQ: return ['(QIX+1234h)', '(QIY-2)', '(IX)', '(QIY+7FFFh)']
            if c == C_BIT: return [str(i) for i in range(a + 1)]
            if c == C_VAL: return [str(a)]
            raise KeyError(c)
        banks = [0] + ([1, 2, 3] if f.bank and any(p[0] in (C_RR, C_INDRR) for p in f.pats) else [])
        for b in banks:
            vs = [vals(c, a, b) for c, a in f.pats]
            combos = list(itertools.product(*vs))
            if b:   # banked forms need at least one banked register
                combos = [c for c in combos if any(x.strip('()') in BANKN[b].values() for x in c)]
            for cmb in combos[:400]:
                out.append('        %s %s' % (f.mn, ','.join(cmb)))
    return out

def run(name, src, files={}):
    d = os.path.join(W, name); os.makedirs(d, exist_ok=True)
    shutil.copy(COM, os.path.join(d, 'R8064AS.COM'))
    open(os.path.join(d, 'TEST.ASM'), 'w').write(src)
    for fn, t in files.items(): open(os.path.join(d, fn), 'w').write(t)
    for fn in ('TEST.BIN',):
        if os.path.exists(os.path.join(d, fn)): os.remove(os.path.join(d, fn))
    r = subprocess.run([SIM, 'R8064AS.COM', 'TEST', '/L'], cwd=d, capture_output=True, text=True)
    zerr = [l.strip() for l in r.stdout.splitlines() if re.match(r'^[A-Z0-9_]+\.[A-Z]*\(\d+\): ', l.strip())]
    zbin = open(os.path.join(d, 'TEST.BIN'), 'rb').read() if os.path.exists(os.path.join(d, 'TEST.BIN')) else b''
    a = Asm(os.path.join(d, 'TEST.ASM')); pbin = bytes(a.run())
    perr = [e.replace('test.asm', 'TEST.ASM').upper().replace('TEST.ASM', 'TEST.ASM') for e in a.errors]
    perr = [re.sub(r'^([^(]*)\((\d+)\): (.*)$', lambda m: '%s(%s): %s' % (m.group(1).upper(), m.group(2), m.group(3).lower()), e) for e in a.errors]
    zerr2 = [re.sub(r'^([^(]*)\((\d+)\): (.*)$', lambda m: '%s(%s): %s' % (m.group(1), m.group(2), m.group(3).lower()), e) for e in zerr]
    ok = (zbin == pbin) and (zerr2 == perr)
    t = re.search(r'([\d.]+) s at 3.58', r.stderr)
    print('%-12s %-4s lines %5d  bytes %6d  errors %3d  MSX time %s s' % (name, 'OK' if ok else 'FAIL', src.count('\n'), len(pbin), len(perr), t.group(1) if t else '?'))
    if not ok:
        if zbin != pbin:
            n = next((i for i in range(min(len(zbin), len(pbin))) if zbin[i] != pbin[i]), min(len(zbin), len(pbin)))
            print('   BIN differs at offset %d (Z80 %d bytes, ref %d bytes)' % (n, len(zbin), len(pbin)))
            print('   Z80:', zbin[n:n + 16].hex(' ')); print('   ref:', pbin[n:n + 16].hex(' '))
        for x, y in itertools.zip_longest(zerr2, perr):
            if x != y: print('   err Z80: %s\n       ref: %s' % (x, y))
        print(r.stdout[-1500:])
    return ok

if __name__ == '__main__':
    allok = True
    z80 = open(os.path.join(HERE, 'z80_all.asm')).read()
    allok &= run('z80', z80)
    allok &= run('ext', '        org 4000h\nstart:\n' + '\n'.join(ext_lines()) + '\n')
    for fn in sorted(os.listdir(os.path.join(HERE, 'tests'))):
        if fn.endswith('.asm'):
            inc = {}
            for g in os.listdir(os.path.join(HERE, 'tests')):
                if g.endswith('.inc'): inc[g.upper()] = open(os.path.join(HERE, 'tests', g)).read()
            allok &= run(fn[:-4], open(os.path.join(HERE, 'tests', fn)).read(), inc)
    print('ALL TESTS PASSED' if allok else 'SOME TESTS FAILED')
    sys.exit(0 if allok else 1)
