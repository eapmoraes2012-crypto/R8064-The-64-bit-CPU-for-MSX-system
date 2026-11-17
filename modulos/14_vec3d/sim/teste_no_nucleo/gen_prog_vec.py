# generates prog_vec.mem (random program LDQ + 3D instructions with/without bank prefixes) and exp_vec.mem (expected result of each 3D instruction, in order).
# reference model: the same as 14_vec3d/sim/gen_vec3d.py (Python integers). usage: python3 gen_prog_vec.py [seed] [n_instr]
import random, sys
seed=int(sys.argv[1]) if len(sys.argv)>1 else 8064; NI=int(sys.argv[2]) if len(sys.argv)>2 else 400
random.seed(seed); LANE0=(len(sys.argv)<=3 or sys.argv[3]!='full')   # default: minimal unit (without op 4-7)
def s16(x): x &= 0xffff; return x-0x10000 if x & 0x8000 else x
def sat(x): return max(-32768, min(32767, x))
def lanes(v): return [s16(v >> (16*i)) for i in range(4)]
def pack(l): return sum((x & 0xffff) << (16*i) for i, x in enumerate(l))
def shr(x, s):
    r = (1 << (s-1)) if s else 0
    return (x + r) >> s
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
corners=[0,1,0xffff,0x7fff,0x8000,0x8001]
def rv():
    if random.random()<0.3: return pack([s16(random.choice(corners)) for _ in range(4)])
    if random.random()<0.3: return pack([random.randint(-300,300) for _ in range(4)])
    return random.getrandbits(64)
CODES=[0,2,4,7]                                   # BC DE HL AX
st={0:{c:0 for c in CODES},0x0E:{c:0 for c in CODES},0x0D:{c:0 for c in CODES}}
P=[]; exp=[]; info=[]
def pre(b): return [] if b==0 else [b]
for n in range(NI):
    b=random.choice([0,0,0x0E,0x0D]); R=st[b]
    if random.random()<0.35:
        c=random.choice(CODES); v=rv(); R[c]=v
        P+= [0xED]+pre(b)+[0x39,0x40|(c<<3)|1]+[(v>>(8*k))&255 for k in range(8)]
    else:
        kind=random.choice(['bin','bin','bin','shuf','un'])
        rd=random.choice(CODES); rs=random.choice(CODES); mod=(rd<<3)|rs
        if kind=='bin':
            op=random.choice([0,1,2,3] if LANE0 else range(8)); sh=random.randint(0,15); imm=(op<<4)|sh
            r=model(op,R[rd],R[rs],sh,imm); b2=0xF8; info.append('F8 op%d sh%d'%(op,sh))
        elif kind=='un':
            op=random.choice([9,10]); sh=random.randint(0,15); imm=(op<<4)|sh
            r=model(op,R[rs],0,0,imm); b2=0xFB; info.append('FB op%d'%op)
        else:
            imm=random.randint(0,255); r=model(8,R[rs],0,0,imm); b2=0xFA; info.append('FA imm%02x'%imm)
        R[rd]=r; exp.append(r)
        P+= [0xED]+pre(b)+[b2,mod,imm]
P+=[0x18,0xFE]
assert len(P)<8192
mem=P+[0]*(8192-len(P))
open('prog_vec.mem','w').write('\n'.join('%016x'%sum(mem[i*8+k]<<(8*k) for k in range(8)) for i in range(1024))+'\n')
open('exp_vec.mem','w').write('\n'.join('%016x'%x for x in exp)+'\n'); open('exp_vec.txt','w').write('\n'.join(info)+'\n')
open('nvec.vh','w').write("localparam NEXP = %d;\n"%len(exp)); print('instr',NI,'vec ops',len(exp),'bytes',len(P))
