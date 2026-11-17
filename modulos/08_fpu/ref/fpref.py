# fpref.py - EXACT reference model (Fraction) of the arithmetic core of the R8064 80-bit FPU.
# Conventions (x87): rc 0=nearest-even 1=toward -inf 2=toward +inf 3=toward zero; pc 0=24 bits 2=53 bits 3=64 bits (1 = 64).
# flags: bit0 IE, bit1 DE, bit2 ZE, bit3 OE, bit4 UE, bit5 PE.  up = magnitude incrementada no arredondamento (C1).
# cc = (c3,c2,c0) only in CMP.  My decisions: unsupported formats (pseudo-denormal, unnormal, pseudo-NaN/inf) -> IE + indefinite;
# tininess BEFORE rounding; UE = tiny && inexact; NaN with two NaNs: larger significand (tie -> A); denormal at input -> DE.
from fractions import Fraction as F
BIAS = 16383; EMIN = -16382; EMAX = 16383
M64 = (1 << 64) - 1
INDEF = (1 << 79) | (0x7FFF << 64) | 0xC000000000000000
IE, DE, ZE, OE, UE, PE = 1, 2, 4, 8, 16, 32
OPS = ['ADD', 'SUB', 'MUL', 'DIV', 'SQRT', 'CMP', 'FILD', 'FIST', 'RNDINT', 'LD32', 'LD64', 'ST32', 'ST64']

def classify(x):
    s = (x >> 79) & 1; ex = (x >> 64) & 0x7FFF; m = x & M64
    if ex == 0:
        if m == 0: return ('zero', s, 0)
        if m >> 63: return ('unsup', s, m)
        return ('denorm', s, m)
    if ex == 0x7FFF:
        if not (m >> 63): return ('unsup', s, m)
        if (m & ((1 << 63) - 1)) == 0: return ('inf', s, m)
        return ('nan', s, m)
    if not (m >> 63): return ('unsup', s, m)
    return ('norm', s, m)

def value(x):
    k, s, m = classify(x); ex = (x >> 64) & 0x7FFF
    if k == 'norm': return F(m) * F(2) ** (ex - BIAS - 63)
    if k == 'denorm': return F(m) * F(2) ** (EMIN - 63)
    return F(0)

def isnan_signaling(m): return not ((m >> 62) & 1)
def qnan(s, m): return (s << 79) | (0x7FFF << 64) | m | (1 << 62)

def flog2(v):
    E = v.numerator.bit_length() - v.denominator.bit_length()
    if F(2) ** E > v: E -= 1
    elif F(2) ** (E + 1) <= v: E += 1
    return E

def round_core(sign, v, rm, p, emin, emax):
    """v>0 exato. Retorna (res_frac, inexact, inc, tiny, overflow)."""
    E = flog2(v); Eq = max(E, emin)
    q = F(2) ** (Eq - (p - 1)); n = v / q; k = n.numerator // n.denominator; rem = n - k
    inex = rem != 0
    if rm == 0: inc = rem > F(1, 2) or (rem == F(1, 2) and (k & 1))
    elif rm == 1: inc = inex and sign == 1
    elif rm == 2: inc = inex and sign == 0
    else: inc = False
    k += 1 if inc else 0
    res = k * q
    tiny = v < F(2) ** emin
    ovf = res >= F(2) ** (emax + 1)
    return res, inex, bool(inc), tiny, ovf

def maxfin(p, emax): return (F(2) ** p - 1) * F(2) ** (emax - (p - 1))

def pack80(sign, res, p=64):
    if res == 0: return sign << 79
    if res < F(2) ** EMIN:
        m = res / F(2) ** (EMIN - 63); assert m.denominator == 1
        return (sign << 79) | int(m)
    E = flog2(res); m = res / F(2) ** (E - 63); assert m.denominator == 1, (res, E)
    return (sign << 79) | ((E + BIAS) << 64) | int(m)

def pack_ieee(sign, res, fmt):
    if fmt == 32: p, emin, emax, eb, fb = 24, -126, 127, 127, 23
    else: p, emin, emax, eb, fb = 53, -1022, 1023, 1023, 52
    ew = 8 if fmt == 32 else 11
    if res == 0: return sign << (fb + ew)
    if res < F(2) ** emin:
        fr = res / F(2) ** (emin - fb); assert fr.denominator == 1
        return (sign << (fb + ew)) | int(fr)
    E = flog2(res); fr = (res / F(2) ** E - 1) * F(2) ** fb; assert fr.denominator == 1
    return (sign << (fb + ew)) | ((E + eb) << fb) | int(fr)

def round_to(sign, v, rc, p, emin, emax, fmt):
    """v>0. Retorna (packed, flags, up)."""
    res, inex, inc, tiny, ovf = round_core(sign, v, rc, p, emin, emax)
    fl = 0; up = inc and inex
    if inex: fl |= PE
    if tiny and inex: fl |= UE
    if ovf:
        fl |= OE | PE; up = False
        inf_ = (rc == 0) or (rc == 2 and sign == 0) or (rc == 1 and sign == 1)
        if inf_:
            up = True
            if fmt == 80: return (sign << 79) | (0x7FFF << 64) | (1 << 63), fl, up
            if fmt == 32: return (sign << 31) | (0xFF << 23), fl, up
            return (sign << 63) | (0x7FF << 52), fl, up
        res = maxfin(p, emax)
    if fmt == 80: return pack80(sign, res), fl, up
    return pack_ieee(sign, res, fmt), fl, up

def pcbits(pc): return {0: 24, 2: 53}.get(pc, 64)

def nan_pick(ca, cb, A, B):
    """Returns NaN result (quiet) and the IE flag."""
    ie = 0
    cands = []
    for c, X in ((ca, A), (cb, B)):
        if c[0] == 'nan':
            if isnan_signaling(c[2]): ie = IE
            cands.append((c[1], c[2] | (1 << 62)))
    if len(cands) == 1: s, m = cands[0]
    else: s, m = cands[1] if cands[1][1] > cands[0][1] else cands[0]
    return qnan(s, m & ~(1 << 62) & M64 | 0) if False else (s << 79) | (0x7FFF << 64) | m, ie

def alu(op, A, B, rc, pc):
    """Retorna (res, flags, up, cc)."""
    name = OPS[op] if isinstance(op, int) else op
    p = pcbits(pc)
    ca = classify(A); cb = classify(B)
    fl = 0; up = False; cc = 0
    if name in ('ADD', 'SUB', 'MUL', 'DIV', 'SQRT', 'CMP', 'RNDINT', 'FIST', 'ST32', 'ST64'):
        used = [ca] if name in ('SQRT', 'RNDINT', 'FIST', 'ST32', 'ST64') else [ca, cb]
        if any(c[0] == 'denorm' for c in used): fl |= DE
    else: used = []
    if name in ('ADD', 'SUB', 'MUL', 'DIV', 'SQRT', 'RNDINT'):
        if any(c[0] == 'unsup' for c in used): return INDEF, fl | IE, False, 0
        if any(c[0] == 'nan' for c in used):
            r, ie = nan_pick(ca, cb, A, B) if len(used) == 2 else nan_pick(ca, ca, A, A)
            return r, fl | ie, False, 0
    if name in ('ADD', 'SUB'):
        sb = cb[1] ^ (1 if name == 'SUB' else 0); sa = ca[1]
        if ca[0] == 'inf' and cb[0] == 'inf':
            return (INDEF, fl | IE, False, 0) if sa != sb else ((sa << 79) | (0x7FFF << 64) | (1 << 63), fl, False, 0)
        if ca[0] == 'inf': return (sa << 79) | (0x7FFF << 64) | (1 << 63), fl, False, 0
        if cb[0] == 'inf': return (sb << 79) | (0x7FFF << 64) | (1 << 63), fl, False, 0
        va = value(A) * (-1 if sa else 1); vb = value(B) * (-1 if sb else 1)
        if ca[0] == 'zero' and cb[0] == 'zero':
            s = sa if sa == sb else (1 if rc == 1 else 0)
            return s << 79, fl, False, 0
        r = va + vb
        if r == 0: return (1 if rc == 1 else 0) << 79, fl, False, 0
        s = 1 if r < 0 else 0
        o, f2, up = round_to(s, abs(r), rc, p, EMIN, EMAX, 80)
        return o, fl | f2, up, 0
    if name == 'MUL':
        s = ca[1] ^ cb[1]
        if (ca[0] == 'inf' and cb[0] == 'zero') or (ca[0] == 'zero' and cb[0] == 'inf'): return INDEF, fl | IE, False, 0
        if ca[0] == 'inf' or cb[0] == 'inf': return (s << 79) | (0x7FFF << 64) | (1 << 63), fl, False, 0
        if ca[0] == 'zero' or cb[0] == 'zero': return s << 79, fl, False, 0
        o, f2, up = round_to(s, value(A) * value(B), rc, p, EMIN, EMAX, 80)
        return o, fl | f2, up, 0
    if name == 'DIV':
        s = ca[1] ^ cb[1]
        if (ca[0] == 'inf' and cb[0] == 'inf') or (ca[0] == 'zero' and cb[0] == 'zero'): return INDEF, fl | IE, False, 0
        if cb[0] == 'zero': return (s << 79) | (0x7FFF << 64) | (1 << 63), fl | ZE, False, 0
        if ca[0] == 'inf': return (s << 79) | (0x7FFF << 64) | (1 << 63), fl, False, 0
        if cb[0] == 'inf' or ca[0] == 'zero': return s << 79, fl, False, 0
        o, f2, up = round_to(s, value(A) / value(B), rc, p, EMIN, EMAX, 80)
        return o, fl | f2, up, 0
    if name == 'SQRT':
        s = ca[1]
        if ca[0] == 'zero': return A & (1 << 79), fl, False, 0
        if s == 1: return INDEF, fl | IE, False, 0
        if ca[0] == 'inf': return (0x7FFF << 64) | (1 << 63), fl, False, 0
        v = value(A); K = 80 - flog2(v) // 2
        from math import isqrt
        Nn = v * F(4) ** K; Ni = Nn.numerator // Nn.denominator
        r = isqrt(Ni); exact = (r * r == Ni) and Nn.denominator == 1
        rv = F(r) if exact else F(r) + F(1, 2)
        o, f2, up = round_to(0, rv / F(2) ** K, rc, p, EMIN, EMAX, 80)
        return o, fl | f2, up, 0
    if name == 'CMP':
        if ca[0] in ('unsup', 'nan') or cb[0] in ('unsup', 'nan'): return 0, fl | IE, False, 7
        def key(c, X):
            if c[0] == 'inf': return (-2 if c[1] else 2, F(0))
            return (0, value(X) * (-1 if c[1] else 1))
        ka, kb = key(ca, A), key(cb, B)
        return 0, fl, False, (4 if ka == kb else (0 if ka > kb else 1))
    if name == 'FILD':
        iv = A & M64
        if iv >> 63: iv -= 1 << 64
        if iv == 0: return 0, 0, False, 0
        s = 1 if iv < 0 else 0
        return pack80(s, F(abs(iv))), 0, False, 0
    if name in ('FIST', 'RNDINT'):
        s = ca[1]
        if name == 'FIST':
            if ca[0] in ('unsup', 'nan', 'inf'): return 0x8000000000000000, fl | IE, False, 0
            if ca[0] == 'zero': return 0, fl, False, 0
        else:
            if ca[0] in ('inf',): return A, fl, False, 0
            if ca[0] == 'zero': return A, fl, False, 0
        v = value(A)
        n = v.numerator // v.denominator; rem = v - n; inex = rem != 0
        if rc == 0: inc = rem > F(1, 2) or (rem == F(1, 2) and (n & 1))
        elif rc == 1: inc = inex and s == 1
        elif rc == 2: inc = inex and s == 0
        else: inc = False
        k = n + (1 if inc else 0)
        f2 = PE if inex else 0
        up = bool(inc and inex)
        if name == 'FIST':
            if (s == 0 and k > (1 << 63) - 1) or (s == 1 and k > (1 << 63)): return 0x8000000000000000, fl | IE, False, 0
            r = (-k if s else k) & M64
            return r, fl | f2, up, 0
        if k == 0: return (s << 79), fl | f2, up, 0
        return pack80(s, F(k)), fl | f2, up, 0
    if name in ('LD32', 'LD64'):
        if name == 'LD32':
            X = A & 0xFFFFFFFF; s = X >> 31; e = (X >> 23) & 0xFF; fr = X & 0x7FFFFF; eb = 127; fb = 23; emax_e = 0xFF
        else:
            X = A & M64; s = X >> 63; e = (X >> 52) & 0x7FF; fr = X & ((1 << 52) - 1); eb = 1023; fb = 52; emax_e = 0x7FF
        if e == emax_e:
            if fr == 0: return (s << 79) | (0x7FFF << 64) | (1 << 63), 0, False, 0
            ie = IE if not (fr >> (fb - 1)) else 0
            m = (1 << 63) | (fr << (63 - fb)) | (1 << 62)
            return (s << 79) | (0x7FFF << 64) | m, ie, False, 0
        if e == 0:
            if fr == 0: return s << 79, 0, False, 0
            return pack80(s, F(fr) * F(2) ** (1 - eb - fb)), DE, False, 0
        return pack80(s, (1 + F(fr, 1 << fb)) * F(2) ** (e - eb)), 0, False, 0
    if name in ('ST32', 'ST64'):
        fmt = 32 if name == 'ST32' else 64
        fb = 23 if fmt == 32 else 52; ew = 8 if fmt == 32 else 11
        ind = (1 << (fb + ew)) | (((1 << ew) - 1) << fb) | (1 << (fb - 1))
        s = ca[1]
        if ca[0] == 'unsup': return ind, fl | IE, False, 0
        if ca[0] == 'nan':
            m = ca[2]; ie = IE if isnan_signaling(m) else 0
            fr = ((m >> (63 - fb)) & ((1 << fb) - 1)) | (1 << (fb - 1))
            return (s << (fb + ew)) | (((1 << ew) - 1) << fb) | fr, fl | ie, False, 0
        if ca[0] == 'inf': return (s << (fb + ew)) | (((1 << ew) - 1) << fb), fl, False, 0
        if ca[0] == 'zero': return s << (fb + ew), fl, False, 0
        p2, emin2, emax2 = (24, -126, 127) if fmt == 32 else (53, -1022, 1023)
        o, f2, up = round_to(s, value(A), rc, p2, emin2, emax2, fmt)
        return o, fl | f2, up, 0
    raise ValueError(name)
