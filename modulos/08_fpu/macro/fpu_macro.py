# fpu_macro.py - FPU "firmware" for the transcendental instructions (FSIN FCOS FSINC FTAN FLN FYL2X FYL2P FREM FREM1).
# A macro sequencer inside fpu_top executes this ROM of 16-bit words using the existing stack/arithmetic commands (no CORDIC).
# This file: (1) constant table, (2) assembler, (3) programs, (4) interpreter in Python (bit-exact model of the RTL), (5) generator of the Verilog ROMs.
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'ref'))
import fpref
from fractions import Fraction as F
M64 = (1 << 64) - 1
# ---------------- constants (80 bits, rounded to 64 mantissa bits) ----------------
SC = 1 << 500
def atan_inv(n):
    s = 0; t = SC // n; k = 0; n2 = n * n
    while t: s += (t // (2 * k + 1)) * (1 if k % 2 == 0 else -1); t //= n2; k += 1
    return s
PI = F(16 * atan_inv(5) - 4 * atan_inv(239), SC)
LN2 = F(sum(SC // (k * (1 << k)) for k in range(1, 520)), SC)
def isqrt_f(v, bits=500):
    from math import isqrt
    return F(isqrt(int(v * (1 << (2 * bits)))), 1 << bits)
SQRT2 = isqrt_f(F(2))
def pk(v):
    v = F(v)
    if v == 0: return 0
    s = 1 if v < 0 else 0
    return fpref.round_to(s, abs(v), 0, 64, fpref.EMIN, fpref.EMAX, 80)[0]
def fact(n):
    r = 1
    for i in range(2, n + 1): r *= i
    return r
HP = PI / 2
P1 = F(int(HP * (1 << 31)), 1 << 31)
P2 = F(int((HP - P1) * (1 << 63)), 1 << 63)
P3 = HP - P1 - P2
KN = {}; KLIST = []
def K(name, v80): KN[name] = len(KN); KLIST.append(v80)
K('ZERO', 0); K('ONE', pk(1)); K('HALF', pk(F(1, 2))); K('TWO', pk(2)); K('TWO64', pk(1 << 64))
K('INDEF', fpref.INDEF); K('NINF', (1 << 79) | (0x7FFF << 64) | (1 << 63))
K('SQRT2', pk(SQRT2)); K('LN2', pk(LN2)); K('LOG2E', pk(1 / LN2)); K('2OPI', pk(2 / PI))
K('P1', pk(P1)); K('P2', pk(P2)); K('P3', pk(P3))
for k in range(1, 10): K('S%d' % k, pk(F((-1) ** k, fact(2 * k + 1))))
for k in range(1, 10): K('C%d' % k, pk(F((-1) ** k, fact(2 * k))))
for k in range(1, 13): K('A%d' % k, pk(F(1, 2 * k + 1)))
assert len(KLIST) <= 64
# ---------------- montador ----------------
KIND = dict(CMD=0, KLD=1, PRED=2, JMP=3, JSR=4, RET=5, END=6, KQ=7, XTR=8, FLG=9, FREM=10, SETDN=11, XINC=12, CC=13)
CMDN = dict(FILD=6, ADD=14, SUB=15, MUL=16, DIV=17, FCOM=19, FCHS=21, FABS=22, FXCH=23, FLD=24, FSTP=25, FRINT=26, POP=27, FIST=38,
            ADDST=48, SUBST=49, MULST=50, DIVST=51)
PRED = dict(kq0=0, kq1=1, kq01=2, nanu=3, inf=4, zero=5, neg=6, den=7, big=8, less=9, small=10, nanu1=11, inf1=12, zero1=13, dn=14)
prog = []; labels = {}; fix = []
def lab(n): labels[n] = len(prog)
def emit(kind, arg=0, cond=0): prog.append((cond, KIND[kind], arg))
def cmd(n, idx=0, cond=0): emit('CMD', CMDN[n] | (idx << 6), cond)
def kld(n, cond=0): emit('KLD', KN[n], cond)
def pred(n): emit('PRED', PRED[n])
def jmp(l, cond=0): fix.append((len(prog), l)); emit('JMP', 0, cond)
def jsr(l): fix.append((len(prog), l)); emit('JSR', 0)
def horner(coefs):
    """empilha a maior constante e aplica p = p*x + c_k (x em ST1)"""
    kld(coefs[0])
    for c in coefs[1:]:
        cmd('MUL', 1); kld(c); cmd('ADD', 1); cmd('FSTP', 1)
SK = ['S%d' % k for k in range(9, 0, -1)]; CK = ['C%d' % k for k in range(9, 0, -1)]; AK = ['A%d' % k for k in range(12, 0, -1)] + ['ONE']
ENTRY = {}
# ---- TRIGCORE: input [x] (finite, |x| < 2^30, non-zero); output [cos r, sin r] and kq = k mod 4
lab('TRIGCORE')
kld('2OPI'); cmd('MUL', 1); cmd('FRINT'); cmd('FIST'); emit('KQ')
for pn in ('P1', 'P2', 'P3'): kld(pn); cmd('MUL', 1); cmd('SUBST', 2); cmd('POP')
cmd('POP')                                                   # [r]
cmd('FLD', 0); cmd('MUL', 1)                                 # [z, r]
horner(SK); cmd('MUL', 1); cmd('MUL', 2); cmd('ADD', 2)      # [s, z, r]
cmd('FXCH', 2); cmd('POP')                                   # [z, s]
horner(CK); cmd('MUL', 1); kld('ONE'); cmd('ADD', 1); cmd('FSTP', 1)   # [c, z, s]
cmd('FXCH', 1); cmd('POP'); emit('RET')                      # [c, s]
def nan_res(): kld('ZERO'); cmd('ADDST', 1); cmd('POP')      # ST0 := ST0 + 0 (quiet NaN / unsupported -> undefined)
def trig(name, ep):
    lab(name); ENTRY[name] = labels[name]
    pred('nanu'); jmp(name + '_nan', 1); pred('inf'); jmp(name + '_inf', 1); pred('zero'); jmp(name + '_zero', 1); pred('big'); jmp(name + '_big', 1)
    jsr('TRIGCORE'); ep(); emit('CC', 0); emit('END')
    lab(name + '_nan'); nan_res()
    if name == 'FSINC': cmd('FLD', 0)
    emit('CC', 0); emit('END')
    lab(name + '_inf'); kld('INDEF'); cmd('FSTP', 1); emit('FLG', 1)
    if name == 'FSINC': cmd('FLD', 0)
    emit('CC', 0); emit('END')
    lab(name + '_zero')
    if name == 'FCOS': kld('ONE'); cmd('FSTP', 1)
    if name == 'FSINC': kld('ONE'); cmd('FXCH', 1)
    emit('CC', 0); emit('END')
    lab(name + '_big'); emit('CC', 4); emit('END')            # reducao incompleta: C2 = 1, ST0 inalterado
def ep_sin():
    pred('kq0'); cmd('FXCH', 1, 2); cmd('FSTP', 1); pred('kq1'); cmd('FCHS', 0, 1)
def ep_cos():
    pred('kq0'); cmd('FXCH', 1, 1); cmd('FSTP', 1); pred('kq01'); cmd('FCHS', 0, 1)
def ep_tan():
    pred('kq0'); cmd('FXCH', 1, 2); cmd('DIV', 1); cmd('FSTP', 1); pred('kq0'); cmd('FCHS', 0, 1)
def ep_sinc():
    pred('kq0'); cmd('FXCH', 1, 2); pred('kq1'); cmd('FCHS', 0, 1); cmd('FXCH', 1); pred('kq01'); cmd('FCHS', 0, 1); cmd('FXCH', 1)
trig('FSIN', ep_sin); trig('FCOS', ep_cos); trig('FTAN', ep_tan); trig('FSINC', ep_sinc)
# ---- logaritmos: LOGPOLY [z] -> [2 z (1 + w/3 + ...)], w = z^2
def logpoly():
    cmd('FLD', 0); cmd('MUL', 1)                              # [w, z]
    horner(AK); cmd('MUL', 2); cmd('ADD', 0); cmd('FSTP', 2); cmd('POP')   # [lnm]
lab('LOGCORE')                                               # [x] finito > 0 -> [ln m], xin = e
pred('den'); emit('SETDN', 1, 1); kld('TWO64', 1); cmd('MUL', 1, 1); cmd('FSTP', 1, 1)
emit('XTR'); kld('SQRT2'); cmd('FCOM', 1); cmd('POP')
pred('less'); kld('HALF', 1); cmd('MUL', 1, 1); cmd('FSTP', 1, 1); emit('XINC', 0, 1)
cmd('FLD', 0); kld('ONE'); cmd('SUBST', 2); cmd('ADD', 1); cmd('DIVST', 2); cmd('POP'); cmd('POP')   # [z]
logpoly(); emit('RET')
lab('FLN'); ENTRY['FLN'] = labels['FLN']
pred('nanu'); jmp('FLN_nan', 1); pred('zero'); jmp('FLN_zero', 1); pred('neg'); jmp('FLN_neg', 1); pred('inf'); jmp('FLN_end', 1)
jsr('LOGCORE'); cmd('FILD'); kld('LN2'); cmd('MULST', 1); cmd('POP'); cmd('ADD', 1); cmd('FSTP', 1)
lab('FLN_end'); emit('CC', 0); emit('END')
lab('FLN_nan'); nan_res(); jmp('FLN_end')
lab('FLN_zero'); kld('NINF'); cmd('FSTP', 1); emit('FLG', 4); jmp('FLN_end')
lab('FLN_neg'); kld('INDEF'); cmd('FSTP', 1); emit('FLG', 1); jmp('FLN_end')
lab('FYL2X'); ENTRY['FYL2X'] = labels['FYL2X']
pred('nanu'); jmp('Y_nan', 1); pred('zero'); jmp('Y_zero', 1); pred('neg'); jmp('Y_neg', 1); pred('inf'); jmp('Y_fin', 1)
jsr('LOGCORE'); kld('LOG2E'); cmd('MULST', 1); cmd('POP'); cmd('FILD'); cmd('ADD', 1); cmd('FSTP', 1)
lab('Y_fin'); cmd('MULST', 1); cmd('POP'); emit('CC', 0); emit('END')
lab('Y_nan'); nan_res(); jmp('Y_fin')
lab('Y_zero'); kld('NINF'); cmd('FSTP', 1); emit('FLG', 4); jmp('Y_fin')
lab('Y_neg'); kld('INDEF'); cmd('FSTP', 1); emit('FLG', 1); jmp('Y_fin')
lab('FYL2P'); ENTRY['FYL2P'] = labels['FYL2P']
pred('small'); jmp('P_slow', 2)
cmd('FLD', 0); kld('TWO'); cmd('ADD', 1); cmd('DIVST', 2); cmd('POP'); cmd('POP')       # [z = x / (2 + x)]
logpoly(); kld('LOG2E'); cmd('MULST', 1); cmd('POP'); jmp('Y_fin')
lab('P_slow'); kld('ONE'); cmd('ADD', 1); cmd('FSTP', 1); jmp('FYL2X')                   # large |x|: log2(1 + x) via the FYL2X path
# ---- FREM / FREM1
for name, near in (('FREM', 0), ('FREM1', 1)):
    lab(name); ENTRY[name] = labels[name]
    pred('nanu'); jmp(name + '_nan', 1); pred('nanu1'); jmp(name + '_nan', 1)
    pred('inf'); jmp(name + '_ind', 1); pred('zero1'); jmp(name + '_ind', 1)
    pred('inf1'); jmp(name + '_end', 1); pred('zero'); jmp(name + '_end', 1)
    emit('FREM', near); emit('END')
    lab(name + '_nan'); cmd('ADD', 1)
    lab(name + '_end'); emit('CC', 0); emit('END')
    lab(name + '_ind'); kld('INDEF'); cmd('FSTP', 1); emit('FLG', 1); emit('CC', 0); emit('END')
for i, l in fix:
    c_, k_, _ = prog[i]; prog[i] = (c_, k_, labels[l])
assert len(prog) < 1024, len(prog)
def word(w): c_, k_, a = w; return (c_ << 14) | (k_ << 10) | a
ROM = [word(w) for w in prog]
# external cmd -> input
EXT = {40: 'FSIN', 41: 'FCOS', 42: 'FSINC', 43: 'FTAN', 44: 'FLN', 45: 'FYL2X', 46: 'FYL2P', 47: 'FREM', 7: 'FREM1'}
# ---------------- exact FREM (same algorithm as the FSM) ----------------
def frem_model(x, y, near):
    sx = x >> 79; ex = (x >> 64) & 0x7FFF; mx = x & M64; ey = (y >> 64) & 0x7FFF; my = y & M64
    Ex = (ex if ex else 1) - 16383 - 63; Ey = (ey if ey else 1) - 16383 - 63
    while not (mx >> 63): mx <<= 1; Ex -= 1
    while not (my >> 63): my <<= 1; Ey -= 1
    d = Ex - Ey; q = 0; sg = sx
    if d < -1: A = mx; E = Ex
    elif d == -1:
        A = mx; E = Ex
        if near and mx > my: A = 2 * my - mx; sg ^= 1; q = 1
    else:
        A = mx; E = Ey
        if A >= my: A -= my; q = 1
        for _ in range(d):
            A <<= 1; q = (q << 1) & 7
            if A >= my: A -= my; q |= 1
        if near:
            t = 2 * A
            if t > my or (t == my and (q & 1)): A = my - A; sg ^= 1; q = (q + 1) & 7
    q &= 7
    if A == 0: res = sg << 79
    else:
        ec = E + 63 + 16383
        while not (A >> 63) and ec > 1: A <<= 1; ec -= 1
        while ec < 1:
            assert A & 1 == 0; A >>= 1; ec += 1
        ef = 0 if (ec == 1 and not (A >> 63)) else ec
        res = (sg << 79) | (ef << 64) | A
    return res, q
# ---------------- interpreter (RTL model) ----------------
def ctag(v):
    e = (v >> 64) & 0x7FFF; m = v & M64
    if e == 0 and m == 0: return 1
    if e == 0x7FFF or e == 0 or not (m >> 63): return 2
    return 0
def cls(v, w):
    ex = (v >> 64) & 0x7FFF; m = v & M64; m63 = m >> 63; mr = m & ((1 << 63) - 1)
    if w == 'zero': return ex == 0 and m == 0
    if w == 'inf': return ex == 0x7FFF and m63 == 1 and mr == 0
    if w == 'nanu': return (ex == 0x7FFF and not (m63 and mr == 0)) or (ex not in (0, 0x7FFF) and not m63) or (ex == 0 and m63 == 1)
    if w == 'den': return ex == 0 and not m63 and m != 0
    if w == 'neg': return (v >> 79) == 1
    if w == 'big': return ex >= 0x3FFF + 30
    if w == 'small': return ex < 0x3FFD
TRACE = False
class Fault(Exception): pass
KIND_R = {v: k for k, v in KIND.items()}; PRED_R = {v: k for k, v in PRED.items()}; CMD_R = {v: k for k, v in CMDN.items()}
def run(fp, entry, strict=True):
    st, tg = fp['st'], fp['tg']
    def fa(i): return (fp['top'] + i) & 7
    def STv(i): return st[fa(i)]
    def setST(i, v): p = fa(i); st[p] = v & ((1 << 80) - 1); tg[p] = ctag(st[p])
    def push(v):
        if tg[(fp['top'] - 1) & 7] != 3 and strict: raise Fault('overflow')
        fp['top'] = (fp['top'] - 1) & 7; setST(0, v)
    def pop():
        if tg[fp['top']] == 3 and strict: raise Fault('underflow')
        tg[fp['top']] = 3; fp['top'] = (fp['top'] + 1) & 7
    kq = 0; xin = 0; rdr = 0; dn = 0; P = 0; ret = 0; pc = entry
    while True:
        cnd, kd, a = prog[pc]; pc += 1
        if cnd == 1 and not P: continue
        if cnd == 2 and P: continue
        kind = KIND_R[kd]
        if TRACE: print(pc - 1, kind, a, 'P=%d' % P, [float(fpref.value(st[(fp['top'] + i) & 7])) * (-1 if st[(fp['top'] + i) & 7] >> 79 else 1) for i in range(8) if tg[(fp['top'] + i) & 7] != 3])
        if kind == 'END': break
        elif kind == 'JMP': pc = a
        elif kind == 'JSR': ret = pc; pc = a
        elif kind == 'RET': pc = ret
        elif kind == 'KQ': kq = rdr & 3
        elif kind == 'SETDN': dn = a
        elif kind == 'XINC': xin = (xin + 1) & M64
        elif kind == 'FLG': fp['exc'] |= a
        elif kind == 'CC': fp['c'] = [a & 1, (a >> 1) & 1, (a >> 2) & 1, (a >> 3) & 1]
        elif kind == 'KLD': push(KLIST[a])
        elif kind == 'XTR':
            v = STv(0); e = ((v >> 64) & 0x7FFF) - 16383 - (64 if dn else 0)
            xin = e & M64; setST(0, (v & (1 << 79)) | (0x3FFF << 64) | (v & M64))
        elif kind == 'PRED':
            n = PRED_R[a]
            if n == 'kq0': P = kq & 1
            elif n == 'kq1': P = (kq >> 1) & 1
            elif n == 'kq01': P = (kq & 1) ^ ((kq >> 1) & 1)
            elif n == 'less': P = fp['c'][0]
            elif n == 'dn': P = dn
            elif n in ('nanu1', 'inf1', 'zero1'): P = 1 if cls(STv(1), n[:-1]) else 0
            else: P = 1 if cls(STv(0), n) else 0
        elif kind == 'FREM':
            res, q = frem_model(STv(0), STv(1), a)
            setST(0, res); fp['c'] = [(q >> 2) & 1, q & 1, 0, (q >> 1) & 1]
        elif kind == 'CMD':
            cn = a & 63; ix = a >> 6; rc, pcw = 0, 3
            nm = CMD_R[cn]
            if nm in ('ADD', 'SUB', 'MUL', 'DIV'):
                r_, fl, up, cc = fpref.alu(nm, STv(0), STv(ix), rc, pcw); setST(0, r_); fp['exc'] |= fl & 0x20
            elif nm in ('ADDST', 'SUBST', 'MULST', 'DIVST'):
                r_, fl, up, cc = fpref.alu(nm[:-2], STv(ix), STv(0), rc, pcw); setST(ix, r_); fp['exc'] |= fl & 0x20
            elif nm == 'FRINT':
                r_, fl, up, cc = fpref.alu('RNDINT', STv(0), STv(0), rc, pcw); setST(0, r_); fp['exc'] |= fl & 0x20
            elif nm == 'FCOM':
                r_, fl, up, cc = fpref.alu('CMP', STv(0), STv(ix), rc, pcw); fp['c'] = [cc & 1, 0, (cc >> 1) & 1, (cc >> 2) & 1]; fp['exc'] |= fl & 0x20
            elif nm == 'FIST':
                r_, fl, up, cc = fpref.alu('FIST', STv(0), 0, rc, pcw); rdr = r_ & M64; fp['exc'] |= fl & 0x20
            elif nm == 'FILD':
                r_, fl, up, cc = fpref.alu('FILD', xin, 0, rc, pcw); push(r_); fp['exc'] |= fl & 0x20
            elif nm == 'FCHS': setST(0, STv(0) ^ (1 << 79))
            elif nm == 'FABS': setST(0, STv(0) & ~(1 << 79))
            elif nm == 'FXCH':
                p0, p1 = fa(0), fa(ix); st[p0], st[p1] = st[p1], st[p0]; tg[p0], tg[p1] = tg[p1], tg[p0]
            elif nm == 'FLD': push(STv(ix))
            elif nm == 'FSTP': setST(ix, STv(0)); pop()
            elif nm == 'POP': pop()
            else: raise ValueError(nm)
# ---------------- Verilog ROM generator ----------------
def verilog():
    s = ['    // generated by 08_fpu/macro/fpu_macro.py - DO NOT edit by hand', '    function [79:0] krom(input [5:0] i);', '        case (i)']
    for i, v in enumerate(KLIST): s.append("            6'd%d: krom = 80'h%020x;" % (i, v))
    s += ["            default: krom = 80'd0;", '        endcase', '    endfunction', '    function [15:0] mrom(input [9:0] a);', '        case (a)']
    for i, w in enumerate(ROM): s.append("            10'd%d: mrom = 16'h%04x;" % (i, w))
    s += ["            default: mrom = 16'h1800;", '        endcase', '    endfunction', '    function [9:0] mentry(input [5:0] c);', '        case (c)']
    for c_, n in EXT.items(): s.append("            6'd%d: mentry = 10'd%d;" % (c_, ENTRY[n]))
    s += ["            default: mentry = 10'd0;", '        endcase', '    endfunction']
    return '\n'.join(s) + '\n'
if __name__ == '__main__':
    print('words', len(ROM), 'constants', len(KLIST))
    open(os.path.join(HERE, 'fpu_macro_rom.vh'), 'w').write(verilog())
