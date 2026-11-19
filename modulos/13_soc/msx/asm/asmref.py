# asmref.py - host reference implementation of the R8064AS assembler (same syntax and rules as R8064AS.COM).
# Used to test R8064AS.COM byte by byte and as a cross-assembler on the PC.  Usage: python3 asmref.py file.asm [out.bin]
import sys, os
from isacore import BYMN, match, encode, Op, K_KW, K_IND, K_IDX, K_MEM, K_IMM, AsmError
from r8isa import KW
M64 = (1 << 64) - 1
IDCH = set('ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.?@$')

def sx(v): v &= M64; return v - (1 << 64) if v >> 63 else v

class Expr:
    def __init__(s, txt, asm): s.t, s.i, s.a, s.known = txt, 0, asm, True
    def peek(s):
        while s.i < len(s.t) and s.t[s.i] in ' \t': s.i += 1
        return s.t[s.i] if s.i < len(s.t) else ''
    def take(s, w):
        s.peek()
        if s.t[s.i:s.i + len(w)].upper() == w:
            if w[-1].isalpha() and s.i + len(w) < len(s.t) and s.t[s.i + len(w)].upper() in IDCH: return False
            s.i += len(w); return True
        return False
    LEVELS = [['|', 'OR'], ['^', 'XOR'], ['&', 'AND'], ['==', '!=', '<>', '='], ['<=', '>=', '<', '>'], ['<<', '>>', 'SHL', 'SHR'], ['+', '-'], ['*', '/', '%', 'MOD']]
    def parse(s):
        v = s.lvl(0)
        if s.peek(): raise AsmError('syntax error')
        return v
    def lvl(s, n):
        if n == len(s.LEVELS): return s.unary()
        v = s.lvl(n + 1)
        while True:
            s.peek()
            for op in s.LEVELS[n]:
                if op == '&' and s.t[s.i:s.i + 2].upper() == '&H': continue
                if op in ('<', '>') and s.t[s.i:s.i + 2] in ('<<', '>>', '<>'): continue
                if op == '=' and s.t[s.i:s.i + 2] == '==': continue
                if s.take(op): break
            else: return v
            w = s.lvl(n + 1); v = s.binop(op, v, w)
    def binop(s, op, a, b):
        a &= M64; b &= M64
        if op in ('|', 'OR'): return a | b
        if op in ('^', 'XOR'): return a ^ b
        if op in ('&', 'AND'): return a & b
        if op in ('==', '='): return int(a == b)
        if op in ('!=', '<>'): return int(a != b)
        if op == '<': return int(sx(a) < sx(b))
        if op == '>': return int(sx(a) > sx(b))
        if op == '<=': return int(sx(a) <= sx(b))
        if op == '>=': return int(sx(a) >= sx(b))
        if op in ('<<', 'SHL'): return (a << b) & M64 if b < 64 else 0
        if op in ('>>', 'SHR'): return a >> b if b < 64 else 0
        if op == '+': return (a + b) & M64
        if op == '-': return (a - b) & M64
        if op == '*': return (a * b) & M64
        if b == 0:
            if s.a.pass2: raise AsmError('division by zero')
            return 0
        return a // b if op == '/' else a % b
    def unary(s):
        c = s.peek()
        if c == '-': s.i += 1; return (-s.unary()) & M64
        if c == '+': s.i += 1; return s.unary()
        if c == '~' or c == '!': s.i += 1; return (~s.unary()) & M64 if c == '~' else int(s.unary() == 0)
        if s.take('NOT'): return (~s.unary()) & M64
        if s.take('HIGH'): return (s.unary() >> 8) & 0xFF
        if s.take('LOW'): return s.unary() & 0xFF
        if c == '(':
            s.i += 1; v = s.lvl(0)
            if s.peek() != ')': raise AsmError('syntax error')
            s.i += 1; return v
        return s.atom()
    def atom(s):
        t = s.t; c = s.peek(); i = s.i
        if c in "'\"":
            if i + 2 < len(t) and t[i + 2] == c: s.i += 3; return ord(t[i + 1])
            raise AsmError('syntax error')
        if c == '$' and (i + 1 >= len(t) or t[i + 1].upper() not in '0123456789ABCDEF'): s.i += 1; return s.a.pc
        if c == '$': return s.digits(i + 1, 16)
        if c == '%': return s.digits(i + 1, 2)
        if c == '&' and t[i + 1:i + 2].upper() == 'H': return s.digits(i + 2, 16)
        if c.isdigit():
            j = i
            while j < len(t) and t[j].upper() in IDCH - set('$?@_.'): j += 1
            w = t[i:j].upper(); s.i = j
            try:
                if w.startswith('0X'): return int(w[2:], 16)
                if w.endswith('H'): return int(w[:-1], 16)
                if w.startswith('0B') and len(w) > 2 and set(w[2:]) <= set('01'): return int(w[2:], 2)
                if w.endswith('B') and set(w[:-1]) <= set('01'): return int(w[:-1], 2)
                if w.endswith('D'): return int(w[:-1], 10)
                return int(w, 10)
            except ValueError: raise AsmError('bad number')
        if c.upper() in IDCH and not c.isdigit():
            j = i
            while j < len(t) and t[j].upper() in IDCH: j += 1
            s.i = j
            if j - i > 32: raise AsmError('name too long')
            return s.a.symval(t[i:j].upper(), s)
        raise AsmError('syntax error')
    def digits(s, j, base):
        k = j; ok = '01' if base == 2 else '0123456789ABCDEF'
        while k < len(s.t) and s.t[k].upper() in ok: k += 1
        if k == j: raise AsmError('bad number')
        s.i = k; return int(s.t[j:k], base)

def split_ops(t):
    out, cur, q, d = [], '', None, 0
    for ch in t:
        if q:
            cur += ch
            if ch == q: q = None
        elif ch in '"\'' and not (ch == "'" and cur[-1:].upper() in IDCH and cur[-1:] != ''): q = ch; cur += ch
        elif ch == '(': d += 1; cur += ch
        elif ch == ')': d -= 1; cur += ch
        elif ch == ',' and d == 0: out.append(cur.strip()); cur = ''
        else: cur += ch
    if cur.strip() or out: out.append(cur.strip())
    return out

class Asm:
    def __init__(s, path):
        s.path = path; s.sym = {}; s.errors = []
    def symval(s, name, ex):
        if name in s.sym: return s.sym[name][0]
        if s.pass2: raise AsmError('undefined symbol')
        ex.known = False; return 0
    def ev(s, txt):
        e = Expr(txt, s); v = e.parse(); return v & M64, e.known
    def operand(s, t):
        u = t.upper()
        if u in KW: return Op(K_KW, u)
        if t.startswith('(') and t.endswith(')') and s.closes_at_end(t):
            inner = t[1:-1].strip(); iu = inner.upper()
            if iu in KW: return Op(K_IND, iu)
            for x in ('QIX', 'QIY', 'IX', 'IY'):
                if iu.startswith(x) and iu[len(x):].lstrip()[:1] in ('+', '-'):
                    v, k = s.ev(inner[len(x):]); return Op(K_IDX, x, sx(v), k)
            v, k = s.ev(inner); return Op(K_MEM, None, v, k)
        v, k = s.ev(t); return Op(K_IMM, None, v, k)
    @staticmethod
    def closes_at_end(t):
        d = 0; q = None
        for i, ch in enumerate(t):
            if q:
                if ch == q: q = None
            elif ch in '"\'' and not (ch == "'" and i > 0 and t[i - 1].upper() in IDCH): q = ch
            elif ch == '(': d += 1
            elif ch == ')':
                d -= 1
                if d == 0: return i == len(t) - 1
        return False
    def emit(s, bs):
        if s.pass2:
            if s.start is None: s.start = s.pc
            off = s.pc - s.start
            if off < len(s.out): raise AsmError('ORG backwards')
            s.out += bytes(off - len(s.out)) + bytes(bs)
        s.pc = (s.pc + len(bs)) & M64
    def define(s, name, v):
        if not s.pass2:
            if name in s.sym and s.sym[name][1] == 1: raise AsmError('symbol defined twice')
            s.sym[name] = (v, 1)
        elif name not in s.sym: s.sym[name] = (v, 2)
        elif s.sym[name][0] != v: raise AsmError('phase error')
    def run(s):
        for s.npass in (1, 2):
            s.pass2 = s.npass == 2; s.pc = 0; s.out = bytearray(); s.start = None; s.cond = []; s.ended = False; s.entry = None; s.depth = 0
            s.file(s.path)
        return s.out
    def file(s, path):
        for n, line in enumerate(open(path, encoding='latin-1').read().split('\n'), 1):
            if s.ended: break
            line = line.rstrip('\r').split('\x1a')[0]
            try: s.line(line, path)
            except AsmError as e:
                if s.pass2: s.errors.append('%s(%d): %s' % (os.path.basename(path), n, e))
    def line(s, line, path):
        t = s.strip_comment(line)
        label = None
        if t and t[0] not in ' \t':
            j = 0
            while j < len(t) and t[j].upper() in IDCH: j += 1
            label = t[:j].upper(); t = t[j:]
            if t.startswith(':'): t = t[1:]
            if not label: raise AsmError('syntax error')
            if len(label) > 32: raise AsmError('name too long')
        else:
            t2 = t.strip(); j = 0
            while j < len(t2) and t2[j].upper() in IDCH: j += 1
            if j and t2[j:j + 1] == ':':
                label = t2[:j].upper(); t = t2[j + 1:]
                if len(label) > 32: raise AsmError('name too long')
        t = t.strip()
        j = 0
        while j < len(t) and (t[j].upper() in IDCH or (j == 0 and t[j] == '.')): j += 1
        mn = t[:j].upper().lstrip('.'); rest = t[j:].strip()
        if mn in ('=',) or t.startswith('='): mn, rest = 'EQU', t[1:].strip()
        # conditional assembly
        active = all(s.cond)
        if mn in ('IF', 'IFDEF', 'IFNDEF'):
            if not active: s.cond.append(False); return
            if mn == 'IF':
                try: v, k = s.ev(rest)
                except AsmError: v, k = 0, False
                s.cond.append(bool(k and v != 0))
                if not k: raise AsmError('value must be known in pass 1')
            else: s.cond.append((rest.upper() in s.sym) == (mn == 'IFDEF'))
            return
        if mn == 'ELSE':
            if not s.cond: raise AsmError('IF/ELSE/ENDIF mismatch')
            outer = all(s.cond[:-1]); s.cond[-1] = outer and not s.cond[-1]; return
        if mn == 'ENDIF':
            if not s.cond: raise AsmError('IF/ELSE/ENDIF mismatch')
            s.cond.pop(); return
        if not active: return
        if mn == 'EQU':
            if not label: raise AsmError('syntax error')
            v, k = s.ev(rest)
            if not k and not s.pass2: s.sym.pop(label, None); return
            s.define(label, v); return
        if label: s.define(label, s.pc)
        if not mn: return
        if mn == 'ORG':
            v, k = s.ev(rest)
            if not k: raise AsmError('value must be known in pass 1')
            if s.pass2 and s.start is not None and v < s.pc: raise AsmError('ORG backwards')
            if s.pass2 and s.start is not None: s.emit(bytes(v - s.pc))
            s.pc = v; return
        if mn in ('DB', 'DEFB', 'DM', 'DEFM', 'BYTE', 'TEXT'):
            bs = []
            for it in split_ops(rest):
                if len(it) >= 2 and it[0] in '"\'' and it[-1] == it[0] and not (len(it) == 3):
                    bs += [ord(c) for c in it[1:-1]]
                else:
                    v, k = s.ev(it)
                    if s.pass2 and not (-128 <= sx(v) <= 255): raise AsmError('value out of range')
                    bs.append(v & 0xFF)
            s.emit(bs); return
        for names, n in ((('DW', 'DEFW', 'WORD'), 2), (('DL', 'DD', 'DWORD'), 4), (('DQ', 'QWORD'), 8)):
            if mn in names:
                bs = []
                for it in split_ops(rest):
                    v, k = s.ev(it)
                    if s.pass2 and n < 8 and not (-(1 << (8 * n - 1)) <= sx(v) < (1 << (8 * n))): raise AsmError('value out of range')
                    bs += [(v >> (8 * i)) & 0xFF for i in range(n)]
                s.emit(bs); return
        if mn in ('DS', 'DEFS', 'BLOCK', 'ALIGN'):
            a = split_ops(rest); v, k = s.ev(a[0])
            if not k: raise AsmError('value must be known in pass 1')
            f = s.ev(a[1])[0] & 0xFF if len(a) > 1 else 0
            if mn == 'ALIGN':
                if v == 0: raise AsmError('value out of range')
                v = (-s.pc) % v
            s.emit([f] * v); return
        if mn == 'END':
            if rest: s.entry = s.ev(rest)[0]
            s.ended = True; return
        if mn == 'INCLUDE':
            fn = rest.strip('"\' ')
            if s.depth >= 3: raise AsmError('include nesting too deep')
            full = os.path.join(os.path.dirname(path), fn.upper())
            if not os.path.exists(full): raise AsmError('include file not found')
            s.depth += 1; s.file(full); s.depth -= 1; return
        if mn not in BYMN: raise AsmError('unknown instruction')
        ops = [s.operand(o) for o in split_ops(rest)] if rest else []
        for f in BYMN[mn]:
            m = match(f, ops)
            if m: s.emit(encode(f, m, s.pc, s.pass2)); return
        raise AsmError('invalid operands')
    @staticmethod
    def strip_comment(line):
        q = None; out = ''
        for i, ch in enumerate(line):
            if q:
                if ch == q: q = None
            elif ch in '"\'' and not (ch == "'" and out[-1:].upper() in IDCH and out[-1:] != ''): q = ch
            elif ch == ';': break
            out += ch
        return out

if __name__ == '__main__':
    a = Asm(sys.argv[1]); out = a.run()
    for e in a.errors: print(e)
    if len(sys.argv) > 2: open(sys.argv[2], 'wb').write(out)
    print('%d bytes, %d symbols, %d errors' % (len(out), len(a.sym), len(a.errors)))
    sys.exit(1 if a.errors else 0)
