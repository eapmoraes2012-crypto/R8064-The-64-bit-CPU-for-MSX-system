# fpu_stk_ref.py - reference model (Python) of the FPU residual hardware: ST0-ST7 stack, tags, CW, SW. Generates vectors for tb_fpu_stk.v.
# Commands: 0 NOP 1 INIT 2 PUSH 3 POP 4 XCH 5 WRST 6 INCSTP 7 DECSTP 8 SETCW 9 CLREX 10 ORFLG 11 SETCC 12 SETSW 13 SETTW 14 FREE
import random, sys
INDEF = (1 << 79) | (0x7FFF << 64) | (0xC000 << 48)
M64 = (1 << 64) - 1
def classify_tag(v):
    ex = (v >> 64) & 0x7FFF; m = v & M64
    if ex == 0 and m == 0: return 1                      # zero
    if ex == 0x7FFF: return 2                            # inf/NaN/pseudo
    if ex == 0: return 2                                 # denormal / pseudo-denormal
    if not (m >> 63): return 2                           # not normalized
    return 0                                             # valid
def fxam(v, empty):
    sign = (v >> 79) & 1; ex = (v >> 64) & 0x7FFF; m = v & M64
    if empty: return (1, 0, sign, 1)                     # c3,c2,c1,c0
    if ex == 0 and m == 0: return (1, 0, sign, 0)
    if ex == 0x7FFF:
        if m >> 63:
            return (0, 1, sign, 1) if (m & ((1 << 63) - 1)) == 0 else (0, 0, sign, 1)   # infinity : NaN
        return (0, 0, sign, 0)                           # pseudo-NaN/inf: unsupported
    if ex == 0: return (0, 0, sign, 0) if (m >> 63) else (1, 1, sign, 0)   # pseudo-denormal : unsupported ; denormal c3=c2=1
    if not (m >> 63): return (0, 0, sign, 0)             # not normalized
    return (0, 1, sign, 0)                               # normal
class Stk:
    def __init__(self): self.init()
    def init(self):
        self.cw = 0x037F; self.exc = 0; self.c = [0, 0, 0, 0]; self.top = 0
        if not hasattr(self, 'st'): self.st = [0] * 8     # FINIT does not erase the data (only the tags)
        self.tag = [3] * 8
    def es(self): return 1 if (self.exc & 0x3F & ~self.cw) else 0
    def sw(self): return (self.exc & 0x7F) | (self.es() << 7) | (self.c[0] << 8) | (self.c[1] << 9) | (self.c[2] << 10) | (self.top << 11) | (self.c[3] << 14) | (self.es() << 15)
    def tw(self): return sum(self.tag[i] << (2 * i) for i in range(8))
    def phys(self, i): return (self.top + i) & 7
    def step(self, cmd, idx, w, fl, ra_i=0, rb_i=0):
        if cmd == 1: self.init()
        elif cmd == 2:
            n = (self.top - 1) & 7
            if self.tag[n] != 3:
                self.exc |= 0x01 | 0x40; self.c[1] = 1
                if self.cw & 1: self.top = n; self.st[n] = INDEF; self.tag[n] = classify_tag(INDEF)
            else:
                self.top = n; self.st[n] = w; self.tag[n] = classify_tag(w)
        elif cmd == 3:
            if self.tag[self.top] == 3:
                self.exc |= 0x01 | 0x40; self.c[1] = 0
                if self.cw & 1: self.top = (self.top + 1) & 7
            else:
                self.tag[self.top] = 3; self.top = (self.top + 1) & 7
        elif cmd == 4:
            a = self.phys(ra_i); b = self.phys(rb_i)
            self.st[a], self.st[b] = self.st[b], self.st[a]; self.tag[a], self.tag[b] = self.tag[b], self.tag[a]
        elif cmd == 5:
            p = self.phys(idx); self.st[p] = w; self.tag[p] = classify_tag(w)
        elif cmd == 6: self.top = (self.top + 1) & 7
        elif cmd == 7: self.top = (self.top - 1) & 7
        elif cmd == 8: self.cw = w & 0xFFFF
        elif cmd == 9: self.exc = 0
        elif cmd == 10: self.exc |= fl & 0x3F
        elif cmd == 11: self.c = [(w >> 0) & 1, (w >> 1) & 1, (w >> 2) & 1, (w >> 3) & 1]
        elif cmd == 12:
            s = w & 0xFFFF; self.exc = s & 0x7F; self.c = [(s >> 8) & 1, (s >> 9) & 1, (s >> 10) & 1, (s >> 14) & 1]; self.top = (s >> 11) & 7
        elif cmd == 13:
            for i in range(8): self.tag[i] = (w >> (2 * i)) & 3
        elif cmd == 14: self.tag[self.phys(idx)] = 3
if __name__ == '__main__':
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 20000
    random.seed(8064)
    S = Stk(); out = []
    def rnd80():
        k = random.random()
        s = random.getrandbits(1) << 79
        if k < .15: return s                                            # zero
        if k < .30: return s | (0x7FFF << 64) | (1 << 63)               # infinity
        if k < .40: return s | (0x7FFF << 64) | (0xC000 << 48) | random.getrandbits(40)   # NaN
        if k < .50: return s | random.getrandbits(63)                    # denormal
        if k < .55: return s | (random.getrandbits(15) << 64) | random.getrandbits(63)    # not normalized
        return s | (random.randrange(1, 0x7FFF) << 64) | (1 << 63) | random.getrandbits(63)
    weights = [1, 2, 18, 18, 8, 12, 4, 4, 3, 3, 8, 4, 2, 2, 5]
    for t in range(n):
        cmd = random.choices(range(15), weights)[0]
        if t == 0: cmd = 1
        idx = random.randrange(8); w = rnd80() if cmd in (2, 5) else random.getrandbits(80) if cmd in (8, 11, 12, 13) else 0
        fl = random.getrandbits(6); ra_i = random.randrange(8); rb_i = random.randrange(8)
        S.step(cmd, idx, w, fl, ra_i, rb_i)
        pa, pb = S.phys(ra_i), S.phys(rb_i)
        f = fxam(S.st[pa], S.tag[pa] == 3)
        out.append('%x %x %x %020x %02x %x %x %020x %020x %x %x %04x %04x %04x %x %x %x %x' % (
            1, cmd, idx, w, fl, ra_i, rb_i, S.st[pa], S.st[pb], S.tag[pa], S.tag[pb], S.cw, S.sw(), S.tw(), f[0], f[1], f[2], f[3]))
    open('vet_stk.txt', 'w').write('\n'.join(out) + '\n'); print('vectors', len(out))
