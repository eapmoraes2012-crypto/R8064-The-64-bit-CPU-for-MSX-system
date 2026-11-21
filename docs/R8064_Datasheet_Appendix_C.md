# R8064 - Datasheet (Preliminary) 2026

## Appendix C — Complete instruction list

<!-- BEGIN APPENDIX_C -->
Generated from `modulos/13_soc/msx/asm/r8isa.py` by `modulos/13_soc/sim/meas/gen_doc_tables.py`: 245 mnemonics, 495 operand forms (249 Z80/R800 base forms and 246 R8064 extension forms). This is the set accepted by the R8064AS assembler; the extension forms are checked against the decode ROMs of the RTL (`verify_rom.py`) and the base set against sjasmplus (`verify_z80.py`).

Operand codes in the encoding: **a** = code of the 1st operand, **b** = of the 2nd, **c** = of the 3rd (`a·8` = shifted 3 bits). Register codes: r = B 0, C 1, D 2, E 3, H 4, L 5, A 7; ss = BC 0, DE 1, HL 2, SP 3; qq = BC, DE, HL, AF; rr (R8064) = BC 0, DE 2, IY 3, HL 4, IX 5, AX 7 (and N0–N7, BC', DE', HL', AX' through the bank prefixes, section 4.2); p = IXH/IXL/IYH/IYL; xy = IX (DD) or IY (FD); cc = NZ 0, Z 1, NC 2, C 3, PO 4, PE 5, P 6, M 7; uu = BC, DE, HL, AX (0–3). `n×8` = 8-byte immediate or address, little-endian. Bytes = length without a bank prefix (ED 0B/0D/0E adds 2).

**Native clocks** = measured clocks per instruction in native mode with code and data in the caches (REV48, Appendix D); a value marked † was measured in simulation only (not in the cartridge build). "–" = not measured (system, FPU and removed instructions; see Appendix D).

### C.1 R8064 extensions

| Mnemonic | Syntax | Encoding (hex) | Bytes | id | Native clocks |
| --- | --- | --- | --- | --- | --- |
| ADCL | `ADCL rr, rr` | ED 3F 40+a·8+b | 3 | 2 | 8.00 |
| ADCQ | `ADCQ rr, rr` | ED 3F 80+a·8+b | 3 | 3 | 8.00 |
| ADCW | `ADCW rr, rr` | ED 3F 00+a·8+b | 3 | 1 | 8.00 |
| ADDL | `ADDL rr, rr` | ED 3E 40+a·8+b | 3 | 5 | 8.00 |
| ADDQ | `ADDQ rr, rr` | ED 3E 80+a·8+b | 3 | 6 | 8.00 |
| ADDW | `ADDW rr, rr` | ED 3E 00+a·8+b | 3 | 4 | 8.00 |
| ANDL | `ANDL rr, rr` | ED 38 40+a·8+b | 3 | 108 | 8.00 |
| ANDQ | `ANDQ rr, rr` | ED 38 80+a·8+b | 3 | 109 | 8.00 |
| ANDW | `ANDW rr, rr` | ED 38 00+a·8+b | 3 | 107 | 8.00 |
| BITL | `BITL b, rr` | ED 33 00+a·8+b | 3 | 127 | 8.00 |
| BITW | `BITW b, rr` | ED 30 00+a·8+b | 3 | 126 | 8.00 |
| CALLL | `CALLL (rr)` | ED 37 08+a | 3 | 116 | 31.00 |
| CALLL | `CALLL cc, (rr)` | ED 37 C0+a·8+b | 3 | 117 | 35.00 taken / 16.00 not taken |
| CALLL | `CALLL nnnn` | ED 35 nnnn | 6 | 118 | 27.75 |
| CALLQ | `CALLQ (rr)` | ED 36 08+a | 3 | 119 | 27.00 |
| CALLQ | `CALLQ cc, (rr)` | ED 36 C0+a·8+b | 3 | 120 | 31.00 taken / 16.00 not taken |
| CALLQ | `CALLQ nnnnnnnn` | ED 34 n×8 | 10 | 121 | 27.75 |
| CASL | `CASL (rr), rr` | ED AD 00+a·8+b | 3 | 189 | 35.25 |
| CASQ | `CASQ (rr), rr` | ED AD 40+a·8+b | 3 | 190 | 31.25 |
| CMPL | `CMPL rr, rr` | ED 02 40+a·8+b | 3 | 38 | 8.00 |
| CMPQ | `CMPQ rr, rr` | ED 02 80+a·8+b | 3 | 39 | 8.00 |
| CMPW | `CMPW rr, rr` | ED 02 00+a·8+b | 3 | 37 | 8.00 |
| CPL | `CPL rr, rr` | ED 02 40+a·8+b | 3 | 38 | 8.00 |
| CPLB | `CPLB rr` | ED 26 08+a | 3 | 294 | – |
| CPLL | `CPLL rr` | ED 26 88+a | 3 | 170 | 8.00 |
| CPLQ | `CPLQ rr` | ED 26 C8+a | 3 | 171 | 8.00 |
| CPLW | `CPLW rr` | ED 26 48+a | 3 | 169 | 8.00 |
| CPQ | `CPQ rr, rr` | ED 02 80+a·8+b | 3 | 39 | 8.00 |
| CPW | `CPW rr, rr` | ED 02 00+a·8+b | 3 | 37 | 8.00 |
| DECL | `DECL rr` | ED 3C 41+a·8 | 3 | 8 | 8.00 |
| DECQ | `DECQ rr` | ED 3C 81+a·8 | 3 | 9 | 8.00 |
| DECW | `DECW rr` | ED 3C 01+a·8 | 3 | 7 | 8.00 |
| DIVSB | `DIVSB AX, r` | ED 3D 08+b | 3 | 10 | 28.00 |
| DIVSB | `DIVSB r` | ED 3D 08+a | 3 | 10 | 28.00 |
| DIVSL | `DIVSL AX, rr` | ED 3D 88+b | 3 | 12 | 47.31 |
| DIVSL | `DIVSL rr` | ED 3D 88+a | 3 | 12 | 47.31 |
| DIVSQ | `DIVSQ QDE:QAX, rr` | ED 3D C8+b | 3 | 13 | 78.31 † |
| DIVSQ | `DIVSQ rr` | ED 3D C8+a | 3 | 13 | 78.31 † |
| DIVSW | `DIVSW DX:AX, rr` | ED 3D 48+b | 3 | 11 | 44.44 |
| DIVSW | `DIVSW rr` | ED 3D 48+a | 3 | 11 | 44.44 |
| DIVUB | `DIVUB AX, r` | ED 3C 08+b | 3 | 14 | 25.00 |
| DIVUB | `DIVUB r` | ED 3C 08+a | 3 | 14 | 25.00 |
| DIVUL | `DIVUL AX, rr` | ED 3C 88+b | 3 | 16 | 49.00 |
| DIVUL | `DIVUL rr` | ED 3C 88+a | 3 | 16 | 49.00 |
| DIVUQ | `DIVUQ QDE:QAX, rr` | ED 3C C8+b | 3 | 17 | 86.00 † |
| DIVUQ | `DIVUQ rr` | ED 3C C8+a | 3 | 17 | 86.00 † |
| DIVUW | `DIVUW DX:AX, rr` | ED 3C 48+b | 3 | 15 | 41.00 |
| DIVUW | `DIVUW rr` | ED 3C 48+a | 3 | 15 | 41.00 |
| DJNZW | `DJNZW ee` | ED 2E ee | 4 | 132 | 20.00 |
| EXINI | `EXINI` | ED 09 | 2 | 291 | – |
| FABS | `FABS` | ED BC 41 | 3 | 201 | – |
| FADD | `FADD ST0, STn` | ED BC 00+b | 3 | 195 | – |
| FADD | `FADD STn` | ED BC 00+a | 3 | 195 | – |
| FCHS | `FCHS` | ED BC 40 | 3 | 200 | – |
| FCOM | `FCOM STn` | ED BC 20+a | 3 | 199 | – |
| FCOPP | `FCOPP` | ED 80 | 2 | 40 | – |
| FCOPP | `FCOPP ST0, ST1` | ED 80 | 2 | 40 | – |
| FCOS | `FCOS` | ED 81 | 2 | 41 | – |
| FCOS | `FCOS ST0` | ED 81 | 2 | 41 | – |
| FDIV | `FDIV ST0, STn` | ED 88+b | 2 | 42 | – |
| FDIV | `FDIV STn` | ED 88+a | 2 | 42 | – |
| FENCE | `FENCE` | ED A5 | 2 | 184 | 8.00 |
| FILD | `FILD (HL)` | ED BC 48 | 3 | 204 | – |
| FINIT | `FINIT` | ED 82 | 2 | 43 | – |
| FIST | `FIST` | ED 83 | 2 | 44 | – |
| FISTP | `FISTP` | ED 84 | 2 | 45 | – |
| FLD | `FLD STn` | ED BC 10+a | 3 | 197 | – |
| FLD1 | `FLD1` | ED BC 42 | 3 | 202 | – |
| FLD32 | `FLD32 (HL)` | ED BC 49 | 3 | 205 | – |
| FLD64 | `FLD64 (HL)` | ED BC 4A | 3 | 206 | – |
| FLD80 | `FLD80 (HL)` | ED 85 | 2 | 46 | – |
| FLDL2 | `FLDL2` | ED 86 | 2 | 47 | – |
| FLDLG | `FLDLG` | ED 87 | 2 | 48 | – |
| FLDLN | `FLDLN` | ED 90 | 2 | 49 | – |
| FLDPI | `FLDPI` | ED 91 | 2 | 50 | – |
| FLDZ | `FLDZ` | ED 92 | 2 | 51 | – |
| FLN | `FLN` | ED 93 | 2 | 52 | – |
| FLN | `FLN ST0` | ED 93 | 2 | 52 | – |
| FLUSH | `FLUSH` | ED 94 | 2 | 53 | – |
| FMUL | `FMUL ST0, STn` | ED 98+b | 2 | 54 | – |
| FMUL | `FMUL STn` | ED 98+a | 2 | 54 | – |
| FREM | `FREM` | ED 95 | 2 | 55 | – |
| FREM1 | `FREM1` | ED 96 | 2 | 56 | – |
| FRINT | `FRINT` | ED BC 43 | 3 | 203 | – |
| FRSTR | `FRSTR (rr)` | ED AF 48+a | 3 | 194 | – |
| FSAVE | `FSAVE (rr)` | ED AF 08+a | 3 | 193 | – |
| FSIN | `FSIN` | ED 97 | 2 | 57 | – |
| FSIN | `FSIN ST0` | ED 97 | 2 | 57 | – |
| FSINC | `FSINC` | ED 10 | 2 | 58 | – |
| FSINC | `FSINC ST0` | ED 10 | 2 | 58 | – |
| FSP32 | `FSP32 (HL)` | ED BC 4C | 3 | 208 | – |
| FSP64 | `FSP64 (HL)` | ED BC 4E | 3 | 210 | – |
| FSQRT | `FSQRT` | ED 11 | 2 | 59 | – |
| FSQRT | `FSQRT ST0` | ED 11 | 2 | 59 | – |
| FST32 | `FST32 (HL)` | ED BC 4B | 3 | 207 | – |
| FST64 | `FST64 (HL)` | ED BC 4D | 3 | 209 | – |
| FST80 | `FST80 (HL)` | ED 12 | 2 | 60 | – |
| FSTP | `FSTP STn` | ED BC 18+a | 3 | 198 | – |
| FSTP8 | `FSTP8 (HL)` | ED 13 | 2 | 61 | – |
| FSTSW | `FSTSW` | ED 14 | 2 | 62 | – |
| FSUB | `FSUB ST0, STn` | ED 18+b | 2 | 63 | – |
| FSUB | `FSUB STn` | ED 18+a | 2 | 63 | – |
| FTAN | `FTAN` | ED 15 | 2 | 64 | – |
| FTAN | `FTAN ST0` | ED 15 | 2 | 64 | – |
| FXCH | `FXCH STn` | ED BC 08+a | 3 | 196 | – |
| FYL2P | `FYL2P` | ED 16 | 2 | 65 | – |
| FYL2P | `FYL2P ST0` | ED 16 | 2 | 65 | – |
| FYL2X | `FYL2X` | ED 17 | 2 | 66 | – |
| FYL2X | `FYL2X ST0` | ED 17 | 2 | 66 | – |
| INCL | `INCL rr` | ED 3E 41+a·8 | 3 | 19 | 8.00 |
| INCQ | `INCQ rr` | ED 3E 81+a·8 | 3 | 20 | 8.00 |
| INCW | `INCW rr` | ED 3E 01+a·8 | 3 | 18 | 8.00 |
| INL | `INL rr, (C)` | ED 27 41+a·8 | 3 | 164 | – |
| INQ | `INQ rr, (C)` | ED 27 81+a·8 | 3 | 165 | – |
| INW | `INW rr, (C)` | ED 27 01+a·8 | 3 | 163 | – |
| ISYNC | `ISYNC` | ED A6 | 2 | 185 | 8.00 |
| JP | `JP USER, (u4)` | ED B4+b | 2 | 175 | – |
| JPL | `JPL (rr)` | ED 2A 41+a·8 | 3 | 135 | 20.00 |
| JPL | `JPL cc, (rr)` | ED 2A 00+a·8+b | 3 | 136 | 20.00 taken / 12.00 not taken |
| JPL | `JPL cc, nnnn` | ED 2A 81+a·8 nnnn | 7 | 137 | 17.12 taken / 8.00 not taken |
| JPL | `JPL nnnn` | ED 2C nnnn | 6 | 138 | 16.75 |
| JPQ | `JPQ (rr)` | ED 2A C1+a·8 | 3 | 139 | 16.00 |
| JPQ | `JPQ cc, (rr)` | ED 2A 40+a·8+b | 3 | 140 | 16.00 taken / 8.00 not taken |
| JPQ | `JPQ cc, nnnnnnnn` | ED 2A C6+a·8 n×8 | 11 | 141 | 17.12 taken / 8.00 not taken |
| JPQ | `JPQ nnnnnnnn` | ED 2B n×8 | 10 | 142 | 16.75 |
| JRW | `JRW cc, ee` | ED 2A 01+a·8 ee | 5 | 133 | 17.12 taken / 8.00 not taken |
| JRW | `JRW ee` | ED 2D ee | 4 | 134 | 16.00 |
| LDCR | `LDCR k, rr` | ED 20 00+a·8+b | 3 | 180 | – |
| LDCTX | `LDCTX (rr)` | ED AE 48+a | 3 | 192 | – |
| LDL | `LDL (nnnnnnnn), rr` | ED 3A 01+b·8 n×8 | 11 | 79 | 15.00 |
| LDL | `LDL (Qxy+dd), rr` | ED DD/FD 06+b·8 dd | 5 | 80 | 15.00 |
| LDL | `LDL (Qxy+dd), nnnn` | ED DD/FD 46 dd nnnn | 9 | 81 | 15.00 |
| LDL | `LDL (rr), rr` | ED 3A C0+a·8+b | 3 | 84 | 11.00 |
| LDL | `LDL rr, (Qxy+dd)` | ED DD/FD 86+a·8 dd | 5 | 85 | 11.00 |
| LDL | `LDL rr, (rr)` | ED 3A 00+a·8+b | 3 | 87 | 11.00 |
| LDL | `LDL rr, nnnn` | ED 3A 41+a·8 nnnn | 7 | 88 | 8.00 |
| LDL | `LDL rr, rr` | ED 3A 40+a·8+b | 3 | 89 | 8.00 |
| LDL | `LDL rr, (nnnnnnnn)` | ED 3A 81+a·8 n×8 | 11 | 90 | 11.00 |
| LDQ | `LDQ (nnnnnnnn), rr` | ED 39 01+b·8 n×8 | 11 | 91 | 15.00 |
| LDQ | `LDQ (Qxy+dd), rr` | ED DD/FD 00+b·8 dd | 5 | 92 | 15.00 |
| LDQ | `LDQ (Qxy+dd), nnnnnnnn` | ED DD/FD 40 dd n×8 | 13 | 93 | 15.00 |
| LDQ | `LDQ (rr), rr` | ED 39 C0+a·8+b | 3 | 96 | 11.00 |
| LDQ | `LDQ rr, (Qxy+dd)` | ED DD/FD C6+a·8 dd | 5 | 97 | 11.00 |
| LDQ | `LDQ rr, (rr)` | ED 39 00+a·8+b | 3 | 99 | 11.00 |
| LDQ | `LDQ rr, nnnnnnnn` | ED 39 41+a·8 n×8 | 11 | 100 | 8.00 |
| LDQ | `LDQ rr, rr` | ED 39 40+a·8+b | 3 | 101 | 8.00 |
| LDQ | `LDQ rr, (nnnnnnnn)` | ED 39 81+a·8 n×8 | 11 | 102 | 11.00 |
| LDW | `LDW (nnnnnnnn), rr` | ED 3B 01+b·8 n×8 | 11 | 67 | 15.00 |
| LDW | `LDW (Qxy+dd), rr` | ED DD/FD 01+b·8 dd | 5 | 68 | 15.00 |
| LDW | `LDW (Qxy+dd), nn` | ED DD/FD 41 dd nn | 7 | 69 | 15.00 |
| LDW | `LDW (rr), rr` | ED 3B C0+a·8+b | 3 | 72 | 11.00 |
| LDW | `LDW rr, (Qxy+dd)` | ED DD/FD 81+a·8 dd | 5 | 73 | 11.00 |
| LDW | `LDW rr, (rr)` | ED 3B 00+a·8+b | 3 | 75 | 11.00 |
| LDW | `LDW rr, nn` | ED 3B 41+a·8 nn | 5 | 76 | 8.00 |
| LDW | `LDW rr, rr` | ED 3B 40+a·8+b | 3 | 77 | 8.00 |
| LDW | `LDW rr, (nnnnnnnn)` | ED 3B 81+a·8 n×8 | 11 | 78 | 11.00 |
| MFCR | `MFCR k` | ED 0A n | 3 | 292 | – |
| MLTSB | `MLTSB A, r` | ED 3F 08+b | 3 | 21 | 16.00 |
| MLTSB | `MLTSB AL, r` | ED 3F 08+b | 3 | 21 | 16.00 |
| MLTSB | `MLTSB r` | ED 3F 08+a | 3 | 21 | 16.00 |
| MLTSL | `MLTSL AX, rr` | ED 3F 88+b | 3 | 23 | 16.00 |
| MLTSL | `MLTSL rr` | ED 3F 88+a | 3 | 23 | 16.00 |
| MLTSQ | `MLTSQ QDE:QAX, rr` | ED 3F C8+b | 3 | 24 | 24.00 † |
| MLTSQ | `MLTSQ rr` | ED 3F C8+a | 3 | 24 | 24.00 † |
| MLTSW | `MLTSW HL, rr` | ED 3F 48+b | 3 | 22 | 21.00 |
| MLTSW | `MLTSW rr` | ED 3F 48+a | 3 | 22 | 21.00 |
| MLTUB | `MLTUB HL, r` | ED C1+b·8 | 2 | 25 | 16.00 |
| MLTUB | `MLTUB r` | ED C1+a·8 | 2 | 25 | 16.00 |
| MLTUL | `MLTUL AX, rr` | ED 3E 88+b | 3 | 29 | 16.00 |
| MLTUL | `MLTUL rr` | ED 3E 88+a | 3 | 29 | 16.00 |
| MLTUQ | `MLTUQ AX, rr` | ED 3E C8+b | 3 | 30 | 19.00 † |
| MLTUQ | `MLTUQ rr` | ED 3E C8+a | 3 | 30 | 19.00 † |
| MLTUW | `MLTUW HL, rr` | ED 3E 48+b | 3 | 28 | 21.00 |
| MLTUW | `MLTUW rr` | ED 3E 48+a | 3 | 28 | 21.00 |
| MTCR | `MTCR k` | ED 0C n | 3 | 293 | – |
| NEGB | `NEGB rr` | ED 26 01+a·8 | 3 | 295 | – |
| NEGL | `NEGL rr` | ED 26 81+a·8 | 3 | 173 | 8.00 |
| NEGQ | `NEGQ rr` | ED 26 C1+a·8 | 3 | 174 | 8.00 |
| NEGW | `NEGW rr` | ED 26 41+a·8 | 3 | 172 | 8.00 |
| ORL | `ORL rr, rr` | ED 37 40+a·8+b | 3 | 111 | 8.00 |
| ORQ | `ORQ rr, rr` | ED 37 80+a·8+b | 3 | 112 | 8.00 |
| ORW | `ORW rr, rr` | ED 37 00+a·8+b | 3 | 110 | 8.00 |
| OUTL | `OUTL (C), rr` | ED 27 46+b·8 | 3 | 167 | – |
| OUTQ | `OUTQ (C), rr` | ED 27 86+b·8 | 3 | 168 | – |
| OUTW | `OUTW (C), rr` | ED 27 06+b·8 | 3 | 166 | – |
| PGINV | `PGINV (rr)` | ED C4+a·8 | 2 | 186 | 8.00 |
| POPL | `POPL rr` | ED 38 08+a | 3 | 103 | 16.00 |
| POPQ | `POPQ rr` | ED 38 48+a | 3 | 104 | 16.00 |
| PROT | `PROT 0` | ED 00 | 2 | 176 | – |
| PROT | `PROT 1` | ED 01 | 2 | 176 | – |
| PROT | `PROT OFF` | ED 00 | 2 | 176 | – |
| PROT | `PROT ON` | ED 01 | 2 | 176 | – |
| PUSHL | `PUSHL rr` | ED 38 88+a | 3 | 105 | 15.00 |
| PUSHQ | `PUSHQ rr` | ED 38 C8+a | 3 | 106 | 15.00 |
| RESET | `RESET` | ED 25 | 2 | 177 | – |
| RESL | `RESL b, rr` | ED 32 00+a·8+b | 3 | 129 | 8.00 |
| RESW | `RESW b, rr` | ED 30 80+a·8+b | 3 | 128 | 8.00 |
| RETL | `RETL cc` | ED 03 40+a·8 | 3 | 122 | 35.00 taken / 16.00 not taken |
| RETL | `RETL` | ED 04 | 2 | 124 | 31.00 |
| RETQ | `RETQ cc` | ED 03 80+a·8 | 3 | 123 | 35.00 taken / 16.00 not taken |
| RETQ | `RETQ` | ED 05 | 2 | 125 | 31.00 |
| RLCL | `RLCL rr` | ED 06 86+a·8 | 3 | 157 | 8.00 |
| RLCQ | `RLCQ rr` | ED 06 C6+a·8 | 3 | 158 | 8.00 |
| RLCW | `RLCW rr` | ED 06 46+a·8 | 3 | 156 | 8.00 |
| RRCL | `RRCL rr` | ED 07 86+a·8 | 3 | 161 | 8.00 |
| RRCQ | `RRCQ rr` | ED 07 C6+a·8 | 3 | 162 | 8.00 |
| RRCW | `RRCW rr` | ED 07 46+a·8 | 3 | 160 | 8.00 |
| SARB | `SARB r` | ED 29 30+a | 3 | 143 | 8.00 |
| SARL | `SARL rr` | ED 29 B0+a | 3 | 145 | 8.00 |
| SARQ | `SARQ rr` | ED 29 F0+a | 3 | 146 | 8.00 |
| SARW | `SARW rr` | ED 29 70+a | 3 | 144 | 8.00 |
| SCALL | `SCALL n` | ED 22 n | 3 | 182 | – |
| SETL | `SETL b, rr` | ED 31 00+a·8+b | 3 | 131 | 8.00 |
| SETW | `SETW b, rr` | ED 2F 00+a·8+b | 3 | 130 | 8.00 |
| SHLB | `SHLB r` | ED 29 06+a·8 | 3 | 147 | 8.00 |
| SHLL | `SHLL rr` | ED 29 86+a·8 | 3 | 149 | 8.00 |
| SHLQ | `SHLQ rr` | ED 29 C6+a·8 | 3 | 150 | 8.00 |
| SHLW | `SHLW rr` | ED 29 46+a·8 | 3 | 148 | 8.00 |
| SHRB | `SHRB r` | ED 28 06+a·8 | 3 | 151 | 8.00 |
| SHRL | `SHRL rr` | ED 28 86+a·8 | 3 | 153 | 8.00 |
| SHRQ | `SHRQ rr` | ED 28 C6+a·8 | 3 | 154 | 8.00 |
| SHRW | `SHRW rr` | ED 28 46+a·8 | 3 | 152 | 8.00 |
| SLAB | `SLAB r` | ED 29 06+a·8 | 3 | 147 | 8.00 |
| SLAL | `SLAL rr` | ED 29 86+a·8 | 3 | 149 | 8.00 |
| SLAQ | `SLAQ rr` | ED 29 C6+a·8 | 3 | 150 | 8.00 |
| SLAW | `SLAW rr` | ED 29 46+a·8 | 3 | 148 | 8.00 |
| SRLB | `SRLB r` | ED 28 06+a·8 | 3 | 151 | 8.00 |
| SRLL | `SRLL rr` | ED 28 86+a·8 | 3 | 153 | 8.00 |
| SRLQ | `SRLQ rr` | ED 28 C6+a·8 | 3 | 154 | 8.00 |
| SRLW | `SRLW rr` | ED 28 46+a·8 | 3 | 152 | 8.00 |
| STCR | `STCR rr, k` | ED 21 00+b·8+a | 3 | 181 | 8.00 |
| STDBY | `STDBY` | ED 24 | 2 | 178 | – |
| SUBCL | `SUBCL rr, rr` | ED 3D 40+a·8+b | 3 | 32 | 8.00 |
| SUBCQ | `SUBCQ rr, rr` | ED 3D 80+a·8+b | 3 | 33 | 8.00 |
| SUBCW | `SUBCW rr, rr` | ED 3D 00+a·8+b | 3 | 31 | 8.00 |
| SUBL | `SUBL rr, rr` | ED 3C 40+a·8+b | 3 | 35 | 8.00 |
| SUBQ | `SUBQ rr, rr` | ED 3C 80+a·8+b | 3 | 36 | 8.00 |
| SUBW | `SUBW rr, rr` | ED 3C 00+a·8+b | 3 | 34 | 8.00 |
| SVCTX | `SVCTX (rr)` | ED AE 08+a | 3 | 191 | 180.00 |
| SYSRT | `SYSRT` | ED A4 | 2 | 183 | – |
| WAKE | `WAKE` | ED 23 | 2 | 179 | – |
| XCHGL | `XCHGL rr, (rr)` | ED AC 00+a·8+b | 3 | 187 | 27.00 |
| XCHGQ | `XCHGQ rr, (rr)` | ED AC 40+a·8+b | 3 | 188 | 27.00 |
| XORL | `XORL rr, rr` | ED 36 40+a·8+b | 3 | 114 | 8.00 |
| XORQ | `XORQ rr, rr` | ED 36 80+a·8+b | 3 | 115 | 8.00 |
| XORW | `XORW rr, rr` | ED 36 00+a·8+b | 3 | 113 | 8.00 |

### C.2 Z80 and R800 base set

Same encodings as the Z80 (including the undocumented instructions) and the R800 multiplications. In the Z80/R800 modes their time is set by the timing governor (chapter 6); measured native-mode examples are in D.2.

| Mnemonic | Syntax | Encoding (hex) | Bytes |
| --- | --- | --- | --- |
| ADC | `ADC (HL)` | 8E | 1 |
| ADC | `ADC (xy+d)` | DD/FD 8E d | 3 |
| ADC | `ADC A, (HL)` | 8E | 1 |
| ADC | `ADC A, (xy+d)` | DD/FD 8E d | 3 |
| ADC | `ADC A, n` | CE n | 2 |
| ADC | `ADC A, p` | DD/FD 88+b | 2 |
| ADC | `ADC A, r` | 88+b | 1 |
| ADC | `ADC HL, ss` | ED 4A+b·16 | 2 |
| ADC | `ADC n` | CE n | 2 |
| ADC | `ADC p` | DD/FD 88+a | 2 |
| ADC | `ADC r` | 88+a | 1 |
| ADD | `ADD (HL)` | 86 | 1 |
| ADD | `ADD (xy+d)` | DD/FD 86 d | 3 |
| ADD | `ADD A, (HL)` | 86 | 1 |
| ADD | `ADD A, (xy+d)` | DD/FD 86 d | 3 |
| ADD | `ADD A, n` | C6 n | 2 |
| ADD | `ADD A, p` | DD/FD 80+b | 2 |
| ADD | `ADD A, r` | 80+b | 1 |
| ADD | `ADD HL, ss` | 09+b·16 | 1 |
| ADD | `ADD n` | C6 n | 2 |
| ADD | `ADD p` | DD/FD 80+a | 2 |
| ADD | `ADD r` | 80+a | 1 |
| ADD | `ADD xy, BC` | DD/FD 09 | 2 |
| ADD | `ADD xy, DE` | DD/FD 19 | 2 |
| ADD | `ADD xy, SP` | DD/FD 39 | 2 |
| ADD | `ADD xy, xy` | DD/FD 29 | 2 |
| AND | `AND (HL)` | A6 | 1 |
| AND | `AND (xy+d)` | DD/FD A6 d | 3 |
| AND | `AND A, (HL)` | A6 | 1 |
| AND | `AND A, (xy+d)` | DD/FD A6 d | 3 |
| AND | `AND A, n` | E6 n | 2 |
| AND | `AND A, p` | DD/FD A0+b | 2 |
| AND | `AND A, r` | A0+b | 1 |
| AND | `AND n` | E6 n | 2 |
| AND | `AND p` | DD/FD A0+a | 2 |
| AND | `AND r` | A0+a | 1 |
| BIT | `BIT b, (HL)` | CB 46+a·8 | 2 |
| BIT | `BIT b, (xy+d)` | DD/FD CB d 46+a·8 | 4 |
| BIT | `BIT b, r` | CB 40+a·8+b | 2 |
| CALL | `CALL cc, nn` | C4+a·8 nn | 3 |
| CALL | `CALL nn` | CD nn | 3 |
| CCF | `CCF` | 3F | 1 |
| CP | `CP (HL)` | BE | 1 |
| CP | `CP (xy+d)` | DD/FD BE d | 3 |
| CP | `CP A, (HL)` | BE | 1 |
| CP | `CP A, (xy+d)` | DD/FD BE d | 3 |
| CP | `CP A, n` | FE n | 2 |
| CP | `CP A, p` | DD/FD B8+b | 2 |
| CP | `CP A, r` | B8+b | 1 |
| CP | `CP n` | FE n | 2 |
| CP | `CP p` | DD/FD B8+a | 2 |
| CP | `CP r` | B8+a | 1 |
| CPD | `CPD` | ED A9 | 2 |
| CPDR | `CPDR` | ED B9 | 2 |
| CPI | `CPI` | ED A1 | 2 |
| CPIR | `CPIR` | ED B1 | 2 |
| CPL | `CPL` | 2F | 1 |
| DAA | `DAA` | 27 | 1 |
| DEC | `DEC (HL)` | 35 | 1 |
| DEC | `DEC (xy+d)` | DD/FD 35 d | 3 |
| DEC | `DEC p` | DD/FD 05+a·8 | 2 |
| DEC | `DEC r` | 05+a·8 | 1 |
| DEC | `DEC ss` | 0B+a·16 | 1 |
| DEC | `DEC xy` | DD/FD 2B | 2 |
| DI | `DI` | F3 | 1 |
| DJNZ | `DJNZ e` | 10 e | 2 |
| EI | `EI` | FB | 1 |
| EX | `EX (SP), HL` | E3 | 1 |
| EX | `EX (SP), xy` | DD/FD E3 | 2 |
| EX | `EX AF, AF` | 08 | 1 |
| EX | `EX AF, AF'` | 08 | 1 |
| EX | `EX DE, HL` | EB | 1 |
| EXX | `EXX` | D9 | 1 |
| HALT | `HALT` | 76 | 1 |
| IM | `IM 0` | ED 46 | 2 |
| IM | `IM 1` | ED 56 | 2 |
| IM | `IM 2` | ED 5E | 2 |
| IN | `IN (C)` | ED 70 | 2 |
| IN | `IN A, (n)` | DB n | 2 |
| IN | `IN F, (C)` | ED 70 | 2 |
| IN | `IN r, (C)` | ED 40+a·8 | 2 |
| INC | `INC (HL)` | 34 | 1 |
| INC | `INC (xy+d)` | DD/FD 34 d | 3 |
| INC | `INC p` | DD/FD 04+a·8 | 2 |
| INC | `INC r` | 04+a·8 | 1 |
| INC | `INC ss` | 03+a·16 | 1 |
| INC | `INC xy` | DD/FD 23 | 2 |
| IND | `IND` | ED AA | 2 |
| INDR | `INDR` | ED BA | 2 |
| INI | `INI` | ED A2 | 2 |
| INIR | `INIR` | ED B2 | 2 |
| JP | `JP (HL)` | E9 | 1 |
| JP | `JP (xy)` | DD/FD E9 | 2 |
| JP | `JP cc, nn` | C2+a·8 nn | 3 |
| JP | `JP nn` | C3 nn | 3 |
| JR | `JR cc, e` | 20+a·8 e | 2 |
| JR | `JR e` | 18 e | 2 |
| LD | `LD (BC), A` | 02 | 1 |
| LD | `LD (DE), A` | 12 | 1 |
| LD | `LD (HL), n` | 36 n | 2 |
| LD | `LD (HL), r` | 70+b | 1 |
| LD | `LD (nn), A` | 32 nn | 3 |
| LD | `LD (nn), HL` | 22 nn | 3 |
| LD | `LD (nn), ss` | ED 43+b·16 nn | 4 |
| LD | `LD (nn), xy` | DD/FD 22 nn | 4 |
| LD | `LD (xy+d), n` | DD/FD 36 d n | 4 |
| LD | `LD (xy+d), r` | DD/FD 70+b d | 3 |
| LD | `LD A, (BC)` | 0A | 1 |
| LD | `LD A, (DE)` | 1A | 1 |
| LD | `LD A, (nn)` | 3A nn | 3 |
| LD | `LD A, I` | ED 57 | 2 |
| LD | `LD A, R` | ED 5F | 2 |
| LD | `LD HL, (nn)` | 2A nn | 3 |
| LD | `LD I, A` | ED 47 | 2 |
| LD | `LD R, A` | ED 4F | 2 |
| LD | `LD SP, HL` | F9 | 1 |
| LD | `LD SP, xy` | DD/FD F9 | 2 |
| LD | `LD p, n` | DD/FD 06+a·8 n | 3 |
| LD | `LD p, p` | DD/FD 40+a·8+b | 2 |
| LD | `LD p, r` | DD/FD 40+a·8+b | 2 |
| LD | `LD r, (HL)` | 46+a·8 | 1 |
| LD | `LD r, (xy+d)` | DD/FD 46+a·8 d | 3 |
| LD | `LD r, n` | 06+a·8 n | 2 |
| LD | `LD r, p` | DD/FD 40+a·8+b | 2 |
| LD | `LD r, r` | 40+a·8+b | 1 |
| LD | `LD ss, (nn)` | ED 4B+a·16 nn | 4 |
| LD | `LD ss, nn` | 01+a·16 nn | 3 |
| LD | `LD xy, (nn)` | DD/FD 2A nn | 4 |
| LD | `LD xy, nn` | DD/FD 21 nn | 4 |
| LDD | `LDD` | ED A8 | 2 |
| LDDR | `LDDR` | ED B8 | 2 |
| LDI | `LDI` | ED A0 | 2 |
| LDIR | `LDIR` | ED B0 | 2 |
| MLTUB | `MLTUB A, r` | ED C1+b·8 | 2 |
| MLTUW | `MLTUW HL, BC` | ED C3 | 2 |
| MLTUW | `MLTUW HL, SP` | ED F3 | 2 |
| MULUB | `MULUB A, r` | ED C1+b·8 | 2 |
| MULUW | `MULUW HL, BC` | ED C3 | 2 |
| MULUW | `MULUW HL, SP` | ED F3 | 2 |
| NEG | `NEG` | ED 44 | 2 |
| NOP | `NOP` | 00 | 1 |
| OR | `OR (HL)` | B6 | 1 |
| OR | `OR (xy+d)` | DD/FD B6 d | 3 |
| OR | `OR A, (HL)` | B6 | 1 |
| OR | `OR A, (xy+d)` | DD/FD B6 d | 3 |
| OR | `OR A, n` | F6 n | 2 |
| OR | `OR A, p` | DD/FD B0+b | 2 |
| OR | `OR A, r` | B0+b | 1 |
| OR | `OR n` | F6 n | 2 |
| OR | `OR p` | DD/FD B0+a | 2 |
| OR | `OR r` | B0+a | 1 |
| OTDR | `OTDR` | ED BB | 2 |
| OTIR | `OTIR` | ED B3 | 2 |
| OUT | `OUT (C), 0` | ED 71 | 2 |
| OUT | `OUT (C), r` | ED 41+b·8 | 2 |
| OUT | `OUT (n), A` | D3 n | 2 |
| OUTD | `OUTD` | ED AB | 2 |
| OUTI | `OUTI` | ED A3 | 2 |
| POP | `POP qq` | C1+a·16 | 1 |
| POP | `POP xy` | DD/FD E1 | 2 |
| PUSH | `PUSH qq` | C5+a·16 | 1 |
| PUSH | `PUSH xy` | DD/FD E5 | 2 |
| RES | `RES b, (HL)` | CB 86+a·8 | 2 |
| RES | `RES b, (xy+d)` | DD/FD CB d 86+a·8 | 4 |
| RES | `RES b, (xy+d), r` | DD/FD CB d 80+a·8+c | 4 |
| RES | `RES b, r` | CB 80+a·8+b | 2 |
| RET | `RET` | C9 | 1 |
| RET | `RET cc` | C0+a·8 | 1 |
| RETI | `RETI` | ED 4D | 2 |
| RETN | `RETN` | ED 45 | 2 |
| RL | `RL (HL)` | CB 16 | 2 |
| RL | `RL (xy+d)` | DD/FD CB d 16 | 4 |
| RL | `RL (xy+d), r` | DD/FD CB d 10+b | 4 |
| RL | `RL r` | CB 10+a | 2 |
| RLA | `RLA` | 17 | 1 |
| RLC | `RLC (HL)` | CB 06 | 2 |
| RLC | `RLC (xy+d)` | DD/FD CB d 06 | 4 |
| RLC | `RLC (xy+d), r` | DD/FD CB d 00+b | 4 |
| RLC | `RLC r` | CB 00+a | 2 |
| RLCA | `RLCA` | 07 | 1 |
| RLD | `RLD` | ED 6F | 2 |
| RR | `RR (HL)` | CB 1E | 2 |
| RR | `RR (xy+d)` | DD/FD CB d 1E | 4 |
| RR | `RR (xy+d), r` | DD/FD CB d 18+b | 4 |
| RR | `RR r` | CB 18+a | 2 |
| RRA | `RRA` | 1F | 1 |
| RRC | `RRC (HL)` | CB 0E | 2 |
| RRC | `RRC (xy+d)` | DD/FD CB d 0E | 4 |
| RRC | `RRC (xy+d), r` | DD/FD CB d 08+b | 4 |
| RRC | `RRC r` | CB 08+a | 2 |
| RRCA | `RRCA` | 0F | 1 |
| RRD | `RRD` | ED 67 | 2 |
| RST | `RST p` | C7+a·8 | 1 |
| SBC | `SBC (HL)` | 9E | 1 |
| SBC | `SBC (xy+d)` | DD/FD 9E d | 3 |
| SBC | `SBC A, (HL)` | 9E | 1 |
| SBC | `SBC A, (xy+d)` | DD/FD 9E d | 3 |
| SBC | `SBC A, n` | DE n | 2 |
| SBC | `SBC A, p` | DD/FD 98+b | 2 |
| SBC | `SBC A, r` | 98+b | 1 |
| SBC | `SBC HL, ss` | ED 42+b·16 | 2 |
| SBC | `SBC n` | DE n | 2 |
| SBC | `SBC p` | DD/FD 98+a | 2 |
| SBC | `SBC r` | 98+a | 1 |
| SCF | `SCF` | 37 | 1 |
| SET | `SET b, (HL)` | CB C6+a·8 | 2 |
| SET | `SET b, (xy+d)` | DD/FD CB d C6+a·8 | 4 |
| SET | `SET b, (xy+d), r` | DD/FD CB d C0+a·8+c | 4 |
| SET | `SET b, r` | CB C0+a·8+b | 2 |
| SLA | `SLA (HL)` | CB 26 | 2 |
| SLA | `SLA (xy+d)` | DD/FD CB d 26 | 4 |
| SLA | `SLA (xy+d), r` | DD/FD CB d 20+b | 4 |
| SLA | `SLA r` | CB 20+a | 2 |
| SLI | `SLI (HL)` | CB 36 | 2 |
| SLI | `SLI (xy+d)` | DD/FD CB d 36 | 4 |
| SLI | `SLI (xy+d), r` | DD/FD CB d 30+b | 4 |
| SLI | `SLI r` | CB 30+a | 2 |
| SLL | `SLL (HL)` | CB 36 | 2 |
| SLL | `SLL (xy+d)` | DD/FD CB d 36 | 4 |
| SLL | `SLL (xy+d), r` | DD/FD CB d 30+b | 4 |
| SLL | `SLL r` | CB 30+a | 2 |
| SRA | `SRA (HL)` | CB 2E | 2 |
| SRA | `SRA (xy+d)` | DD/FD CB d 2E | 4 |
| SRA | `SRA (xy+d), r` | DD/FD CB d 28+b | 4 |
| SRA | `SRA r` | CB 28+a | 2 |
| SRL | `SRL (HL)` | CB 3E | 2 |
| SRL | `SRL (xy+d)` | DD/FD CB d 3E | 4 |
| SRL | `SRL (xy+d), r` | DD/FD CB d 38+b | 4 |
| SRL | `SRL r` | CB 38+a | 2 |
| SUB | `SUB (HL)` | 96 | 1 |
| SUB | `SUB (xy+d)` | DD/FD 96 d | 3 |
| SUB | `SUB A, (HL)` | 96 | 1 |
| SUB | `SUB A, (xy+d)` | DD/FD 96 d | 3 |
| SUB | `SUB A, n` | D6 n | 2 |
| SUB | `SUB A, p` | DD/FD 90+b | 2 |
| SUB | `SUB A, r` | 90+b | 1 |
| SUB | `SUB n` | D6 n | 2 |
| SUB | `SUB p` | DD/FD 90+a | 2 |
| SUB | `SUB r` | 90+a | 1 |
| XOR | `XOR (HL)` | AE | 1 |
| XOR | `XOR (xy+d)` | DD/FD AE d | 3 |
| XOR | `XOR A, (HL)` | AE | 1 |
| XOR | `XOR A, (xy+d)` | DD/FD AE d | 3 |
| XOR | `XOR A, n` | EE n | 2 |
| XOR | `XOR A, p` | DD/FD A8+b | 2 |
| XOR | `XOR A, r` | A8+b | 1 |
| XOR | `XOR n` | EE n | 2 |
| XOR | `XOR p` | DD/FD A8+a | 2 |
| XOR | `XOR r` | A8+a | 1 |
<!-- END APPENDIX_C -->
