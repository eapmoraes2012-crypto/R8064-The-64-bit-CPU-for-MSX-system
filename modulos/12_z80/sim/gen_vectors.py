# gen_vectors.py : generates vectors (memory + regs + C model trace) in vec/
import random, subprocess, os, sys
REF = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'z80ref'))
os.makedirs('vec', exist_ok=True)
def regs_line(r, pc=None, sp=None):
    v = [r.randrange(256) for _ in range(8)] + [r.randrange(65536), r.randrange(65536), sp if sp is not None else r.randrange(0x4000, 0xF000), pc if pc is not None else 0x100 + r.randrange(0x100)]
    v += [r.randrange(256), r.randrange(256)] + [r.randrange(256) for _ in range(8)]
    iff = r.randrange(2); v += [iff, iff, r.randrange(3), r.randrange(65536)]
    return ' '.join('%x' % x for x in v) + '\n'
def unit(r):
    k = r.random(); b = lambda: r.randrange(256)
    if k < .40: u = [b()]
    elif k < .55: u = [r.choice([0xDD, 0xFD]), b()]
    elif k < .72: u = [0xED, b()]
    elif k < .87: u = [0xCB, b()]
    else: u = [r.choice([0xDD, 0xFD]), 0xCB, b(), b()]
    u += [b() for _ in range(3)]
    return u
def mk(seed, n, mix):
    r = random.Random(seed); m = bytearray(65536)
    i = 0
    while i < 65536:
        u = unit(r) if mix else [r.randrange(256) for _ in range(4)]
        for x in u:
            if i < 65536:
                m[i] = (r.randrange(256) if (x == 0x76 and r.random() < .95) else x); i += 1
    return m, regs_line(r)
def emit(name, m, regs, n):
    open('vec/%s_mem.bin' % name, 'wb').write(m)
    open('vec/%s_mem.hex' % name, 'w').write('\n'.join('%02x' % b for b in m) + '\n')
    open('vec/%s_regs.txt' % name, 'w').write(regs)
    out = subprocess.run([REF, '-d', 'vec/%s_mem.bin' % name, 'vec/%s_regs.txt' % name, str(n)], capture_output=True, text=True).stdout
    open('vec/%s_trace.txt' % name, 'w').write(out)
    return out.count('\n')
tot = 0
for s in range(1, 13):
    m, rg = mk(s, 0, s % 3 != 0)
    k = emit('r%02d' % s, m, rg, 20000); tot += k; print('r%02d' % s, k)
# ZEXDOC (initial excerpt)
zc = open('../zexdoc.com', 'rb').read() if os.path.exists('../zexdoc.com') else open('zexdoc.com', 'rb').read()
m = bytearray(65536); m[0x100:0x100 + len(zc)] = zc; m[5] = 0xC9; m[6] = 0; m[7] = 0xF0
r = random.Random(7); rg = '0 0 0 0 0 0 0 0 0 0 f000 100 0 0 0 0 0 0 0 0 0 0 0 0 0 0\n'
k = emit('zex', m, rg, 150000); print('zex', k); tot += k
print('total', tot)
