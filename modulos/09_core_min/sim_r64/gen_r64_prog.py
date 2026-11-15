# gen_r64_prog.py - programa aleatorio das instrucoes inteiras do R8064 (16/32/64 bits) + MODELO de referencia em Python.
# Uso: python3 gen_r64_prog.py <semente> <prefixo> [N]   -> <prefixo>_mem.hex (64 KB), <prefixo>_trace.txt, <prefixo>_fim.hex
# O modelo foi escrito a partir de ../PREMISSAS_R8064.txt (nao do RTL). O programa e gerado e executado no modelo ao mesmo tempo, entao o gerador sabe
# o valor dos registradores: ponteiros de leitura/gravacao sempre caem na area de dados (8000h-FFFFh; o codigo fica abaixo) e os desvios sao para a frente.
# Cada linha do traco = estado depois de uma instrucao: pc ax bc de hl ix iy sp f (64 bits em hexadecimal; f com 2 digitos).
# O testbench usa uma memoria de 64 KB (endereco de 16 bits); o modelo faz o mesmo.
import random, sys
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
def par8(v): return bin(v & 0xFF).count('1') % 2 == 0
def msk(n): return (1 << n) - 1
def wr_reg(name, val, n):                       # escreve n bits, preserva os de cima
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
code = [0]                                      # posicao de montagem (= pc quando a execucao e sequencial)
def emit(bs):
    a = code[0]; mem[a:a + len(bs)] = bytes(bs); code[0] += len(bs); return a
def done(pc):                                   # fim de uma instrucao no modelo
    st['pc'] = pc & M64
    trace.append('%016x %016x %016x %016x %016x %016x %016x %016x %02x' % (st['pc'], r['AX'], r['BC'], r['DE'], r['HL'], r['IX'], r['IY'], r['SP'], st['f']))
def seq(bs): emit(bs); done(code[0])            # instrucao sequencial: executa (ja feito pelo chamador) e avanca
def nops(k):                                    # k NOPs executados em sequencia
    for _ in range(k): seq([0x00])
def filler(k): emit([0x00] * k)                 # k bytes pulados por um desvio tomado
# ---------- emissores (codificam, executam no modelo e registram o traco) ----------
def ldq(code_r, val):                           # LDQ rr, nnnnnnnn
    r[REG[code_r]] = val & M64; seq([0xED, 0x39, 0x40 | code_r << 3 | 1] + le(val, 8))
def ld_sp(v):                                   # LD SP,nn (Z80): escreve 16 bits
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
    elif k == 1: v = rnd.getrandbits(n); wrm(a, v, n); seq([0xED, pfx, 0x40 | o << 3 | low] + d2 + le(v, n // 8))   # LDx (QIX+dd),imediato
    else: wr_reg(REG[o], rdm(a, n), n); seq([0xED, pfx, (0xC0 | o << 3 | 6) if s == 'Q' else (0x80 | o << 3 | low)] + d2)   # LDx rr,(QIX+dd)
def chk_sp():
    if not 0x9000 <= r['SP'] <= 0xFFE0: ld_sp(rnd.randrange(0xC000, 0xFF00))
def t_stack():
    chk_sp(); s = rnd.choice('EQ'); n = BITS[s]; o = rnd.choice(R6); q = 1 if s == 'Q' else 0
    if rnd.random() < .5: wrm(r['SP'] - n // 8, r[REG[o]], n); r['SP'] = (r['SP'] - n // 8) & M64; seq([0xED, 0x38, 0x80 | q << 6 | 1 << 3 | o])   # PUSHx
    else:                                                                                                    # POPx (o valor lido vale antes de SP mudar)
        v = rdm(r['SP'], n); wr_reg(REG[o], v, n); r['SP'] = (r['SP'] + n // 8) & M64; seq([0xED, 0x38, q << 6 | 1 << 3 | o])
def branch(bs, taken, k, target=None):          # desvio para a frente por cima de k bytes; nao tomado: os k NOPs sao executados
    a = emit(bs)
    if taken: filler(k); done(code[0] if target is None else target)
    else: done(code[0]); nops(k)
def t_jr():
    k = rnd.randrange(0, 5); kind = rnd.randrange(3)
    if kind == 0: branch([0xED, 0x2D] + le(k, 2), True, k)                                                   # JRW nn
    elif kind == 1: cc = rnd.randrange(8); branch([0xED, 0x2A, cc << 3 | 1] + le(k, 2), cond(cc), k)         # JRW cc,nn
    else:                                                                                                    # DJNZW nn
        b = ((r['BC'] >> 8) - 1) & 0xFF; r['BC'] = (r['BC'] & ~0xFF00 & M64) | b << 8; branch([0xED, 0x2E] + le(k, 2), b != 0, k)
def t_jpimm():
    k = rnd.randrange(0, 5); kind = rnd.randrange(4)
    if kind == 0: t = code[0] + 6 + k; branch([0xED, 0x2C] + le(t, 4), True, k)                              # JPE nnnn
    elif kind == 1: t = code[0] + 10 + k; branch([0xED, 0x2B] + le(t, 8), True, k)                           # JPQ nnnnnnnn
    elif kind == 2: cc = rnd.randrange(8); t = code[0] + 7 + k; branch([0xED, 0x2A, 0x80 | cc << 3 | 1] + le(t, 4), cond(cc), k)   # JPE cc,nnnn
    else: cc = rnd.randrange(8); t = code[0] + 11 + k; branch([0xED, 0x2A, 0xC0 | cc << 3 | 6] + le(t, 8), cond(cc), k)            # JPQ cc,nnnnnnnn
def t_jpreg():
    k = rnd.randrange(0, 5); kind = rnd.randrange(4); v = rnd.choice(R6); e = kind in (0, 2)
    t = code[0] + 11 + 3 + k                                                                                 # depois do LDQ (11 bytes) e do JP (3 bytes)
    ldq(v, t | (rnd.getrandbits(32) << 32 if e else 0))                                                      # JPE ignora os 32 bits de cima
    if kind == 0: branch([0xED, 0x2A, 0x40 | v << 3 | 1], True, k)                                           # JPE (vv)
    elif kind == 1: branch([0xED, 0x2A, 0xC0 | v << 3 | 1], True, k)                                         # JPQ (vv)
    elif kind == 2: cc = rnd.randrange(8); branch([0xED, 0x2A, cc << 3 | v], cond(cc), k)                    # JPE cc,(vv)
    else: cc = rnd.randrange(8); branch([0xED, 0x2A, 0x40 | cc << 3 | v], cond(cc), k)                       # JPQ cc,(vv)
def push_ret(n, ret):
    wrm(r['SP'] - n // 8, ret, n); r['SP'] = (r['SP'] - n // 8) & M64
def t_call():
    chk_sp(); k = rnd.randrange(0, 5); s = rnd.choice('EQ'); n = BITS[s]; kind = rnd.randrange(3)
    if kind == 0:                                                                                            # CALLx imediato
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
    ldq(v, t | (rnd.getrandbits(32) << 32 if s == 'E' else 0))                                               # RETE usa so os 32 bits baixos
    wrm(r['SP'] - n // 8, r[REG[v]], n); r['SP'] = (r['SP'] - n // 8) & M64; seq([0xED, 0x38, 0x80 | q << 6 | 1 << 3 | v])   # PUSHx rr
    tk = True if cc == 8 else cond(cc)
    if tk: r['SP'] = (r['SP'] + n // 8) & M64
    bs = [0xED, 0x04 + q] if cc == 8 else [0xED, 0x03, (0x80 if q else 0x40) | cc << 3]
    branch(bs, tk, k)                                                                                        # o alvo lido da pilha = t (32 bits baixos em RETE)
def sgn(v, n): v &= msk(n); return v - (1 << n) if v >> (n - 1) else v
def r8get(u): name, sh = R8[u]; return (r[name] >> sh) & 0xFF
def ldx(code_r, val, s):                        # LDW/LDE/LDQ rr, imediato
    n = BITS[s]; wr_reg(REG[code_r], val, n); seq([0xED, LDB2[s], 0x40 | code_r << 3 | 1] + le(val & msk(n), n // 8))
def t_mul():
    k = rnd.randrange(7)
    if k == 0:                                                                                               # MLTUB A,u (R800): HL = A * u
        u = rnd.choice(list(R8)); wr_reg('HL', (r['AX'] & 0xFF) * r8get(u), 16); seq([0xED, 0xC1 | u << 3])
    elif k == 1:                                                                                             # MLTUW HL,BC / HL,SP (R800): DE:HL = HL * rr
        nm, b2 = rnd.choice([('BC', 0xC3), ('SP', 0xF3)]); p = (r['HL'] & 0xFFFF) * (r[nm] & 0xFFFF)
        wr_reg('HL', p, 16); wr_reg('DE', p >> 16, 16); seq([0xED, b2])
    elif k == 2:                                                                                             # MLTSB AL,u: AX (16 bits) = AL * u
        u = rnd.choice(list(R8)); wr_reg('AX', sgn(r['AX'], 8) * sgn(r8get(u), 8), 16); seq([0xED, 0x3F, 0x08 | u])
    else:
        sg = rnd.random() < .5; s = 'WEQ'[k % 3]; n = BITS[s]; c = rnd.choice(R6); b2 = 0x3F if sg else 0x3E
        a, b = (r['HL'] if s == 'W' else r['AX']), r[REG[c]]
        p = (sgn(a, n) * sgn(b, n)) if sg else ((a & msk(n)) * (b & msk(n)))
        if s == 'W': wr_reg('HL', p, 16); wr_reg('DE', p >> 16, 16)                                          # MLTxW HL,rr: DE:HL
        elif s == 'E': r['AX'] = p & M64                                                                     # MLTxE: QA
        else:
            r['AX'] = p & M64                                                                                # MLTUQ: QA ; MLTSQ: QDE:QA
            if sg: r['DE'] = (p >> 64) & M64
        seq([0xED, b2, 'BWEQ'.index(s) << 6 | 1 << 3 | c])
def t_div():                                    # operandos preparados para NAO dar erro (divisor zero / quociente fora da faixa)
    sg = rnd.random() < .5; s = rnd.choice('BWEQ'); n = BITS[s]; b2 = 0x3D if sg else 0x3C
    if s == 'B': c = rnd.randrange(6); dname = None
    else: c = rnd.choice([0, 3, 4, 5]); dname = REG[c]                                                       # divisor: BC, IY, HL ou IX
    while True:
        d = rnd.getrandbits(n) if rnd.random() < .7 else rnd.getrandbits(rnd.randrange(1, n))
        if sg:
            dv = sgn(d, n)
            if dv == 0: continue
            q = rnd.randrange(-(1 << (n - 1)), 1 << (n - 1)); rem = rnd.randrange(abs(dv)); dd = q * dv
            dd += rem if dd >= 0 else -rem
            if dd == 0 and q != 0: continue
            q = abs(dd) // abs(dv) * (1 if (dd < 0) == (dv < 0) else -1); rem = dd - q * dv
            if not -(1 << (n - 1)) <= q < (1 << (n - 1)): continue
        else:
            if d == 0: continue
            dd = rnd.randrange(d << n) if rnd.random() < .7 else rnd.getrandbits(n); q, rem = dd // d, dd % d
        break
    lo, hi = dd & msk(n), (dd >> n) & msk(n)
    if s == 'B':
        name, sh = R8[c]; ldx({'BC': 0, 'DE': 2, 'HL': 4}[name], (rnd.getrandbits(8) << (8 - sh)) | (d << sh), 'W')   # divisor num registrador de 8 bits
        ldx(7, hi << 8 | lo, 'W'); wr_reg('AX', (rem & 0xFF) << 8 | (q & 0xFF), 16)                          # AL = quociente, AH = resto
    elif s == 'E':
        ldx(c, d, 'E'); ldx(7, hi << 32 | lo, 'Q'); r['AX'] = (rem & msk(32)) << 32 | (q & msk(32))          # QA = {resto, quociente}
    else:
        ldx(c, d, s); ldx(2, hi, s); ldx(7, lo, s); wr_reg('AX', q, n); wr_reg('DE', rem, n)                 # AX = quociente, DE = resto
    seq([0xED, b2, 'BWEQ'.index(s) << 6 | 1 << 3 | c])
def t_xchg():
    s = rnd.choice('EQ'); n = BITS[s]; p, o = rnd.choice(R6), rnd.choice(R6); q = 1 if s == 'Q' else 0
    ldq(p, data_addr(n)); a = r[REG[p]]; old = rdm(a, n); wrm(a, r[REG[o]], n); wr_reg(REG[o], old, n)
    seq([0xED, 0xAC, q << 6 | o << 3 | p])                                                                   # XCHGx rr,(rr')
def t_cas():
    s = rnd.choice('EQ'); n = BITS[s]; p, o = rnd.choice([0, 2, 3, 4, 5]), rnd.choice(R6); q = 1 if s == 'Q' else 0
    ldq(p, data_addr(n)); a = r[REG[p]]; m = rdm(a, n)
    if rnd.random() < .5: ldq(7, m | (rnd.getrandbits(32) << 32 if s == 'E' else 0))                         # metade das vezes A ja e igual
    res, f = arith(r['AX'], m, n, True, 0, xy_from_b=True); st['f'] = f; eq = (r['AX'] & msk(n)) == m
    wr_reg('AX', m, n)
    if eq: wrm(a, r[REG[o]], n)
    seq([0xED, 0xAD, q << 6 | p << 3 | o])                                                                   # CASx (rr'),rr
cr = [0] * 8
def t_cr():
    k = rnd.randrange(8); c = rnd.choice(R6)
    if rnd.random() < .5: cr[k] = r[REG[c]]; seq([0xED, 0x20, k << 3 | c])                                   # LDCR kk,rr
    else: r[REG[c]] = cr[k]; seq([0xED, 0x21, k << 3 | c])                                                   # STCR rr,kk
def t_nop2(): seq(rnd.choice([[0xED, 0xA5], [0xED, 0xA6], [0xED, 0x08], [0xED, 0x0F], [0xED, 0xC4], [0xED, 0xFC]]))   # FENCE, ISYNC, ED ilegal (NOP de 2 bytes), PGINV
TESTS = [(t_mul, 10), (t_div, 8), (t_xchg, 3), (t_cas, 4), (t_cr, 3), (t_nop2, 2), (t_alu, 22), (t_incdec, 6), (t_shift, 10), (t_bit, 8), (t_ldrr, 5), (t_ldimm, 8), (t_ldmem, 8), (t_ldabs, 6), (t_ldidx, 8), (t_stack, 6),
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
start = bytearray(final); start[0x8000:] = snapshot_data      # memoria inicial: codigo final + dados iniciais
open(pref + '_mem.hex', 'w').write('\n'.join('%02x' % b for b in start) + '\n')
open(pref + '_fim.hex', 'w').write('\n'.join('%02x' % b for b in final) + '\n')
open(pref + '_trace.txt', 'w').write('\n'.join(trace) + '\n')
sys.stderr.write('%d instrucoes, %d bytes de codigo\n' % (len(trace), code[0]))
