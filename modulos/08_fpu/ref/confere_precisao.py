# confere_precisao.py - measures the error of the transcendentals (the gen_fpu_prog.py steps executed with fpref.py) against exact references in fractions.
import sys, math, random
import os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fpref, gen_fpu_prog as GP
from fractions import Fraction as F
M=2**64-1
def val(v):
    s=-1 if v>>79 else 1; e=(v>>64)&0x7FFF; return s*F(v&M)*F(2)**(e-16383-63)
def run(entry, st, var=0):
    tmp=[0]*16; q=lc=cidx=dq=0; pc=GP.ENTRY[entry]; st=list(st)
    rd=lambda r: st[r-16] if r>=16 else tmp[r]
    def wr(r,v):
        if r>=16: st[r-16]=v
        else: tmp[r]=v
    while True:
        p=GP.PROG[pc]; k=p['k']; pc+=1
        if k==0:
            B=GP.CONST[cidx] if p['bsel']==2 else GP.CONST[p['b']] if p['bsel']==1 else rd(p['b']&31)
            res,fl,up,cc=fpref.alu(p['aop'], dq if p['aop']==6 else rd(p['a']),B,p['rc'],3)
            if p['q']: q=res&3
            else: wr(p['dst'],res)
            if p['bsel']==2: cidx-=1
        elif k==1:
            wr(p['dst'],GP.CONST[cidx if p['bsel']==2 else p['b']]); cidx-= p['bsel']==2
        elif k==2: v=rd(p['a']); wr(p['dst'],0x3FFF<<64|v&M); dq=(((v>>64)&0x7FFF)-16383)&M
        elif k==3:
            c=p['b']&1; src=tmp[13] if c^(q&1) else tmp[12]; neg=((q>>1)^(q&1))&1 if c else (q>>1)&1; wr(p['dst'],src^neg<<79)
        elif k==5:
            if lc: lc-=1; pc=p['b']
        elif k==6: lc=p['a']; cidx=p['b']
        elif k==8: pc+=4*var
        elif k==7: return st
def ulps(g, r): return float(abs(g-r)/F(2)**(math.floor(math.log2(abs(float(r))))-63))
def sin_x(fr): return sum(F((-1)**k)*fr**(2*k+1)/math.factorial(2*k+1) for k in range(45))
def cos_x(fr): return sum(F((-1)**k)*fr**(2*k)/math.factorial(2*k) for k in range(45))
def ln_x(fr):                                   # fr > 0
    e=0
    while fr>=2: fr/=2; e+=1
    while fr<1: fr*=2; e-=1
    f=(fr-1)/(fr+1); return e*GP.LN2+2*sum(f**(2*k+1)/(2*k+1) for k in range(70))
random.seed(5); w={}
def up(n,v): w[n]=max(w.get(n,0),v)
for i in range(120):
    x=F(random.randrange(-2**40,2**40),2**40)*F(2)**random.randrange(-6,6); X=GP.ext(x); xv=val(X)
    if xv==0: continue
    k=round(xv/(GP.PI/2)); r=xv-k*GP.PI/2; s,c=sin_x(r),cos_x(r)
    sx=[s,c,-s,-c][k%4]; cx=[c,-s,-c,s][k%4]
    up('sen',ulps(val(run('trig',[X,0],0)[0]),sx)); up('cos',ulps(val(run('trig',[X,0],1)[0]),cx))
    if abs(cx)>F(1,100): up('tan',ulps(val(run('trig',[X,0],3)[0]),sx/cx))
    p=F(random.randrange(1,2**40),2**20)*F(2)**random.randrange(-30,30); P=GP.ext(p); pv=val(P); l=ln_x(pv)
    if abs(l)>F(1,100):
        up('ln',ulps(val(run('fln',[P,0])[0]),l)); up('yl2x',ulps(val(run('fyl2x',[P,GP.ext(F(3))])[1]),3*l/GP.LN2))
    t=F(random.randrange(-2**40,2**40),2**40)*F(29,100); Tx=GP.ext(t); tv=val(Tx)
    if tv!=0: up('yl2p',ulps(val(run('fyl2p',[Tx,GP.ext(F(1))])[1]),ln_x(1+tv)/GP.LN2))
print('maximum error in units of the last place (64-bit significand):', {k:round(v,1) for k,v in w.items()})
