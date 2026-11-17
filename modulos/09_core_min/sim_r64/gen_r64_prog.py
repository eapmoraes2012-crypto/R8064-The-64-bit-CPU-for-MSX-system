# gen_r64_prog.py - random program of the R8064 integer instructions (16/32/64 bits) + reference MODEL in Python.
# Usage: python3 gen_r64_prog.py <seed> <prefix> [N]   -> <prefix>_mem.hex (64 KB), <prefix>_trace.txt, <prefix>_fim.hex
# The model was written from ../PREMISSAS_R8064.txt (not from the RTL). The program is generated and executed on the model at the same time, so the generator knows
# the value of the registers: read/write pointers always fall in the data area (8000h-FFFFh; the code stays below) and the branches are forward.
# System (../MODELO_PRIVILEGIO.txt): supervisor/user mode, SCALL, SYSRT, JP USER, privileged instructions, illegal / unimplemented instruction exception and
# divide error, LDCTX/SVCTX. Each exception has its handler assembled further on in the program (the CR9 vector is pointed beforehand).
# Each trace line = state after an instruction: pc ax bc de hl ix iy sp f (64 bits in hexadecimal; f with 2 digits) + FPU status word and empties.
# The testbench uses a 64 KB memory (16-bit address); the model does the same.
import random, sys, os
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '08_fpu', 'ref'))
import fpref                                    # exact model of the 80-bit arithmetic (module 08)
import gen_fpu_prog as GP                       # the same steps and constants that are in fpu_unit.v (transcendentals and remainders)
seed = int(sys.argv[1]); pref = sys.argv[2]; N = int(sys.argv[3]) if len(sys.argv) > 3 else 3000
rnd = random.Random(seed)
M64 = (1 << 64) - 1
BITS = {'B': 8, 'W': 16, 'E': 32, 'Q': 64}
REG = {0: 'BC', 2: 'DE', 3: 'IY', 4: 'HL', 5: 'IX', 7: 'AX'}
R6 = [0, 2, 3, 4, 5, 7]; R4 = [0, 2, 4, 7]
FS, FZ, FY, FH, FX, FP, FN, FC = 0x80, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02, 0x01
r = {n: 0 for n in ('AX', 'BC', 'DE', 'HL', 'IX', 'IY', 'SP')}
st = {'f': 0, 'pc': 0}
mem = bytearray(65536)
trace = []
INDEF = fpref.INDEF
fp = dict(st=[0] * 8, wr=[True] * 8, tmp=[0] * 16, emp=[True] * 8, top=0, exc=0, sf=0, c3=0, c2=0, c1=0, c0=0)
def par8(v): return bin(v & 0xFF).count('1') % 2 == 0
def msk(n): return (1 << n) - 1
def wr_reg(name, val, n):                       # writes n bits, preserves the upper ones
    r[name] = (r[name] & ~msk(n) & M64) | (val & msk(n))
def rdm(a, n): return sum(mem[(a + i) & 0xFFFF] << (8 * i) for i in range(n // 8))
def wrm(a, v, n):
    for i in range(n // 8): mem[(a + i) & 0xFFFF] = (v >> (8 * i)) & 0xFF
def szx(res, n):
    f = 0
    if (res >> (n - 1)) & 1: f |= FS
    if res & msk(n) == 0: f |= FZ
    return f | (res & (FY | FX))
def arith(a, b, n, sub, cin, keepc=False, xy_from_b=False):
    a &= msk(n); b &= msk(n)
    res = (a - b - cin) if sub else (a + b + cin)
    carry = (res < 0) if sub else (res >> n) & 1
    res &= msk(n)
    f = szx(res, n)
    if xy_from_b: f = (f & ~(FY | FX)) | (b & (FY | FX))
    if (a ^ b ^ res) & 0x10: f |= FH
    sa, sb, sr = a >> (n - 1) & 1, b >> (n - 1) & 1, res >> (n - 1) & 1
    ov = (sa != sb and sr != sa) if sub else (sa == sb and sr != sa)
    if ov: f |= FP
    if sub: f |= FN
    if keepc: f |= st['f'] & FC
    elif carry: f |= FC
    return res, f
def logic(op, a, b, n):
    a &= msk(n); b &= msk(n)
    res = (a & b) if op == 'AND' else (a | b) if op == 'OR' else (a ^ b)
    f = szx(res, n) | (FP if par8(res) else 0) | (FH if op == 'AND' else 0)
    return res, f
def shift(op, a, n):
    a &= msk(n); top = a >> (n - 1) & 1; low = a & 1
    if op == 'SHL': res, c = (a << 1) & msk(n), top
    elif op == 'SHR': res, c = a >> 1, low
    elif op == 'SAR': res, c = (a >> 1) | (top << (n - 1)), low
    elif op == 'RLC': res, c = ((a << 1) & msk(n)) | top, top
    else: res, c = (a >> 1) | (low << (n - 1)), low
    return res, szx(res, n) | (FP if par8(res) else 0) | (FC if c else 0)
def cond(cc):
    f = st['f']
    return [not f & FZ, f & FZ, not f & FC, f & FC, not f & FP, f & FP, not f & FS, f & FS][cc] != 0
def le(v, n): return [(v >> (8 * i)) & 0xFF for i in range(n)]
code = [0]                                      # assembly position (= pc when execution is sequential)
def emit(bs):
    a = code[0]; mem[a:a + len(bs)] = bytes(bs); code[0] += len(bs); return a
def done(pc):                                   # end of an instruction in the model
    st['pc'] = pc & M64
    trace.append('%016x %016x %016x %016x %016x %016x %016x %016x %02x %04x %02x' % (st['pc'], r['AX'], r['BC'], r['DE'], r['HL'], r['IX'], r['IY'], r['SP'], st['f'], fsw(), femp()))
def fsw(): return fp['c3'] << 14 | fp['top'] << 11 | fp['c2'] << 10 | fp['c1'] << 9 | fp['c0'] << 8 | fp['sf'] << 6 | fp['exc']
def femp(): return sum(e << i for i, e in enumerate(fp['emp']))
def seq(bs): emit(bs); done(code[0])            # sequential instruction: executes (already done by the caller) and advances
def nops(k):                                    # k NOPs executed in sequence
    for _ in range(k): seq([0x00])
def filler(k): emit([0x00] * k)                 # k bytes skipped by a taken branch
# ---------- emitters (encode, execute in the model and record the trace) ----------
def ldq(code_r, val):                           # LDQ rr, nnnnnnnn
    r[REG[code_r]] = val & M64; seq([0xED, 0x39, 0x40 | code_r << 3 | 1] + le(val, 8))
def ld_sp(v):                                   # LD SP,nn (Z80): writes 16 bits
    wr_reg('SP', v, 16); seq([0x31] + le(v, 2))
def data_addr(n): return rnd.randrange(0x8000, 0xFFF0 - 8) | (rnd.getrandbits(48) << 16 if rnd.random() < .3 else 0)
def t_alu():
    op = rnd.choice(['ADD', 'ADC', 'SUB', 'SUBC', 'AND', 'OR', 'XOR', 'CP']); s = rnd.choice('WEQ'); n = BITS[s]
    d, sc = rnd.choice(R6), rnd.choice(R6); a, b = r[REG[d]], r[REG[sc]]; c = st['f'] & FC
    b2 = {'ADD': 0x3E, 'ADC': 0x3F, 'SUB': 0x3C, 'SUBC': 0x3D, 'AND': 0x38, 'OR': 0x37, 'XOR': 0x36, 'CP': 0x02}[op]
    if op in ('AND', 'OR', 'XOR'): res, f = logic(op, a, b, n)
    else: res, f = arith(a, b, n, op in ('SUB', 'SUBC', 'CP'), c if op in ('ADC', 'SUBC') else 0, xy_from_b=(op == 'CP'))
    if op != 'CP': wr_reg(REG[d], res, n)
    st['f'] = f; seq([0xED, b2, 'WEQ'.index(s) << 6 | d << 3 | sc])
def t_incdec():
    inc = rnd.random() < .5; s = rnd.choice('WEQ'); n = BITS[s]; d = rnd.choice(R6)
    res, f = arith(r[REG[d]], 1, n, not inc, 0, keepc=True)
    wr_reg(REG[d], res, n); st['f'] = f; seq([0xED, 0x3E if inc else 0x3C, 'WEQ'.index(s) << 6 | d << 3 | 1])
LDB2 = {'W': 0x3B, 'E': 0x3A, 'Q': 0x39}
R8 = {0: ('BC', 8), 1: ('BC', 0), 2: ('DE', 8), 3: ('DE', 0), 4: ('HL', 8), 5: ('HL', 0), 7: ('AX', 0)}
def t_shift():
    op = rnd.choice(['SHL', 'SHR', 'SAR', 'RLC', 'RRC']); s = rnd.choice('BWEQ' if op in ('SHL', 'SHR', 'SAR') else 'WEQ'); n = BITS[s]; tt = 'BWEQ'.index(s)
    if s == 'B':
        u = rnd.choice(list(R8)); name, sh = R8[u]; res, f = shift(op, r[name] >> sh, 8)
        r[name] = (r[name] & ~(0xFF << sh) & M64) | (res << sh); fld = u
    else:
        fld = rnd.choice(R6); res, f = shift(op, r[REG[fld]], n); wr_reg(REG[fld], res, n)
    st['f'] = f
    if op == 'SAR': seq([0xED, 0x29, tt << 6 | 6 << 3 | fld])
    else: seq([0xED, {'SHL': 0x29, 'SHR': 0x28, 'RLC': 0x06, 'RRC': 0x07}[op], tt << 6 | fld << 3 | 6])
def t_bit():
    op = rnd.choice(['BIT', 'RES', 'SET']); s = rnd.choice('WE'); n = BITS[s]; t = rnd.choice(R4); b = rnd.randrange(n); v = r[REG[t]]
    if op == 'BIT':
        res = v & (1 << b) & msk(n)
        st['f'] = szx(res, n) & ~(FY | FX) | (v & (FY | FX)) | FH | (FP if res == 0 else 0) | (st['f'] & FC)       # PV = Z
    elif op == 'RES': wr_reg(REG[t], v & ~(1 << b), n)
    else: wr_reg(REG[t], v | (1 << b), n)
    if s == 'W': seq([0xED, 0x2F if op == 'SET' else 0x30, (0x80 if op == 'RES' else 0) | b << 3 | t])
    else: seq([0xED, {'BIT': 0x33, 'RES': 0x32, 'SET': 0x31}[op], b << 3 | t])
def t_ldrr():
    s = rnd.choice('WEQ'); n = BITS[s]; d, sc = rnd.choice(R6), rnd.choice(R6)
    wr_reg(REG[d], r[REG[sc]], n); seq([0xED, LDB2[s], 0x40 | d << 3 | sc])
def t_ldimm():
    s = rnd.choice('WEQ'); n = BITS[s]; d = rnd.choice(R6); v = rnd.getrandbits(n)
    wr_reg(REG[d], v, n); seq([0xED, LDB2[s], 0x40 | d << 3 | 1] + le(v, n // 8))
def t_ldmem():
    s = rnd.choice('WEQ'); n = BITS[s]; p, o = rnd.choice(R6), rnd.choice(R6)
    ldq(p, data_addr(n)); a = r[REG[p]]
    if rnd.random() < .5: wr_reg(REG[o], rdm(a, n), n); seq([0xED, LDB2[s], o << 3 | p])                     # LDx rr,(rr')
    else: wrm(a, r[REG[o]], n); seq([0xED, LDB2[s], 0xC0 | p << 3 | o])                                     # LDx (rr),rr'
def t_ldabs():
    s = rnd.choice('WEQ'); n = BITS[s]; o = rnd.choice(R6); a = data_addr(n)
    if rnd.random() < .5: wr_reg(REG[o], rdm(a, n), n); seq([0xED, LDB2[s], 0x80 | o << 3 | 1] + le(a, 8))  # LDx rr,(nnnnnnnn)
    else: wrm(a, r[REG[o]], n); seq([0xED, LDB2[s], o << 3 | 1] + le(a, 8))                                 # LDx (nnnnnnnn),rr
def t_ldidx():
    s = rnd.choice('WEQ'); n = BITS[s]; x = rnd.choice([5, 3]); o = rnd.choice(R6); pfx = 0xDD if x == 5 else 0xFD
    ldq(x, rnd.randrange(0xA000, 0xE000) | (rnd.getrandbits(48) << 16 if rnd.random() < .3 else 0))
    dd = rnd.randrange(-0x1000, 0x1000); a = (r[REG[x]] + dd) & M64; d2 = le(dd & 0xFFFF, 2); k = rnd.randrange(3)
    low = {'W': 1, 'E': 6, 'Q': 0}[s]
    if k == 0: wrm(a, r[REG[o]], n); seq([0xED, pfx, o << 3 | low] + d2)                                    # LDx (QIX+dd),rr
    elif k == 1: v = rnd.getrandbits(n); wrm(a, v, n); seq([0xED, pfx, 0x40 | o << 3 | low] + d2 + le(v, n // 8))   # LDx (QIX+dd),immediate
    else: wr_reg(REG[o], rdm(a, n), n); seq([0xED, pfx, (0xC0 | o << 3 | 6) if s == 'Q' else (0x80 | o << 3 | low)] + d2)   # LDx rr,(QIX+dd)
def chk_sp():
    if not 0x9000 <= r['SP'] <= 0xFFE0: ld_sp(rnd.randrange(0xC000, 0xFF00))
def t_stack():
    chk_sp(); s = rnd.choice('EQ'); n = BITS[s]; o = rnd.choice(R6); q = 1 if s == 'Q' else 0
    if rnd.random() < .5: wrm(r['SP'] - n // 8, r[REG[o]], n); r['SP'] = (r['SP'] - n // 8) & M64; seq([0xED, 0x38, 0x80 | q << 6 | 1 << 3 | o])   # PUSHx
    else:                                                                                                    # POPx (the value read holds before SP changes)
        v = rdm(r['SP'], n); wr_reg(REG[o], v, n); r['SP'] = (r['SP'] + n // 8) & M64; seq([0xED, 0x38, q << 6 | 1 << 3 | o])
def branch(bs, taken, k, target=None):          # forward branch over k bytes; not taken: the k NOPs are executed
    a = emit(bs)
    if taken: filler(k); done(code[0] if target is None else target)
    else: done(code[0]); nops(k)
def t_jr():
    k = rnd.randrange(0, 5); kind = rnd.randrange(3)
    if kind == 0: branch([0xED, 0x2D] + le(k, 2), True, k)                                                   # JRW nn
    elif kind == 1: cc = rnd.randrange(8); branch([0xED, 0x2A, cc << 3 | 1] + le(k, 2), cond(cc), k)         # JRW cc,nn
    else:                                                                                                    # DJNZW nn: counter = BC (16 bits)
        b = (r['BC'] - 1) & 0xFFFF; wr_reg('BC', b, 16); branch([0xED, 0x2E] + le(k, 2), b != 0, k)
def t_jpimm():
    k = rnd.randrange(0, 5); kind = rnd.randrange(4)
    if kind == 0: t = code[0] + 6 + k; branch([0xED, 0x2C] + le(t, 4), True, k)                              # JPL nnnn
    elif kind == 1: t = code[0] + 10 + k; branch([0xED, 0x2B] + le(t, 8), True, k)                           # JPQ nnnnnnnn
    elif kind == 2: cc = rnd.randrange(8); t = code[0] + 7 + k; branch([0xED, 0x2A, 0x80 | cc << 3 | 1] + le(t, 4), cond(cc), k)   # JPL cc,nnnn
    else: cc = rnd.randrange(8); t = code[0] + 11 + k; branch([0xED, 0x2A, 0xC0 | cc << 3 | 6] + le(t, 8), cond(cc), k)            # JPQ cc,nnnnnnnn
def t_jpreg():
    k = rnd.randrange(0, 5); kind = rnd.randrange(4); v = rnd.choice(R6); e = kind in (0, 2)
    t = code[0] + 11 + 3 + k                                                                                 # after the LDQ (11 bytes) and the JP (3 bytes)
    ldq(v, t | (rnd.getrandbits(32) << 32 if e else 0))                                                      # JPL ignores the upper 32 bits
    if kind == 0: branch([0xED, 0x2A, 0x40 | v << 3 | 1], True, k)                                           # JPL (vv)
    elif kind == 1: branch([0xED, 0x2A, 0xC0 | v << 3 | 1], True, k)                                         # JPQ (vv)
    elif kind == 2: cc = rnd.randrange(8); branch([0xED, 0x2A, cc << 3 | v], cond(cc), k)                    # JPL cc,(vv)
    else: cc = rnd.randrange(8); branch([0xED, 0x2A, 0x40 | cc << 3 | v], cond(cc), k)                       # JPQ cc,(vv)
def push_ret(n, ret):
    wrm(r['SP'] - n // 8, ret, n); r['SP'] = (r['SP'] - n // 8) & M64
def t_call():
    chk_sp(); k = rnd.randrange(0, 5); s = rnd.choice('EQ'); n = BITS[s]; kind = rnd.randrange(3)
    if kind == 0:                                                                                            # CALLx immediate
        ln = 2 + n // 8; t = code[0] + ln + k; push_ret(n, code[0] + ln)
        branch([0xED, 0x35 if s == 'E' else 0x34] + le(t, n // 8), True, k)
    else:
        v = rnd.choice(R4); t = code[0] + 11 + 3 + k; ldq(v, t | (rnd.getrandbits(32) << 32 if s == 'E' else 0)); b2 = 0x37 if s == 'E' else 0x36
        if kind == 1: push_ret(n, code[0] + 3); branch([0xED, b2, 1 << 3 | v], True, k)                      # CALLx (rr)
        else:                                                                                                # CALLx cc,(rr)
            cc = rnd.randrange(8); tk = cond(cc)
            if tk: push_ret(n, code[0] + 3)
            branch([0xED, b2, 0xC0 | cc << 3 | v], tk, k)
def t_ret():
    chk_sp(); k = rnd.randrange(0, 5); s = rnd.choice('EQ'); n = BITS[s]; v = rnd.choice(R6); q = 1 if s == 'Q' else 0; cc = rnd.randrange(9)
    ln = 2 if cc == 8 else 3
    t = code[0] + 11 + 3 + ln + k                                                                            # LDQ (11) + PUSHx (3) + RETx
    ldq(v, t | (rnd.getrandbits(32) << 32 if s == 'E' else 0))                                               # RETL uses only the low 32 bits
    wrm(r['SP'] - n // 8, r[REG[v]], n); r['SP'] = (r['SP'] - n // 8) & M64; seq([0xED, 0x38, 0x80 | q << 6 | 1 << 3 | v])   # PUSHx rr
    tk = True if cc == 8 else cond(cc)
    if tk: r['SP'] = (r['SP'] + n // 8) & M64
    bs = [0xED, 0x04 + q] if cc == 8 else [0xED, 0x03, (0x80 if q else 0x40) | cc << 3]
    branch(bs, tk, k)                                                                                        # the target read from the stack = t (low 32 bits in RETL)
def sgn(v, n): v &= msk(n); return v - (1 << n) if v >> (n - 1) else v
def r8get(u): name, sh = R8[u]; return (r[name] >> sh) & 0xFF
def ldx(code_r, val, s):                        # LDW/LDL/LDQ rr, immediate
    n = BITS[s]; wr_reg(REG[code_r], val, n); seq([0xED, LDB2[s], 0x40 | code_r << 3 | 1] + le(val & msk(n), n // 8))
def mflags(p, n, sg):                           # MLT flags: p = product (Python integer), n = bits of each operand
    lo, hi = p & msk(n), (p >> n) & msk(n)
    c = (hi != (msk(n) if lo >> (n - 1) else 0)) if sg else (hi != 0)
    st['f'] = (st['f'] & (FH | FN)) | (FZ if p == 0 else 0) | (FC if c else 0) | ((FP if c else 0) | (FS if p < 0 else 0) if sg else 0)
def t_mul():
    k = rnd.randrange(7)
    if k == 0:                                                                                               # MLTUB A,u (R800): HL = A * u
        u = rnd.choice(list(R8)); p = (r['AX'] & 0xFF) * r8get(u); mflags(p, 8, False); wr_reg('HL', p, 16); seq([0xED, 0xC1 | u << 3])
    elif k == 1:                                                                                             # MLTUW HL,BC / HL,SP (R800): DE:HL = HL * rr
        nm, b2 = rnd.choice([('BC', 0xC3), ('SP', 0xF3)]); p = (r['HL'] & 0xFFFF) * (r[nm] & 0xFFFF)
        mflags(p, 16, False); wr_reg('HL', p, 16); wr_reg('DE', p >> 16, 16); seq([0xED, b2])
    elif k == 2:                                                                                             # MLTSB AL,u: AX (16 bits) = AL * u
        u = rnd.choice(list(R8)); p = sgn(r['AX'], 8) * sgn(r8get(u), 8); mflags(p, 8, True); wr_reg('AX', p, 16); seq([0xED, 0x3F, 0x08 | u])
    else:
        sg = rnd.random() < .5; s = 'WEQ'[k % 3]; n = BITS[s]; c = rnd.choice(R6); b2 = 0x3F if sg else 0x3E
        a, b = (r['HL'] if s == 'W' else r['AX']), r[REG[c]]
        p = (sgn(a, n) * sgn(b, n)) if sg else ((a & msk(n)) * (b & msk(n)))
        mflags(p, n, sg)
        if s == 'W': wr_reg('HL', p, 16); wr_reg('DE', p >> 16, 16)                                          # MLTxW HL,rr: DE:HL
        elif s == 'E': r['AX'] = p & M64                                                                     # MLTxL: QA
        else:
            r['AX'] = p & M64                                                                                # MLTUQ: QA ; MLTSQ: QDE:QA
            if sg: r['DE'] = (p >> 64) & M64
        seq([0xED, b2, 'BWEQ'.index(s) << 6 | 1 << 3 | c])
def div_calc(dd, d, n, sg):                    # dd = 2n-bit dividend, d = n-bit divisor (bit patterns) -> (error, quotient, remainder)
    if sg:
        ddv, dv = sgn(dd, 2 * n), sgn(d, n)
        if dv == 0: return True, 0, 0
        q = abs(ddv) // abs(dv) * (1 if (ddv < 0) == (dv < 0) else -1); rem = ddv - q * dv
        return not -(1 << (n - 1)) <= q < (1 << (n - 1)), q, rem
    if d == 0 or dd // d >> n: return True, 0, 0
    return False, dd // d, dd % d
def div_ops(n, sg, want_err):                   # draws dividend / divisor until it does (or does not) give an error
    while True:
        d = rnd.getrandbits(n) if rnd.random() < .7 else rnd.getrandbits(rnd.randrange(1, n))
        if want_err and rnd.random() < .4: d = 0
        k = rnd.random()
        if sg and d and k < .5:                                                                              # quotient near the edges of the range
            dv = sgn(d, n); q = rnd.choice([-(1 << (n - 1)) - 1, -(1 << (n - 1)), (1 << (n - 1)) - 1, 1 << (n - 1), rnd.randrange(-(1 << (n - 1)), 1 << (n - 1))])
            rem = rnd.randrange(abs(dv)); dd = q * dv; dd += rem if dd >= 0 else -rem; dd &= msk(2 * n)
        elif d and k < .8: dd = rnd.randrange(d << n) if not sg else rnd.getrandbits(n + rnd.randrange(1, n))
        else: dd = rnd.getrandbits(2 * n) if want_err else rnd.getrandbits(n)
        e, q, rem = div_calc(dd, d, n, sg)
        if e == want_err: return dd, d, e, q, rem
def div_emit(s, sg, want_err, te):              # assembles the operands and the instruction; returns (instruction bytes, function that applies the result)
    n = BITS[s]; b2 = 0x3D if sg else 0x3C
    if s == 'B': c = rnd.randrange(6)
    else: c = rnd.choice([0, 3, 4, 5])                                                                       # divisor: BC, IY, HL ou IX
    dd, d, e, q, rem = div_ops(n, sg, want_err)
    lo, hi = dd & msk(n), (dd >> n) & msk(n)
    if e: q, rem = msk(n), lo                                                                                # error without exception: quotient = all ones, remainder = low part of the dividend
    if s == 'B':
        name, sh = R8[c]; ldx({'BC': 0, 'DE': 2, 'HL': 4}[name], (rnd.getrandbits(8) << (8 - sh)) | (d << sh), 'W')   # divisor in an 8-bit register
        ldx(7, hi << 8 | lo, 'W')
    elif s == 'E': ldx(c, d, 'E'); ldx(7, hi << 32 | lo, 'Q')
    else: ldx(c, d, s); ldx(2, hi, s); ldx(7, lo, s)
    def apply():
        if s == 'B': wr_reg('AX', (rem & 0xFF) << 8 | (q & 0xFF), 16)                                        # AL = quotient, AH = remainder
        elif s == 'E': r['AX'] = (rem & msk(32)) << 32 | (q & msk(32))                                       # QA = {remainder, quotient}
        else: wr_reg('AX', q, n); wr_reg('DE', rem, n)                                                       # AX = quotient, DE = remainder
        st['f'] = (st['f'] & (FH | FN)) | ((FP | FC) if e else (FZ if q & msk(n) == 0 else 0) | (FS if sg and q < 0 else 0))
    return [0xED, b2, 'BWEQ'.index(s) << 6 | 1 << 3 | c], apply
def t_div():                                    # 1 in 5 with error (zero divisor / out-of-range quotient): here the exception is off, only flags and fixed result
    bs, apply = div_emit(rnd.choice('BWEQ'), rnd.random() < .5, rnd.random() < .2, False); apply(); seq(bs)
def t_xchg():
    s = rnd.choice('EQ'); n = BITS[s]; p, o = rnd.choice(R6), rnd.choice(R6); q = 1 if s == 'Q' else 0
    ldq(p, data_addr(n)); a = r[REG[p]]; old = rdm(a, n); wrm(a, r[REG[o]], n); wr_reg(REG[o], old, n)
    seq([0xED, 0xAC, q << 6 | o << 3 | p])                                                                   # XCHGx rr,(rr')
def t_cas():
    s = rnd.choice('EQ'); n = BITS[s]; p, o = rnd.choice([0, 2, 3, 4, 5]), rnd.choice(R6); q = 1 if s == 'Q' else 0
    ldq(p, data_addr(n)); a = r[REG[p]]; m = rdm(a, n)
    if rnd.random() < .5: ldq(7, m | (rnd.getrandbits(32) << 32 if s == 'E' else 0))                         # half of the time A is already equal
    res, f = arith(r['AX'], m, n, True, 0, xy_from_b=True); st['f'] = f; eq = (r['AX'] & msk(n)) == m
    wr_reg('AX', m, n)
    if eq: wrm(a, r[REG[o]], n)
    seq([0xED, 0xAD, q << 6 | p << 3 | o])                                                                   # CASx (rr'),rr
# ---------- FPU (../MODELO_FPU.txt): ST0-ST7 stack, status word and the arithmetic of fpref.py (round to nearest, 64 bits) ----------
def f_under(): fp['exc'] |= 1; fp['sf'] = 1; fp['c1'] = 0
def f_set(i, v): fp['st'][i & 7] = v; fp['wr'][i & 7] = True; fp['emp'][i & 7] = False
def f_push(v):
    i = (fp['top'] - 1) & 7; full = not fp['emp'][i]
    f_set(i, INDEF if full else v); fp['top'] = i
    if full: fp['exc'] |= 1; fp['sf'] = 1; fp['c1'] = 1
def f_pop(k=1):
    for _ in range(k): fp['emp'][fp['top']] = True; fp['top'] = (fp['top'] + 1) & 7
def f_alu(code, n=0, din=0, pop2=False):        # arithmetic commands of the unit; returns r0
    t = fp['top']; ib = (t + n) & 7; ea, eb = fp['emp'][t], fp['emp'][ib]; memsrc = code in (6, 9, 10); wr0 = code <= 4 or code == 8; r0 = None
    if memsrc and not fp['emp'][(t - 1) & 7]: fp['c1'] = 0; f_push(INDEF)
    elif not memsrc and (ea or (code in (0, 1, 2, 3, 5) and eb)):
        f_under()
        if wr0: f_set(t, INDEF)
        if code == 5: fp['c3'] = fp['c2'] = fp['c0'] = 1
        r0 = {7: 1 << 63, 11: 0xFFC00000}.get(code, 0xFFF8 << 48)
    else:
        res, fl, up, cc = fpref.alu(code, din if memsrc else fp['st'][t], fp['st'][ib], 0, 3)
        fp['exc'] |= fl; fp['c1'] = int(bool(up))
        if wr0: f_set(t, res)
        if code == 5: fp['c3'], fp['c2'], fp['c0'] = cc >> 2 & 1, cc >> 1 & 1, cc & 1
        if memsrc: f_push(res)
        r0 = res & M64
    if pop2: f_pop(2)
    return r0
def fval80():                                   # 80-bit value to load: almost always a normal with a moderate exponent, sometimes a special case
    k = rnd.random(); sgn_ = rnd.getrandbits(1) << 79
    if k < .60: return sgn_ | (16383 + rnd.randrange(-40, 41)) << 64 | 1 << 63 | rnd.getrandbits(rnd.choice([63, 63, 20, 5]))
    if k < .70: return sgn_ | (16383 + rnd.randrange(0, 20)) << 64 | 1 << 63 | (rnd.getrandbits(6) << 57)       # small integers and halves
    if k < .75: return sgn_
    if k < .80: return sgn_ | rnd.getrandbits(rnd.randrange(1, 64)) & ((1 << 63) - 1)                         # denormal (ou zero)
    if k < .85: return sgn_ | 0x7FFF << 64 | 1 << 63
    if k < .90: return sgn_ | 0x7FFF << 64 | 1 << 63 | rnd.getrandbits(1) << 62 | (rnd.getrandbits(62) or 1)  # quiet or signalling NaN
    if k < .93: return sgn_ | rnd.randrange(1, 32767) << 64 | rnd.getrandbits(63)                             # unnormal (unsupported)
    return sgn_ | rnd.choice([rnd.randrange(1, 32767), rnd.randrange(1, 70), rnd.randrange(32700, 32767)]) << 64 | 1 << 63 | rnd.getrandbits(63)
def poke(a, v, nbytes):                         # writes v to memory with instructions (LDQ rr,immediate + LDx (address),rr)
    for off, s_ in ((0, 'Q'), (8, 'W')) if nbytes == 10 else ((0, {4: 'E', 8: 'Q'}[nbytes]),):
        c = rnd.choice(R6); n = BITS[s_]; ldq(c, (v >> (8 * off)) & M64); wrm(a + off, r[REG[c]], n); seq([0xED, LDB2[s_], c << 3 | 1] + le(a + off, 8))
def faddr(): return rnd.randrange(0x8000, 0xFFE0) | (rnd.getrandbits(48) << 16 if rnd.random() < .3 else 0)   # data address (only the low 16 bits reach the test memory)
def fhl(a=None):                                # QHL := address (AFTER assembling the data: the poke may use HL)
    a = faddr() if a is None else a; ldq(4, a); return a
nfp = {}
def fdepth(): return 8 - sum(fp['emp'])
def t_fload():
    nfp['fload'] = nfp.get('fload', 0) + 1
    k = rnd.randrange(10)
    if k < 4: a = faddr(); v = fval80(); poke(a, v, 10); fhl(a); fp['c1'] = 0; f_push(v); seq([0xED, 0x85])                # FLD80 (QHL)
    elif k < 6:                                                                                               # FLD64 (QHL)
        a = faddr(); v = rnd.getrandbits(1) << 63 | rnd.choice([1023 + rnd.randrange(-40, 41), 0, 0x7FF, rnd.randrange(2047)]) << 52 | rnd.getrandbits(rnd.choice([52, 10]))
        poke(a, v, 8); fhl(a); f_alu(10, din=v); seq([0xED, 0xBC, 0x4A])
    elif k < 7:                                                                                               # FLD32 (QHL)
        a = faddr(); v = rnd.getrandbits(1) << 31 | rnd.choice([127 + rnd.randrange(-30, 31), 0, 0xFF, rnd.randrange(255)]) << 23 | rnd.getrandbits(rnd.choice([23, 5]))
        poke(a, v, 4); fhl(a); f_alu(9, din=v); seq([0xED, 0xBC, 0x49])
    elif k < 9:                                                                                               # FILD (QHL)
        a = faddr(); v = rnd.getrandbits(rnd.choice([64, 64, 20, 4, 1])) * rnd.choice([1, 1, M64]) & M64
        poke(a, v, 8); fhl(a); f_alu(6, din=v); seq([0xED, 0xBC, 0x48])
    else:                                                                                                     # constantes
        nm = rnd.randrange(6); fp['c1'] = 0
        f_push([0x3FFF << 64 | 1 << 63, 0, 0x4000 << 64 | 0xC90FDAA22168C235, 0x4000 << 64 | 0xD49A784BCD1B8AFE, 0x3FFD << 64 | 0x9A209A84FBCFF799, 0x3FFE << 64 | 0xB17217F7D1CF79AC][nm])
        seq([[0xED, 0xBC, 0x42], [0xED, 0x92], [0xED, 0x91], [0xED, 0x86], [0xED, 0x87], [0xED, 0x90]][nm])     # FLD1 FLDZ FLDPI FLDL2 FLDLG FLDLN
def t_farith():
    nfp['farith'] = nfp.get('farith', 0) + 1
    k = rnd.randrange(8); n = rnd.randrange(8) if rnd.random() < .3 else rnd.randrange(max(1, min(8, fdepth())))
    if k < 4: f_alu(k, n); seq([[0xED, 0xBC, n], [0xED, 0x18 | n], [0xED, 0x98 | n], [0xED, 0x88 | n]][k])      # FADD / FSUB / FMUL / FDIV ST0,STn
    elif k == 4: f_alu(4); seq([0xED, 0x11])                                                                  # FSQRT
    elif k == 5: f_alu(8); seq([0xED, 0xBC, 0x43])                                                            # FRINT
    elif k == 6: f_alu(5, n); seq([0xED, 0xBC, 0x20 | n])                                                     # FCOM STn
    else: f_alu(5, 1, pop2=True); seq([0xED, 0x80])                                                           # FCOPP
    if rnd.random() < .6: t_fstsw()
def t_fstsw(): st['f'] = fp['c3'] << 6 | fp['c2'] << 2 | fp['c0']; seq([0xED, 0x14])                           # FSTSW: F := {0, C3, 0, 0, 0, C2, 0, C0}
def t_fstack():
    nfp['fstack'] = nfp.get('fstack', 0) + 1
    k = rnd.randrange(7); n = rnd.randrange(8); t = fp['top']; ib = (t + n) & 7; ea, eb = fp['emp'][t], fp['emp'][ib]
    if k == 0:                                                                                                # FLD STn
        fp['c1'] = 0
        if eb: f_under()
        f_push(INDEF if eb else fp['st'][ib]); seq([0xED, 0xBC, 0x10 | n])
    elif k == 1:                                                                                              # FXCH STn
        fp['c1'] = 0
        if ea or eb: f_under()
        va, vb = (INDEF if ea else fp['st'][t]), (INDEF if eb else fp['st'][ib]); f_set(t, vb); f_set(ib, va); seq([0xED, 0xBC, 0x08 | n])
    elif k == 2:                                                                                              # FSTP STn
        fp['c1'] = 0
        if ea: f_under()
        f_set(ib, INDEF if ea else fp['st'][t]); f_pop(); seq([0xED, 0xBC, 0x18 | n])
    elif k in (3, 4):                                                                                         # FCHS / FABS
        fp['c1'] = 0
        if ea: f_under()
        v = INDEF if ea else (fp['st'][t] ^ (1 << 79) if k == 3 else fp['st'][t] & ~(1 << 79)); f_set(t, v); seq([0xED, 0xBC, 0x40 if k == 3 else 0x41])
    elif k == 5 and rnd.random() < .15:                                                                       # FINIT
        fp.update(emp=[True] * 8, top=0, exc=0, sf=0, c3=0, c2=0, c1=0, c0=0); seq([0xED, 0x82])
    else: t_fstsw()
def t_fstore():
    nfp['fstore'] = nfp.get('fstore', 0) + 1
    k = rnd.randrange(8); a = fhl(); t = fp['top']
    if k < 2:                                                                                                 # FST80 / FSTP8 (QHL)
        fp['c1'] = 0
        if fp['emp'][t]: f_under()
        wrm(a, INDEF if fp['emp'][t] else fp['st'][t], 80)
        if k == 1: f_pop()
        seq([0xED, 0x12 + k])
    else:
        code, nb, ops = [(12, 64, ([0xED, 0xBC, 0x4D], [0xED, 0xBC, 0x4E])), (11, 32, ([0xED, 0xBC, 0x4B], [0xED, 0xBC, 0x4C])), (7, 64, ([0xED, 0x83], [0xED, 0x84]))][k % 3]
        p = rnd.random() < .5; wrm(a, f_alu(code), nb)                                                        # FST64/FSP64, FST32/FSP32, FIST/FISTP
        if p: f_pop()
        seq(ops[p])
def f_prog(code):                                # internal programs: 4 FSIN 5 FCOS 6 FSINC 7 FTAN 8 FLN 9 FYL2X 10 FYL2P 11 FREM 12 FREM1
    t = fp['top']; ib = (t + 1) & 7; ea, eb = fp['emp'][t], fp['emp'][ib]; p2 = code >= 9; pst1 = code in (9, 10); A = fp['st'][t]
    badlog = code in (8, 9) and (A >> 79 or (A >> 64) & 0x7FFF in (0, 0x7FFF) or not (A >> 63) & 1)
    if ea or (p2 and eb) or badlog:
        fp['exc'] |= 1; fp['c1'] = 0
        if ea or (p2 and eb): fp['sf'] = 1
        f_set(ib if pst1 else t, INDEF)
        if pst1: f_pop()
        return
    tmp = fp['tmp']; var = code & 3; q = lc = cidx = dq = 0
    rd = lambda x: fp['st'][(fp['top'] + x - 16) & 7] if x >= 16 else tmp[x]
    def wrr(x, v):
        if x >= 16: f_set(fp['top'] + x - 16, v)
        else: tmp[x] = v
    pc = GP.ENTRY['trig' if code <= 7 else {8: 'fln', 9: 'fyl2x', 10: 'fyl2p', 11: 'frem', 12: 'frem1'}[code]]
    while True:
        p = GP.PROG[pc]; k = p['k']; pc += 1
        if k == 0:
            Bv = GP.CONST[cidx] if p['bsel'] == 2 else GP.CONST[p['b']] if p['bsel'] == 1 else rd(p['b'] & 31)
            res, fl, up, cc = fpref.alu(p['aop'], dq if p['aop'] == 6 else rd(p['a']), Bv, p['rc'], 3)
            fp['exc'] |= fl; fp['c1'] = int(bool(up))
            if p['q']: q = res & 3
            else: wrr(p['dst'], res)
            if p['bsel'] == 2: cidx -= 1
        elif k == 1:
            wrr(p['dst'], GP.CONST[cidx if p['bsel'] == 2 else p['b']])
            if p['bsel'] == 2: cidx -= 1
        elif k == 2: v = rd(p['a']); wrr(p['dst'], 0x3FFF << 64 | v & M64); dq = (((v >> 64) & 0x7FFF) - 16383) & M64
        elif k == 3:
            c = p['b'] & 1; src = tmp[13] if c ^ (q & 1) else tmp[12]; neg = ((q >> 1) ^ (q & 1)) & 1 if c else (q >> 1) & 1; wrr(p['dst'], src ^ neg << 79)
        elif k == 4: f_push(rd(p['a']))
        elif k == 5:
            if lc: lc -= 1; pc = p['b']
        elif k == 6: lc = p['a']; cidx = p['b']
        elif k == 8: pc += 4 * var
        else:
            if p['a'] & 1: f_pop()
            return
def fnum(lo, hi):                               # positive normal with exponent in [lo, hi)
    return (16383 + rnd.randrange(lo, hi)) << 64 | 1 << 63 | rnd.getrandbits(63)
def fput(v): a = faddr(); poke(a, v, 10); fhl(a); fp['c1'] = 0; f_push(v); seq([0xED, 0x85])                    # FLD80 of a chosen value
def t_ftrans():
    nfp['trans'] = nfp.get('trans', 0) + 1
    k = rnd.randrange(9); sg = rnd.getrandbits(1) << 79; esp = rnd.random() < .12                             # esp: uses whatever is on the stack (empties, NaN, ...)
    if not esp:
        if k < 4: fput(sg | fnum(-20, 8))                                                                     # angle
        elif k == 4: fput(fnum(-40, 40))                                                                      # FLN x
        elif k == 5: fput(sg | fnum(-10, 10)); fput(fnum(-40, 40))                                            # FYL2X: y, x
        elif k == 6: fput(sg | fnum(-10, 10)); fput(sg ^ (rnd.getrandbits(1) << 79) | fnum(-30, -2))          # FYL2P: y, small x
        else: fput(sg | fnum(-8, 8)); fput(fnum(-8, 30) | rnd.getrandbits(1) << 79)                           # FREM: divisor, dividend
    f_prog([4, 5, 6, 7, 8, 9, 10, 11, 12][k])
    seq([[0xED, 0x97], [0xED, 0x81], [0xED, 0x10], [0xED, 0x15], [0xED, 0x93], [0xED, 0x17], [0xED, 0x16], [0xED, 0x95], [0xED, 0x96]][k])
    if rnd.random() < .5: t_fstore()
def t_fsave():                                  # FSAVE (uu) / FRSTR (uu): 8 bytes {empties, status word} + 8 physical 10-byte registers
    nfp['save'] = nfp.get('save', 0) + 1
    u = rnd.choice([0, 2, 4, 7]); ldq(u, rnd.randrange(0x8000, 0xFF80) | (rnd.getrandbits(48) << 16 if rnd.random() < .3 else 0)); a = r[REG[u]]
    if rnd.random() < .6:
        wrm(a, femp() << 16 | fsw(), 64)
        for i in range(8): wrm(a + 8 + 10 * i, fp['st'][i], 80)
        seq([0xED, 0xAF, 0x08 | u])
    else:
        v = rdm(a, 64)
        fp.update(exc=v & 63, sf=v >> 6 & 1, c0=v >> 8 & 1, c1=v >> 9 & 1, c2=v >> 10 & 1, top=v >> 11 & 7, c3=v >> 14 & 1, emp=[bool(v >> (16 + i) & 1) for i in range(8)])
        for i in range(8): fp['st'][i] = rdm(a + 8 + 10 * i, 80)
        seq([0xED, 0xAF, 0x48 | u])
def t_fpu():
    d = fdepth(); k = rnd.random()
    if d < 2 and k < .7: t_fload()
    elif d >= 6 and k < .6: t_fstore()
    elif k > .93: t_fsave()
    elif k > .80 and d <= 5: t_ftrans()
    else: rnd.choice([t_fload, t_farith, t_farith, t_farith, t_fstack, t_fstore])()
# ---------- system ----------
cr = [0] * 32                                   # CR0-CR7 free; 9 vector, 11 cause, 12 auxiliary, 13 EPC, 14 {TE [2], MMU [0]}, 18 mode {previous [1], user [0]}
nreg = [0] * 8                                  # N0-N7 (only appear in the test through LDCTX / SVCTX)
def t_cr():
    k = rnd.randrange(8); c = rnd.choice(R6); j = rnd.randrange(4)
    if j == 0: cr[k] = r[REG[c]]; seq([0xED, 0x20, k << 3 | c])                                              # LDCR kk,rr
    elif j == 1: r[REG[c]] = cr[k]; seq([0xED, 0x21, k << 3 | c])                                            # STCR rr,kk
    elif j == 2: cr[k] = r['AX']; seq([0xED, 0x0C, k])                                                       # MTCR n
    else: r['AX'] = cr[k]; seq([0xED, 0x0A, k])                                                              # MFCR n
def t_nop2():                                   # FENCE, ISYNC, illegal ED, PGINV, WAKE, FLUSH (whole TLB + pipeline: no visible effect here), FPU and wide I/O (no microcode; with TE = 0 they are NOP), PROT 0
    if rnd.random() < .15: cr[14] &= ~1; seq([0xED, 0x00]); return
    seq(rnd.choice([[0xED, 0xA5], [0xED, 0xA6], [0xED, 0x08], [0xED, 0x0F], [0xED, 0xC4], [0xED, 0xFC], [0xED, 0x23], [0xED, 0x94]]))
CTXR = ['AX', 'BC', 'DE', 'HL', 'IX', 'IY', 'SP']
def t_ctx():                                    # SVCTX (uu) / LDCTX (uu): 16 words of 8 bytes: AX BC DE HL IX IY SP F N0..N7
    u = rnd.choice([0, 2, 4, 7]); ldq(u, rnd.randrange(0x8000, 0xFF00) & ~7 | (rnd.getrandbits(48) << 16 if rnd.random() < .3 else 0)); a = r[REG[u]]
    if rnd.random() < .5:
        for i, nm in enumerate(CTXR): wrm(a + 8 * i, r[nm], 64)
        wrm(a + 56, st['f'], 64)
        for i in range(8): wrm(a + 64 + 8 * i, nreg[i], 64)
        seq([0xED, 0xAE, 0x08 | u])
    else:
        v = [rdm(a + 8 * i, 64) for i in range(16)]
        for i, nm in enumerate(CTXR): r[nm] = v[i]
        st['f'] = v[7] & 0xFF; nreg[:] = v[8:]
        seq([0xED, 0xAE, 0x48 | u]); chk_sp()
def ldcr(k, val):                               # CR[k] := val (through a drawn register)
    c = rnd.choice(R6); ldq(c, val); cr[k] = val; seq([0xED, 0x20, k << 3 | c])
def trap(bs, cause, aux, epc, H):               # the instruction 'bs' does not execute: enters the exception and the program continues in the handler (H)
    emit(bs); assert code[0] <= H, 'handler too far'
    ntrap[(cause, aux if cause == 7 else 0, cr[18] & 1)] = ntrap.get((cause, aux if cause == 7 else 0, cr[18] & 1), 0) + 1
    cr[12] = aux; cr[11] = cause; cr[13] = epc & M64; cr[18] = (cr[18] & 1) << 1
    code[0] = H; done(cr[9])
def handler(exp, cont=True, force=None, nextvec=False):   # reads cause / auxiliary / EPC / mode into registers (checked in the trace) and returns with SYSRT
    for k in (11, 12, 13, 18):
        c = rnd.choice(R6); r[REG[c]] = cr[k]; seq([0xED, 0x21, k << 3 | c])
    assert (cr[11], cr[12]) == exp
    ln = (14 if cont else 0) + (14 if force is not None else 0) + (14 if nextvec else 0) + 2
    dest = code[0] + ln
    if nextvec: ldcr(9, dest + GAP)
    if cont: ldcr(13, dest)
    if force is not None: ldcr(18, force)
    cr[18] >>= 1; emit([0xED, 0xA4]); done(cr[13])                                                          # SYSRT: mode := previous, PC := EPC
    if cont: assert code[0] == dest
GAP = 0x70
ntrap = {}                                      # (cause, auxiliary, mode) -> how many times
PRIV = [[0xED, 0x20, 0x4A], [0xED, 0x21, 0x58], [0xED, 0x0A, 0x0E], [0xED, 0x0C, 0x12], [0xED, 0xC4], [0xED, 0xA4], [0xED, 0xB5], [0xED, 0x00], [0xED, 0x01], [0xED, 0x25], [0xED, 0x24], [0xED, 0x23], [0xED, 0x94],
        [0xF3], [0xFB], [0xD3, 0x98], [0xDB, 0x98], [0xED, 0x78], [0xED, 0x79], [0xED, 0x56], [0xED, 0x47], [0xED, 0xA2], [0xED, 0xB3]]   # Z80: DI, EI, E/S, IM, LD I,A
def one_trap(H, user, te):                      # draws and assembles ONE instruction that causes an exception; returns (cause, auxiliary)
    kinds = ['scall'] + (['priv'] * 2 if user else []) + (['ill', 'div'] if te else [])
    k = rnd.choice(kinds)
    if k == 'scall': n = rnd.getrandbits(8); trap([0xED, 0x22, n], 5, n, code[0] + 3, H); return 5, n
    if k == 'priv': trap(rnd.choice(PRIV), 7, 2, code[0], H); return 7, 2
    if k == 'ill': trap(rnd.choice([[0xED, 0x08], [0xED, 0x0F]]), 7, 0, code[0], H); return 7, 0
    if k == 'unimp': trap([0xED, 0x27, 0x01], 7, 1, code[0], H); return 7, 1
    bs, apply = div_emit(rnd.choice('BWEQ'), rnd.random() < .5, True, True); trap(bs, 6, 0, code[0], H); return 6, 0   # divide error with TE: nothing changes
def t_trap():                                   # exception in supervisor mode
    te = rnd.random() < .7; ldcr(14, 4 if te else 0)
    if rnd.random() < .3:                                                                                    # SCALL returning through the natural EPC (the next instruction)
        n = rnd.getrandbits(8); H = code[0] + 14 + 3 + 4; ldcr(9, H); hl = 12 + 2
        x = code[0]; emit([0xED, 0x22, n, 0xED, 0x2D] + le(hl, 2)); cr[12] = n; cr[11] = 5; cr[13] = x + 3; cr[18] = (cr[18] & 1) << 1; done(H)
        handler((5, n), cont=False); assert st['pc'] == x + 3
        done(code[0])                                                                                        # the JRW over the handler
    else:
        H = code[0] + 14 + GAP; ldcr(9, H); exp = one_trap(H, False, te); handler(exp)
    if te: ldcr(14, 0)
USERPOOL = None
def t_user():                                   # enters user mode (JP USER), runs ordinary instructions and leaves through exceptions
    te = rnd.random() < .6; ldcr(14, 4 if te else 0)
    H = code[0] + 14 + 13 + GAP; ldcr(9, H)
    j = rnd.randrange(4); u = [0, 2, 4, 7][j]; k = rnd.randrange(3); t = code[0] + 13 + k; ldq(u, t)
    emit([0xED, 0xB4 | j]); filler(k); cr[18] = 1; done(t)                                                   # JP USER,(uu): BC / DE / HL / AX
    rounds = rnd.randrange(1, 4)
    for i in range(rounds):
        for _ in range(rnd.randrange(0, 4)): rnd.choice(USERPOOL)()
        exp = one_trap(H, True, te); assert cr[18] == 2
        if i == rounds - 1: handler(exp, force=0)                        # last: returns in supervisor mode
        else: handler(exp, nextvec=True); H = code[0] + GAP; assert cr[18] == 1                               # returns to user mode
    if te: ldcr(14, 0)
USERPOOL = [t_alu, t_incdec, t_shift, t_bit, t_ldrr, t_ldimm, t_mul, t_ldabs]
io = {'n': 0, 'chk': 0}
def io_rd8(): v = ((r['BC'] & 0xFF) + 37 * io['n'] + io['chk']) & 0xFF; io['n'] = (io['n'] + 1) & 0xFF; return v
def io_wr8(d): io['chk'] = ((((io['chk'] << 1) | (io['chk'] >> 7)) & 0xFF) ^ d ^ (r['BC'] & 0xFF))
def t_io():                                      # INW/INL/INQ rr,(C) and OUTW/OUTL/OUTQ (C),rr: successive bytes on port C
    t = rnd.randrange(3); z = (16, 32, 64)[t]; rr = rnd.choice(R6)
    if rnd.random() < .5:
        v = 0
        for k in range(z // 8): v |= io_rd8() << (8 * k)
        if REG[rr] == 'BC': r['BC'] = (r['BC'] & ~msk(z) & 0xFFFFFFFFFFFFFFFF) | v     # BC is the port address: it cannot be preloaded
        else: wr_reg(REG[rr], v, z)
        seq([0xED, 0x27, t << 6 | rr << 3 | 1])
    else:
        v = r[REG[rr]] & msk(z)
        for k in range(z // 8): io_wr8((v >> (8 * k)) & 0xFF)
        seq([0xED, 0x27, t << 6 | rr << 3 | 6])
TESTS = [(t_io, 8), (t_fpu, int(os.environ.get('FPU_PESO', '14'))), (t_trap, 3), (t_user, 3), (t_ctx, 2), (t_mul, 10), (t_div, 8), (t_xchg, 3), (t_cas, 4), (t_cr, 3), (t_nop2, 2), (t_alu, 22), (t_incdec, 6), (t_shift, 10), (t_bit, 8), (t_ldrr, 5), (t_ldimm, 8), (t_ldmem, 8), (t_ldabs, 6), (t_ldidx, 8), (t_stack, 6),
         (t_jr, 5), (t_jpimm, 4), (t_jpreg, 4), (t_call, 4), (t_ret, 4)]
pool = [t for t, w in TESTS for _ in range(w)]
ld_sp(0xF000)
for c in R6: ldq(c, rnd.getrandbits(64))
init = bytearray(rnd.getrandbits(8) for _ in range(0x8000))
mem[0x8000:] = init
snapshot_data = bytes(init)
while len(trace) < N and code[0] < 0x7F00: rnd.choice(pool)()
emit([0x18, 0xFE])                              # JR $
final = bytes(mem)
start = bytearray(final); start[0x8000:] = snapshot_data      # initial memory: final code + initial data
open(pref + '_mem.hex', 'w').write('\n'.join('%02x' % b for b in start) + '\n')
open(pref + '_fim.hex', 'w').write('\n'.join('%02x' % b for b in final) + '\n')
open(pref + '_trace.txt', 'w').write('\n'.join(trace) + '\n')
# final FPU state: status word, empties and the 8 PHYSICAL registers (x = never written)
open(pref + '_fpu.hex', 'w').write('%04x\n%04x\n' % (fsw(), femp()) + ''.join(('%020x\n' % v) if w else ('x' * 20 + '\n') for v, w in zip(fp['st'], fp['wr'])))
sys.stderr.write('%d instructions, %d bytes of code, exceptions (cause, aux, user mode): %s FPU %s marks %02x\n' % (len(trace), code[0], sorted(ntrap.items()), sorted(nfp.items()), fp['exc'] | fp['sf'] << 6))
