# R8064 — Datasheet (Version 0.0 Alpha)

## Appendix B — Instruction set tables

This appendix reproduces, by functional group, the instruction tables from the R8064 ODT file (mnemonic, operation, flags, binary encoding, hexadecimal bytes and timing). The detailed description of each instruction is in Appendix A, in the main tab.

**Legend.** Timing columns, in clock cycles, as in the source file: TZ and Z1 (Z80), TR and RW (R800), 64 and W6 (R8064). For instructions inherited from the Z80 the 64 and W6 columns are empty, as in the source; for R8064 extensions only the 64 and W6 columns are filled in. Flags: • unchanged; 3 affected according to the result; 0 and 1 forced; ? undefined; V overflow; P parity. Operands: n = 8-bit immediate; nn = 16-bit; imm32 and imm64 = 32- and 64-bit immediates; adr64 = 64-bit absolute address; rr and rr’ = registers of the indicated width. “--” marks a variable byte (operand) and “…” a sequence of bytes.

#### 8-bit load group

| Mnemonic | Operation | C Z P/V S N H | Binary | Hex | TZ | Z1 | TR | RW | 64 | W6 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| LD r,r' | r ← r' | • • • • • • | 01 r r' | -- | 04 | 05 | 01 | 01 |  |  |
| LD r,n | r ← n | • • • • • • | 00 r 110 · ← n → | -- -- | 07 | 08 | 02 | 02 |  |  |
| LD u,u' | u ← u' | • • • • • • | 11 011 101 · 01 u u' | DD -- | 08 | 10 | 02 | 02 |  |  |
| LD v,v' | v ← v' | • • • • • • | 11 111 101 · 01 v v' | FD -- | 08 | 10 | 02 | 02 |  |  |
| LD u,n | u ← n | • • • • • • | 11 011 101 · 00 u 110 · ← n → | DD -- -- | 11 | 13 | 03 | 03 |  |  |
| LD v,n | v ← n | • • • • • • | 11 111 101 · 00 v 110 · ← n → | FD -- -- | 11 | 13 | 03 | 03 |  |  |
| LD r,(HL) | r ← (HL) | • • • • • • | 01 r 110 | -- | 07 | 08 | 02 | 04 |  |  |
| LD r,(IX+d) | r ← (IX+d) | • • • • • • | 11 011 101 · 01 r 110 · ← d → | DD -- -- | 19 | 21 | 05 | 07 |  |  |
| LD r,(IY+d) | r ← (IY+d) | • • • • • • | 11 111 101 · 01 r 110 · ← d → | FD -- -- | 19 | 21 | 05 | 07 |  |  |
| LD (HL),r | (HL) ← r | • • • • • • | 01 110 r | -- | 07 | 08 | 02 | 04 |  |  |
| LD (IX+d),r | (IX+d) ← r | • • • • • • | 11 011 101 · 01 110 r · ← d → | DD -- -- | 19 | 21 | 05 | 07 |  |  |
| LD (IY+d),r | (IY+d) ← r | • • • • • • | 11 111 101 · 01 110 r · ← d → | FD -- -- | 19 | 21 | 05 | 07 |  |  |
| LD (HL),n | (HL) ← n | • • • • • • | 00 110 110 · ← n → | 36 -- | 10 | 11 | 03 | 05 |  |  |
| LD (IX+d),n | (IX+d) ← n | • • • • • • | 11 011 101 · 00 110 110 · ← d → · ← n → | DD 36 -- -- | 19 | 21 | 05 | 07 |  |  |
| LD (IY+d),n | (IY+d) ← n | • • • • • • | 11 111 101 · 00 110 110 · ← d → · ← n → | FD 36 -- -- | 19 | 21 | 05 | 07 |  |  |
| LD A,(BC) | A ← (BC) | • • • • • • | 00 001 010 | 0A | 07 | 08 | 02 | 04 |  |  |
| LD A,(DE) | A ← (DE) | • • • • • • | 00 011 010 | 1A | 07 | 08 | 02 | 04 |  |  |
| LD A,(nn) | A ← (nn) | • • • • • • | 00 111 010 · ← n1 → · ← n0 → | 3A -- -- | 13 | 14 | 04 | 06 |  |  |
| LD (BC),A | (BC) ← A | • • • • • • | 00 000 010 | 02 | 07 | 08 | 02 | 04 |  |  |
| LD (DE),A | (DE) ← A | • • • • • • | 00 010 010 | 12 | 07 | 08 | 02 | 04 |  |  |
| LD (nn),A | (nn) ← A | • • • • • • | 00 110 010 · ← n1 → · ← n0 → | 32 -- -- | 13 | 14 | 04 | 06 |  |  |
| LD A,I | A ← I | • 3 I 3 • • | 11 101 101 · 01 010 111 | ED 57 | 09 | 11 | 02 | 02 |  |  |
| LD A,R | A ← R | • 3 I 3 • • | 11 101 101 · 01 011 111 | ED 5F | 09 | 11 | 02 | 02 |  |  |
| LD I,A | I ← A | • • • • • • | 11 101 101 · 01 000 111 | ED 47 | 09 | 11 | 02 | 02 |  |  |
| LD R,A | R ← A | • • • • • • | 11 101 101 · 01 001 111 | ED 4F | 09 | 11 | 02 | 02 |  |  |

#### 16-bit load group

| Mnemonic | Operation | C Z P/V S N H | Binary | Hex | TZ | Z1 | TR | RW | 64 | W6 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| LD (nn),pp | (nn+1) ← ppH (nn) ← ppL | • • • • • • | 11 101 101 · 01 pp0 011 · ← n1 → · ← n0 → | ED -- -- -- | 20 | 22 | 06 | 08 |  |  |
| LD (nn),HL | (nn+1) ← H (nn) ← L | • • • • • • | 00 100 010 · ← n1 → · ← n0 → | 22 -- -- | 16 | 17 | 05 | 07 |  |  |
| LD (nn),IX | (nn+1) ← IXh (nn) ← IXl | • • • • • • | 11 011 101 · 00 100 010 · ← n1 → · ← n0 → | DD 22 -- -- | 20 | 22 | 06 | 08 |  |  |
| LD (nn),IY | (nn+1) ← IYh (nn) ← IYl | • • • • • • | 11 111 101 · 00 100 010 · ← n1 → · ← n0 → | FD 22 -- -- | 20 | 22 | 06 | 08 |  |  |
| LD pp,(nn) | ppH ← (nn+1) ppL ← (nn) | • • • • • • | 11 101 101 · 01 pp1 011 · ← n1 → · ← n0 → | ED -- -- -- | 20 | 22 | 06 | 08 |  |  |
| LD pp,nn | pp ← nn | • • • • • • | 00 pp0 001 · ← n1 → · ← n0 → | -- -- -- | 10 | 11 | 03 | 03 |  |  |
| LD HL,(nn) | H ← (nn+1) L ← (nn) | • • • • • • | 00 101 010 · ← n1 → · ← n0 → | 2A -- -- | 16 | 17 | 05 | 07 |  |  |
| LD IX,(nn) | IXh ← (nn+1) IXl ← (nn) | • • • • • • | 11 011 101 · 00 101 010 · ← n1 → · ← n0 → | DD 2A -- -- | 20 | 22 | 06 | 08 |  |  |
| LD IX,nn | IX ← nn | • • • • • • | 11 011 101 · 00 100 001 · ← n1 → · ← n0 → | DD 21 -- -- | 14 | 16 | 04 | 04 |  |  |
| LD IY,(nn) | IYh ← (nn+1) IYl ← (nn) | • • • • • • | 11 111 101 · 00 101 010 · ← n1 → · ← n0 → | FD 2A -- -- | 20 | 22 | 06 | 08 |  |  |
| LD IY,nn | IY ← nn | • • • • • • | 11 111 101 · 00 100 001 · ← n1 → · ← n0 → | FD 21 -- -- | 14 | 16 | 04 | 04 |  |  |
| LD SP,HL | SP ← HL | • • • • • • | 11 111 001 | F9 | 06 | 07 | 01 | 01 |  |  |
| LD SP,IX | SP ← IX | • • • • • • | 11 011 101 · 11 111 001 | DD F9 | 10 | 12 | 02 | 02 |  |  |
| LD SP,IY | SP ← IY | • • • • • • | 11 111 101 · 11 111 001 | FD F9 | 10 | 12 | 02 | 02 |  |  |
| LDW (adr64), rr \[rr = 16 bits\] | (adr64) ← rr | • • • • • • | 11 101 101 · 00 111 011 · 00 rr 001 · ← adr\_b7 → · … · ← adr\_b0 → | ED 3B -- -- -- |  |  |  |  | 3 | 10 |
| LDW (QIX+dd), nn | (QIX+dd) ← nn | • • • • • • | 11 101 101 · 11 011 101 · 01 rr 001 · ← d1 → · ← d0 → · ← n1 → · ← n0 → | ED DD -- -- -- -- -- |  |  |  |  | 2 | 6 |
| LDW (QIX+dd), rr \[rr = 16 bits\] | (QIX+dd) ← rr | • • • • • • | 11 101 101 · 11 011 101 · 00 rr 001 · ← d1 → · ← d0 → | ED DD -- -- -- |  |  |  |  | 2 | 6 |
| LDW (QIY+dd), nn | (QIY+dd) ← nn | • • • • • • | 11 101 101 · 11 111 101 · 01 rr 001 · ← d1 → · ← d0 → · ← n1 → · ← n0 → | ED FD -- -- -- -- -- |  |  |  |  | 2 | 6 |
| LDW (QIY+dd), rr \[rr = 16 bits\] | (QIY+dd) ← rr | • • • • • • | 11 101 101 · 11 111 101 · 00 rr 001 · ← d1 → · ← d0 → | ED FD -- -- -- |  |  |  |  | 2 | 6 |
| LDW (rr), rr’ \[rr = 64 bits\] \[rr’ = 16 bits\] | (rr) ← rr’ | • • • • • • | 11 101 101 · 00 111 011 · 11 rr rr’ | ED 3B -- |  |  |  |  | 2 | 6 |
| LDW rr, (adr64) \[rr = 16 bits\] | rr ← (adr64) | • • • • • • | 11 101 101 · 00 111 011 · 10 rr 001 · ← adr\_b7 → · … · ← adr\_b0 → | ED 3B -- -- -- |  |  |  |  | 3 | 12 |
| LDW rr, (QIX+dd) \[rr = 16 bits\] | rr ← (QIX+dd) | • • • • • • | 11 101 101 · 11 011 101 · 10 rr 001 · ← d1 → · ← d0 → | ED DD -- -- -- |  |  |  |  | 2 | 8 |
| LDW rr, (QIY+dd) \[rr = 16 bits\] | rr ← (QIY+dd) | • • • • • • | 11 101 101 · 11 111 101 · 10 rr 001 · ← d1 → · ← d0 → | ED FD -- -- -- |  |  |  |  | 2 | 8 |
| LDW rr, (rr’) \[rr = 16 bits\] \[rr’ = 64 bits\] | rr ← (rr’) | • • • • • • | 11 101 101 · 00 111 011 · 00 rr rr’ | ED 3B -- |  |  |  |  | 2 | 8 |
| LDW rr, nn | rr ← nn | • • • • • • | 11 101 101 · 00 111 011 · 01 rr 001 · ← n1 → · ← n0 → | ED 3B -- -- -- |  |  |  |  | 1 | 4 |
| LDW rr, rr’ \[rr/rr’= 16 bits\] | rr ← rr’ | • • • • • • | 11 101 101 · 00 111 011 · 01 rr rr’ | ED 3B -- |  |  |  |  | 1 | 4 |
| POP IX | IXh ← (SP+1) IXl ← (SP) SP ← SP + 2 | • • • • • • | 11 011 101 · 11 100 001 | DD E1 | 14 | 16 | 04 | 06 |  |  |
| POP IY | IYh ← (SP+1) IYl ← (SP) SP ← SP + 2 | • • • • • • | 11 111 101 · 11 100 001 | FD E1 | 14 | 16 | 04 | 06 |  |  |
| POP qq | qqH ← (SP+1) qqL ← (SP) SP ← SP + 2 | • • • • • • | 11 qq0 001 | -- | 10 | 11 | 03 | 05 |  |  |
| PUSH IX | (SP-2) ← IXl (SP-1) ← IXh SP ← SP – 2 | • • • • • • | 11 011 101 · 11 100 101 | DD E5 | 15 | 17 | 05 | 07 |  |  |
| PUSH IY | (SP-2) ← IYl (SP-1) ← IYh SP ← SP – 2 | • • • • • • | 11 111 101 · 11 100 101 | FD E5 | 15 | 17 | 05 | 07 |  |  |
| PUSH qq | (SP-2) ← qqL (SP-1) ← qqH SP ← SP – 2 | • • • • • • | 11 qq0 101 | -- | 11 | 12 | 04 | 06 |  |  |

#### 32-bit load group

| Mnemonic | Operation | C Z P/V S N H | Binary | Hex | TZ | Z1 | TR | RW | 64 | W6 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| LDL (adr64), rr \[rr = 32 bits\] | (adr64) ← rr | • • • • • • | 11 101 101 · 00 111 010 · 00 rr 001 · ← adr\_b7 → · … · ← adr\_b0 → | ED 3A -- -- … -- |  |  |  |  | 3 | 10 |
| LDL (QIX+dd), rr \[rr = 32 bits\] | (QIX+dd) ← rr | • • • • • • | 11 101 101 · 11 011 101 · 00 rr 001 · ← d1 → · ← d0 → | ED DD -- -- -- |  |  |  |  | 2 | 6 |
| LDL (QIX+dd),imm32 | (QIX+dd) ← imm32 | • • • • • • | 11 101 101 · 11 011 101 · 01 rr 001 · ← d1 → · ← d0 → · ← adr\_b3 → · … · ← adr\_b0 → | ED DD -- -- -- -- … -- |  |  |  |  | 3 | 10 |
| LDL (QIY+dd), rr \[rr = 32 bits\] | (QIY+dd) ← rr | • • • • • • | 11 101 101 · 11 111 101 · 00 rr 001 · ← d1 → · ← d0 → | ED FD -- -- -- |  |  |  |  | 2 | 6 |
| LDL (QIY+dd),imm32 | (QIY+dd) ← imm32 | • • • • • • | 11 101 101 · 11 111 101 · 01 rr 001 · ← d1 → · ← d0 → · ← imm\_b3 → · … · ← imm\_b0 → | ED FD -- -- -- -- … -- |  |  |  |  | 3 | 10 |
| LDL (rr), rr’ \[rr = 64 bits\] \[rr’ = 32 bits\] | (rr) ← rr’ | • • • • • • | 11 101 101 · 00 111 010 · 11 rr rr’ | ED 3A -- |  |  |  |  | 2 | 6 |
| LDL rr, (QIX+dd) (rr = 32 bits) | rr ← (QIX+dd) | • • • • • • | 11 101 101 · 11 011 101 · 10 rr 001 · ← d1 → · ← d0 → | ED DD -- -- -- |  |  |  |  | 2 | 8 |
| LDL rr, (QIY+dd) \[rr = 32 bits\] | rr ← (QIY+dd) | • • • • • • | 11 101 101 · 11 111 101 · 10 rr 001 · ← d1 → · ← d0 → | ED FD -- -- -- |  |  |  |  | 2 | 8 |
| LDL rr, (rr’) \[rr = 32 bits\] \[rr’ = 64 bits\] | rr ← (rr’) | • • • • • • | 11 101 101 · 00 111 010 · 00 rr rr’ | ED 3A -- |  |  |  |  | 2 | 8 |
| LDL rr, imm32 | rr ← imm32 | • • • • • • | 11 101 101 · 00 111 010 · 01 rr 001 · ← imm\_b3 → · … · ← imm\_b0 → | ED 3A -- -- … -- |  |  |  |  | 1 | 4 |
| LDL rr, rr’ \[rr/rr’ = 32 bits\] | rr ← rr’ | • • • • • • | 11 101 101 · 00 111 010 · 01 rr rr’ | ED 3A -- |  |  |  |  | 1 | 4 |
| LDL rr, (adr64) \[rr = 32 bits\] | rr ← (adr64) | • • • • • • | 11 101 101 · 00 111 010 · 10 rr 001 · ← adr\_b7 → · … · ← adr\_b0 → | ED 3A -- -- … -- |  |  |  |  | 3 | 12 |
| POPL rr | rrl ← (SP+3) … … rrh ← (SP) | • • • • • • | 11 101 101 · 00 111 000 · 00 001 rr | ED 38 -- |  |  |  |  | 2 | 8 |
| PUSHL rr | (SP+3) ← rrl … … (SP) ← rrh | • • • • • • | 11 101 101 · 00 111 000 · 10 001 rr | ED 38 -- |  |  |  |  | 2 | 6 |

#### 64-bit load group

| Mnemonic | Operation | C Z P/V S N H | Binary | Hex | TZ | Z1 | TR | RW | 64 | W6 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| LDQ (adr64), rr \[rr = 64 bits\] | (adr64) ← rr | • • • • • • | 11 101 101 · 00 111 001 · 00 rr 001 · ← adr\_b7 → · … · ← adr\_b0 → | ED 39 -- -- … -- |  |  |  |  | 3 | 10 |
| LDQ (QIX+dd), rr \[rr = 64 bits\] | (QIX+dd) ← rr | • • • • • • | 11 101 101 · 11 011 101 · 00 rr 000 · ← d1 → · ← d0 → | ED DD -- -- -- |  |  |  |  | 2 | 6 |
| LDQ (QIX+dd),imm64 | (QIX+dd)← imm64 | • • • • • • | 11 101 101 · 11 011 101 · 01 rr 000 · ← d1 → · ← d0 → · ← imm\_b7 → · … · ← imm\_b0 → | ED DD -- -- -- -- … -- |  |  |  |  | 3 | 10 |
| LDQ (QIY+dd), rr \[rr = 64 bits\] | (QIY+dd) ← rr | • • • • • • | 11 101 101 · 11 111 101 · 00 rr 000 · ← d1 → · ← d0 → | ED FD -- -- -- |  |  |  |  | 2 | 6 |
| LDQ (QIY+dd),imm64 | (QIY+dd)← imm64 | • • • • • • | 11 101 101 · 11 111 101 · 01 rr 000 · ← d1 → · ← d0 → · ← imm\_b7 → · … · ← imm\_b0 → | ED FD -- -- -- -- … -- |  |  |  |  | 3 | 10 |
| LDQ (rr), rr’ \[rr/rr’ = 64 bits\] | (rr) ← rr’ | • • • • • • | 11 101 101 · 00 111 001 · 11 rr rr’ | ED 39 -- |  |  |  |  | 2 | 6 |
| LDQ rr, (QIX+dd) (rr = 64 bits) | rr ← (QIX+dd) | • • • • • • | 11 101 101 · 11 011 101 · 10 rr 000 · ← d1 → · ← d0 → | ED DD -- -- -- |  |  |  |  | 2 | 8 |
| LDQ rr, (QIY+dd) \[rr = 64 bits\] | rr ← (QIY+dd) | • • • • • • | 11 101 101 · 11 111 101 · 10 rr 000 · ← d1 → · ← d0 → | ED FD -- -- -- |  |  |  |  | 2 | 8 |
| LDQ rr, (rr’) \[rr/rr’ = 64 bits\] | rr ← (rr’) | • • • • • • | 11 101 101 · 00 111 001 · 00 rr rr’ | ED 39 -- |  |  |  |  | 2 | 8 |
| LDQ rr, imm64 | rr ← imm64 | • • • • • • | 11 101 101 · 00 111 001 · 01 rr 001 · ← imm\_b7 → · … · ← imm\_b0 → | ED 39 -- -- … -- |  |  |  |  | 2 | 8 |
| LDQ rr, rr’ \[rr/rr’ = 64 bits\] | rr ← rr’ | • • • • • • | 11 101 101 · 00 111 001 · 01 rr rr’ | ED 39 -- |  |  |  |  | 1 | 4 |
| LDQ rr, (adr64) \[rr = 64 bits\] | rr ← (adr64) | • • • • • • | 11 101 101 · 00 111 001 · 10 rr 001 · ← adr\_b7 → · … · ← adr\_b0 → | ED 39 -- -- … -- |  |  |  |  | 3 | 12 |
| POPQ rr | rrl ← (SP+7) … … rrh ← (SP) | • • • • • • | 11 101 101 · 00 111 000 · 01 001 rr | ED 38 -- |  |  |  |  | 2 | 8 |
| PUSHQ rr | (SP+7) ← rrl … … (SP) ← rrh | • • • • • • | 11 101 101 · 00 111 000 · 11 001 rr | ED 38 -- |  |  |  |  | 2 | 6 |

#### 8-bit arithmetic group

| Mnemonic | Operation | C Z P/V S N H | Binary | Hex | TZ | Z1 | TR | RW | 64 | W6 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ADC (HL) | A←A+(HL)+CY | 3 3 V 3 0 3 | 10 001 110 | 8E | 07 | 08 | 02 | 04 | 1 | 4 |
| ADC (IX+d) | A← A+(IX+d)+CY | 3 3 V 3 0 3 | 11 011 101 · 10 001 110 · ←d→ | DD 8E -- | 19 | 21 | 05 | 07 | 1 | 4 |
| ADC (IY+d) | A← A+(IY+d)+CY | 3 3 V 3 0 3 | 11 111 101 · 10 001 110 · ←d→ | FD 8E -- | 19 | 21 | 05 | 07 | 1 | 4 |
| ADC n | A ← A+n+CY | 3 3 V 3 0 3 | 11 001 110 · ←n→ | CE -- | 07 | 08 | 02 | 02 | 1 | 4 |
| ADC p | A ← A+p+CY | 3 3 V 3 0 3 | 11 011 101 · 10 001 r | DD -- | 08 | 10 | 02 | 02 | 1 | 4 |
| ADC q | A ← A+q+CY | 3 3 V 3 0 3 | 11 111 101 · 10 001 r | FD -- | 08 | 10 | 02 | 02 | 1 | 4 |
| ADC r | A ← A+r+CY | 3 3 V 3 0 3 | 10 001 r | -- | 04 | 05 | 01 | 01 | 1 | 4 |
| ADD (HL) | A ← A+(HL) | 3 3 V 3 0 3 | 10 000 110 | 86 | 07 | 08 | 02 | 04 | 1 | 4 |
| ADD (IX+d) | A ← A+(IX+d) | 3 3 V 3 0 3 | 11 011 101 · 10 000 110 · ←d→ | DD 86 -- | 19 | 21 | 05 | 07 | 1 | 4 |
| ADD (IY+d) | A ← A+(IY+d) | 3 3 V 3 0 3 | 11 111 101 · 10 000 110 · ←d→ | FD 86 -- | 19 | 21 | 05 | 07 | 1 | 4 |
| ADD n | A ← A + n | 3 3 V 3 0 3 | 11 000 110 · ←n→ | C6 -- | 07 | 08 | 02 | 02 | 1 | 4 |
| ADD p | A ← A + p | 3 3 V 3 0 3 | 11 011 101 · 10 000 r | DD -- | 08 | 10 | 02 | 02 | 1 | 4 |
| ADD q | A ← A + q | 3 3 V 3 0 3 | 11 111 101 · 10 000 r | FD -- | 08 | 10 | 02 | 02 | 1 | 4 |
| ADD r | A ← A + r | 3 3 V 3 0 3 | 10 000 r | -- | 04 | 05 | 01 | 01 | 1 | 4 |
| DEC (HL) | (HL)←(HL)-1 | • 3 V 3 1 3 | 00 110 101 | 35 | 11 | 12 | 04 | 07 | 1 | 4 |
| DEC (IX+d) | (IX+d)←(IX+d)-1 | • 3 V 3 1 3 | 11 011 101 · 00 110 101 · ←d→ | DD 35 -- | 23 | 25 | 07 | 10 | 1 | 4 |
| DEC (IY+d) | (IY+d)← (IY+d)-1 | • 3 V 3 1 3 | 11 111 101 · 00 110 101 · ←d→ | FD 35 -- | 23 | 25 | 07 | 10 | 1 | 4 |
| DEC r | r ← r – 1 | • 3 V 3 1 3 | 00 r 101 | -- | 04 | 05 | 01 | 01 | 1 | 4 |
| DIVSB r | A ← AX / r AH ← AX % r (remainder) \[r = 8 bits\] | 0 3 3 3 0 ? | 11 101 101 · 00 111 101 · 00 001 r | ED 3D -- | -- | -- | -- | -- | 15 | 4 |
| DIVUB r | A ← AX / r AH ← AX % r (remainder) \[r = 8 bits\] | 0 3 3 3 0 ? | 11 101 101 · 00 111 100 · 00 001 r | ED 3C -- | -- | -- | -- | -- | 10 | 4 |
| INC (HL) | (HL)←(HL)+1 | • 3 V 3 0 3 | 00 110 100 | 34 | 11 | 12 | 04 | 07 | 1 | 4 |
| INC (IX+d) | (IX+d)← (IX+d)+1 | • 3 V 3 0 3 | 11 011 101 · 00 110 100 · ←d→ | DD 34 -- | 23 | 25 | 07 | 10 | 1 | 4 |
| INC (IY+d) | (IY+d)← (IY+d)+1 | • 3 V 3 0 3 | 11 111 101 · 00 110 100 · ←d→ | FD 34 -- | 23 | 25 | 07 | 10 | 1 | 4 |
| INC r | r ← r + 1 | • 3 V 3 0 3 | 00 r 100 | -- | 04 | 05 | 01 | 01 | 1 | 4 |
| MLTSB r | AX ← A \* r \[r = 8 bits\] | 3 3 3 3 0 ? | 11 101 101 · 00 111 111 · 00 001 r | ED 3F -- | -- | -- | -- | -- | 1 | 4 |
| MLTUB r | HL ← A \* r \[r = 8 bits\] | 3 3 ? 0 0 ? | 11 101 101 · 11 r 001 | ED -- | -- | -- | 14 | 14 | 1 | 4 |
| SBC (HL) | A←A-(HL)-CY | 3 3 V 3 1 3 | 10 011 110 | 9E | 07 | 08 | 02 | 04 | 1 | 4 |
| SBC (IX+d) | A← A-(IX+d)-CY | 3 3 V 3 1 3 | 11 011 101 · 10 011 110 · ←d→ | DD 9E -- | 19 | 21 | 05 | 07 | 1 | 4 |
| SBC (IY+d) | A← A-(IY+d)-CY | 3 3 V 3 1 3 | 11 111 101 · 10 011 110 · ←d→ | FD 9E -- | 19 | 21 | 05 | 07 | 1 | 4 |
| SBC n | A ← A-n-CY | 3 3 V 3 1 3 | 11 011 110 · ←n→ | DE -- | 07 | 08 | 02 | 02 | 1 | 4 |
| SBC p | A ← A-p-CY | 3 3 V 3 1 3 | 11 011 101 · 10 011 r | DD -- | 08 | 10 | 02 | 02 | 1 | 4 |
| SBC q | A ← A-q-CY | 3 3 V 3 1 3 | 11 111 101 · 10 011 r | FD -- | 08 | 10 | 02 | 02 | 1 | 4 |
| SBC r | A ← A-r-CY | 3 3 V 3 1 3 | 10 011 r | -- | 04 | 05 | 01 | 01 | 1 | 4 |
| SUB (HL) | A ← A – (HL) | 3 3 V 3 1 3 | 10 010 110 | 96 | 07 | 08 | 02 | 04 | 1 | 4 |
| SUB (IX+d) | A ← A -(IX+d) | 3 3 V 3 1 3 | 11 011 101 · 10 010 110 · ←d→ | DD 96 -- | 19 | 21 | 05 | 07 | 1 | 4 |
| SUB (IY+d) | A ← A -(IY+d) | 3 3 V 3 1 3 | 11 111 101 · 10 010 110 · ←d→ | FD 96 -- | 19 | 21 | 05 | 07 | 1 | 4 |
| SUB n | A ← A – n | 3 3 V 3 1 3 | 11 010 110 · ←n→ | D6 -- | 07 | 08 | 02 | 02 | 1 | 4 |
| SUB p | A ← A – p | 3 3 V 3 1 3 | 11 011 101 · 10 010 r | DD -- | 08 | 10 | 02 | 02 | 1 | 4 |
| SUB q | A ← A – q | 3 3 V 3 1 3 | 11 111 101 · 10 010 r | FD -- | 08 | 10 | 02 | 02 | 1 | 4 |
| SUB r | A ← A – r | 3 3 V 3 1 3 | 10 010 r | -- | 04 | 05 | 01 | 01 | 1 | 4 |

#### 16-bit arithmetic group

| Mnemonic | Operation | C Z P/V S N H | Binary | Hex | TZ | Z1 | TR | RW | 64 | W6 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ADC HL,pp | HL ← HL+pp+CY | 3 3 V 3 0 ? | 11 101 101 · 01 pp1 010 | ED -- | 15 | 17 | 02 | 02 |  |  |
| ADCW HL, rr | HL ← HL+rr+CY | 3 3 3 3 0 3 | 11 101 101 · 00 111 111 · 00 rr rr’ | ED 3F -- |  |  |  |  | 1 | 4 |
| ADD HL,pp | HL ← HL + pp | 3 • • • 0 ? | 00 pp1 001 | -- | 11 | 12 | 01 | 01 |  |  |
| ADD IX,xx | IX ← IX + xx | 3 • • • 0 ? | 11 011 101 · 00 xx1 001 | DD -- | 15 | 17 | 02 | 02 |  |  |
| ADD IY,yy | IY ← IY + yy | 3 • • • 0 ? | 11 111 101 · 00 yy1 001 | FD -- | 15 | 17 | 02 | 02 |  |  |
| ADDW rr, rr’ | rr ← rr + rr’ | 3 3 3 3 0 3 | 11 101 101 · 00 111 110 · 00 rr rr’ | ED 3E -- |  |  |  |  | 1 | 4 |
| DEC IX | IX ← IX – 1 | •••••• | 11 011 101 · 00 101 011 | DD 2B | 10 | 12 | 02 | 02 |  |  |
| DEC IY | IY ← IY – 1 | •••••• | 11 111 101 · 00 101 011 | FD 2B | 10 | 12 | 02 | 02 |  |  |
| DEC pp | pp ← pp – 1 | •••••• | 00 pp1 011 | -- | 06 | 07 | 01 | 01 |  |  |
| DECW rr | rr ← rr – 1 | • 3 3 3 1 3 | 11 101 101 · 00 111 100 · 00 rr 001 | ED 3C -- |  |  |  |  | 1 | 4 |
| DIVSW DX:AX, rr | AX ← DX:AX / rr DX ← DX:AX % rr (remainder) | 0 3 3 3 0 ? | 11 101 101 · 00 111 101 · 01 001 rr | ED 3D -- |  |  |  |  | 23 | 4 |
| DIVUW DX:AX, rr | AX ← DX:AX / rr DX ← DX:AX % rr (remainder) | 0 3 3 3 0 ? | 11 101 101 · 00 111 100 · 01 001 rr | ED 3C -- |  |  |  |  | 18 | 4 |
| INC IX | IX ← IX + 1 | •••••• | 11 011 101 · 00 100 011 | DD 23 | 10 | 12 | 02 | 02 |  |  |
| INC IY | IY ← IY + 1 | •••••• | 11 111 101 · 00 100 011 | FD 23 | 10 | 12 | 02 | 02 |  |  |
| INC pp | pp ← pp + 1 | •••••• | 00 pp0 011 | -- | 06 | 07 | 01 | 01 |  |  |
| INCW rr | rr ← rr + 1 | • 3 3 3 0 3 | 11 101 101 · 00 111 110 · 00 rr 001 | ED 3E -- |  |  |  |  | 1 | 4 |
| MLTSW HL,rr | LHL ← HL \* rr | 3 3 3 3 0 ? | 11 101 101 · 00 111 111 · 01 001 rr | ED 3F -- |  |  |  |  | 1 | 4 |
| MLTUW HL, BC | DE:HL ← HL \* BC | 3 3 ? 0 0 ? | 11 101 101 · 11 000 011 | ED C3 |  |  |  |  | 1 | 4 |
| MLTUW HL, rr | LHL ← HL \* rr | 3 3 ? 0 0 ? | 11 101 101 · 00 111 110 · 01 001 rr | ED 3E -- |  |  |  |  | 1 | 4 |
| MLTUW HL, SP | DE:HL ← HL \* SP | 3 3 ? 0 0 ? | 11 101 101 · 11 110 011 | ED F3 |  |  |  |  | 1 | 4 |
| SBC HL,pp | HL ← HL-pp-CY | 3 3 V 3 1 ? | 11 101 101 · 01 pp0 010 | ED -- | 15 | 17 | 02 | 02 |  |  |
| SUBCW rr, rr’ | rr ← rr - rr’– CY | 3 3 3 3 1 3 | 11 101 101 · 00 111 101 · 00 rr rr’ | ED 3D -- |  |  |  |  | 1 | 4 |
| SUBW rr, rr’ | rr ← rr – rr’ | 3 3 3 3 1 3 | 11 101 101 · 00 111 100 · 00 rr rr’ | ED 3C -- |  |  |  |  | 1 | 4 |

#### 32-bit arithmetic group

| Mnemonic | Operation | C Z P/V S N H | Binary | Hex | TZ | Z1 | TR | RW | 64 | W6 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ADCL LAX, rr \[rr=32 bits\] | LAX ← LAX + rr + CY | 3 3 3 3 0 3 | 11 101 101 · 00 111 111 · 01 rr rr’ | ED 3F -- | -- | -- | -- | -- | 1 | 4 |
| ADDL rr, rr’ \[rr,rr’= 32 bits\] | rr ← rr + rr’ | 3 3 3 3 0 3 | 11 101 101 · 00 111 110 · 01 rr rr’ | ED 3E -- | -- | -- | -- | -- | 1 | 4 |
| DECL rr \[rr=32 bits\] | rr ← rr – 1 | • 3 3 3 1 3 | 11 101 101 · 00 111 100 · 01 rr 001 | ED 3C -- | -- | -- | -- | -- | 1 | 4 |
| DIVSL QAX, rr \[rr=32 bits\] | QAX ← QAX / rr LDE ← QAX % rr (remainder) | 0 3 3 3 0 ? | 11 101 101 · 00 111 101 · 10 001 rr | ED 3D -- | -- | -- | -- | -- | 39 | 4 |
| DIVUL QAX, rr \[rr=32 bits\] | QAX ← QAX / rr LDE ← QAX % rr (remainder) | 0 3 3 3 0 ? | 11 101 101 · 00 111 100 · 10 001 rr | ED 3C -- | -- | -- | -- | -- | 34 | 4 |
| INCL rr \[rr=32 bits\] | rr ← rr + 1 | • 3 3 3 0 3 | 11 101 101 · 00 111 110 · 01 rr 001 | ED 3E -- | -- | -- | -- | -- | 1 | 4 |
| MLTSL QAX, rr \[rr=32 bits\] | QAX ← LAX \* rr | 3 3 3 3 0 ? | 11 101 101 · 00 111 111 · 10 001 rr | ED 3F -- | -- | -- | -- | -- | 1 | 4 |
| MLTUL LAX, rr \[rr=32 bits\] | QAX ← LAX \* rr | 3 3 ? 0 0 ? | 11 101 101 · 00 111 110 · 10 001 rr | ED 3E -- | -- | -- | -- | -- | 1 | 4 |
| SUBCL rr, rr’ \[rr,rr’= 32 bits\] | rr ← rr - rr’ – CY | 3 3 3 3 1 3 | 11 101 101 · 00 111 101 · 01 rr rr’ | ED 3D -- | -- | -- | -- | -- | 1 | 4 |
| SUBL rr, rr’ \[rr,rr’= 32 bits\] | rr ← rr – rr’ | 3 3 3 3 1 3 | 11 101 101 · 00 111 100 · 01 rr rr’ | ED 3C -- | -- | -- | -- | -- | 1 | 4 |

#### 64-bit arithmetic group

| Mnemonic | Operation | C Z P/V S N H | Binary | Hex | TZ | Z1 | TR | RW | 64 | W6 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ADCQ QAX, rr \[rr=64 bits\] | QAX ← QAX + rr + CY | 3 3 3 3 0 3 | 11 101 101 · 00 111 111 · 10 rr rr’ | ED 3F -- | -- | -- | -- | -- | 1 | 4 |
| ADDQ rr, rr’ \[rr,rr’= 64 bits\] | rr ← rr + rr’ \[rr = 64 bits\] | 3 3 3 3 0 3 | 11 101 101 · 00 111 110 · 10 rr rr’ | ED 3E -- | -- | -- | -- | -- | 1 | 4 |
| DECQ rr \[rr=64 bits\] | rr ← rr – 1 | • 3 3 3 1 3 | 11 101 101 · 00 111 100 · 10 rr 001 | ED 3C -- | -- | -- | -- | -- | 1 | 4 |
| DIVSQ QDE:QAX, rr \[rr=64 bits\] | QAX ← QDE:QAX / rr QDE ← QDE:QAX % rr (remainder) | 0 3 3 3 0 ? | 11 101 101 · 00 111 101 · 11 001 rr | ED 3D -- | -- | -- | -- | -- | 71 | 4 |
| DIVUQ QDE:QAX, rr \[rr=64 bits\] | QAX ← QDE:QAX / rr QDE ← QDE:QAX % rr (remainder) | 0 3 3 3 0 ? | 11 101 101 · 00 111 100 · 11 001 rr | ED 3C -- | -- | -- | -- | -- | 66 | 4 |
| INCQ rr \[rr=64 bits\] | rr ← rr + 1 | • 3 3 3 0 3 | 11 101 101 · 00 111 110 · 10 rr 001 | ED 3E -- | -- | -- | -- | -- | 1 | 4 |
| MLTSQ QDE:QAX, rr \[rr=64 bits\] | QDE:QAX ← QAX \* rr | 3 3 3 3 0 ? | 11 101 101 · 00 111 111 · 11 001 rr | ED 3F -- | -- | -- | -- | -- | 4 | 4 |
| MLTUQ QAX, rr \[rr=64 bits\] | QDE:QAX ← QAX \* rr | 3 3 ? 0 0 ? | 11 101 101 · 00 111 110 · 11 001 rr | ED 3E -- | -- | -- | -- | -- | 4 | 4 |
| SUBCQ rr, rr’ \[rr,rr’= 64 bits\] | rr ← rr - rr’ – CY | 3 3 3 3 1 3 | 11 101 101 · 00 111 101 · 10 rr rr’ | ED 3D -- | -- | -- | -- | -- | 1 | 4 |
| SUBQ rr, rr’ \[rr,rr’= 64 bits\] | rr ← rr – rr’ | 3 3 3 3 1 3 | 11 101 101 · 00 111 100 · 10 rr rr’ | ED 3C -- | -- | -- | -- | -- | 1 | 4 |

#### Floating-point arithmetic group (FPU)

| Mnemonic | Operation | C Z P/V S N H | Binary | Hex | TZ | Z1 | TR | RW | 64 | W6 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| FABS | ST0 ← \| ST0 \| | 3 3 3 3 | 11 101 101 10 111 100 01 000 001 | ED BC -- | -- | -- | -- | -- | 1 | 4 |
| FADD ST0, STn | ST0 ← ST0 + STn | 3 3 3 3 | 11 101 101 10 111 100 00 000 STn | ED BC -- | -- | -- | -- | -- | 6 | 4 |
| FCHS | ST0 ← – ST0 | 3 3 3 3 | 11 101 101 10 111 100 01 000 000 | ED BC -- | -- | -- | -- | -- | 1 | 4 |
| FCOM STn | ST0 – STn without popping the stack | 3 3 3 3 | 11 101 101 10 111 100 00 100 STn | ED BC -- | -- | -- | -- | -- | 3 | 4 |
| FCOPP ST0, ST1 | ST0 – ST1, pops both from the stack | 3 3 3 3 | 11 101 101 10 000 000 | ED 80 | -- | -- | -- | -- | 3 | 4 |
| FCOS ST0 | ST0 ← COS(ST0) | 3 3 3 3 | 11 101 101 10 000 001 | ED 81 | -- | -- | -- | -- | 70 | 4 |
| FDIV ST0, STn | ST0 ← ST0 / STn | 3 3 3 3 | 11 101 101 10 001 STn | ED -- | -- | -- | -- | -- | 68 | 4 |
| FILD (QHL) | ST0 ← (QHL) converted from a 64-bit integer | •••• | 11 101 101 10 111 100 01 001 000 | ED BC -- | -- | -- | -- | -- | 4 | 8 |
| FINIT | Resets the FPU to its initial state | 3 3 3 3 | 11 101 101 10 000 010 | ED 82 | -- | -- | -- | -- | 4 | 4 |
| FIST | Converts ST0 to a 16/32-bit integer and transfers 80 bits to (QHL) in RAM. | 3 3 3 3 | 11 101 101 10 000 011 | ED 83 | -- | -- | -- | -- | 4 | 8 |
| FISTP | Converts ST0 to a 16/32-bit integer and pops the stack | 3 3 3 3 | 11 101 101 10 000 100 | ED 84 | -- | -- | -- | -- | 4 | 8 |
| FLD STn | Pushes a copy of STn onto ST0 | •••• | 11 101 101 10 111 100 00 010 STn | ED BC -- | -- | -- | -- | -- | 2 | 4 |
| FLD1 | Loads +1.0 into ST0 | •••• | 11 101 101 10 111 100 01 000 010 | ED BC -- | -- | -- | -- | -- | 2 | 4 |
| FLD32 (QHL) | ST0 ← (QHL) converted from a 32-bit IEEE float | •••• | 11 101 101 10 111 100 01 001 001 | ED BC -- | -- | -- | -- | -- | 4 | 8 |
| FLD64 (QHL) | ST0 ← (QHL) converted from a 64-bit IEEE float | •••• | 11 101 101 10 111 100 01 001 010 | ED BC -- | -- | -- | -- | -- | 4 | 8 |
| FLD80 (QHL) | ST0 ← (QHL) converted from an 80-bit IEEE float | 3 3 3 3 | 11 101 101 10 000 101 | ED 85 | -- | -- | -- | -- | 3 | 12 |
| FLDL2 | Loads the value of log2(10) into ST0 | 3 3 3 3 | 11 101 101 10 000 110 | ED 86 | -- | -- | -- | -- | 2 | 4 |
| FLDLG | Loads the value of log10(2) into ST0 | 3 3 3 3 | 11 101 101 10 000 111 | ED 87 | -- | -- | -- | -- | 2 | 4 |
| FLDLN | Loads the value of ln(2) into ST0 | 3 3 3 3 | 11 101 101 10 010 000 | ED 90 | -- | -- | -- | -- | 2 | 4 |
| FLDPI | Loads the 80-bit value of PI into ST0 | 3 3 3 3 | 11 101 101 10 010 001 | ED 91 | -- | -- | -- | -- | 2 | 4 |
| FLDZ | Loads +0.0 into ST0 (clears the top of the stack) | 3 3 3 3 | 11 101 101 10 010 010 | ED 92 | -- | -- | -- | -- | 2 | 4 |
| FLN ST0 | ST0 ← LN(ST0) | 3 3 3 3 | 11 101 101 10 010 011 | ED 93 | -- | -- | -- | -- | 70 | 4 |
| FLUSH | Flushes the TLB cache and empties the pipeline | 3 3 3 3 | 11 101 101 10 010 100 | ED 94 | -- | -- | -- | -- | 2 | 4 |
| FMUL ST0, STn | ST0 ← ST0 \* STn | 3 3 3 3 | 11 101 101 10 011 STn | ED -- | -- | -- | -- | -- | 6 | 4 |
| FREM | ST0 ← ST0-(ST1 \* trunc(ST0 / ST1)) | 3 3 3 3 | 11 101 101 10 010 101 | ED 95 | -- | -- | -- | -- | 70 | 4 |
| FREM1 | ST0 ← ST0-(ST1 \* round(ST0 / ST1)) | 3 3 3 3 | 11 101 101 10 010 110 | ED 96 | -- | -- | -- | -- | 70 | 4 |
| FRINT | ST0 ← rounds ST0 to an integer | 3 3 3 3 | 11 101 101 10 111 100 01 000 011 | ED BC -- | -- | -- | -- | -- | 4 | 4 |
| FSIN ST0 | ST0 ← SIN(ST0) | 3 3 3 3 | 11 101 101 10 010 111 | ED 97 | -- | -- | -- | -- | 70 | 4 |
| FSINC ST0 | ST0 ← SIN(ST0) ST1 ← COS(ST0) | 3 3 3 3 | 11 101 101 00 010 000 | ED 10 | -- | -- | -- | -- | 70 | 4 |
| FSP32 (QHL) | (QHL) ← ST0 as a 32-bit float and pops the stack | •••• | 11 101 101 10 111 100 01 001 100 | ED BC -- | -- | -- | -- | -- | 4 | 6 |
| FSP64 (QHL) | (QHL) ← ST0 as a 64-bit float and pops the stack | •••• | 11 101 101 10 111 100 01 001 110 | ED BC -- | -- | -- | -- | -- | 4 | 6 |
| FSQRT ST0 | ST0 ← SQRT(ST0) | 3 3 3 3 | 11 101 101 00 010 001 | ED 11 | -- | -- | -- | -- | 68 | 4 |
| FST32 (QHL) | (QHL) ← ST0 as a 32-bit IEEE float (keeps the stack) | •••• | 11 101 101 10 111 100 01 001 011 | ED BC -- | -- | -- | -- | -- | 4 | 6 |
| FST64 (QHL) | (QHL) ← ST0 as a 64-bit IEEE float (keeps the stack) | •••• | 11 101 101 10 111 100 01 001 101 | ED BC -- | -- | -- | -- | -- | 4 | 6 |
| FST80 (QHL) | (QHL) ← ST0 as an 80-bit IEEE float (keeps the stack) | 3 3 3 3 | 11 101 101 00 010 010 | ED 12 | -- | -- | -- | -- | 3 | 8 |
| FSTP STn | STn ← ST0 and pops ST0 from the stack | •••• | 11 101 101 10 111 100 00 011 STn | ED BC -- | -- | -- | -- | -- | 2 | 4 |
| FSTP8 (QHL) | (QHL) ← ST0 (increments the stack) | 3 3 3 3 | 11 101 101 00 010 011 | ED 13 | -- | -- | -- | -- | 3 | 8 |
| FSTSW | Moves the FPU flags to the CPU | 3 3 3 3 | 11 101 101 00 010 100 | ED 14 | -- | -- | -- | -- | 1 | 4 |
| FSUB ST0, STn | ST0 ← ST0 – STn | 3 3 3 3 | 11 101 101 00 011 STn | ED -- | -- | -- | -- | -- | 6 | 4 |
| FTAN ST0 | ST0 ← TAN(ST0) | 3 3 3 3 | 11 101 101 00 010 101 | ED 15 | -- | -- | -- | -- | 138 | 4 |
| FXCH STn | ST0 <-> STn | •••• | 11 101 101 10 111 100 00 001 STn | ED BC -- | -- | -- | -- | -- | 2 | 4 |
| FYL2P ST0 | ST0 ← ST1 \* LOG2(ST0 + 1) | 3 3 3 3 | 11 101 101 00 010 110 | ED 16 | -- | -- | -- | -- | 76 | 4 |
| FYL2X ST0 | ST0 ← ST1 \* LOG2(ST0) | 3 3 3 3 | 11 101 101 00 010 111 | ED 17 | -- | -- | -- | -- | 76 | 4 |

#### Exchange group

| Mnemonic | Operation | C Z P/V S N H | Binary | Hex | TZ | Z1 | TR | RW | 64 | W6 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| EX DE,HL | DE ↔ HL | •••••• | 11 101 011 | EB | 04 | 05 | 01 | 01 |  |  |
| EX AF,AF' | AF ↔ AF' | •••••• | 00 001 000 | 08 | 04 | 05 | 01 | 01 |  |  |
| EXX | BC ↔ BC' DE ↔ DE' HL ↔ HL' | •••••• | 11 011 001 | D9 | 04 | 05 | 01 | 01 |  |  |
| EX (SP),HL | H ↔(SP+1) L ↔(SP) | •••••• | 11 100 011 | E3 | 19 | 20 | 05 | 07 |  |  |
| EX (SP),IX | IXh ↔(SP+1) IXl ↔(SP) | •••••• | 11 011 101 · 11 100 011 | DD E3 | 23 | 25 | 06 | 08 |  |  |
| EX (SP),IY | IYh ↔(SP+1) IYl ↔(SP) | •••••• | 11 111 101 · 11 100 011 | FD E3 | 23 | 25 | 06 | 08 |  |  |
| EXINI | Returns to the main group | •••••• | 11 101 101 · 00 001 001 | ED 09 |  |  |  |  |  |  |

#### Block transfer group

| Mnemonic | Operation | C Z P/V S N H | Binary | Hex | TZ | Z1 | TR | RW | 64 | W6 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| LDI | (DE) ← (HL) DE ← DE+1 HL ← HL+1 BC ← BC-1 | ••3•00 | 11 101 101 · 10 100 000 | ED A0 | 16 | 18 | 04 | 07 | 3 | 10 |
| LDIR | (DE) ← (HL) DE ← DE+1 HL ← HL+1 BC ← BC-1 {Until BC=0} | ••0•00 | 11 101 101 · 10 110 000 | ED B0 | 21 / 16 | 23 / 18 | 04 / 04 | ? / 07 | 3 | 10 |
| LDD | (DE) ← (HL) DE ← DE-1 HL ← HL-1 BC ← BC-1 | ••3•00 | 11 101 101 · 10 101 000 | ED A8 | 16 | 18 | 04 | 07 | 3 | 10 |
| LDDR | (DE) ← (HL) DE ← DE-1 HL ← HL-1 BC ← BC-1 {Until BC=0} | ••0•00 | 11 101 101 · 10 111 000 | ED B8 | 21 / 16 | 23 / 18 | 04 / 04 | ? / 07 | 3 | 10 |

NOTE. When two cycle counts are shown, they refer to the two conditions the instruction can take. Thus, for LDIR, the Z80 time in T-states is 21; when BC reaches 0, 16 T-states are spent.

#### Search group

| Mnemonic | Operation | C Z P/V S N H | Binary | Hex | TZ | Z1 | TR | RW | 64 | W6 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| CPI | A – (HL) HL ← HL+1 BC ← BC-1 | •33313 | 11 101 101 · 10 100 001 | ED A1 | 16 | 18 | 04 | 06 | 2 | 8 |
| CPIR | A – (HL) HL ← HL+1 BC ← BC-1 {Until BC=0 or A=(HL)} | •33313 | 11 101 101 · 10 110 001 | ED B1 | 21 / 16 | 23 / 18 | 05 / 05 | ? / 08 | 2 | 8 |
| CPD | A – (HL) HL ← HL-1 BC ← BC-1 | •33313 | 11 101 101 · 10 101 001 | ED A9 | 16 | 18 | 04 | 06 | 2 | 8 |
| CPDR | A – (HL) HL ← HL-1 BC ← BC-1 {Until BC=0 or A=(HL)} | •33313 | 11 101 101 · 10 111 001 | ED B9 | 21 / 16 | 23 / 18 | 05 / 05 | ? / 08 | 2 | 8 |

NOTE. When two cycle counts are shown, they refer to the two conditions the instruction can take. Thus, for CPIR, the Z80 time in T-states is 21; when BC reaches 0, 16 T-states are spent.

#### Compare group

| Mnemonic | Operation | C Z P/V S N H | Binary | Hex | TZ | Z1 | TR | RW | 64 | W6 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| CP A,r | A – r | 33V313 | 10 111 r | -- | 04 | 05 | 01 | 01 |  |  |
| CP A,p | A – p | 33V313 | 11 011 101 · 10 111 p | DD -- | 08 | 10 | 02 | 02 |  |  |
| CP A,q | A – q | 33V313 | 11 111 101 · 10 111 p | FD -- | 08 | 10 | 02 | 02 |  |  |
| CP A,(HL) | A – (HL) | 33V313 | 10 111 110 | BE | 07 | 08 | 02 | 04 |  |  |
| CP A,(IX+d) | A – (IX+d) | 33V313 | 11 011 101 · 10 111 110 · ← d → | DD BE -- | 19 | 21 | 05 | 07 |  |  |
| CP A,(IY+d) | A – (IY+d) | 33V313 | 11 111 101 · 10 111 110 · ← d → | FD BE -- | 19 | 21 | 05 | 07 |  |  |
| CP A,n | A – n | 33V313 | 11 111 110 · ← n → | FE -- | 07 | 08 | 02 | 02 |  |  |
| CMPW rr, rr’ | rr – rr’ \[rr,rr’ = 16 bits\] | 333313 | 11 101 101 00 000 010 00 rr rr’ | ED 02 -- |  |  |  |  | 1 | 4 |
| CMPL rr, rr’ | rr – rr’ \[rr,rr’ = 32 bits\] | 333313 | 11 101 101 00 000 010 01 rr rr’ | ED 02 -- |  |  |  |  | 1 | 4 |
| CMPQ rr, rr’ | rr – rr’ \[rr,rr’ = 64 bits\] | 333313 | 11 101 101 00 000 010 10 rr rr’ | ED 02 -- |  |  |  |  | 1 | 4 |

#### Logical group

| Mnemonic | Operation | C Z P/V S N H | Binary | Hex | TZ | Z1 | TR | RW | 64 | W6 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| AND r | A ← A ∧ r | 0 3 P 3 0 1 | 10 100 r | -- | 04 | 05 | 01 | 01 |  |  |
| AND p | A ← A ∧ p | 0 3 P 3 0 1 | 11 011 101 · 10 100 p | DD -- | 08 | 10 | 02 | 02 |  |  |
| AND q | A ← A ∧ q | 0 3 P 3 0 1 | 11 111 101 · 10 100 p | FD -- | 08 | 10 | 02 | 02 |  |  |
| AND (HL) | A ← A ∧ (HL) | 0 3 P 3 0 1 | 10 100 110 | A6 | 07 | 08 | 02 | 04 |  |  |
| AND (IX+d) | A ← A ∧(IX+d) | 0 3 P 3 0 1 | 11 011 101 · 10 100 110 · ← d → | DD A6 -- | 19 | 21 | 05 | 07 |  |  |
| AND (IY+d) | A ← A ∧(IY+d) | 0 3 P 3 0 1 | 11 111 101 · 10 100 110 · ← d → | FD A6 -- | 19 | 21 | 05 | 07 |  |  |
| AND n | A ← A ∧ n | 0 3 P 3 0 1 | 11 100 110 · ← n → | E6 -- | 07 | 08 | 02 | 02 |  |  |
| OR r | A ← A ∨ r | 0 3 P 3 0 1 | 10 110 r | -- | 04 | 05 | 01 | 01 |  |  |
| OR p | A ← A ∨ p | 0 3 P 3 0 1 | 11 011 101 · 10 110 p | DD -- | 08 | 10 | 02 | 02 |  |  |
| OR q | A ← A ∨ q | 0 3 P 3 0 1 | 11 111 101 · 10 110 p | FD -- | 08 | 10 | 02 | 02 |  |  |
| OR (HL) | A ← A ∨ (HL) | 0 3 P 3 0 1 | 10 110 110 | B6 | 07 | 08 | 02 | 04 |  |  |
| OR (IX+d) | A ← A ∨(IX+d) | 0 3 P 3 0 1 | 11 011 101 · 10 110 110 · ← d → | DD B6 -- | 19 | 21 | 05 | 07 |  |  |
| OR (IY+d) | A ← A ∨(IY+d) | 0 3 P 3 0 1 | 11 111 101 · 10 110 110 · ← d → | FD B6 -- | 19 | 21 | 05 | 07 |  |  |
| OR n | A ← A ∨ n | 0 3 P 3 0 1 | 11 110 110 · ← n → | F6 -- | 07 | 08 | 02 | 02 |  |  |
| XOR r | A ← A ⊕ r | 0 3 P 3 0 1 | 10 101 r | -- | 04 | 05 | 01 | 01 |  |  |
| XOR p | A ← A ⊕ p | 0 3 P 3 0 1 | 11 011 101 · 10 101 p | DD -- | 08 | 10 | 02 | 02 |  |  |
| XOR q | A ← A ⊕ q | 0 3 P 3 0 1 | 11 111 101 · 10 101 p | FD -- | 08 | 10 | 02 | 02 |  |  |
| XOR (HL) | A ⊕ (HL) | 0 3 P 3 0 1 | 10 101 110 | AE | 07 | 08 | 02 | 04 |  |  |
| XOR (IX+d) | A ← A ⊕(IX+d) | 0 3 P 3 0 1 | 11 011 101 · 10 101 110 · ← d → | DD AE -- | 19 | 21 | 05 | 07 |  |  |
| XOR (IY+d) | A ← A ⊕(IY+d) | 0 3 P 3 0 1 | 11 111 101 · 10 101 110 · ← d → | FD AE -- | 19 | 21 | 05 | 07 |  |  |
| XOR n | A ← A ⊕ n | 0 3 P 3 0 1 | 11 101 110 · ← n → | EE -- | 07 | 08 | 02 | 02 |  |  |
| ANDW rr, rr’ | rr ← rr & rr’ \[rr = 16 bits\] | 033301 | 11 101 101 · 00 111 000 · 00 rr rr’ | ED 38 -- |  |  |  |  | 1 | 4 |
| ANDL rr, rr’ | rr ← rr & rr’ \[rr = 32 bits\] | 033301 | 11 101 101 · 00 111 000 · 01 rr rr’ | ED 38 -- |  |  |  |  | 1 | 4 |
| ANDQ rr, rr’ | rr ← rr & rr’ \[rr = 64 bits\] | 033301 | 11 101 101 · 00 111 000 · 10 rr rr’ | ED 38 -- |  |  |  |  | 1 | 4 |
| ORW rr, rr’ | rr ← rr \| rr’ \[rr = 16 bits\] | 033300 | 11 101 101 · 00 110 111 · 00 rr rr’ | ED 37 -- |  |  |  |  | 1 | 4 |
| ORL rr, rr’ | rr ← rr \| rr’ \[rr = 32 bits\] | 033300 | 11 101 101 · 00 110 111 · 01 rr rr’ | ED 37 -- |  |  |  |  | 1 | 4 |
| ORQ rr, rr’ | rr ← rr \| rr’ \[rr = 64 bits\] | 033300 | 11 101 101 · 00 110 111 · 10 rr rr’ | ED 37 -- |  |  |  |  | 1 | 4 |
| XORW rr, rr’ | rr ← rr ^ rr’ \[rr = 16 bits\] | 033300 | 11 101 101 · 00 110 110 · 00 rr rr’ | ED 36 -- |  |  |  |  | 1 | 4 |
| XORL rr, rr’ | rr ← rr ^ rr’ \[rr = 32 bits\] | 033300 | 11 101 101 · 00 110 110 · 01 rr rr’ | ED 36 -- |  |  |  |  | 1 | 4 |
| XORQ rr, rr’ | rr ← rr ^ rr’ \[rr = 64 bits\] | 033300 | 11 101 101 · 00 110 110 · 10 rr rr’ | ED 36 -- |  |  |  |  | 1 | 4 |

#### Shift and rotate group

| Mnemonic | Operation | C Z P/V S N H | Binary | Hex | TZ | Z1 | TR | RW | 64 | W6 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| RLCA | CY7 0A CY 7 0 A | 3 • • • 0 0 | 00 000 111 | 07 | 04 | 05 | 01 | 01 |  |  |
| RLA | CY7 0A CY 7 0 A | 3 • • • 0 0 | 00 010 111 | 17 | 04 | 05 | 01 | 01 |  |  |
| RRCA | 7 0ACY 7 0 A CY | 3 • • • 0 0 | 00 001 111 | 0F | 04 | 05 | 01 | 01 |  |  |
| RRA | CY7 0A CY 7 0 A | 3 • • • 0 0 | 00 011 111 | 1F | 04 | 05 | 01 | 01 |  |  |
| RLC r | CY7 0r CY 7 0 r | 3 3 P 3 0 0 | 11 001 011 · 00 000 r | CB -- | 08 | 10 | 02 | 02 |  |  |
| RLC (HL) | CY7 0(HL) CY 7 0 (HL) | 3 3 P 3 0 0 | 11 001 011 · 00 000 110 | CB 06 | 15 | 17 | 05 | 08 |  |  |
| RLC (IX+d) | CY7 0(IX+d) CY 7 0 (IX+d) | 3 3 P 3 0 0 | 11 011 101 · 11 001 011 · ← d → · 00 000 110 | DD CB -- 06 | 23 | 25 | 07 | 10 |  |  |
| RLC (IY+d) | CY7 0(IY+d) CY 7 0 (IY+d) | 3 3 P 3 0 0 | 11 111 101 · 11 001 011 · ← d → · 00 000 110 | FD CB -- 06 | 23 | 25 | 07 | 10 |  |  |
| RL r | CY7 0r CY 7 0 r | 3 3 P 3 0 0 | 11 001 011 · 00 010 r | CB -- | 08 | 10 | 02 | 02 |  |  |
| RL (HL) | CY7 0(HL) CY 7 0 (HL) | 3 3 P 3 0 0 | 11 001 011 · 00 010 110 | CB 16 | 15 | 17 | 05 | 08 |  |  |
| RL (IX+d) | CY7 0(IX+d) CY 7 0 (IX+d) | 3 3 P 3 0 0 | 11 011 101 · 11 001 011 · ← d → · 00 010 110 | DD CB -- 16 | 23 | 25 | 07 | 10 |  |  |
| RL (IY+d) | CY7 0(IY+d) CY 7 0 (IY+d) | 3 3 P 3 0 0 | 11 111 101 · 11 001 011 · ← d → · 00 010 110 | FD CB -- 16 | 23 | 25 | 07 | 10 |  |  |
| RRC r | 7 0rCY 7 0 r CY | 3 3 P 3 0 0 | 11 001 011 · 00 001 r | CB -- | 08 | 10 | 02 | 02 |  |  |
| RRC (HL) | 7 0(HL)CY 7 0 (HL) CY | 3 3 P 3 0 0 | 11 001 011 · 00 001 110 | CB 0E | 15 | 17 | 05 | 08 |  |  |
| RRC (IX+d) | 7 0(IX+d)CY 7 0 (IX+d) CY | 3 3 P 3 0 0 | 11 011 101 · 11 001 011 · ← d → · 00 001 110 | DD CB -- 0E | 23 | 25 | 07 | 10 |  |  |
| RRC (IY+d) | 7 0(IY+d)CY 7 0 (IY+d) CY | 3 3 P 3 0 0 | 11 111 101 · 11 001 011 · ← d → · 00 001 110 | FD CB -- 0E | 23 | 25 | 07 | 10 |  |  |
| RR r | CY7 0r CY 7 0 r | 3 3 P 3 0 0 | 11 001 011 · 00 011 r | CB -- | 08 | 10 | 02 | 02 |  |  |
| RR (HL) | CY7 0(HL) CY 7 0 (HL) | 3 3 P 3 0 0 | 11 001 011 · 00 011 110 | CB 1E | 15 | 17 | 05 | 08 |  |  |
| RR (IX+d) | CY7 0(IX+d) CY 7 0 (IX+d) | 3 3 P 3 0 0 | 11 011 101 · 11 001 011 · ← d → · 00 011 110 | DD CB -- 1E | 23 | 25 | 07 | 10 |  |  |
| RR (IY+d) | CY7 0(IY+d) CY 7 0 (IY+d) | 3 3 P 3 0 0 | 11 111 101 · 11 001 011 · ← d → · 00 011 110 | FD CB -- 1E | 23 | 25 | 07 | 10 |  |  |
| SLA r | CY7 0r0 CY 7 0 r 0 | 3 3 P 3 0 0 | 11 001 011 · 00 100 r | CB -- | 08 | 10 | 02 | 02 |  |  |
| SLA (HL) | CY7 0(HL)0 CY 7 0 (HL) 0 | 3 3 P 3 0 0 | 11 001 011 · 00 100 110 | CB 26 | 15 | 17 | 05 | 08 |  |  |
| SLA (IX+d) | CY7 0(IX+d)0 CY 7 0 (IX+d) 0 | 3 3 P 3 0 0 | 11 011 101 · 11 001 011 · ← d → · 00 100 110 | DD CB -- 26 | 23 | 25 | 07 | 10 |  |  |
| SLA (IY+d) | CY7 0(IY+d)0 CY 7 0 (IY+d) 0 | 3 3 P 3 0 0 | 11 111 101 · 11 001 011 · ← d → · 00 100 110 | FD CB -- 26 | 23 | 25 | 07 | 10 |  |  |
| SRA r | CYr7 0 CY r 7 0 | 3 3 P 3 0 0 | 11 001 011 · 00 101 r | CB -- | 08 | 10 | 02 | 02 |  |  |
| SRA (HL) | CY(HL)7 0 CY (HL) 7 0 | 3 3 P 3 0 0 | 11 001 011 · 00 101 110 | CB 2E | 15 | 17 | 05 | 08 |  |  |
| SRA (IX+d) | CY(IX+d)7 0 CY (IX+d) 7 0 | 3 3 P 3 0 0 | 11 011 101 · 11 001 011 · ← d → · 00 101 110 | DD CB -- 2E | 23 | 25 | 07 | 10 |  |  |
| SRA (IY+d) | CY(IY+d)7 0 CY (IY+d) 7 0 | 3 3 P 3 0 0 | 11 111 101 · 11 001 011 · ← d → · 00 101 110 | FD CB -- 2E | 23 | 25 | 07 | 10 |  |  |
| SRL r | CYr7 00 CY r 7 0 0 | 3 3 P 3 0 0 | 11 001 011 · 00 111 r | CB -- | 08 | 10 | 02 | 02 |  |  |
| SRL (HL) | CY(HL)7 00 CY (HL) 7 0 0 | 3 3 P 3 0 0 | 11 001 011 · 00 111 110 | CB 3E | 15 | 17 | 05 | 08 |  |  |
| SRL (IX+d) | CY(IX+d)7 00 CY (IX+d) 7 0 0 | 3 3 P 3 0 0 | 11 011 101 · 11 001 011 · ← d → · 00 111 110 | DD CB -- 3E | 23 | 25 | 07 | 10 |  |  |
| SRL (IY+d) | CY(IY+d)7 00 CY (IY+d) 7 0 0 | 3 3 P 3 0 0 | 11 111 101 · 11 001 011 · ← d → · 00 111 110 | FD CB -- 3E | 23 | 25 | 07 | 10 |  |  |
| RLD | (HL)7 4 3 07 4 3 0A (HL) 7 4 3 0 7 4 3 0 A | • 3 P 3 0 0 | 11 101 101 · 01 101 111 | ED 6F | 18 | 20 | 05 | 08 |  |  |
| RRD | (HL)7 4 3 07 4 3 0A (HL) 7 4 3 0 7 4 3 0 A | • 3 P 3 0 0 | 11 101 101 · 01 100 111 | ED 67 | 18 | 20 | 05 | 08 |  |  |
| RLCW rr \[rr = 16 bits\] | CY15 0rr CY 15 0 rr | 333300 | 11 101 101 00 000 110 01 rr 110 | ED 06 -- |  |  |  |  | 1 | 4 |
| RLCL rr \[rr = 32 bits\] | CY31 0rr CY 31 0 rr | 333300 | 11 101 101 00 000 110 10 rr 110 | ED 06 -- |  |  |  |  | 1 | 4 |
| RLCQ rr \[rr = 64 bits\] | CY63 0rr CY 63 0 rr | 333300 | 11 101 101 00 000 110 11 rr 110 | ED 06 -- |  |  |  |  | 1 | 4 |
| RRCW rr \[rr = 16 bits\] | 15 0rrCY 15 0 rr CY | 333300 | 11 101 101 00 000 111 01 rr 110 | ED 07 -- |  |  |  |  | 1 | 4 |
| RRCL rr \[rr = 32 bits\] | 31 0rrCY 31 0 rr CY | 333300 | 11 101 101 00 000 111 10 rr 110 | ED 07 -- |  |  |  |  | 1 | 4 |
| RRCQ rr \[rr = 64 bits\] | 63 0rrCY 63 0 rr CY | 333300 | 11 101 101 00 000 111 11 rr 110 | ED 07 -- |  |  |  |  | 1 | 4 |
| SARB s \[s = 8 bits\] | sCY7 6 0 s CY 7 6 0 | 333300 | 11 101 101 · 00 101 001 · 00 110 s | ED 29 -- |  |  |  |  | 1 | 4 |
| SARW rr \[rr = 16 bits\] | rrCY15 14 0 rr CY 15 14 0 | 333300 | 11 101 101 · 00 101 001 · 01 110 rr | ED 29 -- |  |  |  |  | 1 | 4 |
| SARL rr \[rr = 32 bits\] | rrCY31 30 0 rr CY 31 30 0 | 333300 | 11 101 101 · 00 101 001 · 10 110 rr | ED 29 -- |  |  |  |  | 1 | 4 |
| SARQ rr \[rr = 64 bits\] | rrCY63 62 0 rr CY 63 62 0 | 333300 | 11 101 101 · 00 101 001 · 11 110 rr | ED 29 -- |  |  |  |  | 1 | 4 |
| SLAW rr \[rr = 16 bits\] | CY15 0rr0 CY 15 0 rr 0 | 333300 | 11 101 101 · 00 101 001 · 01 rr 110 | ED 29 -- |  |  |  |  | 1 | 4 |
| SLAL rr \[rr = 32 bits\] | CY31 0rr0 CY 31 0 rr 0 | 333300 | 11 101 101 · 00 101 001 · 10 rr 110 | ED 29 -- |  |  |  |  | 1 | 4 |
| SLAQ rr \[rr = 64 bits\] | CY63 0rr0 CY 63 0 rr 0 | 333300 | 11 101 101 · 00 101 001 · 11 rr 110 | ED 29 -- |  |  |  |  | 1 | 4 |
| SRLW rr \[rr = 16 bits\] | CYrr15 00 CY rr 15 0 0 | 333300 | 11 101 101 · 00 101 000 · 01 rr 110 | ED 28 -- |  |  |  |  | 1 | 4 |
| SRLL rr \[rr = 32 bits\] | CYrr31 00 CY rr 31 0 0 | 333300 | 11 101 101 · 00 101 000 · 10 rr 110 | ED 28 -- |  |  |  |  | 1 | 4 |
| SRLQ rr \[rr = 64 bits\] | CYrr63 00 CY rr 63 0 0 | 333300 | 11 101 101 · 00 101 000 · 11 rr 110 | ED 28 -- |  |  |  |  | 1 | 4 |

#### Bit set, reset and test group

| Mnemonic | Operation | C Z P/V S N H | Binary | Hex | TZ | Z1 | TR | RW | 64 | W6 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BIT b,r | Z ← rb | 0 3 ? ? 0 1 | 11 001 011 · 01 b r | CB -- | 08 | 10 | 02 | 02 |  |  |
| BIT b,(HL) | Z ← (HL)b | 0 3 ? ? 0 1 | 11 001 011 · 01 b 110 | CB -- | 12 | 14 | 03 | 05 |  |  |
| BIT b,(IX+d) | Z ← (IX+d)b | 0 3 ? ? 0 1 | 11 011 101 · 11 001 011 · ← d → · 01 b 110 | DD CB -- -- | 20 | 22 | 05 | 07 |  |  |
| BIT b,(IY+d) | Z ← (IY+d)b | 0 3 ? ? 0 1 | 11 111 101 · 11 001 011 · ← d → · 01 b 110 | FD CB -- -- | 20 | 22 | 05 | 07 |  |  |
| SET b,r | rb ← 1 | • • • • • • | 11 001 011 · 11 b r | CB -- | 08 | 10 | 02 | 02 |  |  |
| SET b,(HL) | (HL)b ← 1 | • • • • • • | 11 001 011 · 11 b 110 | CB -- | 15 | 17 | 05 | 08 |  |  |
| SET b,(IX+d) | (IX+d)b ← 1 | • • • • • • | 11 011 101 · 11 001 011 · ← d → · 11 b 110 | DD CB -- -- | 23 | 25 | 07 | 10 |  |  |
| SET b,(IY+d) | (IY+d)b ← 1 | • • • • • • | 11 111 101 · 11 001 011 · ← d → · 11 b 110 | FD CB -- -- | 23 | 25 | 07 | 10 |  |  |
| RES b,r | rb ← 0 | • • • • • • | 11 001 011 · 10 b r | CB -- | 08 | 10 | 02 | 02 |  |  |
| RES b,(HL) | (HL)b ← 0 | • • • • • • | 11 001 011 · 10 b 110 | CB -- | 15 | 17 | 05 | 08 |  |  |
| RES b,(IX+d) | (IX+d)b ← 0 | • • • • • • | 11 011 101 · 11 001 011 · ← d → · 10 b 110 | DD CB -- -- | 23 | 25 | 07 | 10 |  |  |
| RES b,(IY+d) | (IY+d)b ← 0 | • • • • • • | 11 111 101 · 11 001 011 · ← d → · 10 b 110 | FD CB -- -- | 23 | 25 | 07 | 10 |  |  |
| BITW b, tt | Z ← ttb \[tt = 16 bits\] | • 3 ? ? 0 1 | 11 101 101 · 00 110 000 · 0b bbb tt | ED 30 -- |  |  |  |  | 1 | 4 |
| BITL b, tt | Z ← ttb \[tt = 32 bits\] | • 3 ? ? 0 1 | 11 101 101 · 00 110 011 · bb bbb tt | ED 33 -- |  |  |  |  | 1 | 4 |
| RESW b, tt | ttb ← 0 \[tt = 16 bits\] | • • • • • • | 11 101 101 · 00 110 000 · 1b bbb tt | ED 30 -- |  |  |  |  | 1 | 4 |
| RESL b, tt | ttb ← 0 \[tt = 32 bits\] | • • • • • • | 11 101 101 · 00 110 010 · bb bbb tt | ED 32 -- |  |  |  |  | 1 | 4 |
| SETW b, tt | ttb ← 1 \[tt = 16 bits\] | • • • • • • | 11 101 101 · 00 101 111 · 0b bbb reg | ED 2F -- |  |  |  |  | 1 | 4 |
| SETL b, tt | ttb ← 1 \[tt = 32 bits\] | • • • • • • | 11 101 101 · 00 110 001 · bb bbb tt | ED 31 -- |  |  |  |  | 1 | 4 |

#### Jump group

| Mnemonic | Operation | C Z P/V S N H | Binary | Hex | TZ | Z1 | TR | RW | 64 | W6 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| DJNZ e | B ← B-1 If B≠0, PC ← PC + e + 2 | •••••• | 00 010 000 · ← e → | 10 -- | 08 / 13 | 09 / 14 | 02 / 03 | 02 / 03 |  |  |
| DJNZW ee | BC = BC-1 If BC ≠ 0, PC ← PC + ee + 2 (ee = -32768 \~ +32767) | •••••• | 11 101 101 · 00 101 110 · ← e1 → · ← e0 → | ED 2E -- -- |  |  |  |  | 1 | 4 |
| JP (HL) | PC ← HL | •••••• | 11 101 001 | E9 | 04 | 05 | 01 | 03 |  |  |
| JP (IX) | PC ← IX | •••••• | 11 011 101 · 11 101 001 | DD E9 | 08 | 10 | 02 | 04 |  |  |
| JP (IY) | PC ← IY | •••••• | 11 111 101 · 11 101 001 | FD E9 | 08 | 10 | 02 | 04 |  |  |
| JP cc,nn | If cc = true, PC ← nn | •••••• | 10 cc 011 · ← n1 → · ← n0 → | -- -- -- | 10 / 10 | 11 / 11 | 03 / 03 | 03 / 05 |  |  |
| JP nn | PC ← nn | •••••• | 11 000 011 · ← n1 → · ← n0 → | C3 -- -- | 10 | 11 | 03 | 05 |  |  |
| JPL (vv) | LPC ← (vv) \[vv = 32 bits\] | •••••• | 11 101 101 · 00 101 010 · 01 vv 001 | ED 2A -- |  |  |  |  | 1 | 4 |
| JPL cc, (vv) | If cc = true, LPC ← (vv) \[vv = 32 bits\] | •••••• | 11 101 101 · 00 101 010 · 00 cc vv | ED 2A -- |  |  |  |  | 1 | 4 |
| JPL cc, imm32 | If cc = true, LPC ← imm32 | •••••• | 11 101 101 · 00 101 010 · 10 cc 001 · ← imm\_b3 → · … · ← imm\_b0 → | ED 2A -- -- … -- |  |  |  |  | 1 | 4 |
| JPL imm32 | LPC ← imm32 | •••••• | 11 101 101 · 00 101 100 · ← imm\_b3 → · … · ← imm\_b0 → | ED 2C -- … -- |  |  |  |  | 1 | 4 |
| JPQ (vv) | QPC ← (vv) \[vv = 64 bits\] | •••••• | 11 101 101 · 00 101 010 · 11 vv 001 | ED 2A -- |  |  |  |  | 1 | 4 |
| JPQ cc, (vv) | If cc = true, QPC ← (vv) \[vv = 64 bits\] | •••••• | 11 101 101 · 00 101 010 · 01 cc vv | ED 2A -- |  |  |  |  | 1 | 4 |
| JPQ cc, imm64 | If cc = true, QPC ← imm64 | •••••• | 11 101 101 · 00 101 010 · 11 cc 110 · ← imm\_b7 → · … · ← imm\_b0 → | ED 2A -- -- … -- |  |  |  |  | 2 | 8 |
| JPQ imm64 | QPC ← imm64 | •••••• | 11 101 101 · 00 101 011 · ← imm\_b7 → · … · ← imm\_b0 → | ED 2B -- … -- |  |  |  |  | 2 | 8 |
| JR C,e | If CY = 1, PC ← PC + e + 2 | •••••• | 00 111 000 · ← e → | 38 -- | 07 / 12 | 08 / 13 | 02 / 03 | 02 / 03 |  |  |
| JR e | PC ← PC + e + 2 | •••••• | 00 011 000 · ← e → | 18 -- | 12 | 13 | 03 | 03 |  |  |
| JR NC,e | If CY = 0, PC ← PC + e + 2 | •••••• | 00 110 000 · ← e → | 30 -- | 07 / 12 | 08 / 13 | 02 / 03 | 02 / 03 |  |  |
| JR NZ,e | If Z = 0, PC ← PC + e + 2 | •••••• | 00 100 000 · ← e → | 20 -- | 07 / 12 | 08 / 13 | 02 / 03 | 02 / 03 |  |  |
| JR Z,e | If Z = 1, PC ← PC + e + 2 | •••••• | 00 101 000 · ← e → | 28 -- | 07 / 12 | 08 / 13 | 02 / 03 | 02 / 03 |  |  |
| JRW cc, ee | If cc = true, QPC ← PC + ee + 2 (ee = -32768 \~ +32767) | •••••• | 11 101 101 · 00 101 010 · 00 cc 001 · ← e1 → · ← e0 → | ED 2A -- -- -- |  |  |  |  | 1 | 4 |
| JRW ee | QPC ← PC + ee + 2 (ee = -32768 \~ +32767) | •••••• | 11 101 101 · 00 101 101 · ← e1 → · ← e0 → | ED 2D -- -- |  |  |  |  | 1 | 4 |

NOTE. When two cycle counts are shown, they refer to the two conditions the instruction can take. Thus, for JR C,e, the Z80 time in T-states is 7 when the condition is false and 12 when it is true.

#### Call and return group

| Mnemonic | Operation | C Z P/V S N H | Binary | Hex | TZ | Z1 | TR | RW | 64 | W6 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| CALL cc,nn | If cc=true, (SP-1) ← PCH (SP-2) ← PCL PC ← nn | •••••• | 11 cc 100 · ← n1 → · ← n0 → | CD -- -- | 10 / 17 | 11 / 18 | 03 / 05 | 07 / 03 / 08 |  |  |
| CALL nn | (SP-1) ← PCH (SP-2) ← PCL PC ← nn | •••••• | 11 001 101 · ← n1 → · ← n0 → | CD -- -- | 17 | 18 | 05 | 08 / 07 |  |  |
| CALLL (rr) | (LSP-1) ← LPC (LPC) ← (rr) \[rr = 32 bits\] | •••••• | 11 101 101 · 00 110 111 · 00 001 tt | ED 37 -- |  |  |  |  |  |  |
| CALLL cc,(rr) | If cc = true, (LSP-1) ← LPC (LPC) ← (rr) \[rr = 32 bits\] | •••••• | 11 101 101 · 00 110 111 · 11 cc tt | ED 37 -- |  |  |  |  |  |  |
| CALLL imm32 | (LSP-1) ← LPC (LPC) ← imm32 \[rr = 32 bits\] | •••••• | 11 101 101 · 00 110 101 · ← imm\_b3 → · … · ← imm\_b0 → | ED 35 -- -- -- |  |  |  |  | 2 | 6 |
| CALLQ (rr) | (QSP-1) ← QPC (QPC) ← (rr) \[rr = 64 bits\] | •••••• | 11 101 101 · 00 110 110 · 00 001 tt | ED 36 -- |  |  |  |  |  |  |
| CALLQ cc,(rr) | If cc = true, (QSP-1) ← QPC (QPC) ← (rr) \[rr = 64 bits\] | •••••• | 11 101 101 · 00 110 110 · 11 cc tt | ED 36 -- |  |  |  |  |  |  |
| CALLQ imm64 | (QSP-1) ← QPC (QPC) ← imm64 \[rr = 64 bits\] | •••••• | 11 101 101 · 00 110 100 · ← imm\_b7 → · … · ← imm\_b0 → | ED 34 -- -- -- |  |  |  |  | 3 | 10 |
| RET | PCH ← (SP+1) PCL ← (SP) | •••••• | 11 001 001 | C9 | 10 | 11 | 03 | 05 |  |  |
| RET cc | If cc = true, PCH ← (SP+1) PCL ← (SP) | •••••• | 11 cc 000 | -- | 05 / 11 | 06 / 12 | 01 / 03 | 01 / 05 |  |  |
| RETL cc (32-bit call) | If cc = true, LPC ← (LSP) LSP ← LSP + 4 | •••••• | 11 101 101 00 000 011 01 cc 000 | ED 03 -- |  |  |  |  | 2 | 8 |
| RETL (32-bit call) | LPC ← (LSP) LSP ← LSP + 4 | •••••• | 11 101 101 00 000 100 | ED 04 |  |  |  |  | 2 | 8 |
| RETI | Return from interrupt | •••••• | 11 101 101 · 01 001 101 | ED 4D | 14 | 16 | 05 | 07 |  |  |
| RETN | Return from non-maskable interrupt | •••••• | 11 101 101 · 01 000 101 | ED 45 | 14 | 16 | 05 | 07 |  |  |
| RETQ cc (64-bit call) | If cc = true, QPC ← (QSP) QSP ← QSP + 8 | •••••• | 11 101 101 00 000 011 10 cc 000 | ED 03 -- |  |  |  |  | 2 | 8 |
| RETQ (64-bit call) | QPC ← (QSP) QSP ← QSP + 8 | •••••• | 11 101 101 00 000 101 | ED 05 |  |  |  |  | 2 | 8 |
| RST p | (SP-1) ← PCH (SP-2) ← PCL PCH ← 0 PCL ← t\*8 | •••••• | 11 t 111 | -- | 11 | 12 | 04 | 06 / 07 |  |  |

NOTE. When two cycle counts are shown, they refer to the two conditions the instruction can take. Thus, for CALL cc,nn, the Z80 time in T-states is 10 when the condition is false and 17 when it is true.

NOTE 1. Tests showed that a CALL followed by a series of NOPs takes 8 cycles, while one followed by a RET or POP AF takes 12 cycles combined (7 for CALL + 5 for RET/POP AF). This also applies to RST (applies only to the highlighted RW value for the R800).

#### Input and output group

| Mnemonic | Operation | C Z P/V S N H | Binary | Hex | TZ | Z1 | TR | RW | 64 | W6 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| IN A,(n) | A ← (n) | •••••• | 11 011 011 · ← n → | DB -- | 11 | 12 | 03 | 10 / 09 |  |  |
| IN r,(C) | r ← (C) | • 3 P 3 0 3 | 11 101 101 · 01 r 000 | ED -- | 12 | 14 | 03 | 10 / 09 |  |  |
| IND | (HL) ← (C) B ← B-1 HL ← HL-1 | • 3 ? ? 1 ? | 11 101 101 · 10 101 010 | ED AA | 16 | 18 | 04 | 12 / 11 |  |  |
| INDR | (HL) ← (C) B ← B-1 HL ← HL-1 {Until B=0} | • 1 ? ? 1 ? | 11 101 101 · 10 111 010 | ED BA | 21 / 16 | 23 / 18 | 04 / 03 | ? / 11 / 12 |  |  |
| INI | (HL) ← (C) B ← B-1 HL ← HL+1 | • 3 ? ? 1 ? | 11 101 101 · 10 100 010 | ED A2 | 16 | 18 | 04 | 12 / 11 |  |  |
| INIR | (HL) ← (C) B ← B-1 HL ← HL+1 {Until B=0} | • 1 ? ? 1 ? | 11 101 101 · 10 110 010 | ED B2 | 21 / 16 | 23 / 18 | 04 / 03 | ? / 11 / 12 |  |  |
| INW rr, (C) | rr ← (C) \[rr = 16 bits\] | •••••• | 11 101 101 · 00 100 111 · 00 rr 001 | ED 27 -- |  |  |  |  | 1 | 5 |
| INL rr, (C) | rr ← (C) \[rr = 32 bits\] | •••••• | 11 101 101 · 00 100 111 · 01 rr 001 | ED 27 -- |  |  |  |  | 1 | 5 |
| INQ rr, (C) | rr ← (C) \[rr = 64 bits\] | •••••• | 11 101 101 · 00 100 111 · 10 rr 001 | ED 27 -- |  |  |  |  | 1 | 5 |
| OTDR | (C) ← (HL) B ← B-1 HL ← HL-1 {Until B=0} | • 1 ? ? 1 ? | 11 101 101 · 10 111 011 | ED BB | 21 / 16 | 23 / 18 | 04 / 03 | ? / 11 / 12 |  |  |
| OTIR | (C) ← (HL) B ← B-1 HL ← HL+1 {Until B=0} | • 1 ? ? 1 ? | 11 101 101 · 10 110 011 | ED B3 | 21 / 16 | 23 / 18 | 04 / 03 | ? / 11 / 12 |  |  |
| OUT (C),r | (C) ← r | •••••• | 11 101 101 · 01 r 001 | ED -- | 12 | 14 | 03 | 10 / 9 |  |  |
| OUT (n),A | (n) ← A | •••••• | 11 010 011 · ← n → | D3 -- | 11 | 12 | 03 | 10 / 9 |  |  |
| OUTD | (C) ← (HL) B ← B-1 HL ← HL-1 | • 3 ? ? 1 ? | 11 101 101 · 10 101 011 | ED AB | 16 | 18 | 04 | 12 / 11 |  |  |
| OUTI | (C) ← (HL) B ← B-1 HL ← HL+1 | • 3 ? ? 1 ? | 11 101 101 · 10 100 011 | ED A3 | 16 | 18 | 04 | 12 / 11 |  |  |
| OUTW (C), rr | (C) ← rr \[rr = 16 bits\] | •••••• | 11 101 101 · 00 100 111 · 00 rr 110 | ED 27 -- |  |  |  |  | 1 | 5 |
| OUTL (C), rr | (C) ← rr \[rr = 32 bits\] | •••••• | 11 101 101 · 00 100 111 · 01 rr 110 | ED 27 -- |  |  |  |  | 1 | 5 |
| OUTQ (C), rr | (C) ← rr \[rr = 64 bits\] | •••••• | 11 101 101 · 00 100 111 · 10 rr 110 | ED 27 -- |  |  |  |  | 1 | 5 |

NOTE. In the INI, IND, OUTI and OUTD instructions the Z flag is set when B-1=0; otherwise it is cleared.

NOTE 1. For IN A,(n) and OUT (n),A, n goes to A0\~A7 and A goes to A8\~A15. For the other instructions, C goes to A0\~A7 and B goes to A8\~A15.

NOTE 2. I/O instructions are aligned to the bus clock, so an extra wait is inserted depending on the alignment. This means that between two OUTs there may be a one-cycle reduction (applies only to the highlighted RW value for the R800).

#### General-purpose group

| Mnemonic | Operation | C Z P/V S N H | Binary | Hex | TZ | Z1 | TR | RW | 64 | W6 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| CCF | CY ← ¬CY | 1 • • • 0 ? | 00 111 111 | 3F | 04 | 05 | 01 | 01 |  |  |
| CPL | A ← ¬A | • • • • 1 1 | 00 101 111 | 2F | 04 | 05 | 01 | 01 |  |  |
| CPLB s | s ← .not.(s) \[s = 8 bits\] | ••••11 | 11 101 101 · 00 100 110 · 00 001 s | ED 26 -- |  |  |  |  | 1 | 4 |
| CPLW rr | rr ← .not.(rr) \[rr = 16 bits\] | ••••11 | 11 101 101 · 00 100 110 · 01 001 rr | ED 26 -- |  |  |  |  | 1 | 4 |
| CPLL rr | rr ← .not.(rr) \[rr = 32 bits\] | ••••11 | 11 101 101 · 00 100 110 · 10 001 rr | ED 26 -- |  |  |  |  | 1 | 4 |
| CPLQ rr | rr ← .not.(rr) \[rr = 64 bits\] | ••••11 | 11 101 101 · 00 100 110 · 11 001 rr | ED 26 -- |  |  |  |  | 1 | 4 |
| DAA | Converts A to BCD | 33P3•3 | 00 100 111 | 27 | 04 | 05 | 01 | 01 |  |  |
| NEG | A ← 0 - A | 33V313 | 11 101 101 · 01 000 100 | ED 44 | 08 | 10 | 02 | 02 |  |  |
| NEGB s \[s = 8 bits\] | s ← 0 - s | 33V313 | 11 101 101 · 00 100 110 · 00 s 001 | ED 26 -- |  |  |  |  | 1 | 4 |
| NEGW rr \[rr = 16 bits\] | rr ← 0 - rr | ••••11 | 11 101 101 · 00 100 110 · 01 rr 001 | ED 26 -- |  |  |  |  | 1 | 4 |
| NEGL rr \[rr = 32 bits\] | rr ← 0 - rr | ••••11 | 11 101 101 · 00 100 110 · 10 rr 001 | ED 26 -- |  |  |  |  | 1 | 4 |
| NEGQ rr \[rr = 64 bits\] | rr ← 0 - rr | ••••11 | 11 101 101 · 00 100 110 · 11 rr 001 | ED 26 -- | -- | -- | -- | -- | 1 | 4 |
| NOP | No action | • • • • • • | 00 000 000 | 00 | 04 | 05 | 01 | 01 |  |  |
| SCF | CY ← 1 | 1 • • • 0 0 | 00 110 111 | 37 | 04 | 05 | 01 | 01 |  |  |

#### Control, multiprocessing and multitasking group

| Mnemonic | Operation | C Z P/V S N H | Binary | Hex | TZ | Z1 | TR | RW | 64 | W6 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| CASL (rr’), rr \[rr = 32 bits; rr’ = 64 bits\] | If LAX = (rr’): (rr’) ← rr and Z ← 1 Else: LAX ← (rr’) and Z ← 0 (atomic) | •3•••• | 11 101 101 10 101 101 00 rr rr’ | ED AD -- |  |  |  |  | 3 | 10 |
| CASQ (rr’), rr \[rr = 64 bits; rr’ = 64 bits\] | If QAX = (rr’): (rr’) ← rr and Z ← 1 Else: QAX ← (rr’) and Z ← 0 (atomic) | •3•••• | 11 101 101 10 101 101 01 rr rr’ | ED AD -- |  |  |  |  | 3 | 10 |
| DI | IFF ← 0 | • • • • • • | 11 110 011 | F3 | 04 | 05 | 02 | 02 |  |  |
| EI | IFF ← 1 | • • • • • • | 11 111 011 | FB | 04 | 05 | 01 | 01 |  |  |
| FENCE | Drains the write buffer; orders earlier accesses before later ones | • • • • • • | 11 101 101 10 100 101 | ED A5 |  |  |  |  | 4 | 4 |
| FRSTR (uu) \[uu = 64 bits\] | Loads ST0–ST7 and CR13/CR14 from (uu) | • • • • • • | 11 101 101 10 101 111 01 001 uu | ED AF -- |  |  |  |  | 18 | 72 |
| FSAVE (uu) \[uu = 64 bits\] | Writes to (uu): ST0–ST7 (80 bits in 16 bytes) and CR13/CR14 | • • • • • • | 11 101 101 10 101 111 00 001 uu | ED AF -- |  |  |  |  | 18 | 38 |
| HALT | CPU halted | • • • • • • | 01 110 110 | 76 | 04 | 05 | 02 | 02 |  |  |
| IM 0 | Interrupt mode 0 | • • • • • • | 11 101 101 · 01 000 110 | ED 46 | 08 | 10 | 03 | 03 |  |  |
| IM 1 | Interrupt mode 1 | • • • • • • | 11 101 101 · 01 010 110 | ED 56 | 08 | 10 | 03 | 03 |  |  |
| IM 2 | Interrupt mode 2 | • • • • • • | 11 101 101 · 01 011 110 | ED 5E | 08 | 10 | 03 | 03 |  |  |
| ISYNC | Drains the pipeline and the fetch buffer (does not touch the TLB) | • • • • • • | 11 101 101 10 100 110 | ED A6 |  |  |  |  | 1 | 4 |
| JP USER, (uu) \[uu = 64 bits\] | Hands control to ordinary user software (P0). Opcode ED B4 to B7 (uu = BC, DE, HL, AX). | • • • • • • | 11 101 101 · 10 110 1uu | ED -- |  |  |  |  | 2 | 4 |
| LDCR bbbbb, rr \[rr = 64 bits\] \[bbbb = 0\~31\] | CR\[bbbbb\] ← rr Writes a control register (privileged) | • • • • • • | 11 101 101 00 100 000 bb bbb rr | ED 20 -- |  |  |  |  | 1 | 4 |
| LDCTX (uu) \[uu = 64 bits\] | Loads from (uu) the context saved by SVCTX and starts executing at the loaded QPC. | 333333 | 11 101 101 10 101 110 01 001 uu | ED AE -- |  |  |  |  | 17 | 68 |
| PGINV (uu) \[uu = 64 bits\] | Invalidates in the TLB the entry for the address in uu | • • • • • • | 11 101 101 11 uu 100 | ED -- |  |  |  |  | 2 | 4 |
| PROT | ON / OFF (ON = 01, OFF = 00) Turns protected mode on/off | • • • • • • | 11 101 101 · 00 000 00x | ED -- |  |  |  |  | 2 | 4 |
| RESET | Restarts the R8064 APU. Requires supervisor privilege (Ring 0) | 000000 | 11 101 101 · 00 100 101 | ED 25 |  |  |  |  | 8 | 4 |
| SCALL n \[n = 0\~255\] | Saves QPC in CR13 and state in CR14; CR11 ← n; enters supervisor mode; QPC ← CR09. | • • • • • • | 11 101 101 00 100 010 ←n→ | ED 22 -- |  |  |  |  | 2 | 4 |
| STCR rr, kk \[rr = 64 bits\] \[kk = 0\~31\] | rr ← CR\[kk\] Reads a control register | • • • • • • | 11 101 101 00 100 001 kk kkk rr | ED 21 -- |  |  |  |  | 1 | 4 |
| STDBY | Static power freeze (standby) | • • • • • • | 11 101 101 · 00 100 100 | ED 24 |  |  |  |  | 1 | 4 |
| SVCTX (uu) \[uu = 64 bits\] | Writes to (uu) the context: QAX, QBC, QDE, QHL, QWX, shadows, QIX, QIY, QSP, QPC, F, I, R (128 bytes) | • • • • • • | 11 101 101 10 101 110 00 001 uu | ED AE -- |  |  |  |  | 17 | 36 |
| SYSRT | QPC ← CR13; State ← CR14. Return from SCALL, exception and interrupt | 333333 | 11 101 101 10 100 100 | ED A4 |  |  |  |  | 2 | 4 |
| WAKE | Synchronous wake-up of the cores in multiprocessing mode. Requires supervisor mode (Ring 0). | • • • • • • | 11 101 101 · 00 100 011 | ED 23 |  |  |  |  | 2 | 4 |
| XCHGL rr, (rr’) \[rr = 32 bits\] \[rr’ = 64 bits\] | rr ↔ (rr’) (atomic exchange) | • • • • • • | 11 101 101 10 101 100 00 rr rr’ | ED AC -- |  |  |  |  | 3 | 10 |
| XCHGQ rr, (rr’) \[rr = 64 bits\] \[rr’ = 64 bits\] | rr ↔ (rr’) (atomic exchange) | • • • • • • | 11 101 101 10 101 100 01 rr rr’ | ED AC -- |  |  |  |  | 3 | 10 |

NOTE. IFF denotes the interrupt-enable flip-flop. CY denotes the carry flip-flop.
