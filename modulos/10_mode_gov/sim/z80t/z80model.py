# Modelo de referencia (Z80 classico) das instrucoes de pagina principal implementadas no nucleo (REV47)
PAR=[bin(i).count('1')%2==0 for i in range(256)]
class Z:
    def __init__(s,mem): s.m=bytearray(mem); s.r=dict(a=0,b=0,c=0,d=0,e=0,h=0,l=0,f=0); s.sp=0xF00; s.pc=0; s.n=0; s.x=dict(ix=0,iy=0); s.cbarg=None; s.sh=dict(b=0,c=0,d=0,e=0,h=0,l=0)
    def rd(s,a): return s.m[a&0xFFF]
    def wr(s,a,v): s.m[a&0xFFF]=v&255
    def rd16(s,a): return s.rd(a)|s.rd(a+1)<<8
    def wr16(s,a,v): s.wr(a,v); s.wr(a+1,v>>8)
    def pr(s,n): return {'bc':(s.r['b']<<8)|s.r['c'],'de':(s.r['d']<<8)|s.r['e'],'hl':(s.r['h']<<8)|s.r['l'],'sp':s.sp}[n]
    def spr(s,n,v):
        v&=0xFFFF
        if n=='sp': s.sp=v
        else: hi,lo=n[0],n[1]; s.r[hi]=v>>8; s.r[lo]=v&255
    def getr(s,i): # B C D E H L (HL) A
        return [s.r['b'],s.r['c'],s.r['d'],s.r['e'],s.r['h'],s.r['l'],s.rd(s.pr('hl')),s.r['a']][i]
    def setr(s,i,v):
        v&=255
        if i==6: s.wr(s.pr('hl'),v)
        else: s.r['bcdehl?a'[i]]=v if False else v if False else None
    def setreg(s,i,v):
        v&=255
        if i==6: s.wr(s.pr('hl'),v)
        else: s.r['bcdehl?a'[i]]=v
    def alu(s,op,b):
        a=s.r['a']; f=s.r['f']; c=f&1
        if op in (0,1,2,3,7):
            sub=op in (2,3,7); cin=c if op in (1,3) else 0
            res=(a-b-cin) if sub else (a+b+cin)
            r8=res&255
            h=((a^b^r8)&0x10)!=0
            if sub: pv=((a^b)&(a^r8)&0x80)!=0; cf=res<0
            else: pv=((a^r8)&(b^r8)&0x80)!=0; cf=res>0xFF
            yx=(b if op==7 else r8)&0x28
            nf=(r8&0x80)|(0x40 if r8==0 else 0)|yx|(0x10 if h else 0)|(4 if pv else 0)|(2 if sub else 0)|(1 if cf else 0)
            s.r['f']=nf
            if op!=7: s.r['a']=r8
        else:
            r8=[a&b,a^b,a|b][op-4]&255
            s.r['f']=(r8&0x80)|(0x40 if r8==0 else 0)|(r8&0x28)|(0x10 if op==4 else 0)|(4 if PAR[r8] else 0)
            s.r['a']=r8
    def incdec(s,v,dec):
        f=s.r['f']; r8=(v-1 if dec else v+1)&255
        h=((r8&15)==15) if dec else ((r8&15)==0); pv=(r8==0x7F) if dec else (r8==0x80)
        s.r['f']=(f&1)|(r8&0x80)|(0x40 if r8==0 else 0)|(r8&0x28)|(0x10 if h else 0)|(4 if pv else 0)|(2 if dec else 0)
        return r8
    def cc(s,c):
        f=s.r['f']; return [not f&0x40,bool(f&0x40),not f&1,bool(f&1),not f&4,bool(f&4),not f&0x80,bool(f&0x80)][c]
    def fetch(s): v=s.rd(s.pc); s.pc=(s.pc+1)&0xFFFF; return v
    def fetch16(s): lo=s.fetch(); return lo|s.fetch()<<8
    def push(s,v): s.sp=(s.sp-2)&0xFFFF; s.wr16(s.sp,v)
    def pop(s): v=s.rd16(s.sp); s.sp=(s.sp+2)&0xFFFF; return v
    def stepx(s,pre):
        nm='ix' if pre==0xDD else 'iy'; op=s.fetch()
        if op in (0xDD,0xFD,0xED): raise ValueError('prefixo duplo')
        sd=lambda v: v-256 if v>127 else v
        memop = op in (0x34,0x35,0x36) or (0x40<=op<0xC0 and op!=0x76 and ((op&7)==6 or (op<0x80 and (op>>3&7)==6)))
        if op==0xCB:
            d=sd(s.fetch()); c2=s.fetch(); addr=(s.x[nm]+d)&0xFFFF
            sv=(s.r['h'],s.r['l']); s.spr('hl',addr); s.cbarg=c2; s.ex(0xCB); s.cbarg=None; s.r['h'],s.r['l']=sv
        elif memop:
            d=sd(s.fetch()); addr=(s.x[nm]+d)&0xFFFF
            if 0x70<=op<=0x77: s.wr(addr,s.getr(op&7))
            else:
                sv=(s.r['h'],s.r['l']); s.spr('hl',addr); s.ex(op); nh,nl=s.r['h'],s.r['l']; s.r['h'],s.r['l']=sv
                if op==0x66: s.r['h']=nh
                if op==0x6E: s.r['l']=nl
        else:
            sw = op!=0xEB
            if sw: v=s.x[nm]; s.x[nm]=(s.r['h']<<8)|s.r['l']; s.r['h'],s.r['l']=v>>8,v&255
            s.ex(op)
            if sw: v=s.x[nm]; s.x[nm]=(s.r['h']<<8)|s.r['l']; s.r['h'],s.r['l']=v>>8,v&255
    def step(s):
        op=s.fetch(); s.n+=1
        if op in (0xDD,0xFD): return s.stepx(op)
        return s.ex(op)
    def ex(s,op):
        p=['bc','de','hl','sp']
        if op==0: pass
        elif op&0xC7==6:
            d=op>>3&7; n=s.fetch(); s.setreg(d,n)
        elif 0x40<=op<0x80:
            assert op!=0x76; d=op>>3&7; r=op&7; s.setreg(d,s.getr(r))
        elif 0x80<=op<0xC0: s.alu(op>>3&7,s.getr(op&7))
        elif op&0xC7==0xC6: s.alu(op>>3&7,s.fetch())
        elif op&0xC7==4: d=op>>3&7; s.setreg(d,s.incdec(s.getr(d),0))
        elif op&0xC7==5: d=op>>3&7; s.setreg(d,s.incdec(s.getr(d),1))
        elif op&0xCF==3: n=p[op>>4&3]; s.spr(n,s.pr(n)+1)
        elif op&0xCF==0xB: n=p[op>>4&3]; s.spr(n,s.pr(n)-1)
        elif op&0xCF==1 and op!=0x31: n=p[op>>4&3]; s.spr(n,s.fetch16())
        elif op==0x31: s.sp=s.fetch16()
        elif op==0x0A: s.r['a']=s.rd(s.pr('bc'))
        elif op==0x1A: s.r['a']=s.rd(s.pr('de'))
        elif op==0x02: s.wr(s.pr('bc'),s.r['a'])
        elif op==0x12: s.wr(s.pr('de'),s.r['a'])
        elif op==0x3A: s.r['a']=s.rd(s.fetch16())
        elif op==0x32: s.wr(s.fetch16(),s.r['a'])
        elif op==0x2A: s.spr('hl',s.rd16(s.fetch16()))
        elif op==0x22: s.wr16(s.fetch16(),s.pr('hl'))
        elif op==0xF9: s.sp=s.pr('hl')
        elif op==0x2F:
            a=(~s.r['a'])&255; s.r['a']=a; s.r['f']=(s.r['f']&0xC5)|(a&0x28)|0x12
        elif op==0xC3: s.pc=s.fetch16()
        elif op==0xE9: s.pc=s.pr('hl')
        elif op&0xC7==0xC2: n=s.fetch16(); s.pc=n if s.cc(op>>3&7) else s.pc
        elif op&0xC7==0xC4:
            n=s.fetch16()
            if s.cc(op>>3&7): s.push(s.pc); s.pc=n
        elif op&0xC7==0xC0:
            if s.cc(op>>3&7): s.pc=s.pop()
        elif op==0xC9: s.pc=s.pop()
        elif op==0xCD: n=s.fetch16(); s.push(s.pc); s.pc=n
        elif op in (0x18,0x20,0x28,0x30,0x38):
            e=s.fetch(); e=e-256 if e>127 else e
            if op==0x18 or s.cc((op>>3&7)-4): s.pc=(s.pc+e)&0xFFFF
        elif op==0x10:
            e=s.fetch(); e=e-256 if e>127 else e; s.r['b']=(s.r['b']-1)&255
            if s.r['b']: s.pc=(s.pc+e)&0xFFFF
        elif op==0xD9:
            for k in 'bcdehl': s.r[k],s.sh[k]=s.sh[k],s.r[k]
        elif op==0xEB:
            d,h=s.pr('de'),s.pr('hl'); s.spr('de',h); s.spr('hl',d)
        elif op in (0xC5,0xD5,0xE5): s.push(s.pr(['bc','de','hl'][op>>4&3]))
        elif op in (0xC1,0xD1,0xE1): s.spr(['bc','de','hl'][op>>4&3],s.pop())
        elif op in (0x07,0x0F,0x17,0x1F):
            a=s.r['a']; c=s.r['f']&1
            if op==0x07: co=a>>7; a=((a<<1)|co)&255
            elif op==0x0F: co=a&1; a=(a>>1)|(co<<7)
            elif op==0x17: co=a>>7; a=((a<<1)|c)&255
            else: co=a&1; a=(a>>1)|(c<<7)
            s.r['a']=a; s.r['f']=(s.r['f']&0xC4)|(a&0x28)|co
        elif op==0x27:
            a=s.r['a']; f=s.r['f']; c=f&1; h=(f>>4)&1; n=(f>>1)&1; corr=0; cf=c
            if h or (a&15)>9: corr|=6
            if c or a>0x99: corr|=0x60; cf=1
            r8=(a-corr if n else a+corr)&255
            hf=((a&15)<6) if n and h else (((a&15)>9) if not n else 0)
            if n: hf=1 if (h and (a&15)<6) else 0
            else: hf=1 if (a&15)>9 else 0
            s.r['a']=r8; s.r['f']=(r8&0x80)|(0x40 if r8==0 else 0)|(r8&0x28)|(0x10 if hf else 0)|(4 if PAR[r8] else 0)|(n<<1)|cf
        elif op==0x37: s.r['f']=(s.r['f']&0xC4)|(s.r['a']&0x28)|1
        elif op==0x3F: f=s.r['f']; s.r['f']=(f&0xC4)|(s.r['a']&0x28)|((f&1)<<4)|((f&1)^1)
        elif op&0xCF==9:
            n=p[op>>4&3]; h=s.pr('hl'); b=s.pr(n); r=h+b; f=s.r['f']
            hf=((h&0xFFF)+(b&0xFFF))>0xFFF
            s.spr('hl',r); s.r['f']=(f&0xC4)|((r>>8)&0x28)|(0x10 if hf else 0)|(1 if r>0xFFFF else 0)
        elif op==0xF5: s.push((s.r['a']<<8)|s.r['f'])
        elif op==0xF1: v=s.pop(); s.r['a']=v>>8; s.r['f']=v&255
        elif op==0xE3: t=s.rd16(s.sp); s.wr16(s.sp,s.pr('hl')); s.spr('hl',t)
        elif op==0xED:
            o=s.fetch(); p2=['bc','de','hl','sp']; pp=p2[o>>4&3]
            if o&0xC7==0x42:
                h=s.pr('hl'); b=s.pr(pp); c=s.r['f']&1
                if not o&8:
                    r=h-b-c; hf=((h&0xFFF)-(b&0xFFF)-c)<0; pv=((h^b)&(h^r)&0x8000)!=0; n=2; cf=r<0
                else:
                    r=h+b+c; hf=((h&0xFFF)+(b&0xFFF)+c)>0xFFF; pv=((h^r)&(b^r)&0x8000)!=0; n=0; cf=r>0xFFFF
                r&=0xFFFF; s.spr('hl',r)
                s.r['f']=((r>>8)&0x80)|(0x40 if r==0 else 0)|((r>>8)&0x28)|(0x10 if hf else 0)|(4 if pv else 0)|n|(1 if cf else 0)
            elif o&0xC7==0x44:
                a=s.r['a']; r=(-a)&255; s.r['a']=r
                s.r['f']=(r&0x80)|(0x40 if r==0 else 0)|(r&0x28)|(0x10 if a&15 else 0)|(4 if a==0x80 else 0)|2|(1 if a else 0)
            elif o&0xCF==0x43: s.wr16(s.fetch16(),s.pr(pp))
            elif o&0xCF==0x4B: s.spr(pp,s.rd16(s.fetch16()))
            elif o in (0x6F,0x67):
                m=s.rd(s.pr('hl')); a=s.r['a']
                if o==0x6F: na=(a&0xF0)|(m>>4); nm=((m<<4)|(a&15))&255
                else: na=(a&0xF0)|(m&15); nm=((a&15)<<4)|(m>>4)
                s.wr(s.pr('hl'),nm); s.r['a']=na
                s.r['f']=(s.r['f']&1)|(na&0x80)|(0x40 if na==0 else 0)|(na&0x28)|(4 if PAR[na] else 0)
            else: raise ValueError('ed %02x'%o)
        elif op==0xFF: s.push(s.pc); s.pc=0x38
        elif op==0xCB:
            c2=s.fetch() if s.cbarg is None else s.cbarg; x=c2>>6; y=c2>>3&7; z=c2&7; v=s.getr(z)
            if x==0:
                c=s.r['f']&1
                if y==0: co=v>>7; r8=((v<<1)|co)&255
                elif y==1: co=v&1; r8=(v>>1)|(co<<7)
                elif y==2: co=v>>7; r8=((v<<1)|c)&255
                elif y==3: co=v&1; r8=(v>>1)|(c<<7)
                elif y==4: co=v>>7; r8=(v<<1)&255
                elif y==5: co=v&1; r8=(v>>1)|(v&0x80)
                elif y==6: co=v>>7; r8=((v<<1)|1)&255
                else: co=v&1; r8=v>>1
                s.setreg(z,r8); s.r['f']=(r8&0x80)|(0x40 if r8==0 else 0)|(r8&0x28)|(4 if PAR[r8] else 0)|co
            elif x==1:
                b=(v>>y)&1; s.r['f']=(s.r['f']&1)|0x10|(v&0x28)|(0 if b else 0x44)|((0x80) if (y==7 and b) else 0)
            elif x==2: s.setreg(z,v&~(1<<y))
            else: s.setreg(z,v|(1<<y))
        else: raise ValueError('op %02x'%op)
