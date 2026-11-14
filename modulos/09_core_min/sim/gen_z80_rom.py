# gen_z80_rom.py - microcodigo da pagina PRINCIPAL do Z80 real para o nucleo R8064 (r8064_core_min).
# Uso (na pasta sim, depois de gen_roms.py):  python3 gen_z80_rom.py
# Le uop.mem / mainctrl.mem (pagina principal de TESTE + pagina ED + cadeias de interrupcao) e grava uop_z80.mem / mainctrl_z80.mem,
# em que as 256 entradas da pagina principal passam a ser as instrucoes do Z80. A pagina ED e as cadeias 600/601 sao mantidas.
# O nucleo escolhe o arquivo pelos parametros UOP_FILE / MAINC_FILE; os testes antigos continuam usando uop.mem.
#
# Campos novos da uop (bits 80-89; ver r8064_core_min.v):
#   [80] bshr8  operando B / dado de escrita = registrador >> 8 (B, D, H)      [81] condx  condicoes estendidas (0 P, 1 tz, 2 nao-tz)
#   [85:82] fop regra de flags (1 rotacoes de A, 2 ADD HL, 3 ADC/SBC HL, 4 SCF, 5 CCF, 6 F := resultado, 7 BIT)
#   [86] tzw    tz := (resultado == 0), sem tocar nas flags (DJNZ)            [88:87] immsel 1 = vetor de RST, 2/3 = mascara de bit
#   [89] bfl    operando B = F
#   Prefixos DD/FD (o nucleo remove o prefixo e usa estas MESMAS uops, trocando o indice HL por IX/IY):
#   [90] ns     operandos D e B NAO trocam (LD H,(IX+d) usa o H de verdade)   [91] nsa    operando A nao troca (EX DE,HL)
#   [92] xd     com DD/FD o endereco soma o deslocamento d                    [93] ixs    com DD/FD o imediato vem 1 byte depois (LD (IX+d),n)
#   [94] altinv desvio de pulo (CALL cc / RET cc): o tempo alternativo do governador vale quando o desvio E tomado
#   mainctrl[4] = a instrucao tem operando (HL): com DD/FD ganha o byte d.  DD CB d op: regiao 1792 + op.
# Registradores de 8 bits: metade de um registrador de 16 (B = BC>>8 ...). Leitura do byte alto: ashr8 (lado A) / bshr8 (lado B); escrita: hb.
# Pagina CB: regiao 768 + segundo byte. Pagina ED: 256 + id (ids de instr_ids.csv); este script acrescenta os opcodes ED do Z80 que faltavam.
# PENDENTE: R nao conta buscas; ED indefinido no Z80 nao vira NOP de 2 bytes; DD/FD seguidos de outro prefixo viram NOP de 1 byte; X/Y de BIT n,(HL) e dos blocos.
import sys
POS=dict(alu=0,sz=5,use_imm=7,rd=8,wr=9,wren=10,br=11,cond=12,rel=15,fwe=16,dF=17,aF=18,bF=19,fpos=20,dI=21,aI=27,bI=33,ioff=39,isz=42,sext=44,exx=45,exaf=46,aD=47,
         hb=48,more=49,crd=77,cra=78,iord=50,iowr=51,nxt=52,immz=63,bsrc=64,bpcn=65,tabs=66,zx=67,fmode=68,tself=70,cmix=71,ashr8=72,keepc=73,misc=74,immc=79,
         bshr8=80,condx=81,fop=82,tzw=86,immsel=87,bfl=89,ns=90,nsa=91,xd=92,ixs=93,altinv=94)
def uop(**k):
    v=0
    for n,x in k.items(): v|=x<<POS[n]
    return v
ADD,ADC,SUB,SBC,AND,OR,XOR,CP,INC,DEC,NEG,CPL,SHL,SHR,SAR,ROL,ROR,RL,RR,SLL,DAA,SHL4,SHR4=range(23)
AX,BC,DE,HL,SP,TMP,ZERO=0,1,2,3,11,13,63
T2,RREG,T3=12,15,24      # temporarios internos (12 e 24) e registrador R (15: so guarda o valor escrito por LD R,A; nao conta buscas)
uops=[int(x,16) for x in open('uop.mem').read().split()]
lens=[int(x,16) for x in open('mainctrl.mem').read().split()]
assert len(uops)==2048 and len(lens)==256
for i in range(256): uops[i]=0; lens[i]=1                       # apaga a pagina principal de teste
nextfree=[max(i for i in range(2048) if uops[i])+1]            # cadeias novas depois das existentes
memo={}                                                           # caudas de cadeia iguais sao compartilhadas (a uop codificada inclui o endereco da seguinte)
def chain(op,ulist,ln=None):
    nxt=None
    for k in reversed(ulist[1:]):
        k=dict(k)
        if nxt is not None: k['more']=1; k['nxt']=nxt
        v=uop(**k)
        if v not in memo:
            assert nextfree[0]<1792,'ROM de uops cheia (cadeias ate 1791)'
            memo[v]=nextfree[0]; uops[nextfree[0]]=v; nextfree[0]+=1
        nxt=memo[v]
    k=dict(ulist[0])
    if nxt is not None: k['more']=1; k['nxt']=nxt
    uops[op]=uop(**k)
    if ln is not None: lens[op]=ln
R8={0:(BC,1),1:(BC,0),2:(DE,1),3:(DE,0),4:(HL,1),5:(HL,0),7:(AX,0)}     # codigo r -> (registrador, byte alto)
RP=[BC,DE,HL,SP]
ALUOP=[ADD,ADC,SUB,SBC,AND,XOR,OR,CP]
def srcA(r): i,h=R8[r]; return dict(aI=i,ashr8=h)
def srcB(r): i,h=R8[r]; return dict(bI=i,bshr8=h)
def dst(r):  i,h=R8[r]; return dict(wren=1,dI=i,hb=h,sz=0)
MOV=dict(alu=ADD,use_imm=1,immz=1)                               # resultado = operando A
LDTMP=dict(rd=1,wren=1,dI=TMP,aI=HL,immz=1,sz=0,zx=1,xd=1)          # TMP := (HL)
STTMP=dict(wr=1,aI=HL,immz=1,bI=TMP,sz=0,xd=1)                     # (HL) := TMP
SPADD2=dict(alu=SUB,use_imm=1,immc=1,isz=1,wren=1,dI=SP,aI=SP,sz=1)   # SP := SP - (-2)
SPSUB2=dict(alu=ADD,use_imm=1,immc=1,isz=1,wren=1,dI=SP,aI=SP,sz=1)   # SP := SP + (-2)
PUSHPC=dict(wr=1,aI=SP,immc=1,isz=1,bpcn=1,sz=1)                 # [SP-2] := PC seguinte (antes de mexer em SP: reiniciavel)
JPNN=dict(br=1,cond=0,tabs=1,aI=ZERO,ioff=1,isz=1)
RETSEQ=[dict(rd=1,wren=1,dI=TMP,aI=SP,immz=1,sz=1,zx=1),SPADD2,dict(br=1,cond=0,aI=TMP,immz=1)]
# condicoes do Z80 (y): NZ Z NC C PO PE P M -> campos da uop; INV = condicao contraria (pula CALL cc / RET cc quando falsa)
CC =[dict(cond=2),dict(cond=1),dict(cond=4),dict(cond=3),dict(cond=6),dict(cond=5),dict(cond=0,condx=1),dict(cond=7)]
INV=[dict(cond=1),dict(cond=2),dict(cond=3),dict(cond=4),dict(cond=5),dict(cond=6),dict(cond=7),dict(cond=0,condx=1)]
SKIP=lambda y: dict(br=1,rel=1,immz=1,altinv=1,**INV[y])                 # desvia para a instrucao seguinte

for op in range(256):
    x,y,z=op>>6,(op>>3)&7,op&7; p,q=y>>1,y&1
    if x==0:
        if z==0:
            if y==0: chain(op,[dict()],1)                                                             # NOP
            elif y==1: chain(op,[dict(exaf=1)],1)                                                     # EX AF,AF'
            elif y==2: chain(op,[dict(alu=DEC,wren=1,dI=BC,aD=1,ashr8=1,hb=1,sz=0,tzw=1),            # DJNZ: B := B-1 sem flags
                                 dict(br=1,cond=2,condx=1,rel=1,ioff=1,sext=1)],2)
            elif y==3: chain(op,[dict(br=1,cond=0,rel=1,ioff=1,sext=1)],2)                            # JR d
            else:      chain(op,[dict(br=1,rel=1,ioff=1,sext=1,**CC[y-4])],2)                         # JR cc,d
        elif z==1:
            if q==0: chain(op,[dict(alu=ADD,use_imm=1,wren=1,dI=RP[p],aI=ZERO,ioff=1,isz=1,sz=1)],3)  # LD rr,nn
            else:    chain(op,[dict(alu=ADD,wren=1,dI=HL,aI=HL,bI=RP[p],sz=1,fwe=1,fop=2)],1)         # ADD HL,rr
        elif z==2:
            if   y==0: chain(op,[dict(wr=1,aI=BC,immz=1,bI=AX,sz=0)],1)                               # LD (BC),A
            elif y==1: chain(op,[dict(rd=1,wren=1,dI=AX,aI=BC,immz=1,sz=0)],1)                        # LD A,(BC)
            elif y==2: chain(op,[dict(wr=1,aI=DE,immz=1,bI=AX,sz=0)],1)                               # LD (DE),A
            elif y==3: chain(op,[dict(rd=1,wren=1,dI=AX,aI=DE,immz=1,sz=0)],1)                        # LD A,(DE)
            elif y==4: chain(op,[dict(wr=1,aI=ZERO,ioff=1,isz=1,bI=HL,sz=1)],3)                       # LD (nn),HL
            elif y==5: chain(op,[dict(rd=1,wren=1,dI=HL,aI=ZERO,ioff=1,isz=1,sz=1)],3)                # LD HL,(nn)
            elif y==6: chain(op,[dict(wr=1,aI=ZERO,ioff=1,isz=1,bI=AX,sz=0)],3)                       # LD (nn),A
            else:      chain(op,[dict(rd=1,wren=1,dI=AX,aI=ZERO,ioff=1,isz=1,sz=0)],3)                # LD A,(nn)
        elif z==3: chain(op,[dict(alu=DEC if q else INC,wren=1,dI=RP[p],aD=1,sz=1)],1)               # INC/DEC rr (sem flags)
        elif z in (4,5):
            a=INC if z==4 else DEC
            if y==6: chain(op,[LDTMP,dict(alu=a,wren=1,dI=TMP,aD=1,sz=0,fwe=1),STTMP],1)              # INC/DEC (HL)
            else:    chain(op,[dict(alu=a,aD=1,ashr8=R8[y][1],fwe=1,**dst(y))],1)                     # INC/DEC r
        elif z==6:
            if y==6: chain(op,[dict(alu=ADD,use_imm=1,wren=1,dI=TMP,aI=ZERO,ioff=1,isz=0,sz=0,zx=1,ixs=1),STTMP],2)   # LD (HL),n
            else:    chain(op,[dict(alu=ADD,use_imm=1,aI=ZERO,ioff=1,isz=0,**dst(y))],2)              # LD r,n
        else:
            if y<4: chain(op,[dict(alu=[ROL,ROR,RL,RR][y],wren=1,dI=AX,aD=1,sz=0,fwe=1,fop=1)],1)     # RLCA RRCA RLA RRA
            elif y==4: chain(op,[dict(alu=DAA,wren=1,dI=AX,aD=1,sz=0,fwe=1)],1)                       # DAA
            elif y==5: chain(op,[dict(alu=CPL,wren=1,dI=AX,aD=1,sz=0,fwe=1)],1)                       # CPL
            elif y==6: chain(op,[dict(aI=AX,sz=0,fwe=1,fop=4,**MOV)],1)                               # SCF
            else:      chain(op,[dict(aI=AX,sz=0,fwe=1,fop=5,**MOV)],1)                               # CCF
    elif x==1:
        if op==0x76: chain(op,[dict(br=1,cond=0,tself=1,aI=ZERO)],1)                                  # HALT: repete a si mesma ate a interrupcao
        elif z==6:   chain(op,[dict(rd=1,aI=HL,immz=1,xd=1,ns=1,**dst(y))],1)                                   # LD r,(HL)
        elif y==6:   chain(op,[dict(wr=1,aI=HL,immz=1,sz=0,xd=1,ns=1,**srcB(z))],1)                             # LD (HL),r
        else:        chain(op,[dict(**MOV,**srcA(z),**dst(y))],1)                                     # LD r,r'
    elif x==2:
        a=ALUOP[y]; w=dict(wren=1,dI=AX) if a!=CP else dict()
        if z==6: chain(op,[LDTMP,dict(alu=a,aI=AX,bI=TMP,sz=0,fwe=1,**w)],1)                          # ALU A,(HL)
        else:    chain(op,[dict(alu=a,aI=AX,sz=0,fwe=1,**w,**srcB(z))],1)                             # ALU A,r
    else:
        if z==0: chain(op,[SKIP(y)]+RETSEQ,1)                                                         # RET cc
        elif z==1:
            if q==0:
                if p<3: chain(op,[dict(rd=1,wren=1,dI=RP[p],aI=SP,immz=1,sz=1),SPADD2],1)             # POP rr
                else:   chain(op,[dict(rd=1,wren=1,dI=TMP,aI=SP,immz=1,sz=1,zx=1),                   # POP AF
                                  dict(aI=TMP,ashr8=1,wren=1,dI=AX,sz=0,**MOV),
                                  dict(aI=TMP,sz=0,fwe=1,fop=6,**MOV),SPADD2],1)
            elif p==0: chain(op,RETSEQ,1)                                                             # RET
            elif p==1: chain(op,[dict(exx=1)],1)                                                      # EXX
            elif p==2: chain(op,[dict(br=1,cond=0,aI=HL,immz=1)],1)                                   # JP (HL)
            else:      chain(op,[dict(aI=HL,wren=1,dI=SP,sz=1,**MOV)],1)                              # LD SP,HL
        elif z==2: chain(op,[dict(br=1,tabs=1,aI=ZERO,ioff=1,isz=1,**CC[y])],3)                       # JP cc,nn
        elif z==3:
            if   y==0: chain(op,[JPNN],3)                                                             # JP nn
            elif y==1: chain(op,[dict()],2)                                                           # prefixo CB: comprimento 2; a uop vem da regiao 768+
            elif y==2: chain(op,[dict(iowr=1,aI=ZERO,ioff=1,bI=AX)],2)                                # OUT (n),A
            elif y==3: chain(op,[dict(iord=1,wren=1,dI=AX,aI=ZERO,ioff=1,sz=0)],2)                    # IN A,(n)
            elif y==4: chain(op,[dict(rd=1,wren=1,dI=TMP,aI=SP,immz=1,sz=1,zx=1),                    # EX (SP),HL
                                 dict(wr=1,aI=SP,immz=1,bI=HL,sz=1),dict(aI=TMP,wren=1,dI=HL,sz=1,**MOV)],1)
            elif y==5: chain(op,[dict(aI=DE,wren=1,dI=TMP,sz=1,zx=1,**MOV),                          # EX DE,HL
                                 dict(aI=HL,nsa=1,wren=1,dI=DE,sz=1,**MOV),dict(aI=TMP,wren=1,dI=HL,ns=1,sz=1,**MOV)],1)
            elif y==6: chain(op,[dict(misc=2)],1)                                                     # DI
            else:      chain(op,[dict(misc=1)],1)                                                     # EI
        elif z==4: chain(op,[SKIP(y),PUSHPC,SPSUB2,JPNN],3)                                           # CALL cc,nn
        elif z==5:
            if q==0:
                if p<3: chain(op,[dict(wr=1,aI=SP,immc=1,isz=1,bI=RP[p],sz=1),SPSUB2],1)              # PUSH rr
                else:   chain(op,[dict(alu=ADD,aI=ZERO,bfl=1,wren=1,dI=TMP,sz=3),                     # PUSH AF: TMP = {A, F}
                                  dict(aI=AX,wren=1,dI=TMP,hb=1,sz=0,**MOV),
                                  dict(wr=1,aI=SP,immc=1,isz=1,bI=TMP,sz=1),SPSUB2],1)
            elif p==0: chain(op,[PUSHPC,SPSUB2,JPNN],3)                                               # CALL nn
            else:      chain(op,[dict()],1)                                                           # prefixos DD / ED / FD (ED e tratado pelo decodificador)
        elif z==6:
            a=ALUOP[y]; w=dict(wren=1,dI=AX) if a!=CP else dict()
            chain(op,[dict(alu=a,use_imm=1,ioff=1,isz=0,aI=AX,sz=0,fwe=1,**w)],2)                     # ALU A,n
        else: chain(op,[PUSHPC,SPSUB2,dict(br=1,cond=0,tabs=1,aI=ZERO,immsel=1,ioff=0)],1)            # RST n
for op in range(256):                                              # mainctrl[4]: operando (HL) -> byte d com DD/FD
    x,y,z=op>>6,(op>>3)&7,op&7
    if op in (0x34,0x35,0x36,0xCB) or (x==1 and op!=0x76 and (y==6 or z==6)) or (x==2 and z==6): lens[op]|=16
# ---------------- pagina CB (768 + opcode) e DD CB d op / FD CB d op (1792 + opcode) ----------------
ROT=[ROL,ROR,RL,RR,SHL,SAR,SLL,SHR]                               # RLC RRC RL RR SLA SRA SLL SRL
for op in range(256):
    x,y,z=op>>6,(op>>3)&7,op&7; base=768+op
    if x==0:   core=dict(alu=ROT[y],fwe=1)
    elif x==1: core=dict(alu=AND,use_imm=1,immsel=2,ioff=1,fwe=1,fop=7)        # BIT: so flags
    elif x==2: core=dict(alu=AND,use_imm=1,immsel=3,ioff=1)                    # RES
    else:      core=dict(alu=OR,use_imm=1,immsel=2,ioff=1)                     # SET
    # DD CB d op: sempre sobre (IX+d); o opcode e o 4o byte (mascara de bit em ioff=2); fora BIT, o resultado tambem vai para o registrador z (se z != 6)
    xcore=dict(core); 
    if 'ioff' in xcore: xcore['ioff']=2
    if x==1: chain(1792+op,[LDTMP,dict(aI=TMP,sz=0,**xcore)])
    else:    chain(1792+op,[LDTMP,dict(wren=1,dI=TMP,aD=1,sz=0,**xcore),STTMP]+([dict(aI=TMP,ns=1,**MOV,**dst(z))] if z!=6 else []))
    if z==6:
        if x==1: chain(base,[LDTMP,dict(aI=TMP,sz=0,**core)])
        else:    chain(base,[LDTMP,dict(wren=1,dI=TMP,aD=1,sz=0,**core),STTMP])
    else:
        if x==1: chain(base,[dict(sz=0,**srcA(z),**core)])
        else:    chain(base,[dict(aD=1,ashr8=R8[z][1],**dst(z),**core)])
# ---------------- pagina ED: opcodes do Z80 que faltavam ----------------
edid={}
for ln in open('instr_ids.csv',encoding='utf-8-sig').read().splitlines()[1:]:
    p=ln.split(';')
    if len(p)>=3 and p[2].startswith('ED ') and len(p[2])>=5 and int(p[0])>=200: edid[int(p[2][3:5],16)]=int(p[0])
def ed(b2,ulist): chain(256+edid[b2],ulist)
for p in range(4):
    ed(0x42+16*p,[dict(alu=SBC,wren=1,dI=HL,aI=HL,bI=RP[p],sz=1,fwe=1,fop=3)])                 # SBC HL,rr
    ed(0x4A+16*p,[dict(alu=ADC,wren=1,dI=HL,aI=HL,bI=RP[p],sz=1,fwe=1,fop=3)])                 # ADC HL,rr
    ed(0x43+16*p,[dict(wr=1,aI=ZERO,ioff=2,isz=1,bI=RP[p],sz=1)])                              # LD (nn),rr
    ed(0x4B+16*p,[dict(rd=1,wren=1,dI=RP[p],aI=ZERO,ioff=2,isz=1,sz=1)])                       # LD rr,(nn)
for b2 in range(0x44,0x80,8): ed(b2,[dict(alu=NEG,wren=1,dI=AX,aD=1,sz=0,fwe=1)])              # NEG (e espelhos)
ed(0x4F,[dict(aI=AX,wren=1,dI=RREG,sz=0,zx=1,**MOV)])                                          # LD R,A
ed(0x5F,[dict(aI=RREG,wren=1,dI=AX,sz=0,**MOV),dict(alu=OR,use_imm=1,immz=1,aI=RREG,sz=0,fwe=1,keepc=1,misc=7)])   # LD A,R (flags como LD A,I)
OLD=dict(wren=1,sz=0,zx=1)
nib=lambda d,a,op: dict(alu=op,use_imm=1,immz=1,dI=d,aI=a,**OLD)
fin=dict(alu=OR,aI=T2,bI=TMP,wren=1,dI=AX,sz=0,fwe=1,keepc=1)                                  # A := T2 | TMP ; S,Z,P de A, H=N=0, C mantido
ed(0x6F,[LDTMP,nib(T2,AX,SHL4),nib(T2,T2,SHR4),nib(T3,TMP,SHL4),dict(alu=OR,aI=T3,bI=T2,dI=T3,**OLD),   # RLD: (HL) = m<<4 | A&0F ; A = A&F0 | m>>4
         dict(wr=1,aI=HL,immz=1,bI=T3,sz=0),nib(TMP,TMP,SHR4),nib(T2,AX,SHR4),nib(T2,T2,SHL4),fin])
ed(0x67,[LDTMP,nib(T2,AX,SHL4),nib(T3,TMP,SHR4),dict(alu=OR,aI=T3,bI=T2,dI=T3,**OLD),                    # RRD: (HL) = A<<4 | m>>4 ; A = A&F0 | m&0F
         dict(wr=1,aI=HL,immz=1,bI=T3,sz=0),nib(TMP,TMP,SHL4),nib(TMP,TMP,SHR4),nib(T2,AX,SHR4),nib(T2,T2,SHL4),fin])
open('uop_z80.mem','w').write('\n'.join('%024x'%u for u in uops)+'\n')
open('mainctrl_z80.mem','w').write('\n'.join('%08x'%l for l in lens)+'\n')
print('uop_z80.mem: %d entradas usadas de 2048 (cadeias ate %d)'%(sum(1 for u in uops if u),nextfree[0]-1))
