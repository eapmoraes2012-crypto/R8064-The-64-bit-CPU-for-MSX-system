# generates bank.mem (512 x 1 bit): 1 = ED instruction accepts a bank prefix (BC/DE/HL/AX register operand); from ref/instr_ids.csv
import re,sys
csv=sys.argv[1]; ctrl=[int(x,16) for x in open(sys.argv[2]).read().split()]
bk=[0]*512; n=0; tot=0
tok=re.compile(r"(?<![A-Za-z])(rr|BC|DE|HL|AX|EA|QA|AL)(?![A-Za-z])")
for ln in open(csv,encoding='utf-8-sig').read().splitlines()[1:]:
    p=ln.split(';')
    if len(p)<3: continue
    i=int(p[0]); mn=p[1]; hx=p[2]
    if i==0 or not hx.startswith('ED'): continue
    tot+=1
    if re.search(r"\(Q?I[XY]\+dd\)",mn) and not re.search(r"\brr\b",mn): continue
    if tok.search(mn) and (ctrl[i]&15)<=12:
        bk[i]=1; n+=1
open('ctrl_b.mem','w').write('\n'.join('%08x'%(ctrl[i]|(bk[i]<<28)) for i in range(len(ctrl)))+'\n')
print('ED ids',tot,'bankable',n)
