# gera gov_rom.mem (2048 x 32): tabela de tempo por (pagina, opcode) para o governador de tempo do R8064
# uso: python3 gen_gov_rom.py <ref/z80_classico_tstates.csv>   (grava gov_rom.mem na pasta atual)
# indice = pagina*256 + opcode ; pagina: 0 principal, 1 CB, 2 ED, 3 DD, 4 FD, 5 DDCB, 6 FDCB, 7 aceitacao de interrupcao
# palavra: [5:0] Z80 T-states | [11:6] Z80 T alt | [17:12] R800 ciclos (total DRAM) | [23:18] R800 alt | [24] 2 ciclos M1 | [25] E/S
import re,sys,csv
from r800cls import classify
src=sys.argv[1]
PG={'00':0,'CB':1,'ED':2,'DD':3,'FD':4,'DDCB':5,'FDCB':6}
MUL={0xC1:'MULUB',0xC9:'MULUB',0xD1:'MULUB',0xD9:'MULUB',0xE1:'MULUB',0xE9:'MULUB',0xF9:'MULUB',0xC3:'MULUW',0xF3:'MULUW'}
rows=list(csv.reader(open(src,encoding='utf-8-sig'),delimiter=';'))[1:]
tab={}; miss=[]
def parse(base,tot):
    t=[x for x in tot.split('/')]; tn=[x for x in t if x!='?']
    tt=int(tn[0]); ta=int(t[-1]) if len(t)>1 and t[-1]!='?' else 0
    return tt,ta
for pg,opc,mn,doc,ts,alt,nb in rows:
    p=PG[pg]; tk=opc.split(); o=int(tk[0] if p==0 else (tk[-1] if p>=5 else tk[1]),16)
    z=int(ts); za=int(alt) if alt else 0
    m1=0 if p==0 else 1
    if p==2 and o in MUL:
        rt,ra=(14,0) if MUL[o]=='MULUB' else (36,0)
    else:
        c=classify(mn)
        if c is None: miss.append((pg,opc,mn)); rt,ra=2,0
        else:
            rt,ra=parse(*c)
            if '?' in c[1] and ra==0: ra=0
    if p==5 and 0: pass
    io=1 if re.match(r'^(IN|OUT|INI|IND|OUTI|OUTD|INIR|INDR|OTIR|OTDR)\b',mn) else 0
    tab[(p,o)]=(z,za,rt,ra,m1,io)
# entradas ausentes
rom=[0]*(7*256)
for p in range(7):
    for o in range(256):
        if (p,o) in tab: z,za,rt,ra,m1,io=tab[(p,o)]
        elif p in (3,4):   # DD/FD sem IX/IY: prefixo (4 T / 1 ciclo R800) + instrucao da pagina principal
            z,za,rt,ra,m1,io=tab[(0,o)] if (0,o) in tab else (4,0,1,0,0,0)
            z+=4; za=za+4 if za else 0; rt+=1; ra=ra+1 if ra else 0; m1=1
        elif p==2: z,za,rt,ra,m1,io=8,0,(14 if MUL.get(o)=='MULUB' else 36 if MUL.get(o)=='MULUW' else 2),0,1,0   # ED indefinido = NOP de 2 bytes (R800: MULUB/MULUW)
        elif p==0: z,za,rt,ra,m1,io=4,0,1,0,0,0     # (nao deve ocorrer)
        else: z,za,rt,ra,m1,io=8,0,2,0,1,0
        assert z<64 and za<64 and rt<64 and ra<64,(p,o,z,za,rt,ra)
        rom[p*256+o]=z|za<<6|rt<<12|ra<<18|m1<<24|io<<25
# pagina 7 (aceitacao de interrupcao; antes acrescentada a parte por gov_irq_page.py): Z80 = 13 T (INTA com 2 waits automaticos; o M1_WAIT
# do MSX soma +1 no governador), R800 = tempo do RST 38h (a confirmar). As 256 entradas sao iguais (o nucleo usa op 0).
rst=rom[0*256+0xFF]
e=13 | 0<<6 | (rst>>12&63)<<12 | (rst>>12&63)<<18 | 0<<24
rom+=[e]*256
assert len(rom)==2048
open('gov_rom.mem','w').write('\n'.join('%08x'%w for w in rom)+'\n')
print('entradas',len(tab),'sem classe R800:',len(miss),miss[:5])
