# zasm.py - minimal assembler (subset of the Z80 used by zexdoc.z80 + macros) -> .com. Usage: python3 zasm.py zexdoc.z80 zexdoc.com
import re, sys
R8 = {'b': 0, 'c': 1, 'd': 2, 'e': 3, 'h': 4, 'l': 5, '(hl)': 6, 'a': 7}
RP = {'bc': 0, 'de': 1, 'hl': 2, 'sp': 3}; RP2 = {'bc': 0, 'de': 1, 'hl': 2, 'af': 3}
CC = {'nz': 0, 'z': 1, 'nc': 2, 'c': 3, 'po': 4, 'pe': 5, 'p': 6, 'm': 7}
ALU = {'add': 0, 'adc': 1, 'sub': 2, 'sbc': 3, 'and': 4, 'xor': 5, 'or': 6, 'cp': 7}
SIMPLE = {'nop': [0x00], 'halt': [0x76], 'di': [0xF3], 'ei': [0xFB], 'exx': [0xD9], 'rlca': [0x07], 'rrca': [0x0F], 'rla': [0x17], 'rra': [0x1F],
          'daa': [0x27], 'cpl': [0x2F], 'scf': [0x37], 'ccf': [0x3F], 'ldir': [0xED, 0xB0], 'lddr': [0xED, 0xB8], 'ldi': [0xED, 0xA0], 'ldd': [0xED, 0xA8],
          'neg': [0xED, 0x44], 'ret': [0xC9]}
def split_args(s):
    out = []; cur = ''; q = None; dep = 0; par = 0
    for ch in s:
        if q:
            cur += ch
            if ch == q: q = None
        elif ch in "'\"": q = ch; cur += ch
        elif ch == '<': dep += 1; cur += ch
        elif ch == '>' and dep: dep -= 1; cur += ch
        elif ch == '(': par += 1; cur += ch
        elif ch == ')': par -= 1; cur += ch
        elif ch == ',' and dep == 0 and par == 0: out.append(cur.strip()); cur = ''
        else: cur += ch
    if cur.strip() or out: out.append(cur.strip())
    return out
class Asm:
    def __init__(self, text):
        self.lines = text.splitlines(); self.macros = {}; self.sym = {}; self.mem = bytearray(65536); self.lo = 0xFFFF; self.hi = 0; self.nl = 0
    def num(self, t):
        if re.fullmatch(r'[0-9][0-9a-fA-F]*[hH]', t): return int(t[:-1], 16)
        if re.fullmatch(r'[0-9]+', t): return int(t)
        raise ValueError(t)
    def ev(self, e, pc):
        e = e.strip()
        e = re.sub(r'\bhigh\s+(\w+)', r'((\1)/256&255)', e, flags=re.I)
        e = re.sub(r'\blow\s+(\w+)', r'((\1)&255)', e, flags=re.I)
        toks = re.findall(r"'(?:[^']|'')'|[A-Za-z_.][\w.]*|[0-9][0-9a-fA-F]*[hH]?|\$|<<|>>|[-+*/&|()]|\S", e); out = []
        for t in toks:
            if t[0] == "'": out.append(str(ord(t[1])))
            elif t == '$': out.append(str(pc))
            elif t.lower() == 'ne': out.append('!=')
            elif t.lower() == 'ge': out.append('>=')
            elif t.lower() == 'eq': out.append('==')
            elif t.lower() == 'lt': out.append('<')
            elif t.lower() == 'gt': out.append('>')
            elif t.lower() == 'le': out.append('<=')
            elif re.fullmatch(r'[0-9][0-9a-fA-F]*[hH]|[0-9]+', t): out.append(str(self.num(t)))
            elif re.fullmatch(r'[A-Za-z_.][\w.]*', t): out.append(str(self.sym.get(t.lower(), 0)))
            else: out.append(t)
        return int(eval(' '.join(out).replace('/', '//')))
    def expand(self, src):
        # expands macros; returns list of lines
        out = []; i = 0; defs = None; cnt = 0; lines = src
        res = []
        while i < len(lines):
            ln = lines[i]; i += 1
            code = ln.split(';')[0] if "'" not in ln else ln
            m = re.match(r'^([A-Za-z_]\w*):?\s+macro\s*(.*)$', ln.split(';')[0], re.I)
            if m:
                name = m.group(1).lower(); params = [p.strip().lower() for p in m.group(2).split(',') if p.strip()]
                body = []
                while not re.match(r'^\s*endm\b', lines[i], re.I): body.append(lines[i]); i += 1
                i += 1; self.macros[name] = (params, body); continue
            res.append(ln)
        # second phase: calls
        final = []
        for ln in res: final.extend(self.call_macros(ln))
        return final
    def call_macros(self, ln):
        m = re.match(r'^(?:([A-Za-z_]\w*):?)?\s+([A-Za-z_]\w*)\s*(.*)$', ln.split(';')[0] if not re.search(r"'.*;.*'", ln) else ln)
        if m and m.group(2).lower() in self.macros:
            params, body = self.macros[m.group(2).lower()]; args = split_args(m.group(3).split(';')[0] if not re.search(r"'.*;.*'", m.group(3)) else m.group(3))
            args = [a[1:-1] if a.startswith('<') and a.endswith('>') else a for a in args]
            self.nl += 1; sub = dict(zip(params, args)); loc = {}
            res = []
            if m.group(1): res.append(m.group(1) + ':')
            for b in body:
                bl = re.match(r'^\s*local\s+(\w+)', b, re.I)
                if bl: loc[bl.group(1).lower()] = '%s_%d' % (bl.group(1), self.nl); continue
                def r(mm):
                    k = mm.group(1).lower()
                    return sub[k] if k in sub else loc.get(k, mm.group(0))
                bb = re.sub(r'&(\w+)', r, b)
                parts = re.split(r"('[^']*')", bb)
                for pi in range(0, len(parts), 2):
                    parts[pi] = re.sub(r'\b(\w+)\b', lambda mm: sub[mm.group(1).lower()] if mm.group(1).lower() in sub else mm.group(0), parts[pi])
                bb = ''.join(parts)
                res.extend(self.call_macros(bb))
            return res
        return [ln]
    def encode(self, mn, ops, pc):
        mn = mn.lower(); o = [x.strip() for x in ops]; ol = [x.lower() for x in o]
        def imm8(e): v = self.ev(e, pc); return v & 0xFF
        def imm16(e): v = self.ev(e, pc) & 0xFFFF; return [v & 255, v >> 8]
        def ismem(s): return s.startswith('(') and s.endswith(')') and s.lower() != '(hl)' and s.lower() not in ('(bc)', '(de)', '(sp)', '(c)')
        if mn in SIMPLE and not o: return SIMPLE[mn]
        if mn == 'ex':
            if ol == ['de', 'hl']: return [0xEB]
            if ol == ['af', "af'"]: return [0x08]
            if ol == ['(sp)', 'hl']: return [0xE3]
        if mn in ALU:
            if len(o) == 2 and ol[0] == 'a': o = o[1:]; ol = ol[1:]
            elif len(o) == 2 and mn == 'add' and ol[0] in ('hl', 'ix', 'iy'):
                pre = {'hl': [], 'ix': [0xDD], 'iy': [0xFD]}[ol[0]]
                rr = ol[1]
                rp = 2 if rr == ol[0] else RP[rr]
                return pre + [0x09 | (rp << 4)]
            elif len(o) == 2 and mn in ('adc', 'sbc') and ol[0] == 'hl':
                return [0xED, (0x4A if mn == 'adc' else 0x42) | (RP[ol[1]] << 4)]
            if len(o) == 1:
                if ol[0] in R8: return [0x80 | (ALU[mn] << 3) | R8[ol[0]]]
                return [0xC6 | (ALU[mn] << 3), imm8(o[0])]
        if mn in ('inc', 'dec'):
            if ol[0] in R8: return [0x04 | (R8[ol[0]] << 3) | (1 if mn == 'dec' else 0)]
            if ol[0] in RP: return [0x03 | (RP[ol[0]] << 4) | (8 if mn == 'dec' else 0)]
        if mn == 'push' or mn == 'pop':
            base = 0xC5 if mn == 'push' else 0xC1
            if ol[0] in RP2: return [base | (RP2[ol[0]] << 4)]
            if ol[0] == 'ix': return [0xDD, base | (2 << 4)]
            if ol[0] == 'iy': return [0xFD, base | (2 << 4)]
        if mn in ('rlc', 'rrc', 'rl', 'rr', 'sla', 'sra', 'sll', 'srl') and ol[0] in R8:
            return [0xCB, ['rlc', 'rrc', 'rl', 'rr', 'sla', 'sra', 'sll', 'srl'].index(mn) << 3 | R8[ol[0]]]
        if mn == 'out' and len(o) == 2 and ismem(o[0]) and ol[1] == 'a': return [0xD3, imm8(o[0][1:-1])]
        if mn == 'in' and len(o) == 2 and ol[0] == 'a' and ismem(o[1]): return [0xDB, imm8(o[1][1:-1])]
        if mn == 'jp':
            if len(o) == 1 and ol[0] == '(hl)': return [0xE9]
            if len(o) == 1: return [0xC3] + imm16(o[0])
            return [0xC2 | (CC[ol[0]] << 3)] + imm16(o[1])
        if mn == 'call':
            if len(o) == 1: return [0xCD] + imm16(o[0])
            return [0xC4 | (CC[ol[0]] << 3)] + imm16(o[1])
        if mn == 'ret' and o: return [0xC0 | (CC[ol[0]] << 3)]
        if mn == 'jr':
            if len(o) == 1: t = self.ev(o[0], pc); self.chkrel(t, pc); return [0x18, (t - (pc + 2)) & 255]
            t = self.ev(o[1], pc); self.chkrel(t, pc); return [0x20 | (CC[ol[0]] << 3), (t - (pc + 2)) & 255]
        if mn == 'djnz': t = self.ev(o[0], pc); self.chkrel(t, pc); return [0x10, (t - (pc + 2)) & 255]
        if mn == 'rst': return [0xC7 | (self.ev(o[0], pc) & 0x38)]
        if mn == 'im': return [0xED, {0: 0x46, 1: 0x56, 2: 0x5E}[self.ev(o[0], pc)]]
        if mn == 'ld':
            d, s = ol[0], ol[1]
            if d in R8 and s in R8: return [0x40 | (R8[d] << 3) | R8[s]]
            if d in R8 and not ismem(o[1]) and s not in ('(bc)', '(de)', 'i', 'r'): return [0x06 | (R8[d] << 3), imm8(o[1])]
            if d == 'a' and s == '(bc)': return [0x0A]
            if d == 'a' and s == '(de)': return [0x1A]
            if d == '(bc)' and s == 'a': return [0x02]
            if d == '(de)' and s == 'a': return [0x12]
            if d == 'a' and ismem(o[1]): return [0x3A] + imm16(o[1][1:-1])
            if s == 'a' and ismem(o[0]): return [0x32] + imm16(o[0][1:-1])
            if d == 'hl' and ismem(o[1]): return [0x2A] + imm16(o[1][1:-1])
            if s == 'hl' and ismem(o[0]): return [0x22] + imm16(o[0][1:-1])
            if d in ('bc', 'de', 'sp') and ismem(o[1]): return [0xED, 0x4B | (RP[d] << 4)] + imm16(o[1][1:-1])
            if s in ('bc', 'de', 'sp') and ismem(o[0]): return [0xED, 0x43 | (RP[s] << 4)] + imm16(o[0][1:-1])
            if d == 'sp' and s == 'hl': return [0xF9]
            if d == 'i' and s == 'a': return [0xED, 0x47]
            if d in RP and not ismem(o[1]): return [0x01 | (RP[d] << 4)] + imm16(o[1])
        raise ValueError('unsupported instruction: %s %s' % (mn, ops))
    def chkrel(self, t, pc):
        if getattr(self, 'final', False) and not (-128 <= t - (pc + 2) <= 127): raise SystemExit('JR/DJNZ out of range at %04X -> %04X' % (pc, t))
    def emit(self, pc, bs):
        for k, b in enumerate(bs): self.mem[pc + k] = b & 255
        self.lo = min(self.lo, pc); self.hi = max(self.hi, pc + len(bs))
    def run_pass(self, lines):
        pc = 0; stack = [True]; ifstack = []
        for ln in lines:
            raw = ln
            if not raw.strip() or raw.strip().startswith(';'): continue
            body = raw
            if ';' in raw:
                # removes comment outside quotes
                q = None; cut = len(raw)
                for k, ch in enumerate(raw):
                    if q:
                        if ch == q: q = None
                    elif ch in "'\"": q = ch
                    elif ch == ';': cut = k; break
                body = raw[:cut]
            if not body.strip(): continue
            label = None
            m = None if body[0].isspace() else (re.match(r'^([A-Za-z_.][\w.]*):(.*)$', body) or re.match(r'^([A-Za-z_.][\w.]*)(?:\s+(.*))?$', body))
            if m: label = m.group(1); rest = (m.group(2) or '').strip()
            else: rest = body.strip()
            if m and not body[len(label):].startswith(':') and re.match(r'^(if|else|endif|org|aseg|end|db|dw|ds|ld|push|pop|call|jp|jr|ret|halt|di|ei)$', label.lower()):
                label = None; rest = body.strip()
            mm = re.match(r'^([A-Za-z_.][\w.]*)\s*(.*)$', rest)
            mn = mm.group(1).lower() if mm else ''; arg = mm.group(2).strip() if mm else ''
            if mn == 'if':
                v = self.ev(arg, pc); ifstack.append(stack[-1] and bool(v)); stack.append(ifstack[-1]); continue
            if mn == 'else': stack[-1] = (not stack[-1]) and (stack[-2] if len(stack) > 1 else True); continue
            if mn == 'endif': stack.pop(); ifstack.pop(); continue
            if not stack[-1]: continue
            if mn == 'equ':
                self.sym[label.lower()] = self.ev(arg, pc); continue
            if label: self.sym[label.lower()] = pc
            if not mn or mn in ('aseg', '.title', 'title', 'end'): continue
            if mn == 'org': pc = self.ev(arg, pc); continue
            if mn == 'error': raise SystemExit('ERROR no fonte: ' + arg)
            if mn == 'db':
                bs = []
                for a in split_args(arg):
                    if a.startswith("'") and len(a) > 3 and a.endswith("'"): bs += [ord(c) for c in a[1:-1]]
                    else: bs.append(self.ev(a, pc) & 255)
                self.emit(pc, bs); pc += len(bs); continue
            if mn == 'dw':
                bs = []
                for a in split_args(arg):
                    v = self.ev(a, pc) & 0xFFFF; bs += [v & 255, v >> 8]
                self.emit(pc, bs); pc += len(bs); continue
            if mn == 'ds':
                a = split_args(arg); n = self.ev(a[0], pc); fill = self.ev(a[1], pc) if len(a) > 1 else 0
                if len(a) > 1 or True: self.emit(pc, [fill] * max(n, 0))
                pc += max(n, 0); continue
            bs = self.encode(mn, split_args(arg), pc)
            self.emit(pc, bs); pc += len(bs)
    def assemble(self):
        lines = self.expand(self.lines)
        for i in range(3):
            self.final = (i == 2); self.run_pass(lines)
        import os
        return bytes(self.mem[0:self.hi]) if os.environ.get('ZASM_ORG0') else bytes(self.mem[0x100:self.hi])
if __name__ == '__main__':
    a = Asm(open(sys.argv[1], encoding='latin-1').read()); b = a.assemble(); open(sys.argv[2], 'wb').write(b)
    print('montado: %d bytes (0100h-%04Xh)' % (len(b), 0x100 + len(b) - 1))
