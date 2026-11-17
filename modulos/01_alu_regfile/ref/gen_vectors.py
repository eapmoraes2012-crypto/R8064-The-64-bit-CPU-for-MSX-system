#!/usr/bin/env python3
"""INDEPENDENT reference model of the ALU (Python integers) and testbench vector generator."""
import random, sys
random.seed(8064)
C,N,PV,X,H,Y,Z,S=1,2,4,8,16,32,64,128
ADD,ADC,SUB,SBC,AND,OR,XOR,CP,INC,DEC,NEG,CPL,SHL,SHR,SAR,ROL,ROR=range(17)
def parity(v): return 1 if bin(v&0xFF).count('1')%2==0 else 0
def alu(a,b,op,sz,fin):
    W=(8,16,32,64)[sz]; M=(1<<W)-1; a&=M; b&=M; top=(1<<(W-1))
    cf=fin&C; f=0
    if op in (ADD,ADC,SUB,SBC,CP,INC,DEC,NEG):
        if op in (ADD,ADC):
            t=a+b+(cf if op==ADC else 0); r=t&M; c=(t>>W)&1; n=0; bb=b
            ov=(~(a^b)&(a^r))&top
        elif op in (SUB,SBC,CP):
            cin=cf if op==SBC else 0; t=a-b-cin; r=t&M; c=1 if a<b+cin else 0; n=1; bb=b
            ov=((a^b)&(a^r))&top
        elif op==INC:
            r=(a+1)&M; c=cf; n=0; bb=1; ov=top if a==top-1 else 0
        elif op==DEC:
            r=(a-1)&M; c=cf; n=1; bb=1; ov=top if a==top else 0
        else:
            r=(-a)&M; c=1 if a!=0 else 0; n=1; bb=a; ov=top if a==top else 0
        h=((a if op!=NEG else 0)^bb^r)>>4&1
        f=(c*C)|(n*N)|((1 if ov else 0)*PV)|(h*H)
        if op==CP: f|=(b&Y)|(b&X)
        else: f|=(r&Y)|(r&X)
    elif op in (AND,OR,XOR):
        r={AND:a&b,OR:a|b,XOR:a^b}[op]
        f=(H if op==AND else 0)|(PV if parity(r) else 0)|(r&Y)|(r&X)
    elif op==CPL:
        r=(~a)&M; f=(fin&(S|Z|PV|C))|H|N|(r&Y)|(r&X)
        return r,f&0xFF
    else:
        if op==SHL: out=a>>(W-1)&1; r=(a<<1)&M
        elif op==SHR: out=a&1; r=a>>1
        elif op==SAR: out=a&1; r=(a>>1)|(a&top)
        elif op==ROL: out=a>>(W-1)&1; r=((a<<1)&M)|out
        else: out=a&1; r=(a>>1)|(out<<(W-1))
        f=(out*C)|(PV if parity(r) else 0)|(r&Y)|(r&X)
    f|=S if r&top else 0
    f|=Z if r==0 else 0
    return r,f&0xFF
corner=[0,1,2,0xF,0x10,0x7F,0x80,0xFF,0x7FFF,0x8000,0xFFFF,0x7FFFFFFF,0x80000000,0xFFFFFFFF,0x7FFFFFFFFFFFFFFF,0x8000000000000000,0xFFFFFFFFFFFFFFFF,0x0123456789ABCDEF]
V=[]
for op in range(17):
    for sz in range(4):
        for fin in (0x00,0xFF,0x01,random.randrange(256)):
            for a in corner:
                for b in corner: V.append((a,b,op,sz,fin))
for _ in range(60000):
    V.append((random.getrandbits(64),random.getrandbits(64),random.randrange(17),random.randrange(4),random.randrange(256)))
with open('alu_a.mem','w') as fa, open('alu_b.mem','w') as fb, open('alu_c.mem','w') as fc, open('alu_ra.mem','w') as fr, open('alu_rf.mem','w') as ff:
    for a,b,op,sz,fin in V:
        r,f=alu(a,b,op,sz,fin)
        fa.write('%016X\n'%a); fb.write('%016X\n'%b); fc.write('%04X\n'%((op<<10)|(sz<<8)|fin)); fr.write('%016X\n'%r); ff.write('%02X\n'%f)
# regmap
RM={0:1,2:2,3:10,4:3,5:9,7:0}
with open('regmap_exp.mem','w') as f:
    for k in range(32):
        rr=k&7; sm=(k>>3)&1; sa=(k>>4)&1
        if rr in RM:
            idx=RM[rr]
            if rr in(0,2,4) and sm: idx={0:6,2:7,4:8}[rr]
            if rr==7 and sa: idx=5
            f.write('%02X\n'%(0x40|idx))
        else: f.write('00\n')
# regmerge
with open('merge_old.mem','w') as fo, open('merge_new.mem','w') as fn, open('merge_c.mem','w') as fc2, open('merge_exp.mem','w') as fe:
    for _ in range(5000):
        o=random.getrandbits(64); n=random.getrandbits(64); w=random.randrange(5)
        e={0:(o&~0xFF)|(n&0xFF),1:(o&~0xFF00)|((n&0xFF)<<8),2:(o&~0xFFFF)|(n&0xFFFF),3:(o&~0xFFFFFFFF)|(n&0xFFFFFFFF),4:n}[w]
        fo.write('%016X\n'%o); fn.write('%016X\n'%n); fc2.write('%X\n'%w); fe.write('%016X\n'%e)
open('nvec.txt','w').write(str(len(V)))
print('ALU vectors:',len(V))
