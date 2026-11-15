# gen_r64_rom.py - microcodigo das instrucoes INTEIRAS proprias do R8064 (pagina ED, 16/32/64 bits): ALU, cargas, armazenamentos, pilha, desvios, chamadas,
# deslocamentos e bits. NAO se roda sozinho: gen_roms.py chama aplica(uops, livre) depois do Z80.
# A semantica foi INFERIDA dos mnemonicos, da ROM de decodificacao e das instrucoes que ja existiam (LDW rr,nn / CPLW / NEGW): ver ../PREMISSAS_R8064.txt.
# Indice da uop = 256 + id (instr_ids.csv). Os registradores vem dos campos do 3o byte (b3): fpos=1 -> destino b3[5:3], fonte A b3[2:0];
# fpos=0 -> destino b3[2:0], fonte A b3[5:3]; a fonte B e sempre b3[2:0]. Codigos: 000 BC, 010 DE, 011 IY, 100 HL, 101 IX, 111 AX.
# Bits novos da uop: [95] r8 (o campo do destino e um registrador de 8 bits do Z80: SARB/SHLB/SHRB), [96] ccf (condicao vinda de b3[5:3]),
#   [97] ccinv (condicao contraria: desvio de pulo de CALL cc / RET cc).  immsel com isz = 1 / 2: numero do bit em b3[6:3] / b3[7:3].
# FORA desta etapa: E/S de 16/32/64 bits (INW/OUTW...), multiplicacao e divisao, FPU, instrucoes de sistema e atomicas.
from gen_z80_rom import POS, ADD, ADC, SUB, SBC, AND, OR, XOR, CP, INC, DEC, SHL, SHR, SAR, ROL, ROR, SP, TMP, ZERO
POS.update(r8=95, ccf=96, ccinv=97)
IX, IY, BC = 9, 10, 1
def uop(**k):
    v = 0
    for n, x in k.items(): v |= x << POS[n]
    return v
def aplica(uops, livre):
    """acrescenta as instrucoes inteiras do R8064; 'livre' = 1a entrada de cadeia livre; devolve a nova 1a entrada livre"""
    nextfree = [livre]; memo = {}
    def chain(i, ulist):
        nxt = None
        for k in reversed(ulist[1:]):
            k = dict(k)
            if nxt is not None: k['more'] = 1; k['nxt'] = nxt
            v = uop(**k)
            if v not in memo:
                assert nextfree[0] < 1792, 'ROM de uops cheia (cadeias ate 1791)'
                memo[v] = nextfree[0]; uops[nextfree[0]] = v; nextfree[0] += 1
            nxt = memo[v]
        k = dict(ulist[0])
        if nxt is not None: k['more'] = 1; k['nxt'] = nxt
        uops[256 + i] = uop(**k)
    D1 = dict(dF=1, fpos=1)                       # destino = b3[5:3]
    D0 = dict(dF=1, fpos=0)                       # destino = b3[2:0]
    MOV = dict(alu=ADD, use_imm=1, immz=1)        # resultado = operando A
    SZ = {'W': 1, 'E': 2, 'Q': 3}
    def tri(ids): return zip('WEQ', ids)
    # ---- ALU rr, rr' (destino b3[5:3], fonte b3[2:0]); flags pelo tamanho ----
    for a, ids in ((ADD, (4, 5, 6)), (ADC, (1, 2, 3)), (SUB, (34, 35, 36)), (SBC, (31, 32, 33)), (AND, (107, 108, 109)), (OR, (110, 111, 112)), (XOR, (113, 114, 115))):
        for s, i in tri(ids): chain(i, [dict(alu=a, aD=1, bF=1, wren=1, fwe=1, sz=SZ[s], **D1)])
    for s, i in tri((37, 38, 39)): chain(i, [dict(alu=CP, aD=1, bF=1, fwe=1, sz=SZ[s], **D1)])                    # CPx: so flags
    for s, i in tri((18, 19, 20)): chain(i, [dict(alu=INC, aD=1, wren=1, fwe=1, sz=SZ[s], **D1)])                 # INCx rr (C mantido)
    for s, i in tri((7, 8, 9)):    chain(i, [dict(alu=DEC, aD=1, wren=1, fwe=1, sz=SZ[s], **D1)])                 # DECx rr
    # ---- deslocamentos de 1 bit: SAR (reg em b3[2:0]); SHL, SHR, RLC, RRC (reg em b3[5:3]); B = registrador de 8 bits do Z80 ----
    for a, fp, ids in ((SAR, D0, (143, 144, 145, 146)), (SHL, D1, (147, 148, 149, 150)), (SHR, D1, (151, 152, 153, 154)), (ROL, D1, (None, 156, 157, 158)), (ROR, D1, (None, 160, 161, 162))):
        for sz, i in enumerate(ids):
            if i is not None: chain(i, [dict(alu=a, aD=1, wren=1, fwe=1, sz=sz, r8=(1 if sz == 0 else 0), **fp)])
    # ---- bits: BIT/RES/SET n, tt (tt em b3[2:0]; n em b3[6:3] para W e b3[7:3] para E) ----
    for s, w, (ib, ir, ist) in (('W', 1, (126, 128, 130)), ('E', 2, (127, 129, 131))):
        chain(ib,  [dict(alu=AND, use_imm=1, immsel=2, isz=w, ioff=2, aD=1, fwe=1, fop=7, sz=SZ[s], **D0)])       # BIT: Z = bit em 0 (flags como BIT do Z80)
        chain(ir,  [dict(alu=AND, use_imm=1, immsel=3, isz=w, ioff=2, aD=1, wren=1, sz=SZ[s], **D0)])             # RES
        chain(ist, [dict(alu=OR,  use_imm=1, immsel=2, isz=w, ioff=2, aD=1, wren=1, sz=SZ[s], **D0)])             # SET
    # ---- LDx: registrador, imediato, (rr'), (nnnnnnnn), (QIX+dd), (QIY+dd) ----
    for s, (rr, imm, ld, st, stabs, ldabs) in (('W', (77, 76, 75, 72, 67, 78)), ('E', (89, 88, 87, 84, 79, 90)), ('Q', (101, 100, 99, 96, 91, 102))):
        z = SZ[s]
        chain(rr,    [dict(aF=1, wren=1, sz=z, **MOV, **D1)])                                                     # LDx rr, rr'
        chain(imm,   [dict(alu=ADD, use_imm=1, aI=ZERO, ioff=3, isz=z, wren=1, sz=z, **D1)])                      # LDx rr, imediato
        chain(ld,    [dict(rd=1, aF=1, immz=1, wren=1, sz=z, **D1)])                                              # LDx rr, (rr')
        chain(st,    [dict(wr=1, aF=1, fpos=0, immz=1, bF=1, sz=z)])                                              # LDx (rr), rr'   (endereco b3[5:3], dado b3[2:0])
        chain(stabs, [dict(aF=1, fpos=0, wren=1, dI=TMP, sz=3, **MOV), dict(wr=1, aI=ZERO, ioff=3, isz=3, bI=TMP, sz=z)])   # LDx (nnnnnnnn), rr
        chain(ldabs, [dict(rd=1, aI=ZERO, ioff=3, isz=3, wren=1, sz=z, **D1)])                                    # LDx rr, (nnnnnnnn)
    for s, x, (st, sti, ld) in (('W', IX, (68, 69, 73)), ('W', IY, (70, 71, 74)), ('E', IX, (80, 81, 85)), ('E', IY, (82, 83, 86)), ('Q', IX, (92, 93, 97)), ('Q', IY, (94, 95, 98))):
        z = SZ[s]; ea = dict(aI=x, ioff=3, isz=1, sext=1)                                                         # endereco = QIX/QIY + dd (16 bits com sinal)
        chain(st,  [dict(aF=1, fpos=0, wren=1, dI=TMP, sz=3, **MOV), dict(wr=1, bI=TMP, sz=z, **ea)])             # LDx (QIX+dd), rr
        chain(sti, [dict(alu=ADD, use_imm=1, aI=ZERO, ioff=5, isz=z, wren=1, dI=TMP, sz=3), dict(wr=1, bI=TMP, sz=z, **ea)])   # LDx (QIX+dd), imediato
        chain(ld,  [dict(rd=1, wren=1, sz=z, **ea, **D1)])                                                        # LDx rr, (QIX+dd)
    # ---- pilha de 32/64 bits (QSP): a gravacao em [SP-n] vem antes de alterar SP (reiniciavel) ----
    def spadj(z, a): return dict(alu=a, use_imm=1, immc=1, isz=z, wren=1, dI=SP, aI=SP, sz=3)                     # ADD: SP - n ; SUB: SP + n
    for z, (pop, push) in ((2, (103, 105)), (3, (104, 106))):
        chain(pop,  [dict(rd=1, aI=SP, immz=1, wren=1, sz=z, **D0), spadj(z, SUB)])                               # POPx rr
        chain(push, [dict(wr=1, aI=SP, immc=1, isz=z, bF=1, sz=z), spadj(z, ADD)])                                # PUSHx rr
    # ---- desvios ----
    CCF = dict(ccf=1)
    chain(134, [dict(br=1, cond=0, rel=1, ioff=2, isz=1, sext=1)])                                                # JRW nn
    chain(133, [dict(br=1, rel=1, ioff=3, isz=1, sext=1, **CCF)])                                                 # JRW cc, nn
    chain(132, [dict(alu=DEC, wren=1, dI=BC, aD=1, ashr8=1, hb=1, sz=0, tzw=1), dict(br=1, cond=2, condx=1, rel=1, ioff=2, isz=1, sext=1)])   # DJNZW nn (B, como DJNZ)
    chain(138, [dict(br=1, cond=0, tabs=1, aI=ZERO, ioff=2, isz=2)])                                              # JPE nnnn
    chain(142, [dict(br=1, cond=0, tabs=1, aI=ZERO, ioff=2, isz=3)])                                              # JPQ nnnnnnnn
    chain(137, [dict(br=1, tabs=1, aI=ZERO, ioff=3, isz=2, **CCF)])                                               # JPE cc, nnnn
    chain(141, [dict(br=1, tabs=1, aI=ZERO, ioff=3, isz=3, **CCF)])                                               # JPQ cc, nnnnnnnn
    T32 = lambda fp: dict(aF=1, fpos=fp, wren=1, dI=TMP, sz=2, zx=1, **MOV)                                       # TMP = 32 bits baixos do registrador
    JTMP = dict(br=1, aI=TMP, immz=1)
    chain(135, [T32(0), dict(cond=0, **JTMP)])                                                                    # JPE (vv)      vv = b3[5:3]
    chain(139, [dict(br=1, cond=0, aF=1, fpos=0, immz=1)])                                                        # JPQ (vv)
    chain(136, [T32(1), dict(**JTMP, **CCF)])                                                                     # JPE cc, (vv)  vv = b3[2:0]
    chain(140, [dict(br=1, aF=1, fpos=1, immz=1, **CCF)])                                                         # JPQ cc, (vv)
    # ---- chamadas e retornos (endereco de retorno de 4 ou 8 bytes) ----
    SKIP = dict(br=1, rel=1, immz=1, ccf=1, ccinv=1, altinv=1)                                                    # condicao falsa: pula o resto da cadeia
    for z, (cimm, creg, ccreg, ret, retcc, ioffimm) in ((2, (118, 116, 117, 124, 122, 2)), (3, (121, 119, 120, 125, 123, 2))):
        push = [dict(wr=1, aI=SP, immc=1, isz=z, bpcn=1, sz=z), spadj(z, ADD)]
        jreg = ([T32(1), dict(cond=0, **JTMP)] if z == 2 else [dict(br=1, cond=0, aF=1, fpos=1, immz=1)])         # alvo = registrador b3[2:0]
        chain(cimm,  push + [dict(br=1, cond=0, tabs=1, aI=ZERO, ioff=ioffimm, isz=z)])                           # CALLx imediato
        chain(creg,  push + jreg)                                                                                 # CALLx (rr)
        chain(ccreg, [SKIP] + push + jreg)                                                                        # CALLx cc, (rr)
        rseq = [dict(rd=1, aI=SP, immz=1, wren=1, dI=TMP, sz=z, zx=1), spadj(z, SUB), dict(cond=0, **JTMP)]
        chain(ret,   rseq)                                                                                        # RETx
        chain(retcc, [SKIP] + rseq)                                                                               # RETx cc
    return nextfree[0]
