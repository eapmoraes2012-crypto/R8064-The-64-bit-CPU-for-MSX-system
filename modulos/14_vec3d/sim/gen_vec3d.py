# gera vetores e resultados esperados (modelo em inteiros do Python) para vec3d_unit. uso: python3 gen_vec3d.py <pasta_saida>
import random, sys
random.seed(8064)
def s16(x): x &= 0xffff; return x-0x10000 if x & 0x8000 else x
def sat(x): return max(-32768, min(32767, x))
def lanes(v): return [s16(v >> (16*i)) for i in range(4)]
def pack(l): return sum((x & 0xffff) << (16*i) for i, x in enumerate(l))
def shr(x, s):
    r = (1 << (s-1)) if s else 0
    return (x + r) >> s                     # >> em Python = deslocamento aritmetico (piso)
def model(op, a, b, sh, imm):
    A, B = lanes(a), lanes(b)
    if op == 0: return pack([sat(shr(A[i]*B[i], sh)) for i in range(4)])
    if op == 1: return shr(sum(A[i]*B[i] for i in range(4)), sh) & (2**64-1)
    if op == 2: return shr(sum(A[i]*B[i] for i in range(3)), sh) & (2**64-1)
    if op == 3:
        c = [A[1]*B[2]-A[2]*B[1], A[2]*B[0]-A[0]*B[2], A[0]*B[1]-A[1]*B[0], 0]
        return pack([sat(shr(x, sh)) for x in c])
    if op == 4: return pack([sat(A[i]+B[i]) for i in range(4)])
    if op == 5: return pack([sat(A[i]-B[i]) for i in range(4)])
    if op == 6: return pack([min(A[i], B[i]) for i in range(4)])
    if op == 7: return pack([max(A[i], B[i]) for i in range(4)])
    if op == 8: return pack([A[(imm >> (2*i)) & 3] for i in range(4)])
    if op == 9: return pack([sat(-A[i]) for i in range(4)])
    return pack([sat(abs(A[i])) for i in range(4)])
out = sys.argv[1] if len(sys.argv) > 1 else '.'
N = 30000; fa = open(out+'/v_a.mem', 'w'); fb = open(out+'/v_b.mem', 'w'); fc = open(out+'/v_c.mem', 'w'); fe = open(out+'/v_e.mem', 'w')
corners = [0, 1, 0xffff, 0x7fff, 0x8000, 0x8001]
for n in range(N):
    op = random.randint(0, 10); sh = random.randint(0, 15); imm = random.randint(0, 255)
    def rv():
        if random.random() < 0.3: return pack([s16(random.choice(corners)) for _ in range(4)])
        if random.random() < 0.3: return pack([random.randint(-300, 300) for _ in range(4)])
        return random.getrandbits(64)
    a, b = rv(), rv()
    fa.write('%016x\n' % a); fb.write('%016x\n' % b); fc.write('%02x%02x%x\n' % (imm, sh, op)); fe.write('%016x\n' % model(op, a, b, sh, imm))
open(out+'/nvec_v.txt', 'w').write(str(N))
