# isacore.py - compiles the forms of r8isa.py (patterns -> classes, operand masks taken from the RTL decode ROMs for the
# R8064 extensions) and implements operand matching and encoding exactly as R8064AS.COM does.
import os, re
from r8isa import KW, FORMS, BANKPFX
HERE = os.path.dirname(os.path.abspath(__file__))
SIM = os.path.join(HERE, '..', '..', 'sim')

# ---------------------------------------------------------------- RTL decode ROMs (ED page)
def _rd(f): return [int(l, 16) for l in open(os.path.join(SIM, f)) if l.strip()]
_A, _AMB, _B, _C = _rd('rom_ed_a.mem'), _rd('amb_idx.mem'), _rd('rom_ed_b.mem'), _rd('ctrl_b.mem')
def rom_decode(b2, b3):
    """id and length of ED b2 b3 according to the RTL decoder"""
    a = _A[b2]
    i = _B[(_AMB[b2] & 0x3F) * 256 + b3] if a & 0x400 else a & 0x3FF
    return i, _C[i] & 15
def rom_bankable(i): return (_C[i] >> 28) & 1

# ---------------------------------------------------------------- pattern classes (same codes as the Z80 table)
C_KW, C_IND, C_R8, C_XH, C_SS, C_QQ, C_XY, C_RR, C_INDRR, C_U4, C_CC, C_IMM, C_MEM, C_REL, C_IDX8, C_IDXQ, C_BIT, C_ST, C_RST, C_VAL = range(1, 21)
KWIDS = sorted(set(a['id'] for a in KW.values()), key=lambda s: (len(s), s))
KWNUM = {k: i + 1 for i, k in enumerate(KWIDS)}            # keyword id -> number 1..
CANDS = {C_U4: [0, 1, 2, 3], C_R8: [0, 1, 2, 3, 4, 5, 7], C_RR: [0, 2, 3, 4, 5, 7], C_INDRR: [0, 2, 3, 4, 5, 7], C_CC: list(range(8)), C_ST: list(range(8))}

def parse_pat(p):
    simple = {'r': (C_R8, 0xBF), 'r-hl': (C_R8, 0x8F), 'xh': (C_XH, 0), 'ss': (C_SS, 0), 'qq': (C_QQ, 0), 'xy': (C_XY, 0), 'rr': (C_RR, 0xBD),
              '(rr)': (C_INDRR, 0xBD), '(u4)': (C_U4, 0x0F), 'cc': (C_CC, 0xFF), 'jcc': (C_CC, 0x0F), 'n': (C_IMM, 1), 'nn': (C_IMM, 2), 'n32': (C_IMM, 4),
              'n64': (C_IMM, 8), 'e': (C_REL, 1), 'ee': (C_REL, 2), '(n)': (C_MEM, 1), '(nn)': (C_MEM, 2), '(a64)': (C_MEM, 8), '(xy+d)': (C_IDX8, 0),
              '(qxy+dd)': (C_IDXQ, 0), '(xy)': (C_IND, KWNUM['IX']), 'b3': (C_BIT, 7), 'b4': (C_BIT, 15), 'b5': (C_BIT, 31), 'k5': (C_BIT, 31),
              'st': (C_ST, 0xFF), 'rst': (C_RST, 0)}
    if p in simple: return list(simple[p])
    if p.startswith('='): return [C_VAL, int(p[1:])]
    if p.startswith('(') and p.endswith(')'): return [C_IND, KWNUM[KW[p[1:-1]]['id']]]
    return [C_KW, KWNUM[KW[p]['id']]]

def parse_tpl(t):
    out = []
    for it in t:
        if it == 'E': out.append(('E',))
        elif re.fullmatch(r'P\d', it): out.append(('P', int(it[1])))
        elif re.fullmatch(r'[IRD]\d:\d', it): out.append((it[0], int(it[1]), int(it[3])))
        elif '|' in it:
            parts = it.split('|'); f = []
            for x in parts[1:]:
                k, s = (x.split('<<') + ['0'])[:2]; f.append((int(k), int(s)))
            out.append(('F', int(parts[0], 16), f))
        else: out.append(('L', int(it, 16)))
    return out

def tpl_len(tpl):
    n = 0
    for it in tpl:
        if it[0] in ('E', 'P', 'L', 'F'): n += 1
        elif it[0] in ('I', 'R', 'D'): n += it[2]
    return n

class Form:
    def __init__(s, mn, pats, tpl, o):
        s.mn, s.src, s.pats, s.tpl, s.id = mn, pats, [parse_pat(p) for p in pats], parse_tpl(tpl), o.get('id')
        s.bank = bool(o.get('bank')) or (s.id is not None and rom_bankable(s.id) and tpl[0] == 'E')
        s.same = o.get('same', 0); s.len = tpl_len(s.tpl)

def _encode_fields(form, codes, pfx=0xDD):
    """bytes of the ED extension for given operand codes (registers/conditions only), to test against the ROM"""
    out = []
    for it in form.tpl:
        if it[0] == 'E': out.append(0xED)
        elif it[0] == 'L': out.append(it[1])
        elif it[0] == 'F':
            v = it[1]
            for k, sh in it[2]: v |= (codes.get(k, 0) << sh)
            out.append(v & 0xFF)
        elif it[0] == 'P': out.append(pfx)
        else: break
    return out

def derive_masks(form):
    """for an extension form: keep only the register/condition codes that decode to the expected id (RTL ROM)"""
    if form.id is None: return
    var = [k for k, p in enumerate(form.pats, 1) if p[0] in CANDS]
    if not var: return
    import itertools
    ok = {k: set() for k in var}; combos = 0; good = 0
    for vals in itertools.product(*[CANDS[form.pats[k - 1][0]] for k in var]):
        codes = dict(zip(var, vals))
        if any(not (form.pats[k - 1][1] >> codes[k] & 1) for k in var): continue
        b = _encode_fields(form, codes); combos += 1
        i, L = rom_decode(b[1], b[2] if len(b) > 2 else 0)
        if i == form.id:
            good += 1
            for k in var: ok[k].add(codes[k])
    for k in var:
        m = 0
        for c in ok[k]: m |= 1 << c
        form.pats[k - 1][1] = m
    n = 1
    for k in var: n *= len(ok[k])
    form.cartesian = (n == good)

COMPILED = [Form(*f) for f in FORMS]
for f in COMPILED: derive_masks(f)
MNEMS = []
for f in COMPILED:
    if f.mn not in MNEMS: MNEMS.append(f.mn)
BYMN = {m: [f for f in COMPILED if f.mn == m] for m in MNEMS}

# ---------------------------------------------------------------- operands
class Op:
    def __init__(s, kind, kw=None, val=None, known=True): s.kind, s.kw, s.val, s.known = kind, kw, val, known
K_KW, K_IND, K_IDX, K_MEM, K_IMM = range(5)

def match(form, ops):
    """returns (codes, prefixes, values, bank) or None"""
    if len(ops) != len(form.pats): return None
    codes, pfx, vals, banks, plain = {}, {}, {}, set(), False
    for k, ((c, a), op) in enumerate(zip(form.pats, ops), 1):
        at = KW[op.kw] if op.kw else {}
        if c == C_KW:
            if op.kind != K_KW or KWNUM[at['id']] != a: return None
        elif c == C_IND:
            if op.kind not in (K_IND,) or KWNUM[at['id']] != a:
                if not (a == KWNUM['IX'] and op.kind == K_IND and at['id'] in ('IX', 'IY')): return None
            if 'xy' in at: pfx[k] = at['xy']
        elif c == C_R8:
            if op.kind != K_KW or 'r8' not in at or not (a >> at['r8'] & 1): return None
            codes[k] = at['r8']
        elif c == C_XH:
            if op.kind != K_KW or 'xh' not in at: return None
            pfx[k], codes[k] = at['xh']
        elif c in (C_SS, C_QQ, C_U4):
            key = {C_SS: 'z16', C_QQ: 'qq', C_U4: 'u4'}[c]
            if op.kind != (K_IND if c == C_U4 else K_KW) or at.get(key) is None: return None
            codes[k] = at[key]
            if c == C_SS:
                if at.get('bank'): banks.add(at['bank'])
                else: plain = True
        elif c == C_XY:
            if op.kind != K_KW or 'xy' not in at: return None
            pfx[k] = at['xy']
        elif c in (C_RR, C_INDRR):
            if op.kind != (K_KW if c == C_RR else K_IND) or 'rr' not in at or not (a >> at['rr'] & 1): return None
            codes[k] = at['rr']
            if at.get('bank'): banks.add(at['bank'])
            elif at['rr'] not in (3, 5): plain = True
        elif c == C_CC:
            if op.kind != K_KW or 'cc' not in at or not (a >> at['cc'] & 1): return None
            codes[k] = at['cc']
        elif c == C_ST:
            if op.kind != K_KW or 'st' not in at or not (a >> at['st'] & 1): return None
            codes[k] = at['st']
        elif c in (C_IMM, C_REL):
            if op.kind != K_IMM: return None
            vals[k] = op.val
        elif c == C_MEM:
            if op.kind != K_MEM: return None
            vals[k] = op.val
        elif c in (C_IDX8, C_IDXQ):
            if op.kind == K_IDX: pfx[k], vals[k] = KW[op.kw]['xy'], op.val
            elif op.kind == K_IND and at.get('xy'): pfx[k], vals[k] = at['xy'], 0
            else: return None
        elif c == C_BIT:
            if op.kind != K_IMM: return None
            codes[k] = op.val & 0xFF; vals[k] = op.val
        elif c == C_RST:
            if op.kind != K_IMM: return None
            codes[k] = (op.val >> 3) & 7; vals[k] = op.val
        elif c == C_VAL:
            if op.kind != K_IMM or not op.known or op.val != a: return None
    if form.same and len(set(pfx.values())) > 1: return None
    if len(banks) > 1: raise AsmError('bank registers mixed')
    bank = banks.pop() if banks else 0
    if bank and not form.bank: return None
    if bank and plain: raise AsmError('bank registers mixed')
    return codes, pfx, vals, bank

class AsmError(Exception): pass

def encode(form, m, pc, check):
    codes, pfx, vals, bank = m
    L = form.len + (1 if bank else 0); out = []
    def rng(v, n, signed_only=False):
        if not check: return
        v &= (1 << 64) - 1; v = v - (1 << 64) if v >> 63 else v
        lo, hi = (-(1 << (8 * n - 1)), (1 << (8 * n - 1)) - 1) if signed_only else (-(1 << (8 * n - 1)), (1 << (8 * n)) - 1)
        if n < 8 and not (lo <= v <= hi): raise AsmError('value out of range')
    for it in form.tpl:
        if it[0] == 'E':
            out.append(0xED)
            if bank: out.append(BANKPFX[bank])
        elif it[0] == 'L': out.append(it[1])
        elif it[0] == 'F':
            v = it[1]
            for k, sh in it[2]: v |= codes[k] << sh
            out.append(v & 0xFF)
        elif it[0] == 'P': out.append(pfx[it[1]])
        elif it[0] == 'I':
            v = vals[it[1]]; rng(v, it[2]); out += [(v >> (8 * i)) & 0xFF for i in range(it[2])]
        elif it[0] == 'D':
            v = vals[it[1]]; rng(v, it[2], True); out += [(v >> (8 * i)) & 0xFF for i in range(it[2])]
        elif it[0] == 'R':
            v = vals[it[1]] - (pc + L); rng(v, it[2], True); out += [(v >> (8 * i)) & 0xFF for i in range(it[2])]
    if check:
        for k, (c, a) in enumerate(form.pats, 1):
            if c == C_BIT and not (0 <= vals[k] <= a): raise AsmError('value out of range')
            if c == C_RST and vals[k] not in range(0, 0x40, 8): raise AsmError('value out of range')
    assert len(out) == L
    return out
