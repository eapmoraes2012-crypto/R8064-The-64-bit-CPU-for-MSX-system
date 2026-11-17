import random,subprocess,sys
def model(o,w,a,h,b):
    W=8<<w; mW=(1<<W)-1; m2=(1<<(2*W))-1
    sg=o&1; dv=o>>1
    def sx(x,bits): x&=(1<<bits)-1; return x-(1<<bits) if (sg and x>>(bits-1)) else x
    if not dv:
        p=sx(a,W)*sx(b,W); r=p&m2
        hi=(r>>W)&mW; lo=r&mW
        ovf = (hi!=(mW if (lo>>(W-1)) else 0)) if sg else hi!=0
        fl=((r>>(2*W-1))&1)<<7 | (r==0)<<6 | (sg&ovf)<<2 | ovf
        return r,r>>W,fl,0
    Lw=16 if W<=16 else 64
    D=((h&mW if (w&1) else 0)<<Lw)|(a&((1<<Lw)-1))
    d=sx(b,W); D=sx(D,2*W)
    if d==0: return None
    q=abs(D)//abs(d); rem=abs(D)%abs(d)
    if (D<0)!=(d<0): q=-q
    if D<0: rem=-rem
    lo,hi=(-(1<<(W-1)),(1<<(W-1))-1) if sg else (0,mW)
    if not(lo<=q<=hi): return None
    qm=q&mW; rm=rem&mW; r=(rm<<W)|qm
    return r,r>>W,(qm==0)<<6,0
N=int(sys.argv[1]); random.seed(int(sys.argv[2]))
vec=[]
def rnd(W):
    t=random.random()
    if t<.15: return random.choice([0,1,(1<<W)-1,1<<(W-1),(1<<(W-1))-1,2])
    if t<.5: return random.getrandbits(random.randint(1,W))
    return random.getrandbits(W)
for _ in range(N):
    o=random.randint(0,3); w=random.randint(0,3); W=8<<w
    if o&2:   # divisao: dividendo de 2W bits
        a=random.getrandbits(64); h=random.getrandbits(64)
        if random.random()<.6:   # evita overflow na maioria
            b=rnd(W) or 1
            Dw=random.getrandbits(2*W-1) if random.random()<.3 else random.getrandbits(W+random.randint(0,W-1))
            D=Dw
            if random.random()<.4: D=(-D)&((1<<(2*W))-1)
            Lw=16 if W<=16 else 64
            a=D&((1<<Lw)-1); h=(D>>Lw)&((1<<64)-1) if (w&1) else 0
        else: b=rnd(W)
    else:
        a=rnd(W); h=0; b=rnd(W)
    vec.append((o,w,a,h,b))
open('vec.txt','w').write(''.join('%x %x %x %x %x\n'%v for v in vec))
out=subprocess.run(['vvp','a.out'],capture_output=True,text=True).stdout.splitlines()
res=[l.split() for l in out if l.startswith('R ')]
assert len(res)==N,(len(res),out[-3:])
err=0;ninv=0
for v,rr in zip(vec,res):
    m=model(*v); fl=int(rr[3],16); inv=int(rr[4],16)
    if m is not None: r=int(rr[1],16); rhi=int(rr[2],16)
    if m is None:
        ninv+=1
        if not(inv==1 and fl==4): err+=1; print('INV esperado',v,rr) if err<8 else 0
    else:
        W=8<<v[1]; m2=(1<<(2*W))-1
        ok= inv==0 and (r&m2)==m[0] and rhi==(m[1]&((1<<64)-1)) and fl==m[2]
        if not ok:
            err+=1
            if err<8: print('ERRO',v,'rtl',hex(r),hex(rhi),hex(fl),inv,'mod',hex(m[0]),hex(m[1]),hex(m[2]))
print('vetores',N,'invalidos',ninv,'erros',err,[l for l in out if 'MAXCYC' in l])
