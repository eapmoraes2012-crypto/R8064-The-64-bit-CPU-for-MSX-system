#!/usr/bin/env python3
# Independent reference model (Python integers) and vector generator for mul_unit and div_unit.
import random, sys
OUT = sys.argv[1]; rnd = random.Random(8064)
BITS = {0: 8, 1: 16, 2: 32, 3: 64}
def sx(v, n): v &= (1 << n) - 1; return v - (1 << n) if v >> (n - 1) else v
def rbits(n):
    k = rnd.choice([0, 1, 2, n // 4 or 1, n // 2, n - 1, n, n, n]); k = max(0, min(n, k))
    return rnd.getrandbits(k) if k else 0
# ---- multiplicador
mul = []
for sz in range(4):
    n = BITS[sz]; M = (1 << n) - 1
    corners = [0, 1, M, M - 1, 1 << (n - 1), (1 << (n - 1)) - 1, (1 << (n - 1)) + 1, 0x5555555555555555 & M, 0xAAAAAAAAAAAAAAAA & M, 2, 3]
    for sgn in (0, 1):
        for a in corners:
            for b in corners: mul.append((a, b, sz, sgn))
        for _ in range(2500): mul.append((rbits(n), rbits(n), sz, sgn))
        for _ in range(500): mul.append((rnd.getrandbits(n), rnd.getrandbits(n), sz, sgn))
rnd.shuffle(mul)
def mul_exp(a, b, sz, sgn):
    n = BITS[sz]; M = (1 << n) - 1; a &= M; b &= M
    if sgn: a, b = sx(a, n), sx(b, n)
    return (a * b) & ((1 << (2 * n)) - 1)
with open(OUT + '/mul_a.mem', 'w') as fa, open(OUT + '/mul_b.mem', 'w') as fb, open(OUT + '/mul_c.mem', 'w') as fc, open(OUT + '/mul_e.mem', 'w') as fe:
    for a, b, sz, sgn in mul:
        fa.write('%016x\n' % a); fb.write('%016x\n' % b); fc.write('%02x\n' % (sgn * 4 + sz)); fe.write('%032x\n' % mul_exp(a, b, sz, sgn))
# ---- divisor
div = []
def add(N, d, sz, sgn):   # N = dividend (integer, signed according to sgn), d = divisor
    n = BITS[sz]
    div.append((N & ((1 << (2 * n)) - 1), d & ((1 << n) - 1), sz, sgn))
for sz in range(4):
    n = BITS[sz]
    for sgn in (0, 1):
        lim = 1 << (n - 1)
        for _ in range(2200):
            kd = rnd.randint(1, n); d = rnd.getrandbits(kd) or 1
            kq = rnd.randint(0, n - 1 if sgn else n); q = rnd.getrandbits(kq) if kq else 0
            r = rnd.randrange(d); N = q * d + r
            if sgn:
                if rnd.random() < .5: d = -d
                if rnd.random() < .5: N = -N
                if d == -lim * 2: d = -lim
                if not (-lim <= sx(d, n) < lim): d = sx(d, n)
            add(N, d, sz, sgn)
        for _ in range(300):   # aleatorios totais (muitos estouros)
            add(rnd.getrandbits(2 * n), rnd.getrandbits(rnd.randint(1, n)), sz, sgn)
        # cantos
        if sgn:
            for N, d in [(-lim, -1), (-lim * 5, -1), (lim - 1, -1), (-lim, 1), (-(1 << (2 * n - 1)), 1), ((1 << (2 * n - 1)) - 1, 1),
                         (-(1 << (2 * n - 1)), -1), (0, -1), (0, 0), (5, 0), (-7, 2), (7, -2), (-7, -2), (7, 2), (-lim, lim - 1), (-lim * lim, -lim), (lim * lim - 1, lim)]:
                add(N, d, sz, sgn)
        else:
            for N, d in [(0, 1), ((1 << n) - 1, 1), (1 << n, 1), ((1 << (2 * n)) - 1, (1 << n) - 1), ((1 << (2 * n)) - 1, 1 << n >> 1), (5, 0), (0, 0), (1, 2), ((1 << (2 * n)) - 1, (1 << n) - 1), (((1 << n) - 1) * ((1 << n) - 1), (1 << n) - 1)]:
                add(N, d, sz, sgn)
rnd.shuffle(div)
def div_exp(N2, d, sz, sgn):
    n = BITS[sz]; M = (1 << n) - 1
    if sgn:
        N = sx(N2, 2 * n); dd = sx(d, n)
        if dd == 0: return 0, 0, 1
        qa = abs(N) // abs(dd); q = qa if (N < 0) == (dd < 0) else -qa
        r = N - q * dd
        if not (-(1 << (n - 1)) <= q < (1 << (n - 1))): return 0, 0, 1
        return q & M, r & M, 0
    if d == 0: return 0, 0, 1
    q, r = divmod(N2, d)
    if q > M: return 0, 0, 1
    return q, r, 0
with open(OUT + '/div_h.mem', 'w') as fh, open(OUT + '/div_l.mem', 'w') as fl, open(OUT + '/div_d.mem', 'w') as fd, open(OUT + '/div_c.mem', 'w') as fc, \
     open(OUT + '/div_q.mem', 'w') as fq, open(OUT + '/div_r.mem', 'w') as fr, open(OUT + '/div_e.mem', 'w') as fe:
    for N2, d, sz, sgn in div:
        n = BITS[sz]; M = (1 << n) - 1; q, r, e = div_exp(N2, d, sz, sgn)
        fh.write('%016x\n' % ((N2 >> n) & M)); fl.write('%016x\n' % (N2 & M)); fd.write('%016x\n' % d); fc.write('%02x\n' % (sgn * 4 + sz))
        fq.write('%016x\n' % q); fr.write('%016x\n' % r); fe.write('%x\n' % e)
open(OUT + '/nvec.txt', 'w').write('%d %d\n' % (len(mul), len(div)))
print('mul', len(mul), 'div', len(div), 'div with error', sum(div_exp(*x)[2] for x in div))
