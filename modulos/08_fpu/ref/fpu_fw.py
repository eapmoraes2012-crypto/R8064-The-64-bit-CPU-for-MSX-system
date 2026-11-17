# fpu_fw.py - 80-bit x87 FPU in FIRMWARE (measure A): only 64-bit integer primitives (mul 64x64->128, div 128/64, clz, shifts, add/sub/cmp with carry).
# Verified bit by bit against the same vectors as the hardware FPU (sim/vetores.txt). Special cases (NaN, inf, zero, unsupported) fall into the table
# decision (fpref.alu, branches only, fixed cost SPC clocks). Cost = pipeline clocks counted per primitive (model below).
import sys
from math import isqrt
import fpref as R
M64 = R.M64; BIAS = R.BIAS; EMIN = R.EMIN; EMAX = R.EMAX
# cost model (pipeline clocks at 100 MHz, 1 instruction/clock in dependent ALU; values from module03 and core_min)
C_ALU, C_MUL, C_DIV, C_BR, SPC = 1, 8, 66, 2, 40
cnt = 0
def c(n): 
    global cnt; cnt += n
def clz64(x): c(2); return 64 - x.bit_length()
def unpack(x):
    """(s,e,m) with m normalized (bit63=1), e = unbiased exponent of the leading bit; also returns denormal?"""
    s = x >> 79; ex = (x >> 64) & 0x7FFF; m = x & M64; c(5)
    if ex == 0:
        lz = clz64(m); c(3); return s, EMIN - lz, (m << lz) & M64, True
    return s, ex - BIAS, m, False

def rpack(s, E, M, stk, rc, p, emin, emax, fmt):
    """M: 128 bits normalized (bit127=1) value = M*2^(E-127). Returns (packed, flags, up)."""
    c(30)  # keep/drop, masks, half-scale comparisons (~30 64-bit ops, 128 bits = 2x)
    keep = p if E >= emin else p - (emin - E)
    d = 128 - keep
    k = M >> d if d < 128 else 0
    rem = M & ((1 << d) - 1)
    half = 1 << (d - 1)
    inex = (rem != 0) or stk
    gt = rem > half or (rem == half and stk); eq = rem == half and not stk
    if rc == 0: inc = gt or (eq and (k & 1))
    elif rc == 1: inc = inex and s == 1
    elif rc == 2: inc = inex and s == 0
    else: inc = False
    inc = bool(inc); k += inc
    fl = 0; up = inc and inex
    if inex: fl |= R.PE
    if E < emin and inex: fl |= R.UE
    Eq = max(E, emin)
    if k == 0:
        return (s << (79 if fmt == 80 else (31 if fmt == 32 else 63))), fl, up
    bl = k.bit_length(); Ef = Eq - (p - 1) + bl - 1
    if bl > p: k >>= 1; bl -= 1
    if Ef > emax:
        fl |= R.OE | R.PE; up = False
        inf_ = (rc == 0) or (rc == 2 and s == 0) or (rc == 1 and s == 1)
        if inf_:
            up = True
            if fmt == 80: return (s << 79) | (0x7FFF << 64) | (1 << 63), fl, up
            if fmt == 32: return (s << 31) | (0xFF << 23), fl, up
            return (s << 63) | (0x7FF << 52), fl, up
        k = (1 << p) - 1; bl = p; Ef = emax   # maior finito
    if fmt == 80:
        if Ef < EMIN:
            return (s << 79) | (k << (Eq - (p - 1) - (EMIN - 63))), fl, up
        return (s << 79) | ((Ef + BIAS) << 64) | (k << (64 - bl)), fl, up
    fb, ew, eb = (23, 8, 127) if fmt == 32 else (52, 11, 1023)
    if Ef < emin: return (s << (fb + ew)) | k, fl, up
    return (s << (fb + ew)) | ((Ef + eb) << fb) | ((k << (p - bl)) & ((1 << fb) - 1)), fl, up

def norm128(x):
    lz = 128 - x.bit_length(); c(6); return x << lz, lz

def k_add(sa, ea, ma, sb, eb, mb, rc, p):
    if (ea, ma) < (eb, mb): sa, ea, ma, sb, eb, mb = sb, eb, mb, sa, ea, ma; c(4)
    c(4); d = ea - eb
    A = ma << 64; B = mb << 64
    if d >= 130: Bs, stk = 0, True
    else: Bs = B >> d; stk = (Bs << d) != B
    c(14)
    if sa == sb:
        S = A + Bs; E = ea; c(6)
        if S >> 128: stk = stk or bool(S & 1); S >>= 1; E += 1
        return sa, E, S, stk
    S = A - Bs - (1 if stk else 0); c(6)
    if S == 0 and not stk: return None
    S, lz = norm128(S)
    return sa, ea - lz, S, stk

def k_mul(sa, ea, ma, sb, eb, mb):
    c(C_MUL + 2); P = ma * mb; E = ea + eb
    if P >> 127: E += 1
    else: P <<= 1
    c(3); return sa ^ sb, E, P, False

def k_div(sa, ea, ma, sb, eb, mb):
    c(2 * C_DIV + 8)
    N = ma << 128; Q, r = divmod(N, mb); stk = r != 0
    E = ea - eb
    if Q >> 128: stk = stk or bool(Q & 1); Q >>= 1
    else: E -= 1
    return sa ^ sb, E, Q, stk

def k_sqrt(ea, ma):
    t = ea - 63; sh = 130 + (t & 1); N = ma << sh
    r = isqrt(N); stk = r * r != N
    c(97 * 6 + 20)  # digit-by-digit: ~97 bits x (shift, compare, sub, or, 128 bits) ~ 6 ops
    bl = r.bit_length(); M = r << (128 - bl); E = (t - sh) // 2 + bl - 1
    return 0, E, M, stk

def fw_alu(op, A, B, rc, pc):
    """Retorna (res, flags, up, cc) e acumula clocks em cnt."""
    global cnt
    cnt = 0
    name = R.OPS[op]; p = R.pcbits(pc)
    ca = R.classify(A); cb = R.classify(B); c(8)
    if name == 'FILD':
        iv = A & M64
        if iv == 0: c(2); return R.alu(op, A, B, rc, pc), cnt
        s = iv >> 63; mag = ((1 << 64) - iv) & M64 if s else iv; c(4)
        lz = clz64(mag); m = (mag << lz) & M64; c(6)
        return ((s << 79) | ((63 - lz + BIAS) << 64) | m, 0, False, 0), cnt
    one = name in ('SQRT', 'RNDINT', 'FIST', 'ST32', 'ST64')
    if name in ('LD32', 'LD64'):
        if name == 'LD32':
            X = A & 0xFFFFFFFF; s = X >> 31; e = (X >> 23) & 0xFF; fr = X & 0x7FFFFF; eb_, fb, emx = 127, 23, 0xFF
        else:
            X = A & M64; s = X >> 63; e = (X >> 52) & 0x7FF; fr = X & ((1 << 52) - 1); eb_, fb, emx = 1023, 52, 0x7FF
        c(8)
        if e == emx or (e == 0 and fr == 0):
            c(SPC); return R.alu(op, A, B, rc, pc), cnt
        if e == 0:
            lz = 64 - fr.bit_length(); c(8)
            m = fr << lz; E = (1 - eb_) - (fb - (63 - lz)) if False else (1 - eb_) - fb + (63 - lz)
            return ((s << 79) | ((E + BIAS) << 64) | m, R.DE, False, 0), cnt
        c(6)
        return ((s << 79) | ((e - eb_ + BIAS) << 64) | (1 << 63) | (fr << (63 - fb)), 0, False, 0), cnt
    used = [ca] if one else [ca, cb]
    if name == 'CMP':
        used = [ca, cb]
    if any(u[0] not in ('norm', 'denorm') for u in used) or (name == 'SQRT' and ca[1]):
        c(SPC); return R.alu(op, A, B, rc, pc), cnt
    fl = R.DE if any(u[0] == 'denorm' for u in used) else 0
    sa, ea, ma, _ = unpack(A)
    if not one: sb, eb, mb, _ = unpack(B)
    if name == 'CMP':
        key = lambda s, e, m: (s, e, m)
        c(10)
        if (sa, ea, ma) == (sb, eb, mb): cc = 4
        elif sa != sb: cc = 1 if sa else 0
        else:
            gt = (ea, ma) > (eb, mb); cc = (0 if gt else 1) if not sa else (1 if gt else 0)
        return (0, fl, False, cc), cnt
    if name in ('ADD', 'SUB', 'MUL', 'DIV', 'SQRT'):
        if name == 'ADD': r = k_add(sa, ea, ma, sb, eb, mb, rc, p)
        elif name == 'SUB': r = k_add(sa, ea, ma, sb ^ 1, eb, mb, rc, p)
        elif name == 'MUL': r = k_mul(sa, ea, ma, sb, eb, mb)
        elif name == 'DIV': r = k_div(sa, ea, ma, sb, eb, mb)
        else: r = k_sqrt(ea, ma)
        if r is None: return ((1 if rc == 1 else 0) << 79, fl, False, 0), cnt
        s, E, M, stk = r
        o, f2, up = rpack(s, E, M, stk, rc, p, EMIN, EMAX, 80)
        return (o, fl | f2, up, 0), cnt
    if name in ('ST32', 'ST64'):
        fmt = 32 if name == 'ST32' else 64
        p2, e2, x2 = (24, -126, 127) if fmt == 32 else (53, -1022, 1023)
        o, f2, up = rpack(sa, ea, ma << 64, False, rc, p2, e2, x2, fmt)
        return (o, fl | f2, up, 0), cnt
    if name in ('FIST', 'RNDINT'):
        c(30)
        if ea >= 63:
            k = ma << (ea - 63); inex = False; rem = 0; half = 1; up = False
            if name == 'FIST':
                if ea > 63 or (sa == 0 and ma >> 63 and False): pass
        else:
            sh = 63 - ea
            k = ma >> sh if sh < 64 else 0
            rem = ma & ((1 << sh) - 1); half = 1 << (sh - 1)
            inex = rem != 0
        if rc == 0: inc = rem > half or (rem == half and (k & 1))
        elif rc == 1: inc = inex and sa == 1
        elif rc == 2: inc = inex and sa == 0
        else: inc = False
        inc = bool(inc); k += inc
        f2 = R.PE if inex else 0; up = inc and inex
        if name == 'FIST':
            if (sa == 0 and k > (1 << 63) - 1) or (sa == 1 and k > (1 << 63)): return (0x8000000000000000, fl | R.IE, False, 0), cnt
            return (((-k if sa else k) & M64), fl | f2, up, 0), cnt
        if k == 0: return (sa << 79, fl | f2, up, 0), cnt
        bl = k.bit_length(); c(6)
        m = (k >> (bl - 64)) if bl > 64 else (k << (64 - bl))
        return ((sa << 79) | ((bl - 1 + BIAS) << 64) | m, fl | f2, up, 0), cnt
    raise ValueError(name)

if __name__ == '__main__':
    fn = sys.argv[1] if len(sys.argv) > 1 else '../sim/vetores.txt'
    bad = 0; n = 0; tot = {}; mx = {}
    for ln in open(fn):
        t = ln.split()
        op, rc, pc = int(t[0], 16), int(t[1]), int(t[2])
        A, B, Rr = int(t[3], 16), int(t[4], 16), int(t[5], 16)
        fl, up, cc = int(t[6], 16), int(t[7]), int(t[8])
        (res, f, u, k), cy = fw_alu(op, A, B, rc, pc); n += 1
        if (res, f, int(bool(u)), k) != (Rr, fl, up, cc):
            bad += 1
            if bad <= 8: print('ERROR', ln.strip(), '->', hex(res), hex(f), int(bool(u)), k)
        nm = R.OPS[op]; tot.setdefault(nm, []).append(cy)
    print('vectors', n, 'errors', bad)
    for nm, l in tot.items():
        l.sort(); print('%-7s n=%5d median=%4d max=%4d' % (nm, len(l), l[len(l)//2], l[-1]))
