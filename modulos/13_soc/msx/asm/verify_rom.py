# verify_rom.py - checks the R8064 extension forms of r8isa.py against the ED-page decode ROMs of the RTL
# (rom_ed_a.mem / amb_idx.mem / rom_ed_b.mem / ctrl_b.mem): every operand combination the assembler accepts must decode to
# the expected instruction id with the expected length, and every (b2, b3) the ROM accepts must be reachable.
import itertools, collections, sys
from isacore import COMPILED, CANDS, rom_decode, _encode_fields, C_RR, C_INDRR, C_R8, C_CC, C_ST, C_BIT
from r8isa import FORMS
err = 0
def bad(*a):
    global err; err += 1; print('ERROR', *a)
reach = collections.defaultdict(set)
FDID = {68: 70, 69: 71, 73: 74, 80: 82, 81: 83, 85: 86, 92: 94, 93: 95, 97: 98}   # (QIY+dd) variants
for f in COMPILED:
    if f.id is None:
        # Z80 ED forms: must decode to some non-illegal id
        if f.tpl[0] in (('L', 0xED), ('E',)) and len(f.tpl) > 1 and f.tpl[1][0] in ('L', 'F'):
            b = _encode_fields(f, {k: 0 for k in range(1, 4)})
            i, L = rom_decode(b[1], 0)
            if i == 0: bad('Z80 ED form illegal in ROM:', f.mn, f.src)
        continue
    var = [k for k, p in enumerate(f.pats, 1) if p[0] in CANDS]
    for k in var:
        if f.pats[k - 1][1] == 0: bad('no valid code for operand', k, f.mn, f.src)
    if var and not f.cartesian: bad('operand codes not independent', f.mn, f.src)
    lists = [[c for c in range(8) if f.pats[k - 1][1] >> c & 1] for k in var]
    # bit / CR numbers also go into b3: test their whole range
    bits = [k for k, p in enumerate(f.pats, 1) if p[0] == C_BIT and any(it[0] == 'F' and any(x[0] == k for x in it[2]) for it in f.tpl)]
    lists += [list(range(f.pats[k - 1][1] + 1)) for k in bits]
    pf = [0xDD, 0xFD] if any(it[0] == 'P' for it in f.tpl) else [0xDD]
    for px, vals in itertools.product(pf, itertools.product(*lists)):
        codes = dict(zip(var + bits, vals))
        b = _encode_fields(f, codes, px)
        b2, b3 = b[1], (b[2] if len(b) > 2 else 0)
        i, L = rom_decode(b2, b3)
        want_id = FDID.get(f.id, f.id) if px == 0xFD else f.id
        if i != want_id: bad('%s %s codes %s -> ED %02X %02X decodes to id %d, expected %d' % (f.mn, f.src, codes, b2, b3, i, want_id)); break
        if L != f.len: bad('%s %s: length %d, ROM says %d' % (f.mn, f.src, f.len, L)); break
        reach[want_id].add((b2, b3 if len(b) > 2 else None))
# completeness: every ROM encoding of each id used by the table is produced by some form
import isacore
for i in sorted(reach):
    want = set()
    for b2 in range(256):
        a = isacore._A[b2]
        if a & 0x400:
            for b3 in range(256):
                if isacore._B[(isacore._AMB[b2] & 0x3F) * 256 + b3] == i: want.add((b2, b3))
        elif (a & 0x3FF) == i: want.add((b2, None))
    got = set()
    for (b2, b3) in reach[i]:
        got.add((b2, b3) if (isacore._A[b2] & 0x400) else (b2, None))
    if i in (69, 71, 81, 83, 93, 95):          # immediate stores: the register field of b3 is not used; the assembler writes 000
        want = set(w for w in want if (w[1] >> 3) & 7 == 0)
    if want - got: bad('id %d: ROM encodings not produced by the assembler: %s' % (i, sorted(want - got)[:8]))
ids_used = set(reach)
ids_rom = set(i for b2 in range(256) for i in ([isacore._A[b2] & 0x3FF] if not isacore._A[b2] & 0x400 else
              [isacore._B[(isacore._AMB[b2] & 0x3F) * 256 + b3] for b3 in range(256)]) if i)
missing = sorted(i for i in ids_rom - ids_used if i < 211 or i > 290)
print('extension ids in ROM:', len([i for i in ids_rom if i < 211 or i > 290]), ' covered:', len(ids_used), ' not covered:', missing)
print('forms:', len(COMPILED), ' errors:', err)
sys.exit(1 if err else 0)
