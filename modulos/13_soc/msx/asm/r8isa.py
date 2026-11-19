# r8isa.py - R8064 instruction set for the R8064AS assembler: keywords, operand patterns and encoding templates.
# Single source of truth: gen_table.py turns it into r8tab.asm (the table used by R8064AS.COM on the MSX), asmref.py (host
# reference assembler) uses it directly, verify_rom.py checks every ED extension against the decode ROMs of the RTL and
# verify_z80.py checks the Z80/R800 base set against sjasmplus.
#
# Operand patterns (strings):
#   'A','HL','AF\'','DX:AX',...   keyword (aliases share one keyword)         '(HL)','(C)','(SP)'...  indirect keyword
#   u4     BC DE HL AX (code 0-3, JP USER)
#   r      8-bit register B C D E H L A (code 0-5,7)    r-hl  same without H and L     xh  IXH IXL IYH IYL (prefix + code 4/5)
#   ss     BC DE HL SP (Z80 code 0-3)                    qq    BC DE HL AF (code 0-3)  xy  IX or IY (prefix)
#   rr     R8064 64-bit register BC DE IY HL IX AX (code 0,2,3,4,5,7; also N0-N7, BC' DE' HL' AX'; the set is taken
#          from the decode ROM)                          (rr)  the same, indirect
#   cc     NZ Z NC C PO PE P M                           jcc   NZ Z NC C (JR)
#   n nn n32 n64   immediate of 1/2/4/8 bytes            e ee  relative 8/16 bits     (n) (nn) (a64)  absolute address 1/2/8 bytes
#   (xy+d) IX/IY + 8-bit displacement                    (qxy+dd)  QIX/QIY + 16-bit displacement
#   b3 b4 b5  bit number 0-7 / 0-15 / 0-31               k5   control register 0-31   st  ST0-ST7    rst  RST vector
#   =N     constant expression equal to N (IM 0, PROT 1...)
# Template items:  XX literal byte | B|1<<3|2  byte B with operand codes shifted in | E  ED (+ bank prefix when banked
#   registers are used) | P1 P2 DD/FD prefix of an operand | I1:n immediate | R1:n relative | D1:n displacement
KW = {}           # name -> attributes
def kw(names, **a):
    names = names.split()
    a['id'] = names[0]
    for n in names: KW[n] = a
R8 = dict(B=0, C=1, D=2, E=3, H=4, L=5, A=7)
for n, c in R8.items(): kw(n, r8=c)
KW['C']['cc'] = 3
kw('I'); kw('R'); kw('F')
kw('IXH', xh=(0xDD, 4)); kw('IXL', xh=(0xDD, 5)); kw('IYH', xh=(0xFD, 4)); kw('IYL', xh=(0xFD, 5))
kw('BC QBC LBC', rr=0, z16=0, qq=0, u4=0); kw('DE QDE LDE', rr=2, z16=1, qq=1, u4=1); kw('HL QHL LHL', rr=4, z16=2, qq=2, u4=2)
kw('SP QSP LSP', z16=3); kw('AF', qq=3); kw("AF'")
kw('IX QIX LIX', rr=5, xy=0xDD); kw('IY QIY LIY', rr=3, xy=0xFD); kw('AX QAX LAX EA QA', rr=7, u4=3)
for i, (c, z) in enumerate(((0, 0), (2, 1), (4, 2), (7, None))):
    kw('N%d' % i, rr=c, z16=z, bank=1); kw('N%d' % (i + 4), rr=c, z16=z, bank=2)
kw("BC' QBC'", rr=0, z16=0, bank=3); kw("DE' QDE'", rr=2, z16=1, bank=3); kw("HL' QHL'", rr=4, z16=2, bank=3); kw("AX' QAX'", rr=7, bank=3)
for n, c in dict(NZ=0, Z=1, NC=2, PO=4, PE=5, P=6, M=7).items(): kw(n, cc=c)
for i in range(8): kw('ST%d' % i, st=i)
kw('DX:AX'); kw('QDE:QAX QDE:QA'); kw('USER'); kw('AL'); kw('ON'); kw('OFF')
BANKPFX = {1: 0x0E, 2: 0x0D, 3: 0x0B}

FORMS = []        # (mnemonic, [patterns], [template items], options)
def F(mn, ops, tpl, **o):
    for m in mn.split():
        FORMS.append((m, [x for x in ops.split(',') if x] if ops else [], tpl.split(), o))

# ======================================================================= Z80 / R800 base set
ALU = dict(ADD=0, ADC=1, SUB=2, SBC=3, AND=4, XOR=5, OR=6, CP=7)
for m, k in ALU.items():
    for pre in ('A,', ''):
        F(m, pre + 'r', '%02X|1' % (0x80 | k << 3) if not pre else '%02X|2' % (0x80 | k << 3))
        F(m, pre + 'xh', 'P%d %02X|%d' % ((2, 0x80 | k << 3, 2) if pre else (1, 0x80 | k << 3, 1)))
        F(m, pre + '(HL)', '%02X' % (0x86 | k << 3))
        F(m, pre + '(xy+d)', ('P2 %02X D2:1' if pre else 'P1 %02X D1:1') % (0x86 | k << 3))
        F(m, pre + 'n', ('%02X I2:1' if pre else '%02X I1:1') % (0xC6 | k << 3))
F('ADD', 'HL,ss', '09|2<<4'); F('ADC', 'HL,ss', 'E 4A|2<<4', bank=1); F('SBC', 'HL,ss', 'E 42|2<<4', bank=1)
for p, c in (('BC', 0), ('DE', 1), ('SP', 3)): F('ADD', 'xy,' + p, 'P1 %02X' % (0x09 | c << 4))
F('ADD', 'xy,xy', 'P1 29', same=1)
for m, k in (('INC', 4), ('DEC', 5)):
    F(m, 'r', '%02X|1<<3' % k); F(m, 'xh', 'P1 %02X|1<<3' % k); F(m, '(HL)', '%02X' % (0x30 | k)); F(m, '(xy+d)', 'P1 %02X D1:1' % (0x30 | k))
    F(m, 'ss', '%02X|1<<4' % (0x03 if m == 'INC' else 0x0B)); F(m, 'xy', 'P1 %02X' % (0x23 if m == 'INC' else 0x2B))
# 8-bit loads
F('LD', 'r,r', '40|1<<3|2'); F('LD', 'r-hl,xh', 'P2 40|1<<3|2'); F('LD', 'xh,r-hl', 'P1 40|1<<3|2'); F('LD', 'xh,xh', 'P1 40|1<<3|2', same=1)
F('LD', 'r,n', '06|1<<3 I2:1'); F('LD', 'xh,n', 'P1 06|1<<3 I2:1')
F('LD', 'r,(HL)', '46|1<<3'); F('LD', 'r,(xy+d)', 'P2 46|1<<3 D2:1'); F('LD', '(HL),r', '70|2'); F('LD', '(xy+d),r', 'P1 70|2 D1:1')
F('LD', '(HL),n', '36 I2:1'); F('LD', '(xy+d),n', 'P1 36 D1:1 I2:1')
F('LD', 'A,(BC)', '0A'); F('LD', 'A,(DE)', '1A'); F('LD', 'A,(nn)', '3A I2:2'); F('LD', '(BC),A', '02'); F('LD', '(DE),A', '12'); F('LD', '(nn),A', '32 I1:2')
F('LD', 'A,I', 'ED 57'); F('LD', 'A,R', 'ED 5F'); F('LD', 'I,A', 'ED 47'); F('LD', 'R,A', 'ED 4F')
# 16-bit loads
F('LD', 'ss,nn', '01|1<<4 I2:2'); F('LD', 'xy,nn', 'P1 21 I2:2')
F('LD', 'HL,(nn)', '2A I2:2'); F('LD', 'xy,(nn)', 'P1 2A I2:2'); F('LD', 'ss,(nn)', 'E 4B|1<<4 I2:2', bank=1)
F('LD', '(nn),HL', '22 I1:2'); F('LD', '(nn),xy', 'P2 22 I1:2'); F('LD', '(nn),ss', 'E 43|2<<4 I1:2', bank=1)
F('LD', 'SP,HL', 'F9'); F('LD', 'SP,xy', 'P2 F9')
F('PUSH', 'qq', 'C5|1<<4'); F('PUSH', 'xy', 'P1 E5'); F('POP', 'qq', 'C1|1<<4'); F('POP', 'xy', 'P1 E1')
# exchanges and blocks
F('EX', 'DE,HL', 'EB'); F('EX', "AF,AF'", '08'); F('EX', 'AF,AF', '08'); F('EXX', '', 'D9'); F('EX', '(SP),HL', 'E3'); F('EX', '(SP),xy', 'P2 E3')
for m, c in dict(LDI=0xA0, CPI=0xA1, INI=0xA2, OUTI=0xA3, LDD=0xA8, CPD=0xA9, IND=0xAA, OUTD=0xAB,
                 LDIR=0xB0, CPIR=0xB1, INIR=0xB2, OTIR=0xB3, LDDR=0xB8, CPDR=0xB9, INDR=0xBA, OTDR=0xBB).items():
    F(m, '', 'ED %02X' % c)
# general purpose
for m, c in dict(DAA='27', CPL='2F', CCF='3F', SCF='37', NOP='00', HALT='76', DI='F3', EI='FB', RLCA='07', RLA='17', RRCA='0F', RRA='1F').items():
    F(m, '', c)
F('NEG', '', 'ED 44'); F('IM', '=0', 'ED 46'); F('IM', '=1', 'ED 56'); F('IM', '=2', 'ED 5E')
F('RLD', '', 'ED 6F'); F('RRD', '', 'ED 67'); F('RETI', '', 'ED 4D'); F('RETN', '', 'ED 45')
# rotations, shifts and bits (CB page)
for m, k in dict(RLC=0, RRC=1, RL=2, RR=3, SLA=4, SRA=5, SLL=6, SLI=6, SRL=7).items():
    F(m, 'r', 'CB %02X|1' % (k << 3)); F(m, '(HL)', 'CB %02X' % (k << 3 | 6)); F(m, '(xy+d)', 'P1 CB D1:1 %02X' % (k << 3 | 6))
    F(m, '(xy+d),r', 'P1 CB D1:1 %02X|2' % (k << 3))
for m, k in dict(BIT=1, RES=2, SET=3).items():
    F(m, 'b3,r', 'CB %02X|1<<3|2' % (k << 6)); F(m, 'b3,(HL)', 'CB %02X|1<<3' % (k << 6 | 6)); F(m, 'b3,(xy+d)', 'P2 CB D2:1 %02X|1<<3' % (k << 6 | 6))
    if m != 'BIT': F(m, 'b3,(xy+d),r', 'P2 CB D2:1 %02X|1<<3|3' % (k << 6))
# jumps, calls, returns
F('JP', 'nn', 'C3 I1:2'); F('JP', 'cc,nn', 'C2|1<<3 I2:2'); F('JP', '(HL)', 'E9'); F('JP', '(xy)', 'P1 E9')
F('JR', 'e', '18 R1:1'); F('JR', 'jcc,e', '20|1<<3 R2:1'); F('DJNZ', 'e', '10 R1:1')
F('CALL', 'nn', 'CD I1:2'); F('CALL', 'cc,nn', 'C4|1<<3 I2:2'); F('RET', '', 'C9'); F('RET', 'cc', 'C0|1<<3'); F('RST', 'rst', 'C7|1<<3')
# I/O
F('IN', 'A,(n)', 'DB I2:1'); F('IN', 'r,(C)', 'ED 40|1<<3'); F('IN', 'F,(C)', 'ED 70'); F('IN', '(C)', 'ED 70')
F('OUT', '(n),A', 'D3 I1:1'); F('OUT', '(C),r', 'ED 41|2<<3'); F('OUT', '(C),=0', 'ED 71')
# R800 multiplications (also with their R8064 names, below)
F('MULUB MLTUB', 'A,r', 'ED C1|2<<3'); F('MULUW MLTUW', 'HL,BC', 'ED C3'); F('MULUW MLTUW', 'HL,SP', 'ED F3')

# ======================================================================= R8064 extensions (ED page; id = instr_ids.csv)
def X(mn, ops, tpl, id, **o): F(mn, ops, tpl, id=id, **o)
SZ = ((0, 'W'), (1, 'L'), (2, 'Q'))
for base, b2, ids in (('ADC', 0x3F, (1, 2, 3)), ('ADD', 0x3E, (4, 5, 6)), ('SUB', 0x3C, (34, 35, 36)), ('SUBC', 0x3D, (31, 32, 33)),
                      ('AND', 0x38, (107, 108, 109)), ('OR', 0x37, (110, 111, 112)), ('XOR', 0x36, (113, 114, 115))):
    for (s, L), i in zip(SZ, ids): X(base + L, 'rr,rr', 'E %02X %02X|1<<3|2' % (b2, s << 6), i)
for (s, L), i in zip(SZ, (37, 38, 39)): X('CMP%s CP%s' % (L, L), 'rr,rr', 'E 02 %02X|1<<3|2' % (s << 6), i)
for base, b2, ids in (('INC', 0x3E, (18, 19, 20)), ('DEC', 0x3C, (7, 8, 9))):
    for (s, L), i in zip(SZ, ids): X(base + L, 'rr', 'E %02X %02X|1<<3' % (b2, s << 6 | 1), i)
# multiply / divide: optional implicit first operand
X('DIVSB', 'r', 'E 3D 08|1', 10); X('DIVSB', 'AX,r', 'E 3D 08|2', 10); X('DIVUB', 'r', 'E 3C 08|1', 14); X('DIVUB', 'AX,r', 'E 3C 08|2', 14)
X('MLTSB', 'r', 'E 3F 08|1', 21); X('MLTSB', 'A,r', 'E 3F 08|2', 21); X('MLTSB', 'AL,r', 'E 3F 08|2', 21)
X('MLTUB', 'r', 'E C1|1<<3', 25); X('MLTUB', 'HL,r', 'E C1|2<<3', 25)
for m, b2, b3, impl, i in (('DIVSW', 0x3D, 0x48, 'DX:AX', 11), ('DIVUW', 0x3C, 0x48, 'DX:AX', 15), ('MLTSW', 0x3F, 0x48, 'HL', 22), ('MLTUW', 0x3E, 0x48, 'HL', 28),
                           ('DIVSL', 0x3D, 0x88, 'AX', 12), ('DIVUL', 0x3C, 0x88, 'AX', 16), ('MLTSL', 0x3F, 0x88, 'AX', 23), ('MLTUL', 0x3E, 0x88, 'AX', 29),
                           ('DIVSQ', 0x3D, 0xC8, 'QDE:QAX', 13), ('DIVUQ', 0x3C, 0xC8, 'QDE:QAX', 17), ('MLTSQ', 0x3F, 0xC8, 'QDE:QAX', 24), ('MLTUQ', 0x3E, 0xC8, 'AX', 30)):
    X(m, 'rr', 'E %02X %02X|1' % (b2, b3), i); X(m, impl + ',rr', 'E %02X %02X|2' % (b2, b3), i)
# loads W/L/Q
for (s, L), (ld_ind, st_ind, rr_, imm, ldabs, stabs) in zip(SZ, ((75, 72, 77, 76, 78, 67), (87, 84, 89, 88, 90, 79), (99, 96, 101, 100, 102, 91))):
    b2 = 0x3B - s; isz = (2, 4, 8)[s]; ni = ('nn', 'n32', 'n64')[s]
    X('LD' + L, 'rr,(rr)', 'E %02X 00|1<<3|2' % b2, ld_ind); X('LD' + L, '(rr),rr', 'E %02X C0|1<<3|2' % b2, st_ind)
    X('LD' + L, 'rr,rr', 'E %02X 40|1<<3|2' % b2, rr_); X('LD' + L, 'rr,' + ni, 'E %02X 41|1<<3 I2:%d' % (b2, isz), imm)
    X('LD' + L, 'rr,(a64)', 'E %02X 81|1<<3 I2:8' % b2, ldabs); X('LD' + L, '(a64),rr', 'E %02X 01|2<<3 I1:8' % b2, stabs)
for (s, L), ids in zip(SZ, ((68, 69, 73, 70, 71, 74), (80, 81, 85, 82, 83, 86), (92, 93, 97, 94, 95, 98))):
    st_r, st_i, ld_r = (0x01, 0x41, 0x81), (0x06, 0x46, 0x86), (0x00, 0x40, 0xC6)
    c = (st_r, st_i, ld_r)[s]; isz = (2, 4, 8)[s]; ni = ('nn', 'n32', 'n64')[s]
    X('LD' + L, '(qxy+dd),rr', 'E P1 %02X|2<<3 D1:2' % c[0], ids[0]); X('LD' + L, '(qxy+dd),' + ni, 'E P1 %02X D1:2 I2:%d' % (c[1], isz), ids[1])
    X('LD' + L, 'rr,(qxy+dd)', 'E P2 %02X|1<<3 D2:2' % c[2], ids[2])
for (s, L), (pop, push) in zip(SZ[1:], ((103, 105), (104, 106))):
    X('POP' + L, 'rr', 'E 38 %02X|1' % (0x08 | (s - 1) << 6), pop); X('PUSH' + L, 'rr', 'E 38 %02X|1' % (0x88 | (s - 1) << 6), push)
# CPL / NEG by size (ED 26)
X('CPLB', 'rr', 'E 26 08|1', 294); X('NEGB', 'rr', 'E 26 01|1<<3', 295)
for (s, L), (ic, ineg) in zip(SZ, ((169, 172), (170, 173), (171, 174))):
    X('CPL' + L, 'rr', 'E 26 %02X|1' % ((s + 1) << 6 | 8), ic); X('NEG' + L, 'rr', 'E 26 %02X|1<<3' % ((s + 1) << 6 | 1), ineg)
# shifts and rotations (1 bit)
X('SARB', 'r', 'E 29 30|1', 143); X('SLAB SHLB', 'r', 'E 29 06|1<<3', 147); X('SRLB SHRB', 'r', 'E 28 06|1<<3', 151)
for (s, L), (sar, sla, srl, rlc, rrc) in zip(SZ, ((144, 148, 152, 156, 160), (145, 149, 153, 157, 161), (146, 150, 154, 158, 162))):
    c = (s + 1) << 6
    X('SAR' + L, 'rr', 'E 29 %02X|1' % (c | 0x30), sar); X('SLA%s SHL%s' % (L, L), 'rr', 'E 29 %02X|1<<3' % (c | 6), sla)
    X('SRL%s SHR%s' % (L, L), 'rr', 'E 28 %02X|1<<3' % (c | 6), srl)
    X('RLC' + L, 'rr', 'E 06 %02X|1<<3' % (c | 6), rlc); X('RRC' + L, 'rr', 'E 07 %02X|1<<3' % (c | 6), rrc)
# bits
X('BITW', 'b4,rr', 'E 30 00|1<<3|2', 126); X('RESW', 'b4,rr', 'E 30 80|1<<3|2', 128); X('SETW', 'b4,rr', 'E 2F 00|1<<3|2', 130)
X('BITL', 'b5,rr', 'E 33 00|1<<3|2', 127); X('RESL', 'b5,rr', 'E 32 00|1<<3|2', 129); X('SETL', 'b5,rr', 'E 31 00|1<<3|2', 131)
# jumps, calls, returns
X('JRW', 'ee', 'E 2D R1:2', 134); X('JRW', 'cc,ee', 'E 2A 01|1<<3 R2:2', 133); X('DJNZW', 'ee', 'E 2E R1:2', 132)
X('JPL', 'n32', 'E 2C I1:4', 138); X('JPL', 'cc,n32', 'E 2A 81|1<<3 I2:4', 137); X('JPL', '(rr)', 'E 2A 41|1<<3', 135); X('JPL', 'cc,(rr)', 'E 2A 00|1<<3|2', 136)
X('JPQ', 'n64', 'E 2B I1:8', 142); X('JPQ', 'cc,n64', 'E 2A C6|1<<3 I2:8', 141); X('JPQ', '(rr)', 'E 2A C1|1<<3', 139); X('JPQ', 'cc,(rr)', 'E 2A 40|1<<3|2', 140)
X('CALLL', 'n32', 'E 35 I1:4', 118); X('CALLL', '(rr)', 'E 37 08|1', 116); X('CALLL', 'cc,(rr)', 'E 37 C0|1<<3|2', 117)
X('CALLQ', 'n64', 'E 34 I1:8', 121); X('CALLQ', '(rr)', 'E 36 08|1', 119); X('CALLQ', 'cc,(rr)', 'E 36 C0|1<<3|2', 120)
X('RETL', '', 'E 04', 124); X('RETL', 'cc', 'E 03 40|1<<3', 122); X('RETQ', '', 'E 05', 125); X('RETQ', 'cc', 'E 03 80|1<<3', 123)
X('JP', 'USER,(u4)', 'E B4|2', 175)
# I/O by size on port (C)
for (s, L), (i_, o_) in zip(SZ, ((163, 166), (164, 167), (165, 168))):
    X('IN' + L, 'rr,(C)', 'E 27 %02X|1<<3' % (s << 6 | 1), i_); X('OUT' + L, '(C),rr', 'E 27 %02X|2<<3' % (s << 6 | 6), o_)
# atomics
X('XCHGL', 'rr,(rr)', 'E AC 00|1<<3|2', 187); X('XCHGQ', 'rr,(rr)', 'E AC 40|1<<3|2', 188)
X('CASL', '(rr),rr', 'E AD 00|1<<3|2', 189); X('CASQ', '(rr),rr', 'E AD 40|1<<3|2', 190)
# system
X('EXINI', '', 'E 09', 291); X('MFCR', 'k5', 'E 0A I1:1', 292); X('MTCR', 'k5', 'E 0C I1:1', 293)
X('LDCR', 'k5,rr', 'E 20 00|1<<3|2', 180); X('STCR', 'rr,k5', 'E 21 00|2<<3|1', 181)
X('SCALL', 'n', 'E 22 I1:1', 182); X('SYSRT', '', 'E A4', 183); X('FENCE', '', 'E A5', 184); X('ISYNC', '', 'E A6', 185)
X('PGINV', '(rr)', 'E C4|1<<3', 186); X('PROT', '=0', 'E 00', 176); X('PROT', '=1', 'E 01', 176); X('PROT', 'OFF', 'E 00', 176); X('PROT', 'ON', 'E 01', 176)
X('RESET', '', 'E 25', 177); X('STDBY', '', 'E 24', 178); X('WAKE', '', 'E 23', 179); X('FLUSH', '', 'E 94', 53)
X('SVCTX', '(rr)', 'E AE 08|1', 191); X('LDCTX', '(rr)', 'E AE 48|1', 192); X('FSAVE', '(rr)', 'E AF 08|1', 193); X('FRSTR', '(rr)', 'E AF 48|1', 194)
# FPU
for m, c, i in (('FCOPP', '80', 40), ('FINIT', '82', 43), ('FIST', '83', 44), ('FISTP', '84', 45), ('FLDL2', '86', 47), ('FLDLG', '87', 48), ('FLDLN', '90', 49),
                ('FLDPI', '91', 50), ('FLDZ', '92', 51), ('FREM', '95', 55), ('FREM1', '96', 56), ('FSTSW', '14', 62)):
    X(m, '', 'E ' + c, i)
X('FCOPP', 'ST0,ST1', 'E 80', 40)
for m, c, i in (('FCOS', '81', 41), ('FLN', '93', 52), ('FSIN', '97', 57), ('FSINC', '10', 58), ('FSQRT', '11', 59), ('FTAN', '15', 64), ('FYL2P', '16', 65), ('FYL2X', '17', 66)):
    X(m, '', 'E ' + c, i); X(m, 'ST0', 'E ' + c, i)
for m, c, i in (('FLD80', '85', 46), ('FST80', '12', 60), ('FSTP8', '13', 61)): X(m, '(HL)', 'E ' + c, i)
for m, b2, i in (('FDIV', 0x88, 42), ('FMUL', 0x98, 54), ('FSUB', 0x18, 63)):
    X(m, 'st', 'E %02X|1' % b2, i); X(m, 'ST0,st', 'E %02X|2' % b2, i)
X('FADD', 'st', 'E BC 00|1', 195); X('FADD', 'ST0,st', 'E BC 00|2', 195)
for m, c, i in (('FXCH', 0x08, 196), ('FLD', 0x10, 197), ('FSTP', 0x18, 198), ('FCOM', 0x20, 199)): X(m, 'st', 'E BC %02X|1' % c, i)
for m, c, i in (('FCHS', 0x40, 200), ('FABS', 0x41, 201), ('FLD1', 0x42, 202), ('FRINT', 0x43, 203)): X(m, '', 'E BC %02X' % c, i)
for m, c, i in (('FILD', 0x48, 204), ('FLD32', 0x49, 205), ('FLD64', 0x4A, 206), ('FST32', 0x4B, 207), ('FSP32', 0x4C, 208), ('FST64', 0x4D, 209), ('FSP64', 0x4E, 210)):
    X(m, '(HL)', 'E BC %02X' % c, i)
