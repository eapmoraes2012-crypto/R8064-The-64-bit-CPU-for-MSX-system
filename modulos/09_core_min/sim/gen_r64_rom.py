# gen_r64_rom.py - microcodigo das instrucoes INTEIRAS proprias do R8064 (pagina ED, 16/32/64 bits): ALU, cargas, armazenamentos, pilha, desvios, chamadas,
# deslocamentos e bits. NAO se roda sozinho: gen_roms.py chama aplica(uops, livre) depois do Z80.
# A semantica foi INFERIDA dos mnemonicos, da ROM de decodificacao e das instrucoes que ja existiam (LDW rr,nn / CPLW / NEGW): ver ../PREMISSAS_R8064.txt.
# Indice da uop = 256 + id (instr_ids.csv). Os registradores vem dos campos do 3o byte (b3): fpos=1 -> destino b3[5:3], fonte A b3[2:0];
# fpos=0 -> destino b3[2:0], fonte A b3[5:3]; a fonte B e sempre b3[2:0]. Codigos: 000 BC, 010 DE, 011 IY, 100 HL, 101 IX, 111 AX.
# Bits novos da uop: [95] r8 (o campo do destino e um registrador de 8 bits do Z80: SARB/SHLB/SHRB), [96] ccf (condicao vinda de b3[5:3]),
#   [97] ccinv (condicao contraria: desvio de pulo de CALL cc / RET cc).  immsel com isz = 1 / 2: numero do bit em b3[6:3] / b3[7:3].
#   [98] mdu (multiplicacao/divisao; o campo alu vira o comando: 0-3 dispara MULU/MULS/DIVU/DIVS, 8+n le o resultado n, 16 guarda a parte alta do dividendo),
#   [99] r8b (fonte B = registrador de 8 bits do Z80), [100] bb2 (campo da fonte B no 2o byte), [101] crk (LDCR/STCR: CR em b3[7:3]).
#   [102] priv (instrucao privilegiada: excecao em modo usuario), [103] (livre),
#   [104] scall (a instrucao e uma chamada de sistema: sempre excecao), [105] ju (JP USER: registrador pelos 2 bits baixos do 2o byte).
# Modelo de privilegio e de excecao: ../MODELO_PRIVILEGIO.txt.
# Todas as instrucoes tem microcodigo; FENCE, ISYNC e WAKE sao NOP.
from gen_z80_rom import POS, ADD, ADC, SUB, SBC, AND, OR, XOR, CP, INC, DEC, SHL, SHR, SAR, ROL, ROR, SP, TMP, ZERO
POS.update(r8=95, ccf=96, ccinv=97, mdu=98, r8b=99, bb2=100, crk=101, priv=102, scall=104, ju=105, fpu=106)
IX, IY, BC, AX, DE, HL, T2 = 9, 10, 1, 0, 2, 3, 12
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
    chain(132, [dict(alu=DEC, wren=1, dI=BC, aD=1, sz=1, tzw=1), dict(br=1, cond=2, condx=1, rel=1, ioff=2, isz=1, sext=1)])   # DJNZW nn: BC (16 bits) := BC - 1 sem flags; salta se BC != 0
    chain(138, [dict(br=1, cond=0, tabs=1, aI=ZERO, ioff=2, isz=2)])                                              # JPL nnnn
    chain(142, [dict(br=1, cond=0, tabs=1, aI=ZERO, ioff=2, isz=3)])                                              # JPQ nnnnnnnn
    chain(137, [dict(br=1, tabs=1, aI=ZERO, ioff=3, isz=2, **CCF)])                                               # JPL cc, nnnn
    chain(141, [dict(br=1, tabs=1, aI=ZERO, ioff=3, isz=3, **CCF)])                                               # JPQ cc, nnnnnnnn
    T32 = lambda fp: dict(aF=1, fpos=fp, wren=1, dI=TMP, sz=2, zx=1, **MOV)                                       # TMP = 32 bits baixos do registrador
    JTMP = dict(br=1, aI=TMP, immz=1)
    chain(135, [T32(0), dict(cond=0, **JTMP)])                                                                    # JPL (vv)      vv = b3[5:3]
    chain(139, [dict(br=1, cond=0, aF=1, fpos=0, immz=1)])                                                        # JPQ (vv)
    chain(136, [T32(1), dict(**JTMP, **CCF)])                                                                     # JPL cc, (vv)  vv = b3[2:0]
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
    # ---- multiplicacao (MLTUB do R800: ED C1..F9; MLTUW HL,BC / HL,SP: ED C3 / F3; demais: tt 001 rrr) e divisao; nao alteram flags ----
    def START(op, z, **k): return dict(mdu=1, alu=op, sz=z, fwe=1, **k)                    # op: 0 MULU, 1 MULS, 2 DIVU, 3 DIVS
    def READ(sel, d, z, **k): return dict(mdu=1, alu=8 | sel, wren=1, dI=d, sz=z, **k)  # sel: 0 baixo/quociente, 1 alto/resto, 2 produto[31:16], 3 {resto32, quociente32}
    def SETHI(a, z, **k): return dict(mdu=1, alu=16, aI=a, sz=z, **k)
    chain(25, [START(0, 0, aI=AX, r8b=1, bb2=1), READ(0, HL, 1)])                                                 # MLTUB A,u    -> HL = A * u
    chain(26, [START(0, 1, aI=HL, bI=BC), READ(0, HL, 1), READ(2, DE, 1)])                                        # MLTUW HL,BC  -> DE:HL
    chain(27, [START(0, 1, aI=HL, bI=SP), READ(0, HL, 1), READ(2, DE, 1)])                                        # MLTUW HL,SP
    for sg, (ib, iw, ie, iq) in ((0, (None, 28, 29, 30)), (1, (21, 22, 23, 24))):
        if ib: chain(ib, [START(sg, 0, aI=AX, r8b=1), READ(0, AX, 1)])                                            # MLTSB AL,u   -> AX (16 bits)
        chain(iw, [START(sg, 1, aI=HL, bF=1), READ(0, HL, 1), READ(2, DE, 1)])                                    # MLTxW HL,rr  -> DE:HL
        chain(ie, [START(sg, 2, aI=AX, bF=1), READ(0, AX, 3)])                                                    # MLTxL        -> QA (64 bits)
        chain(iq, [START(sg, 3, aI=AX, bF=1), READ(0, AX, 3)] + ([READ(1, DE, 3)] if sg else []))                 # MLTUQ -> QA ; MLTSQ -> QDE:QA
    for sg, (ib, iw, ie, iq) in ((0, (14, 15, 16, 17)), (1, (10, 11, 12, 13))):
        chain(ib, [SETHI(AX, 0, ashr8=1), START(2 | sg, 0, aI=AX, r8b=1), READ(0, AX, 0), READ(1, AX, 0, hb=1)])  # DIVxB AX,t   -> AL = quociente, AH = resto
        chain(iw, [SETHI(DE, 1), START(2 | sg, 1, aI=AX, bF=1), READ(0, AX, 1), READ(1, DE, 1)])                  # DIVxW DX:AX  -> AX = quociente, DE = resto
        chain(ie, [SETHI(AX, 2), START(2 | sg, 2, aI=AX, bF=1), READ(3, AX, 3)])                                  # DIVxL QA     -> QA = {resto, quociente}
        chain(iq, [SETHI(DE, 3), START(2 | sg, 3, aI=AX, bF=1), READ(0, AX, 3), READ(1, DE, 3)])                  # DIVxQ QDE:QA -> QA = quociente, QDE = resto
    # ---- registradores de controle, TLB, troca e comparacao-e-troca ----
    chain(180, [dict(aF=1, fpos=1, crd=1, crk=1, wren=1, sz=3, priv=1, **MOV)])                                           # LDCR kk,rr : CR[kk] := rr
    chain(181, [dict(cra=1, crk=1, dF=1, fpos=0, wren=1, sz=3, priv=1, **MOV)])                                           # STCR rr,kk : rr := CR[kk]
    chain(186, [dict(alu=ADD, aI=ZERO, bF=1, bb2=1, wren=1, dI=48, sz=3, priv=1)])                                        # PGINV (uu) : descarga da TLB pelo endereco (= escrever CR16)
    for z, (ix, ic) in ((2, (187, 189)), (3, (188, 190))):
        chain(ix, [dict(aF=1, fpos=0, wren=1, dI=T2, sz=3, **MOV), dict(rd=1, aF=1, fpos=1, immz=1, wren=1, dI=TMP, sz=z, zx=1),   # XCHGx rr,(rr')
                   dict(wr=1, aF=1, fpos=1, immz=1, bI=T2, sz=z), dict(aI=TMP, wren=1, sz=z, **MOV, **D1)])
        chain(ic, [dict(rd=1, aF=1, fpos=0, immz=1, wren=1, dI=TMP, sz=z, zx=1), dict(alu=CP, aI=AX, bI=TMP, fwe=1, sz=z),         # CASx (rr'),rr: se (rr') == A:
                   dict(aI=TMP, wren=1, dI=AX, sz=z, **MOV), dict(br=1, rel=1, immz=1, cond=2, altinv=1),                         #   (rr') := rr, Z = 1 ; senao A := (rr'), Z = 0
                   dict(wr=1, aF=1, fpos=0, immz=1, bF=1, sz=z)])
    # ---- sistema (MODELO_PRIVILEGIO.txt). CR: 10 = indice 42 (IE), 13 = 45 (EPC), 14 = 46 (MMU/TE), 18 = 50 (modo) ----
    CR10, CR13, CR14, CR18 = 42, 45, 46, 50
    chain(292, [dict(alu=ADD, use_imm=1, immz=1, wren=1, dI=AX, cra=1, sz=3, priv=1)])                            # MFCR n (ED 0A n): AX := CR[n]   (agora privilegiada)
    chain(293, [dict(alu=ADD, use_imm=1, immz=1, wren=1, crd=1, aI=AX, sz=3, priv=1)])                            # MTCR n (ED 0C n): CR[n] := AX
    chain(182, [dict(scall=1)])                                                                                   # SCALL n: excecao causa 5, CR12 = n, EPC = instrucao seguinte
    chain(183, [dict(alu=SHR, aI=CR18, wren=1, dI=CR18, sz=3, priv=1), dict(br=1, cond=0, aI=CR13, immz=1, misc=3)])   # SYSRT: modo := anterior; IFF1 := IFF2; PC := EPC
    chain(175, [dict(alu=INC, aI=ZERO, wren=1, dI=CR18, sz=3, priv=1), dict(br=1, cond=0, ju=1, immz=1)])         # JP USER,(uu): modo := usuario; PC := uu
    chain(176, [dict(alu=AND, use_imm=1, immsel=3, ioff=1, aI=CR14, wren=1, dI=TMP, sz=3, priv=1),                # PROT 0 / PROT 1 (ED 00 / ED 01): desliga / liga a MMU
                dict(alu=ADD, use_imm=1, aI=ZERO, ioff=1, isz=0, wren=1, dI=T2, sz=3), dict(alu=OR, aI=TMP, bI=T2, wren=1, dI=CR14, sz=3)])   #   (CR14 bit 0 := bit 0 do opcode)
    Z0 = lambda d: dict(aI=ZERO, wren=1, dI=d, sz=3, **MOV)
    chain(177, [dict(priv=1, **Z0(CR14)), Z0(CR18), Z0(CR10), dict(br=1, cond=0, tabs=1, aI=ZERO, immz=1)])       # RESET: MMU desligada, supervisor, IE = 0, PC := 0
    chain(178, [dict(br=1, cond=0, tself=1, aI=ZERO, priv=1)])                                                    # STDBY: espera interrupcao (repete a si mesma, como HALT)
    chain(179, [dict(priv=1)])                                                                                    # WAKE: NOP (nucleo unico)
    # contexto: bloco de 16 palavras de 8 bytes em (uu): AX BC DE HL IX IY SP F N0..N7 (os registradores visiveis; o grupo alternativo e EXX nao entram)
    CTX = [AX, BC, DE, HL, IX, IY, SP, None] + list(range(16, 24))
    PTR = dict(alu=ADD, aI=ZERO, bF=1, wren=1, dI=TMP, sz=3)                                                      # TMP := uu (b3[2:0])
    NEXT = dict(alu=SUB, use_imm=1, immc=1, isz=3, wren=1, dI=TMP, aI=TMP, sz=3)                                  # TMP := TMP + 8
    sv = [PTR]; ld = [PTR]
    for k, rg in enumerate(CTX):
        sv.append(dict(wr=1, aI=TMP, immz=1, sz=3, **(dict(bfl=1) if rg is None else dict(bI=rg))))
        if rg is None: ld += [dict(rd=1, aI=TMP, immz=1, wren=1, dI=T2, sz=3), dict(aI=T2, sz=0, fwe=1, fop=6, **MOV)]
        else: ld.append(dict(rd=1, aI=TMP, immz=1, wren=1, dI=rg, sz=3))
        if k < len(CTX) - 1: sv.append(NEXT); ld.append(NEXT)
    chain(191, sv)                                                                                                # SVCTX (uu)
    chain(192, ld)                                                                                                # LDCTX (uu)
    # ---- FPU (../MODELO_FPU.txt): a unidade 08_fpu/rtl/fpu_unit.v faz a conta; a uop so entrega o comando (campo dI), n (byte da instrucao) e os dados de memoria ----
    def FX(cmd, ioff=1, **k): return dict(mdu=1, fpu=1, alu=0, dI=cmd, use_imm=1, ioff=ioff, isz=0, sz=3, **k)     # dispara e espera
    def FRD(sel, d): return dict(mdu=1, fpu=1, alu=8 | sel, wren=1, dI=d, sz=3)                                    # le r0 (sel 0) / r1 (sel 1)
    def FHI(a): return dict(mdu=1, fpu=1, alu=16, aI=a, sz=3)                                                      # 16 bits altos de um valor de 80 bits
    K1, K2, POP, T3 = 16, 32, 32 | 8, 24
    LDM = lambda z: dict(rd=1, aI=HL, immz=1, wren=1, dI=TMP, sz=z)                                                # TMP := (QHL)
    STM = lambda z: dict(wr=1, aI=HL, immz=1, sz=z, bI=TMP)                                                        # (QHL) := TMP
    HL8 = dict(alu=SUB, use_imm=1, immc=1, isz=3, wren=1, dI=T3, aI=HL, sz=3)                                      # T3 := QHL + 8
    chain(195, [FX(0, ioff=2)]); chain(63, [FX(1)]); chain(54, [FX(2)]); chain(42, [FX(3)])                        # FADD / FSUB / FMUL / FDIV ST0,STn
    chain(59, [FX(4)]); chain(203, [FX(8)]); chain(199, [FX(5, ioff=2)]); chain(40, [FX(K1 | 5)])                  # FSQRT, FRINT, FCOM STn, FCOPP
    chain(197, [FX(K2 | 0, ioff=2)]); chain(196, [FX(K2 | 1, ioff=2)]); chain(198, [FX(K2 | 2, ioff=2)])           # FLD STn, FXCH STn, FSTP STn
    chain(200, [FX(K2 | 3)]); chain(201, [FX(K2 | 4)]); chain(43, [FX(K2 | 5)])                                    # FCHS, FABS, FINIT
    chain(202, [FX(K2 | 10)]); chain(51, [FX(K2 | 11)]); chain(50, [FX(K2 | 12)])                                  # FLD1, FLDZ, FLDPI
    chain(47, [FX(K2 | 13)]); chain(48, [FX(K2 | 14)]); chain(49, [FX(K2 | 15)])                                   # FLDL2, FLDLG, FLDLN
    chain(62, [FX(K2 | 9), FRD(0, T2), dict(aI=T2, sz=0, fwe=1, fop=6, **MOV)])                                    # FSTSW: F := {0, C3, 0, 0, 0, C2, 0, C0}
    chain(204, [LDM(3), FX(6, aI=TMP)]); chain(205, [LDM(2), FX(9, aI=TMP)]); chain(206, [LDM(3), FX(10, aI=TMP)]) # FILD, FLD32, FLD64 (QHL)
    chain(46, [LDM(3), HL8, dict(rd=1, aI=T3, immz=1, wren=1, dI=T2, sz=1), FHI(T2), FX(K2 | 6, aI=TMP)])          # FLD80 (QHL)
    # gravacoes: o valor e convertido, gravado e SO DEPOIS a pilha anda (uma falta de pagina na gravacao reinicia a instrucao com a pilha intacta)
    chain(44, [FX(7), FRD(0, TMP), STM(3)]); chain(45, [FX(7), FRD(0, TMP), STM(3), FX(POP)])                      # FIST, FISTP (QHL): inteiro de 64 bits
    chain(207, [FX(11), FRD(0, TMP), STM(2)]); chain(208, [FX(11), FRD(0, TMP), STM(2), FX(POP)])                  # FST32, FSP32
    chain(209, [FX(12), FRD(0, TMP), STM(3)]); chain(210, [FX(12), FRD(0, TMP), STM(3), FX(POP)])                  # FST64, FSP64
    ST80 = [FX(K2 | 7), FRD(0, TMP), STM(3), FRD(1, T2), HL8, dict(wr=1, aI=T3, immz=1, sz=1, bI=T2)]
    chain(60, ST80); chain(61, ST80 + [FX(POP)])                                                                   # FST80, FSTP8 (QHL)
    chain(53, [dict(alu=INC, aI=ZERO, wren=1, dI=49, sz=3, priv=1), dict(br=1, cond=0, rel=1, immz=1)])            # FLUSH: descarrega a TLB inteira (CR17 := 1) e o pipeline
    # transcendentais e restos: programas internos da unidade (08_fpu/ref/gen_fpu_prog.py); a uop so dispara
    K3 = 48
    for i, c in ((57, 4), (41, 5), (58, 6), (64, 7), (52, 8), (66, 9), (65, 10), (55, 11), (56, 12)): chain(i, [FX(K3 | c)])   # FSIN FCOS FSINC FTAN FLN FYL2X FYL2P FREM FREM1
    # FSAVE / FRSTR (uu): 8 bytes de estado {vazios [23:16], palavra de estado [15:0]} + 8 registradores FISICOS de 10 bytes (88 bytes). FSAVE nao altera a FPU.
    NEXT2 = dict(alu=SUB, use_imm=1, immc=1, isz=1, wren=1, dI=TMP, aI=TMP, sz=3)
    WT = lambda z: dict(wr=1, aI=TMP, immz=1, sz=z, bI=T2)
    sv = [PTR, FX(K3 | 0), FRD(0, T2), WT(3), NEXT]; ld = [PTR, dict(rd=1, aI=TMP, immz=1, wren=1, dI=T2, sz=3), FX(K3 | 2, aI=T2), NEXT]
    for k in range(8):
        sv += [FX(K3 | 1), FRD(0, T2), WT(3), NEXT, FRD(1, T2), WT(1), NEXT2]
        ld += [dict(rd=1, aI=TMP, immz=1, wren=1, dI=T3, sz=3), NEXT, dict(rd=1, aI=TMP, immz=1, wren=1, dI=T2, sz=1), FHI(T2), FX(K3 | 3, aI=T3), NEXT2]
    chain(193, sv); chain(194, ld)
    # ---- E/S de 16/32/64 bits em UMA porta (C): bytes sucessivos, o menos significativo primeiro (faixa k em ioff = u[41:39] com immz) ----
    T2_ = 12
    for z, ii, io in ((1, 163, 166), (2, 164, 167), (3, 165, 168)):
        nb = {1: 2, 2: 4, 3: 8}[z]
        rdk = lambda k, d: dict(iord=1, wren=1, dI=d, aI=BC, immz=1, ioff=k, sz=3, zx=1)
        ul = [rdk(0, T2_)]
        for k in range(1, nb): ul += [rdk(k, TMP), dict(alu=OR, aI=T2_, bI=TMP, wren=1, dI=T2_, sz=3)]
        ul += [dict(aI=T2_, wren=1, sz=z, **MOV, **D1)]                          # rr := acumulado (so no fim: rr pode ser BC)
        chain(ii, ul)                                                           # INx rr,(C)
        ol = [dict(aF=1, fpos=0, wren=1, dI=T2_, sz=z, zx=1, **MOV)]            # copia rr (b3[5:3]) para T2
        for k in range(nb): ol.append(dict(iowr=1, aI=BC, immz=1, ioff=k, bI=T2_))
        chain(io, ol)                                                           # OUTx (C),rr
    return nextfree[0]
