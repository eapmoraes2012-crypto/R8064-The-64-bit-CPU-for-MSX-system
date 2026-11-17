# gen_vectors.py <seed> <n_per_operation> > vetores.txt   (op rc pc A B -> res flags up cc, all in hex)
import sys, random
sys.path.insert(0, '.')
from fpref import *
random.seed(int(sys.argv[1])); N = int(sys.argv[2])
R = random.getrandbits
def mant_special():
    c = random.random()
    if c < 0.25: return (1 << 63) | R(63)
    if c < 0.35: return 1 << 63
    if c < 0.45: return (1 << 64) - 1
    if c < 0.55: return (1 << 63) | ((1 << random.randint(1, 62)) - 1)
    if c < 0.65: return (1 << 63) | (1 << random.randint(0, 62))
    return (1 << 63) | R(63)
def exp_pick():
    c = random.random()
    if c < 0.35: return 16383 + random.randint(-80, 80)
    if c < 0.5: return random.randint(1, 8)
    if c < 0.65: return random.randint(32760, 32766)
    if c < 0.75: return random.choice([16383 + 127, 16383 - 126, 16383 + 128, 16383 - 127, 16383 + 1023, 16383 - 1022, 16383 + 1024, 16383 - 1023, 16383 - 149, 16383 - 1074, 16383 + 63, 16383 + 62, 16383 + 64])
    return random.randint(1, 32766)
def rnd80(kind=None):
    s = R(1) << 79
    k = kind or random.choices(['norm', 'zero', 'den', 'inf', 'qnan', 'snan', 'uns'], [60, 5, 8, 4, 3, 3, 2])[0]
    if k == 'norm': return s | (exp_pick() << 64) | mant_special()
    if k == 'zero': return s
    if k == 'den': return s | (R(random.randint(1, 63)) & ((1 << 63) - 1) or 1)
    if k == 'inf': return s | (0x7FFF << 64) | (1 << 63)
    if k == 'qnan': return s | (0x7FFF << 64) | (3 << 62) | R(62)
    if k == 'snan': return s | (0x7FFF << 64) | (1 << 63) | (R(62) or 1)
    c = random.randint(0, 3)
    if c == 0: return s | (0x7FFF << 64) | R(63)          # pseudo-inf/NaN
    if c == 1: return s | (random.randint(1, 32766) << 64) | R(63)  # not normalized
    if c == 2: return s | (R(1) << 63) | R(63) if False else s | (1 << 63) | R(63)  # pseudo-denormal
    return s | (random.randint(1, 32766) << 64) | (R(63))
def near(x):
    """second operand close to the first (cancellation / alignment)"""
    c = random.random(); s = R(1) << 79
    ex = (x >> 64) & 0x7FFF
    if ex in (0, 0x7FFF) or not (x >> 63) & 1: return rnd80()
    if c < 0.3: return s | (ex << 64) | (x & ((1 << 64) - 1)) ^ R(random.randint(1, 8))
    if c < 0.6: return s | (max(1, min(32766, ex + random.randint(-3, 3))) << 64) | mant_special()
    if c < 0.8: return s | (max(1, min(32766, ex - random.randint(60, 70))) << 64) | mant_special()
    return s | (max(1, min(32766, ex + random.randint(-70, 70))) << 64) | mant_special()
def emit(op, rc, pc, A, B):
    r, fl, up, cc = alu(op, A, B, rc, pc)
    print('%x %x %x %020x %020x %020x %02x %d %x' % (OPS.index(op) if isinstance(op, str) else op, rc, pc, A, B, r, fl, 1 if up else 0, cc))
def ieee32(): 
    c = random.random()
    if c < 0.2: return (R(1) << 31) | (random.choice([0, 0xFF, 1, 0xFE]) << 23) | R(23)
    return (R(1) << 31) | (random.randint(0, 255) << 23) | R(23)
def ieee64():
    c = random.random()
    if c < 0.2: return (R(1) << 63) | (random.choice([0, 0x7FF, 1, 0x7FE]) << 52) | R(52)
    return (R(1) << 63) | (random.randint(0, 2047) << 52) | R(52)
for op in ['ADD', 'SUB', 'MUL', 'DIV']:
    for i in range(N):
        A = rnd80(); B = near(A) if random.random() < 0.5 else rnd80()
        emit(op, random.randint(0, 3) if random.random() < 0.5 else 0, random.choice([0, 2, 3, 3, 3]), A, B)
for i in range(N):
    A = rnd80(); A = A & ~(1 << 79) if random.random() < 0.85 else A
    emit('SQRT', random.randint(0, 3) if random.random() < 0.5 else 0, random.choice([0, 2, 3, 3]), A, 0)
for i in range(N):
    A = rnd80(); B = near(A) if random.random() < 0.5 else rnd80(); emit('CMP', 0, 3, A, B)
for i in range(N):
    c = random.random()
    v = R(64) if c < 0.3 else R(random.randint(1, 63)) if c < 0.8 else random.choice([0, 1, (1 << 63), (1 << 63) - 1, (1 << 64) - 1, (1 << 64) - (1 << 63)])
    emit('FILD', 0, 3, v, 0)
for i in range(N):
    c = random.random()
    if c < 0.6: A = (R(1) << 79) | ((16383 + random.randint(-3, 66)) << 64) | mant_special()
    else: A = rnd80()
    emit('FIST', random.randint(0, 3), 3, A, 0)
    emit('RNDINT', random.randint(0, 3), 3, A, 0)
for i in range(N):
    emit('LD32', 0, 3, ieee32(), 0); emit('LD64', 0, 3, ieee64(), 0)
for i in range(N):
    c = random.random()
    if c < 0.7:
        e = random.choice([16383 + 127, 16383 - 126, 16383 + 128, 16383 - 127, 16383 - 149, 16383 - 150, 16383 + 126, 16383 + 1023, 16383 - 1022, 16383 + 1024, 16383 - 1074, 16383 - 1075, 16383 - 1023]) + random.randint(-2, 2)
        A = (R(1) << 79) | (e << 64) | mant_special()
    else: A = rnd80()
    rc = random.randint(0, 3)
    emit('ST32', rc, 3, A, 0); emit('ST64', rc, 3, A, 0)
