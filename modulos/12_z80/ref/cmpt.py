import re,sys
# usage: python3 cmpt.py <R8064_Z80_instrucoes_fpga.txt>   (the instruction table is NOT in this repository; run in the tdump.txt folder)
if len(sys.argv)<2: sys.exit('uso: python3 cmpt.py <R8064_Z80_instrucoes_fpga.txt>')
pages={}; cur=None
for ln in open(sys.argv[1],encoding='latin-1'):
    m=re.match(r'^\[(Z80_\w+)\]',ln)
    if m: cur=m.group(1); pages[cur]={}; continue
    if ln.startswith('['): cur=None; continue
    if cur and ln.strip() and not ln.startswith('#'):
        f=ln.rstrip('\n').split('|')
        if len(f)<8: continue
        tk=f[0].split()
        op=tk[-1] if cur in('Z80_DDCB','Z80_FDCB') else (tk[0] if cur=='Z80_00' else tk[1])
        try: T=int(f[5]); TA=int(f[6]) if f[6].strip() else T
        except: continue
        pages[cur][op.upper()]=(T,TA,f[2])
nm={'00':'Z80_00','CB':'Z80_CB','ED':'Z80_ED','DD':'Z80_DD','FD':'Z80_FD','DDCB':'Z80_DDCB','FDCB':'Z80_FDCB'}
tot=0;bad=[];miss=[]
for ln in open('tdump.txt'):
    p,op,tmax,tmin=ln.split(); tmax=int(tmax);tmin=int(tmin)
    e=pages[nm[p]].get(op)
    if not e: miss.append((p,op,tmax)); continue
    tot+=1
    if (max(e[0],e[1]),min(e[0],e[1]))!=(tmax,tmin): bad.append((p,op,e,(tmax,tmin)))
print('compared',tot,'without a table entry (non-op ED/DD/FD opcodes)',len(miss),'divergences',len(bad))
for b in bad: print(b)
