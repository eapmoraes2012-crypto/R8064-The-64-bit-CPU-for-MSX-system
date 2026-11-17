# test_macro.py - accuracy of the macro programs (Python model) against high-precision ground truth
import random, sys
import fpu_macro as M, fpref
from fractions import Fraction as F
rnd = random.Random(int(sys.argv[1]) if len(sys.argv) > 1 else 1)
HP = M.HP; LN2 = M.LN2
def val(v):
    s = -1 if (v >> 79) & 1 else 1; return s * fpref.value(v)
def tsincos(x):
    k = round(x / HP); r = x - k * HP
    s = F(0); c = F(0); t = F(1); n = 0
    while abs(t) > F(1, 1 << 220):
        if n % 2 == 0: c += t * (1 if (n // 2) % 2 == 0 else -1)
        else: s += t * (1 if (n // 2) % 2 == 0 else -1)
        n += 1; t = t * r / n
    q = k % 4
    S = [s, c, -s, -c][q]; C = [c, -s, -c, s][q]
    return S, C
def tln(x):
    e = 0
    while x > 2: x /= 2; e += 1
    while x < 1: x *= 2; e -= 1
    z = (x - 1) / (x + 1); w = z * z; t = z; s = F(0); k = 0
    while abs(t) > F(1, 1 << 230): s += t / (2 * k + 1); t *= w; k += 1
    return 2 * s + e * LN2
def ulps(res, t):
    if t == 0: return 0 if val(res) == 0 else 1e9
    E = fpref.flog2(abs(t)); u = F(2) ** (E - 63)
    return float(abs(val(res) - t) / u)
def mk(x):
    return fpref.pack80(1 if x < 0 else 0, abs(x)) if x != 0 else 0
def newfp():
    return {'st': [0] * 8, 'tg': [3] * 8, 'top': 0, 'cw': 0x37F, 'exc': 0, 'c': [0, 0, 0, 0]}
def push(fp, v):
    fp['top'] = (fp['top'] - 1) & 7; fp['st'][fp['top']] = v; fp['tg'][fp['top']] = M.ctag(v)
def rx(lo, hi):
    e = rnd.uniform(lo, hi); m = 1 + rnd.random(); x = F(m) * F(2) ** int(e)
    return -x if rnd.random() < .5 else x
worst = {}
def rec(n, u): worst[n] = max(worst.get(n, 0), u)
N = int(sys.argv[2]) if len(sys.argv) > 2 else 150
for _ in range(N):
    x = rx(-30, 28.9) if rnd.random() < .8 else rx(-8, 3)
    xv = pk = mk(x); xv = fpref.pack80(1 if x < 0 else 0, abs(x))
    xe = val(xv)
    S, C = tsincos(xe)
    for name, tru in (('FSIN', S), ('FCOS', C), ('FTAN', S / C)):
        fp = newfp(); push(fp, xv); M.run(fp, M.ENTRY[name]); rec(name, ulps(fp['st'][fp['top']], tru))
    fp = newfp(); push(fp, xv); M.run(fp, M.ENTRY['FSINC'])
    rec('FSINC.sin', ulps(fp['st'][fp['top']], S)); rec('FSINC.cos', ulps(fp['st'][(fp['top'] + 1) & 7], C))
    ax = abs(xe) if xe != 0 else F(1)
    if rnd.random() < .5: ax = F(rnd.randrange(1, 1 << 30), 1 << rnd.randrange(0, 40))
    av = M.pk(ax); ax = val(av); fp = newfp(); push(fp, av); M.run(fp, M.ENTRY['FLN']); rec('FLN', ulps(fp['st'][fp['top']], tln(ax)))
    y = rx(-3, 3); yv = fpref.pack80(1 if y < 0 else 0, abs(y))
    fp = newfp(); push(fp, yv); push(fp, av); M.run(fp, M.ENTRY['FYL2X']); rec('FYL2X', ulps(fp['st'][fp['top']], val(yv) * tln(ax) / LN2 * 0 + val(yv) * (tln(ax) / LN2)))
    p = F(rnd.randrange(-290, 1000), 1000) if rnd.random() < .7 else F(rnd.randrange(-999, 5000), 100)
    pv = M.pk(p)
    fp = newfp(); push(fp, yv); push(fp, pv); M.run(fp, M.ENTRY['FYL2P'])
    if p > -1 and p != 0: rec('FYL2P', ulps(fp['st'][fp['top']], val(yv) * (tln(1 + val(pv)) / LN2)))
for k, v in sorted(worst.items()): print('%-10s max error %.2f ulp' % (k, v))
# exact FREM
bad = 0
for _ in range(400):
    a = rx(-40, 40) if rnd.random() < .7 else rx(-3, 3); b = rx(-20, 20) if rnd.random() < .7 else rx(-3, 3)
    xa = fpref.pack80(1 if a < 0 else 0, abs(a)); yb = fpref.pack80(1 if b < 0 else 0, abs(b))
    for near in (0, 1):
        res, q = M.frem_model(xa, yb, near)
        n = int(abs(a) / abs(b)) if not near else None
        if near:
            qq = abs(a) / abs(b); n = int(qq); rem = qq - n
            n = n + 1 if (rem > F(1, 2) or (rem == F(1, 2) and n % 2)) else n
        r = abs(a) - n * abs(b)
        if r < 0: sg = 1 - (1 if a < 0 else 0)
        else: sg = 1 if a < 0 else 0
        exp = fpref.pack80(sg, abs(r)) if r != 0 else (1 if a < 0 else 0) << 79
        if res != exp or (q != n % 8): bad += 1; print('FREM error', near, hex(xa), hex(yb), hex(res), hex(exp), q, n % 8)
print('FREM/FREM1: %d errors in 800' % bad)
