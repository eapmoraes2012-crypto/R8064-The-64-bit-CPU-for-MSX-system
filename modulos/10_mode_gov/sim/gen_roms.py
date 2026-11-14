# gera uop.mem (2048 x 80 bits), mainctrl.mem (256 x 32) e prog*.mem para o nucleo minimo
# ATENCAO: a pagina principal daqui e uma codificacao de TESTE (LDI, ADD de 3 operandos, LD, ST, ADDI, JR, JRNZ + alguns opcodes reais do Z80).
# O microcodigo do Z80 de verdade e gerado por gen_z80_rom.py (uop_z80.mem / mainctrl_z80.mem, uops de 96 bits), a partir da saida deste script.
# formato do uop (80 bits): [4:0] alu [6:5] sz(0..3 = 8/16/32/64) [7] use_imm [8] rd [9] wr [10] wren [11] br [14:12] cond [15] rel [16] fwe
#   [17] dF [18] aF [19] bF [20] fpos [26:21] dI [32:27] aI [38:33] bI [41:39] ioff [43:42] isz [44] sext [45] exx [46] exaf [47] aD
#   [48] hb (escreve byte alto) [49] more [50] io_rd [51] io_wr [62:52] nxt [63] immz [64] bsrc [65] bpcn [66] tabs [67] zx [69:68] fmode (flags de bloco) [70] tself (alvo = PC da propria instrucao) [71] cmix (cond = PV e nao-Z) [72] ashr8 (operando A = A>>8, para B) [79] immc (imediato constante = -(1<<isz): -1,-2,-4,-8; usado por PUSH/CALL para endereçar [SP-n] ANTES de alterar SP)
import sys
F=dict(alu=0,sz=3,use_imm=0,rd=0,wr=0,wren=0,br=0,cond=0,rel=0,fwe=0,dF=0,aF=0,bF=0,fpos=0,dI=0,aI=0,bI=0,ioff=0,isz=0,sext=0,exx=0,exaf=0,aD=0,
       hb=0,more=0,crd=0,cra=0,iord=0,iowr=0,nxt=0,immz=0,bsrc=0,bpcn=0,tabs=0,zx=0,fmode=0,tself=0,cmix=0,ashr8=0,keepc=0,misc=0,immc=0)
POS=dict(alu=0,sz=5,use_imm=7,rd=8,wr=9,wren=10,br=11,cond=12,rel=15,fwe=16,dF=17,aF=18,bF=19,fpos=20,dI=21,aI=27,bI=33,ioff=39,isz=42,sext=44,exx=45,exaf=46,aD=47,
         hb=48,more=49,crd=77,cra=78,iord=50,iowr=51,nxt=52,immz=63,bsrc=64,bpcn=65,tabs=66,zx=67,fmode=68,tself=70,cmix=71,ashr8=72,keepc=73,misc=74,immc=79)
def uop(**k):
    d=dict(F); d.update(k); v=0
    for n,x in d.items(): v|=x<<POS[n]
    return v
ALU=dict(ADD=0,SUB=2,INC=8,DEC=9)
SP=11; TMP=13   # indices do banco: 11 = QSP, 12 = QPC (reservado), 13 = temporario
uops=[0]*2048; lens=[1]*256; chain_next=[1024]
def put(addr,u): uops[addr]=u
def chain(base,ulist):
    # ulist: lista de dicts; o primeiro vai em 'base', os demais em 1024+ (ligados por nxt)
    addrs=[base]+[chain_next[0]+i for i in range(len(ulist)-1)]
    chain_next[0]+=len(ulist)-1
    for i,k in enumerate(ulist):
        k=dict(k)
        if i<len(ulist)-1: k['more']=1; k['nxt']=addrs[i+1]
        put(addrs[i],uop(**k))
for b in range(256):
    c=b>>6; lo=b&7
    if c==0: uops[b]=uop(use_imm=1,wren=1,dF=1,aI=63,ioff=1,sext=1); lens[b]=2
    elif c==1: uops[b]=uop(wren=1,fwe=1,dF=1,aF=1,bF=1); lens[b]=2
    elif c==2: uops[b]=uop(rd=1,wren=1,dF=1,aF=1,ioff=1,sext=1); lens[b]=2
    else:
        if lo==0: uops[b]=uop(wr=1,aF=1,bF=1,ioff=2,sext=1); lens[b]=3
        elif lo==1: uops[b]=uop(br=1,cond=0,rel=1,ioff=1,sext=1); lens[b]=2
        elif lo==2: uops[b]=uop(br=1,cond=2,rel=1,ioff=1,sext=1); lens[b]=2
        elif lo==3: uops[b]=uop(use_imm=1,wren=1,fwe=1,dF=1,fpos=1,aD=1,ioff=1,sext=1); lens[b]=2
# ---- instrucoes Z80 de verdade implementadas com sequencias de uops ----
put(0x18,uop(br=1,cond=0,rel=1,ioff=1,sext=1)); lens[0x18]=2                                  # JR e
put(0x31,uop(use_imm=1,wren=1,dI=SP,aI=63,ioff=1,isz=1,sz=3,zx=1)); lens[0x31]=3               # LD SP,nn (zero-estende)
# PUSH/CALL REINICIAVEIS: a gravacao em [SP-n] vem ANTES da atualizacao de SP (imediato constante immc = -n), entao uma falta no acesso deixa SP intacto e a instrucao
# pode ser reexecutada inteira (EPC = PC da instrucao). Antes: DEC SP, DEC SP, store (a falta deixava SP ja decrementado).
SPDEC=lambda: dict(alu=ALU['ADD'],use_imm=1,immc=1,isz=1,wren=1,dI=SP,aI=SP,sz=3)                  # SP := SP - 2
for op in (0xC5,0xD5,0xE5):                                                                     # PUSH rr (BC, DE, HL)
    chain(op,[dict(wr=1,aI=SP,immc=1,isz=1,bF=1,bsrc=1,sz=1),SPDEC()]); lens[op]=1
for op in (0xC1,0xD1,0xE1):                                                                     # POP rr
    chain(op,[dict(rd=1,wren=1,dF=1,fpos=1,aI=SP,immz=1,sz=1),dict(alu=ALU['INC'],wren=1,dI=SP,aI=SP,aD=1,sz=3),dict(alu=ALU['INC'],wren=1,dI=SP,aI=SP,aD=1,sz=3)]); lens[op]=1
chain(0xCD,[dict(wr=1,aI=SP,immc=1,isz=1,bpcn=1,sz=1),SPDEC(),dict(br=1,cond=0,aI=63,tabs=1,ioff=1,isz=1)]); lens[0xCD]=3   # CALL nn (store em [SP-2], depois SP, depois salto)
chain(0xC9,[dict(rd=1,wren=1,dI=TMP,aI=SP,immz=1,sz=1,zx=1),dict(alu=ALU['INC'],wren=1,dI=SP,aI=SP,aD=1,sz=3),dict(alu=ALU['INC'],wren=1,dI=SP,aI=SP,aD=1,sz=3),
            dict(br=1,cond=0,aI=TMP,immz=1)]); lens[0xC9]=1                                      # RET
put(0xD3,uop(iowr=1,aI=63,ioff=1,bI=0)); lens[0xD3]=2                                          # OUT (n),A
put(0xDB,uop(iord=1,wren=1,dI=0,aI=63,ioff=1,sz=0)); lens[0xDB]=2                              # IN A,(n)

# ---- instrucoes de bloco do Z80 (ED A0..BB): indice 256+id, ids 275..290 ----
HL,DE,BC,AX=3,2,1,0
def blk(eid,kind,dirn,rep):
    inc=ALU['INC'] if dirn=='i' else ALU['DEC']
    ld=dict(rd=1,wren=1,dI=TMP,aI=HL,immz=1,sz=0,zx=1)
    st=dict(wr=1,aI=DE,immz=1,bI=TMP,sz=0)
    stH=dict(wr=1,aI=HL,immz=1,bI=TMP,sz=0)
    adj=lambda r: dict(alu=inc,wren=1,dI=r,aI=r,aD=1,sz=1)
    decb=dict(alu=ALU['DEC'],wren=1,dI=BC,aI=BC,aD=1,sz=0,hb=1,ashr8=1,fwe=1)
    if kind=='ld':   seq=[ld,st,adj(HL),adj(DE),dict(alu=ALU['DEC'],wren=1,dI=BC,aI=BC,aD=1,sz=1,fwe=1,fmode=3)]; br=dict(br=1,cond=5,tself=1,aI=63)
    elif kind=='cp': seq=[ld,dict(alu=7,aI=AX,bI=TMP,sz=0,fwe=1,fmode=2),adj(HL),dict(alu=ALU['DEC'],wren=1,dI=BC,aI=BC,aD=1,sz=1,fwe=1,fmode=1)]; br=dict(br=1,cmix=1,tself=1,aI=63)
    elif kind=='in': seq=[dict(iord=1,wren=1,dI=TMP,aI=BC,immz=1,sz=0,zx=1),stH,adj(HL),decb]; br=dict(br=1,cond=2,tself=1,aI=63)
    else:            seq=[ld if False else dict(rd=1,wren=1,dI=TMP,aI=HL,immz=1,sz=0,zx=1),decb,adj(HL),dict(iowr=1,aI=BC,immz=1,bI=TMP)]; br=dict(br=1,cond=2,tself=1,aI=63)
    if rep: seq=seq+[br]
    chain(256+eid,seq)
ids=[(275,'ld','i',0),(276,'cp','i',0),(277,'in','i',0),(278,'out','i',0),(279,'ld','d',0),(280,'cp','d',0),(281,'in','d',0),(282,'out','d',0),
     (283,'ld','i',1),(284,'cp','i',1),(285,'in','i',1),(286,'out','i',1),(287,'ld','d',1),(288,'cp','d',1),(289,'in','d',1),(290,'out','d',1)]
for e,k,d,r in ids: blk(e,k,d,r)
# ED (indice 256+id): toy de LDW rr,nn e LDQ rr,imm64 (prefixos de banco)
uops[256+76]=uop(use_imm=1,wren=1,dF=1,aI=63,sz=1,ioff=3,isz=1,fpos=1)
uops[256+100]=uop(use_imm=1,wren=1,dF=1,aI=63,sz=3,ioff=3,isz=3,fpos=1)

chain(256+259,[dict(iord=1,wren=1,dI=TMP,aI=BC,immz=1,sz=0,zx=1),dict(alu=5,use_imm=1,immz=1,aI=TMP,sz=0,fwe=1,keepc=1)])   # IN F,(C): so flags
chain(256+260,[dict(iowr=1,aI=BC,immz=1,bI=63)])                                                                                   # OUT (C),0
# ---- IN r,(C) / OUT (C),r (ED 40..79): dado; flags de IN r,(C) ainda nao implementadas ----
REGS={'B':(1,1,211),'C':(1,0,219),'D':(2,1,227),'E':(2,0,235),'H':(3,1,243),'L':(3,0,251),'A':(0,0,267)}
for n,(rg,hi,eid) in REGS.items():
    chain(256+eid,[dict(iord=1,wren=1,dI=rg,aI=BC,immz=1,sz=0,hb=hi),dict(alu=5,use_imm=1,immz=1,aI=rg,ashr8=hi,sz=0,fwe=1,keepc=1)])
    if hi: chain(256+eid+1,[dict(alu=ALU['ADD'],use_imm=1,immz=1,wren=1,dI=TMP,aI=rg,ashr8=1,sz=0,zx=1),dict(iowr=1,aI=BC,immz=1,bI=TMP)])
    else:  chain(256+eid+1,[dict(iowr=1,aI=BC,immz=1,bI=rg)])

# ---- interrupcoes: EI/DI, IM 0/1/2, RETI/RETN, LD I,A / LD A,I, entrada de interrupcao (cadeias 600/601) ----
put(0xFB,uop(misc=1)); lens[0xFB]=1
put(0xF3,uop(misc=2)); lens[0xF3]=1
for eid,m in ((217,0),(225,0),(249,0),(257,0),(233,1),(265,1),(241,2),(273,2)): put(256+eid,uop(misc=4+m))
for eid in (216,224,232,240,248,256,264,272):
    chain(256+eid,[dict(rd=1,wren=1,dI=TMP,aI=SP,immz=1,sz=1,zx=1),dict(alu=ALU['INC'],wren=1,dI=SP,aI=SP,aD=1,sz=3),dict(alu=ALU['INC'],wren=1,dI=SP,aI=SP,aD=1,sz=3),
                   dict(br=1,cond=0,aI=TMP,immz=1,misc=3)])
put(256+218,uop(alu=ALU['ADD'],use_imm=1,immz=1,wren=1,dI=14,aI=0,sz=0,zx=1))     # LD I,A
chain(256+234,[dict(alu=ALU['ADD'],use_imm=1,immz=1,wren=1,dI=0,aI=14,sz=0),dict(alu=5,use_imm=1,immz=1,aI=14,sz=0,fwe=1,keepc=1,misc=7)])   # LD A,I: dado + flags (S,Z de I; H=N=0; PV=IFF2; C mantido)

# ---- grupo EXX: EXX (D9), EX AF,AF' (08) e EXINI (ED 09, id 291: desfaz EXX e EX AF,AF') ----
put(0xD9,uop(exx=1)); lens[0xD9]=1
put(0x08,uop(exaf=1)); lens[0x08]=1
put(256+291,uop(exx=1,exaf=1))     # EXINI: sw_main <= 0 (grupo principal ativo, como apos o reset)
# ---- MFCR (ED 0A n: AX <- CR[n]) e MTCR (ED 0C n: CR[n] <- AX); CR n = indice 32+n do banco: 8 tcmp, 9 vec, 10 ie, 11 causa, 12 endereco, 13 EPC, 14 MMU, 15 raiz, 16 TLB-VA, 17 controle ----
put(256+292,uop(alu=ALU['ADD'],use_imm=1,immz=1,wren=1,dI=0,cra=1,sz=3))
put(256+293,uop(alu=ALU['ADD'],use_imm=1,immz=1,wren=1,crd=1,aI=0,sz=3))
IRQ_PUSH=[dict(wr=1,aI=SP,immc=1,isz=1,bpcn=1,sz=1),SPDEC()]      # empilha o PC em [SP-2] e depois atualiza SP (falta na pilha: SP intacto)
chain(600,IRQ_PUSH+[dict(br=1,cond=0,aI=63,tabs=1,ioff=1,isz=1)])                                   # IM 0/1: PC empilhado, salta para 0038h
chain(601,[dict(rd=1,wren=1,dI=TMP,aI=63,ioff=1,isz=1,sz=1,zx=1)]+IRQ_PUSH+[dict(br=1,cond=0,aI=TMP,immz=1)])   # IM 2: le o vetor [I:FF] em TMP ANTES de empilhar (uma falta nele nao altera estado); a leitura de 16 bits cruza a palavra (2 transacoes)

# ---- familia ED 26 (3o byte: tamanho[7:6] 00=B 01=W 10=E 11=Q): CPL x = tam,001,x ; NEG x = tam,x,001. B/W/E/Q = ids CPL 294/169/170/171, NEG 295/172/173/174 ----
# CPLB/NEGB nao aceitam o registrador A (AX): o Z80 ja tem CPL e NEG para A. NEGB s: A <- 0 - s (destino fixo AX, fonte s)
for szc,(ci,ni) in enumerate(((294,295),(169,172),(170,173),(171,174))):
    uops[256+ci]=uop(alu=11,dF=1,aD=1,wren=1,fwe=1,sz=szc,fpos=0)                          # s <- NOT s (rr em b3[2:0])
    if szc: uops[256+ni]=uop(alu=10,dF=1,aD=1,wren=1,fwe=1,sz=szc,fpos=1)                  # rr <- 0 - rr (rr em b3[5:3])
    else:   uops[256+ni]=uop(alu=10,aF=1,dI=0,wren=1,fwe=1,sz=0,fpos=0)                    # A <- 0 - s  (s em b3[5:3])
if len(sys.argv)>1 and sys.argv[1]=='rand':    # conteudo pseudo-aleatorio para a sintese (nada vira constante)
    import random; random.seed(1)
    for i in range(2048): uops[i]=random.getrandbits(80)
    for i in range(256): lens[i]=random.randint(1,13)
open('uop.mem','w').write('\n'.join('%020x'%u for u in uops)+'\n')
open('mainctrl.mem','w').write('\n'.join('%08x'%l for l in lens)+'\n')
def words(prog,name):
    mem=prog+[0]*(4096-len(prog)); w=[sum(mem[i*8+k]<<(8*k) for k in range(8)) for i in range(512)]
    open(name,'w').write('\n'.join('%016x'%x for x in w)+'\n')
# programa antigo (JR e agora e o opcode real 18)
words([0x00,5, 0x02,0, 0x04,0x40, 0x52,0x00, 0xE0,0x02,0x00, 0xE3,0x08, 0xC3,0xFF, 0xC2,0xF5, 0xA7,0xF8, 0x18,0xFE],'prog.mem')
# programa de sequencias: LD SP,0F00h ; CALL 20h ; JR $ ; sub-rotina em 20h
P=[0]*0x40
def at(a,b): P[a:a+len(b)]=b
at(0x00,[0x31,0x00,0x0F, 0x00,0x11, 0xCD,0x20,0x00, 0x18,0xFE])      # SP, BC=0x11, CALL 20h, laco em 8
at(0x20,[0x02,0x22, 0xD5, 0x04,0x33, 0xE5, 0xC1, 0xE1, 0x07,0x41, 0xD3,0x77, 0xDB,0x78, 0xC9])
words(P,'prog_seq.mem')
# programa dos prefixos de banco (tb_bank): LDW/LDQ ED-page com ED 0B / 0E / 0D
P2=[]
def ldw(pfx,rr,val): P2.extend([0xED]+([pfx] if pfx else [])+[0x3B,0x40|(rr<<3)|1,val&255,val>>8])
BC,DE,HL,AX,IY=0,2,4,7,3
ldw(0,BC,0x1234); ldw(0x0B,BC,0x5678); ldw(0x0E,DE,0xABCD); ldw(0x0D,HL,0x2211)
P2.extend([0xED,0x0E,0x39,0x40|(AX<<3)|1,0x88,0x77,0x66,0x55,0x44,0x33,0x22,0x11])
ldw(0x0B,IY,0x9999); P2.extend([0xED,0x0B,0x04]); ldw(0,BC,0xBEEF); P2.extend([0x18,0xFE])
words(P2,'prog_bank.mem')

# EXINI: EXX troca o grupo; EXINI volta ao principal (ver tb_exini.v)
P7=[]
def ldw7(rr,val): P7.extend([0xED,0x3B,0x40|(rr<<3)|1,val&255,val>>8])
ldw7(0,0x1111); P7.append(0xD9); ldw7(0,0x2222); P7.extend([0xED,0x09]); ldw7(0,0x3333)      # BC: 1111 | EXX | 2222 (sombra) | EXINI | 3333 (principal)
P7.extend([0xED,0x09]); ldw7(2,0x4444)                                                          # EXINI com grupo ja principal: sem efeito
P7.append(0xD9); P7.append(0xD9); P7.append(0x08); P7.extend([0xED,0x09]); ldw7(7,0x5555)        # EX AF,AF' ativo; EXINI volta AF/AF' para AF
P7.extend([0xD9,0x18,0xFE])
words(P7,'prog_exini.mem')

# CPL/NEG (ED 26): tb_cplneg. grupo principal: BC,DE,HL,AX ; apos EXX: BC',DE',HL' ; IX
P8=[]
def ldw8(rr,val): P8.extend([0xED,0x3B,0x40|(rr<<3)|1,val&255,val>>8])
def ldq8(rr,val): P8.extend([0xED,0x39,0x40|(rr<<3)|1]+[(val>>(8*i))&255 for i in range(8)])
def cpl8(sz,rr): P8.extend([0xED,0x26,(sz<<6)|(1<<3)|rr])
def neg8(sz,rr): P8.extend([0xED,0x26,(sz<<6)|(rr<<3)|1])
ldw8(0,0x1234); cpl8(0,0)                       # CPLB BC          -> BC = 12CB
ldq8(7,1); neg8(3,7)                         # NEGQ AX          -> AX = FFFFFFFFFFFFFFFF
ldw8(2,0x00FF); neg8(0,2)                       # NEGB DE: A <- 0-FF -> AX = FFFFFFFFFFFFFF01 (so o byte baixo)
cpl8(1,2)                                       # CPLW DE          -> DE = FF00
ldw8(4,0x0001); neg8(1,4)                       # NEGW HL          -> HL = FFFF
P8.append(0xD9)                                 # EXX
ldq8(0,0x1122334455667788); cpl8(2,0)           # CPLE BC'         -> 11223344AA998877
ldq8(2,0xAAAAAAAA00000002); neg8(2,2)           # NEGE DE'         -> AAAAAAAAFFFFFFFE
ldq8(4,0x0123456789ABCDEF); cpl8(3,4)           # CPLQ HL'         -> FEDCBA9876543210
P8.extend([0x18,0xFE]); words(P8,'prog_cplneg.mem')
# programa de blocos: LDIR, LDDR, CPIR, INIR, OTIR (ver tb_blk.v)
P3=[]; pcs={}
def ldrr(rr,val): P3.extend([0xED,0x3B,0x40|(rr<<3)|1,val&255,val>>8])
def mark(n): pcs[n]=len(P3)
ldrr(4,0x0100); ldrr(2,0x0200); ldrr(0,5); mark('ldir'); P3.extend([0xED,0xB0]); mark('after_ldir')
ldrr(4,0x0124); ldrr(2,0x0224); ldrr(0,3); mark('lddr'); P3.extend([0xED,0xB8]); mark('after_lddr')
P3.extend([0x07,0x43]); ldrr(4,0x0100); ldrr(0,5); mark('cpir'); P3.extend([0xED,0xB1]); mark('after_cpir')
ldrr(4,0x0300); ldrr(0,0x0378); mark('inir'); P3.extend([0xED,0xB2]); mark('after_inir')
ldrr(4,0x0100); ldrr(0,0x0377); mark('otir'); P3.extend([0xED,0xB3]); mark('after_otir')
mark('end'); P3.extend([0x18,0xFE])
mem=P3+[0]*(4096-len(P3))
mem[0x100:0x105]=[0x41,0x42,0x43,0x44,0x45]; mem[0x122:0x125]=[0x61,0x62,0x63]
open('prog_blk.mem','w').write('\n'.join('%016x'%sum(mem[i*8+k]<<(8*k) for k in range(8)) for i in range(512))+'\n')
open('prog_blk_pcs.vh','w').write(''.join("localparam PC_%s = 16'h%04x;\n"%(n.upper(),a) for n,a in pcs.items()))

# programa de IN/OUT (C),r (tb_io)
P4=[]
def ldrr4(rr,val): P4.extend([0xED,0x3B,0x40|(rr<<3)|1,val&255,val>>8])
ldrr4(0,0x0378); ldrr4(2,0xABCD); ldrr4(4,0x1234); P4.extend([0x07,0x41])
for o in (0x61,0x69,0x51,0x59,0x79): P4.extend([0xED,o])
for o in (0x50,0x78,0x58,0x40,0x70,0x71): P4.extend([0xED,o])
P4.extend([0x18,0xFE]); words(P4,'prog_io.mem')

# programa de IRQ durante LDIR: igual ao inicio de prog_blk, tratador em 0x40 volta ao LDIR por JR
P5=[]
def ldrr5(rr,val): P5.extend([0xED,0x3B,0x40|(rr<<3)|1,val&255,val>>8])
ldrr5(4,0x0100); ldrr5(2,0x0200); ldrr5(0,5); P5.extend([0xED,0xB0]); P5.extend([0x18,0xFE])
mem5=P5+[0]*(4096-len(P5)); mem5[0x100:0x105]=[0x41,0x42,0x43,0x44,0x45]
mem5[0x40:0x42]=[0x18,(0x0f-0x42)&255]       # tratador: JR LDIR (PC 0x0f)
open('prog_irq.mem','w').write('\n'.join('%016x'%sum(mem5[i*8+k]<<(8*k) for k in range(8)) for i in range(512))+'\n')

# programas de interrupcao real (tb_irq2): SP, IM 1 ou IM 2, EI, LDIR; tratador: LD A,41 / OUT (77),A / EI / RETI
def mk_irq(name,im2):
    P=[0x31,0x00,0x0F]
    if im2: P+= [0x07,0x02, 0xED,0x47, 0xED,0x5E]
    else:   P+= [0xED,0x56]
    P+=[0xFB]
    for rr,v in ((4,0x0100),(2,0x0200),(0,5)): P+=[0xED,0x3B,0x40|(rr<<3)|1,v&255,v>>8]
    pc=len(P); P+=[0xED,0xB0,0x18,0xFE]
    m=P+[0]*(4096-len(P)); h=[0x07,0x41,0xD3,0x77,0xFB,0xED,0x4D]
    m[0x38:0x38+len(h)]=h; m[0x50:0x50+len(h)]=h; m[0x100:0x105]=[0x41,0x42,0x43,0x44,0x45]; m[0x2FF]=0x50; m[0x300]=0x00
    open(name,'w').write('\n'.join('%016x'%sum(m[i*8+k]<<(8*k) for k in range(8)) for i in range(512))+'\n')
    return pc
PC_IM1=mk_irq('prog_irq1.mem',0); PC_IM2=mk_irq('prog_irq2.mem',1)
open('prog_irq_pcs.vh','w').write("localparam PC_IM1 = 16'h%04x;\nlocalparam PC_IM2 = 16'h%04x;\n"%(PC_IM1,PC_IM2))

# tb_irq3: atraso do EI e flags de LD A,I
def wmem(name,P,handler=None):
    m=P+[0]*(4096-len(P))
    if handler: m[0x38:0x38+len(handler)]=handler
    open(name,'w').write('\n'.join('%016x'%sum(m[i*8+k]<<(8*k) for k in range(8)) for i in range(512))+'\n')
wmem('prog_irq3.mem',[0x31,0x00,0x0F, 0xED,0x56, 0xFB, 0x07,0x55, 0x18,0xFE],[0xD3,0x77,0xED,0x4D])
wmem('prog_ldai.mem',[0xFB, 0x07,0x80, 0xED,0x47, 0x07,0x00, 0xED,0x57, 0xF3, 0x07,0x00, 0xED,0x57, 0x18,0xFE])

# tb_xing: acessos que cruzam a palavra de 8 bytes (SP impar): PUSH/POP/CALL/RET
P6=[0x31,0x01,0x0F, 0xED,0x3B,0x41,0x34,0x12, 0xC5, 0xD1, 0xCD,0x20,0x00, 0x18,0xFE]
m6=P6+[0]*(4096-len(P6)); m6[0x20]=0xC9
open('prog_xing.mem','w').write('\n'.join('%016x'%sum(m6[i*8+k]<<(8*k) for k in range(8)) for i in range(512))+'\n')
