#!/usr/bin/env python3
# Analysis of the gain of an I and D cache in BSRAM over the spreadsheet cycle model (HIT_I/HIT_D).
# Method: synthetic program kernels (fetch and data addresses) -> cache simulator (LRU, write-through, no write allocate) -> hit rates -> cycles by the spreadsheet model.
# LIMIT: there is no real R8064 program trace; the kernels are typical examples, not the user's programs.
import csv, random, sys, json
P = sys.argv[1]
rows = {}
for r in csv.DictReader(open(P + '/ref/expected_cycles.csv', encoding='utf-8-sig'), delimiter=';'): rows[r['mnemonic']] = r
def ins(name):
    r = rows[name]; return dict(n=name, len=int(r['bytes']), busca=int(r['fetch_accesses']), nr=int(r['reads']), nw=int(r['writes']), ex=int(r['x_occupancy']), pen=int(r['branch_penalty']))
ADD, INC = ins('ADDQ rr, rr’'), ins('INCQ rr'); LDL, LDS = ins('LDQ rr, (rr’)'), ins('LDQ (rr), rr’')
LDLX, LDSX = ins('LDQ rr, (QIX+dd)'), ins('LDQ (QIX+dd), rr'); DJ, JR, JRC = ins('DJNZW nn'), ins('JRW nn'), ins('JRW cc, nn')
CALL, RET, MUL = ins('CALLQ nnnnnnnn'), ins('RETQ'), ins('MLTUQ QA, rr'); CP = ins('SUBQ rr, rr’')
WRD, WRM, WWH, WWM = 4, 8, 2, 6      # Spreadsheet parameters (read page hit/miss, write)
rnd = random.Random(8064)
# ---- generators: each instruction -> (pc, ins, [(type,'r'|'w', address)])
def kern_memcpy(n=60000):
    out = []; src = 0x100000; dst = 0x200000; i = 0
    while len(out) < n:
        pc = 0x1000
        for k, (x, d) in enumerate([(LDL, ('r', src + 8 * i)), (LDS, ('w', dst + 8 * i)), (ADD, None), (ADD, None), (DJ, None)]):
            out.append((pc, x, [d] if d else [])); pc += x['len']
        i = (i + 1) % 8192
    return out
def kern_matmul(N=40, n=70000):
    out = []; A, B, C = 0x100000, 0x200000, 0x300000
    while len(out) < n:
        for i in range(N):
            for j in range(N):
                for k in range(N):
                    pc = 0x2000
                    for x, d in [(LDL, ('r', A + 8 * (i * N + k))), (LDL, ('r', B + 8 * (k * N + j))), (MUL, None), (ADD, None), (INC, None), (DJ, None)]:
                        out.append((pc, x, [d] if d else [])); pc += x['len']
                    if len(out) >= n: return out
                pc = 0x2100
                for x, d in [(LDS, ('w', C + 8 * (i * N + j))), (INC, None), (DJ, None)]:
                    out.append((pc, x, [d] if d else [])); pc += x['len']
    return out
def kern_sort(N=400, n=70000):
    out = []; base = 0x100000; a = [rnd.random() for _ in range(N)]
    while len(out) < n:
        for p in range(N - 1):
            for j in range(N - 1 - p):
                pc = 0x3000
                seq = [(LDL, ('r', base + 8 * j)), (LDLX, ('r', base + 8 * j + 8)), (CP, None), (JRC, None)]
                swap = a[j] > a[j + 1]
                if swap:
                    seq += [(LDS, ('w', base + 8 * j)), (LDSX, ('w', base + 8 * j + 8))]; a[j], a[j + 1] = a[j + 1], a[j]
                seq += [(INC, None), (DJ, None)]
                for x, d in seq:
                    out.append((pc, x, [d] if d else [])); pc += x['len']
                if len(out) >= n: return out
        a = [rnd.random() for _ in range(N)]
    return out
def kern_list(nodes=2048, n=70000):
    out = []; order = list(range(nodes)); rnd.shuffle(order); nxt = {order[i]: order[(i + 1) % nodes] for i in range(nodes)}; cur = order[0]; base = 0x100000
    while len(out) < n:
        pc = 0x4000
        for x, d in [(LDL, ('r', base + 32 * cur + 8)), (LDLX, ('r', base + 32 * cur)), (ADD, None), (CP, None), (JRC, None), (INC, None), (JR, None)]:
            out.append((pc, x, [d] if d else [])); pc += x['len']
        cur = nxt[cur]
    return out
def kern_app(n=90000, nfun=120):
    out = []; funs = [(0x10000 + 512 * i, rnd.randint(20, 70)) for i in range(nfun)]
    w = [1.0 / (i + 1) ** 0.9 for i in range(nfun)]; heap = 0x200000; sp = 0x3F0000; stack = []
    mix = [ADD, ADD, INC, CP, JRC, LDL, LDLX, LDS, LDSX, MUL, ADD, LDL]
    while len(out) < n:
        f = rnd.choices(range(nfun), w)[0]; base, cnt = funs[f]; pc = base
        sp -= 64; out.append((pc, CALL, [('w', sp)])); pc = base
        for _ in range(cnt):
            x = rnd.choice(mix); d = []
            if x in (LDL, LDLX): d = [('r', (sp + 8 * rnd.randint(0, 6)) if rnd.random() < 0.5 else heap + 8 * min(int(rnd.paretovariate(1.2)) * 3, 8191) + (0 if rnd.random() < 0.8 else 8 * rnd.randint(0, 8191)))]
            if x in (LDS, LDSX): d = [('w', (sp + 8 * rnd.randint(0, 6)) if rnd.random() < 0.6 else heap + 8 * min(int(rnd.paretovariate(1.2)) * 3, 8191))]
            if x is JRC and rnd.random() < 0.25: pc = base + (pc - base) % 128 if rnd.random() < 0.5 else pc
            out.append((pc, x, [(t, a) for t, a in d])); pc += x['len']
        out.append((pc, RET, [('r', sp)])); sp += 64
    return out
KERN = {'memory copy (streaming)': kern_memcpy(), '40x40 matrix (nested loops)': kern_matmul(), 'sorting (bubble, 400 items)': kern_sort(),
        'linked list (256 KB ... 64 KB of nodes)': kern_list(), 'application (120 functions, calls/returns)': kern_app()}
# ---- cache (LRU, write-through, no write allocate; a write that hits updates the line)
class Cache:
    def __init__(s, size, line, ways):
        s.line = line; s.sets = size // (line * ways); s.ways = ways; s.tag = [[] for _ in range(s.sets)]
    def access(s, addr, alloc=True):
        ln = addr // s.line; st = ln % s.sets; t = ln // s.sets; L = s.tag[st]
        if t in L:
            L.remove(t); L.append(t); return True
        if alloc:
            L.append(t)
            if len(L) > s.ways: L.pop(0)
        return False
def simula(prog, isize, dsize, line, ways):
    ic = Cache(isize, line, ways); dc = Cache(dsize, line, ways); ih = im = dh = dm = 0
    for pc, x, ds in prog:
        for b in range(x['busca']):
            if ic.access((pc & ~7) + 8 * b): ih += 1
            else: im += 1
        for t, a in ds:
            if t == 'r':
                if dc.access(a, True): dh += 1
                else: dm += 1
            else: dc.access(a, False)
    return ih, im, dh, dm
POPEN = 0.8     # fraction of fills that find the SDRAM page open (assumption)
def fill(line, ctrl):
    n = line // 8; first = POPEN * (1 + WRD) + (1 - POPEN) * (1 + WRM)
    return first + (n - 1) * (5 if ctrl == 'atual' else 2)      # 'atual' (current): 5 clocks per 64-bit word (module 05); 'rajada' (burst): 2 (ESTIMATE, controller with overlapped reads, not simulated)
def ciclos(prog, ih, im, dh, dm, line, ctrl, pf=False):
    clk = w0 = nw = 0.0; nb = 0.0
    for pc, x, ds in prog:
        bf = (x['len'] / 8.0) if pf else x['busca']
        nb += bf
        clk += max(1, bf + x['nr'] + x['nw'], x['ex']) + x['pen']
        w0 += (bf + x['nr']) * (POPEN * WRD + (1 - POPEN) * WRM) + x['nw'] * (POPEN * WWH + (1 - POPEN) * WWM)
        nw += x['nw'] * (POPEN * WWH + (1 - POPEN) * WWM)
    f = fill(line, ctrl)
    hi = ih / (ih + im)
    imiss = nb * (1 - hi)                      # with prefetch: fetch accesses = bytes/8; the miss rate comes from the simulation
    wc = (imiss + dm) * (f - 1) + nw
    return clk, w0, wc
CONF = [(2, 2, 32, 1), (4, 4, 32, 1), (8, 8, 32, 2), (8, 8, 64, 2), (16, 16, 64, 2)]    # (I KB, D KB, linha B, vias)
out = []; res = {}
for kn, prog in KERN.items():
    N = len(prog)
    for (ik, dk, line, ways) in CONF:
        ih, im, dh, dm = simula(prog, ik * 1024, dk * 1024, line, ways)
        hi = ih / (ih + im); hd = dh / (dh + dm) if dh + dm else 1.0
        row = dict(k=kn, N=N, ik=ik, dk=dk, line=line, ways=ways, hi=hi, hd=hd)
        c0 = None
        for pf in (False, True):
            for ctrl in ('atual', 'rajada'):
                clk, w0, wc = ciclos(prog, ih, im, dh, dm, line, ctrl, pf)
                row[('p' if pf else '') + ctrl] = (clk + wc) / N; row[('p' if pf else '') + 'sem'] = (clk + w0) / N
        res[(kn, ik, dk, line, ways)] = row
lines = []
lines.append('GAIN OF AN I AND D CACHE IN BSRAM (synthetic kernels; spreadsheet cycle model; write-through, no write allocate)')
lines.append('CPI = clocks per instruction. none = no cache (spreadsheet: HIT_I=HIT_D=0). current = with the module 05 SDRAM controller (5 clocks per 64-bit word on fill). burst = estimate with overlapped reads (2 clocks per word).')
hdr = f'{"kernel":44s} {"I/D KB":>7s} {"line":>5s} {"ways":>4s} {"HIT_I":>6s} {"HIT_D":>6s} {"CPI none":>8s} {"CPI current":>9s} {"gain":>6s} {"CPI burst":>10s} {"gain":>6s}'
for (ik, dk, line, ways) in CONF:
    lines.append(f'\n== Cache I={ik} KB, D={dk} KB, line {line} B, {ways} way(s)  (data BSRAM: {(ik + dk) // 2} 18 Kbit blocks; tags in SSRAM/LUT)'); lines.append(hdr)
    for kn in KERN:
        r = res[(kn, ik, dk, line, ways)]
        lines.append(f'{kn:44s} {ik:>3d}/{dk:<3d} {line:>5d} {ways:>4d} {r["hi"]:6.3f} {r["hd"]:6.3f} {r["sem"]:8.2f} {r["atual"]:9.2f} {r["sem"]/r["atual"]:5.2f}x {r["rajada"]:10.2f} {r["sem"]/r["rajada"]:5.2f}x')
    # geometric mean
    import math
    g = lambda key: math.exp(sum(math.log(res[(kn, ik, dk, line, ways)][key]) for kn in KERN) / len(KERN))
    lines.append(f'{"GEOMETRIC MEAN":44s} {"":>7s} {"":>5s} {"":>4s} {"":>6s} {"":>6s} {g("sem"):8.2f} {g("atual"):9.2f} {g("sem")/g("atual"):5.2f}x {g("rajada"):10.2f} {g("sem")/g("rajada"):5.2f}x')
lines.append('\n\n######## BASELINE WITH PREFETCH QUEUE (module 02): effective fetch = bytes/8 per instruction (instead of 1 access per instruction) - cache gain OVER this baseline ########')
for (ik, dk, line, ways) in CONF:
    lines.append(f'\n== Cache I={ik} KB, D={dk} KB, linha {line} B, {ways} via(s)'); lines.append(hdr)
    for kn in KERN:
        r = res[(kn, ik, dk, line, ways)]
        lines.append(f'{kn:44s} {ik:>3d}/{dk:<3d} {line:>5d} {ways:>4d} {r["hi"]:6.3f} {r["hd"]:6.3f} {r["psem"]:8.2f} {r["patual"]:9.2f} {r["psem"]/r["patual"]:5.2f}x {r["prajada"]:10.2f} {r["psem"]/r["prajada"]:5.2f}x')
    g = lambda key: math.exp(sum(math.log(res[(kn, ik, dk, line, ways)][key]) for kn in KERN) / len(KERN))
    lines.append(f'{"GEOMETRIC MEAN":44s} {"":>7s} {"":>5s} {"":>4s} {"":>6s} {"":>6s} {g("psem"):8.2f} {g("patual"):9.2f} {g("psem")/g("patual"):5.2f}x {g("prajada"):10.2f} {g("psem")/g("prajada"):5.2f}x')
open(P + '/modulos/05b_cache/resultado_cache.txt', 'w').write('\n'.join(lines) + '\n')
print('\n'.join(lines))
