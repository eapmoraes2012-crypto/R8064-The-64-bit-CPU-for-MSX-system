# verifica_tempos_z80.py - INDEPENDENTLY derives the T-states of the real Z80 (Zilog Z80 CPU User Manual, UM0080) by decoding rules
# and compares with the [Z80_*] table of R8064_Z80_instrucoes_fpga.txt. Usage: python3 verifica_tempos_z80.py file.txt
import sys, re
def main_t(op):
    x, y, z = op >> 6, (op >> 3) & 7, op & 7; p, q = y >> 1, y & 1
    if x == 0:
        if z == 0: return {0: (4, None), 1: (4, None), 2: (13, 8), 3: (12, None)}.get(y, (12, 7))
        if z == 1: return (10, None) if q == 0 else (11, None)
        if z == 2: return {0: (7, None), 1: (7, None), 2: (16, None), 3: (13, None)}[p]
        if z == 3: return (6, None)
        if z in (4, 5): return (11, None) if y == 6 else (4, None)
        if z == 6: return (10, None) if y == 6 else (7, None)
        return (4, None)
    if x == 1:
        if op == 0x76: return (4, None)
        return (7, None) if (y == 6 or z == 6) else (4, None)
    if x == 2: return (7, None) if z == 6 else (4, None)
    if z == 0: return (11, 5)
    if z == 1: return (10, None) if q == 0 else {0: (10, None), 1: (4, None), 2: (4, None), 3: (6, None)}[p]
    if z == 2: return (10, None)
    if z == 3: return {0: (10, None), 2: (11, None), 3: (11, None), 4: (19, None), 5: (4, None), 6: (4, None), 7: (4, None)}[y]
    if z == 4: return (17, 10)
    if z == 5: return (11, None) if q == 0 else (17, None)
    if z == 6: return (7, None)
    return (11, None)
def cb_t(op):
    x, z = op >> 6, op & 7
    if z == 6: return (12, None) if x == 1 else (15, None)
    return (8, None)
def ed_t(op):
    x, y, z = op >> 6, (op >> 3) & 7, op & 7
    if x == 1:
        if z in (0, 1): return (12, None)
        if z == 2: return (15, None)
        if z == 3: return (20, None)
        if z == 4: return (8, None)
        if z == 5: return (14, None)
        if z == 6: return (8, None)
        return (9, None) if y < 4 else (18, None) if y < 6 else (8, None)
    if x == 2 and y >= 4 and z <= 3: return (21, 16) if y >= 6 else (16, None)
    return None
def idx_t(op):
    x, y, z = op >> 6, (op >> 3) & 7, op & 7
    if op in (0x34, 0x35): return (23, None)
    if op == 0x36: return (19, None)
    if x == 1 and op != 0x76 and (y == 6 or z == 6): return (19, None)
    if x == 2 and z == 6: return (19, None)
    if op == 0xE3: return (23, None)
    if op == 0xE9: return (8, None)
    if op == 0xF9: return (10, None)
    if op == 0x21: return (14, None)
    if op in (0x22, 0x2A): return (20, None)
    t, a = main_t(op); return (t + 4, a + 4 if a else None)
def idxcb_t(op): return (20, None) if (op >> 6) == 1 else (23, None)
page = None; rows = []
for ln in open(sys.argv[1], encoding='utf8'):
    m = re.match(r'\[(Z80_\w+)\]', ln)
    if m: page = m.group(1)[4:] if m.group(1) != 'Z80_SISTEMA' else None; continue
    if ln.startswith('[') : page = None; continue
    if page and not ln.startswith('#'):
        f = ln.rstrip('\n').split('|')
        if len(f) < 7: continue
        toks = f[0].split(); op = int([t for t in toks if re.fullmatch(r'[0-9A-F]{2}', t)][-1], 16)
        if page in ('DDCB', 'FDCB'): op = int(toks[-1], 16)
        rows.append((page, op, f[0], f[2], f[5], f[6]))
bad = 0; n = 0; byp = {}
for page, op, raw, mn, t, ta in rows:
    exp = {'00': main_t, 'CB': cb_t, 'ED': ed_t, 'DD': idx_t, 'FD': idx_t, 'DDCB': idxcb_t, 'FDCB': idxcb_t}[page](op)
    n += 1; byp[page] = byp.get(page, 0) + 1
    if exp is None: print('NO RULE', page, raw, mn, t, ta); continue
    et, ea = exp
    got = (int(t), int(ta) if ta.strip() else None)
    if got != (et, ea):
        bad += 1; print('DIFFERS', page, raw, mn, 'table', got, 'rule', (et, ea))
print('lines', n, byp, 'differences', bad)
