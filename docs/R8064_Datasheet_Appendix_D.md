# R8064 - Datasheet (Preliminary) 2026

## Appendix D — Measured instruction timing (REV48, native mode)

<!-- BEGIN APPENDIX_D -->
Generated from `modulos/13_soc/bench/ref_rev48.json` (simulation of the REV48 RTL by `sim/meas/gen_meas.py`) by `sim/meas/gen_doc_tables.py`. Native mode, MMU off, code and data in the caches; each value is the average over 16 copies of the instruction in a loop, minus the same loop without it. Total = execution + wait. **Wait** = clocks in which the core stands still waiting for memory: *fetch* (the decoder lacks instruction bytes) or *data* (a load/store waits for the cache). Column **Board**: ✓ = the same value was measured on the Tang Nano 20K by the timing bench (256 of 256 cases, 2026-11-20). ns at 57.375 MHz (board crystal; × 1.0018 for 57.2727 MHz).

### D.1 R8064 instructions

| id | Instruction | Total | Execution | Fetch wait | Data wait | ns | Class | Board | Note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | ADCW HL, rr | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ALU 64-bit (1 cycle) | ✓ |  |
| 2 | ADCL EA, rr | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ALU 64-bit (1 cycle) | ✓ |  |
| 3 | ADCQ QA, rr | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ALU 64-bit (1 cycle) | ✓ |  |
| 4 | ADDW rr, rr’ | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ALU 64-bit (1 cycle) | ✓ |  |
| 5 | ADDL rr, rr’ | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ALU 64-bit (1 cycle) | ✓ |  |
| 6 | ADDQ rr, rr’ | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ALU 64-bit (1 cycle) | ✓ |  |
| 7 | DECW rr | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ALU 64-bit (1 cycle) | ✓ |  |
| 8 | DECL rr | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ALU 64-bit (1 cycle) | ✓ |  |
| 9 | DECQ rr | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ALU 64-bit (1 cycle) | ✓ |  |
| 10 | DIVSB AX, t | 28.00 | 28.00 | 0.00 | 0.00 | 488 | Iterative divider 1 bit/cycle | ✓ |  |
| 11 | DIVSW DX:AX, rr | 44.44 | 44.44 | 0.00 | 0.00 | 775 | Iterative divider 1 bit/cycle | ✓ |  |
| 12 | DIVSL QA, rr | 47.31 | 47.31 | 0.00 | 0.00 | 825 | Iterative divider 1 bit/cycle | ✓ |  |
| 13 | DIVSQ QDE:QA, rr | 78.31 | 78.31 | 0.00 | 0.00 | 1365 | Iterative divider 1 bit/cycle | n/a | not in the cartridge build (R8064_NO_MD64) |
| 14 | DIVUB AX, t | 25.00 | 25.00 | 0.00 | 0.00 | 436 | Iterative divider 1 bit/cycle | ✓ |  |
| 15 | DIVUW DX:AX, rr | 41.00 | 41.00 | 0.00 | 0.00 | 715 | Iterative divider 1 bit/cycle | ✓ |  |
| 16 | DIVUL QA, rr | 49.00 | 49.00 | 0.00 | 0.00 | 854 | Iterative divider 1 bit/cycle | ✓ |  |
| 17 | DIVUQ QDE:QA, rr | 86.00 | 86.00 | 0.00 | 0.00 | 1499 | Iterative divider 1 bit/cycle | n/a | not in the cartridge build (R8064_NO_MD64) |
| 18 | INCW rr | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ALU 64-bit (1 cycle) | ✓ |  |
| 19 | INCL rr | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ALU 64-bit (1 cycle) | ✓ |  |
| 20 | INCQ rr | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ALU 64-bit (1 cycle) | ✓ |  |
| 21 | MLTSB AL, u | 16.00 | 16.00 | 0.00 | 0.00 | 279 | Multiplier in DSP 18x18 | ✓ |  |
| 22 | MLTSW HL,rr | 21.00 | 21.00 | 0.00 | 0.00 | 366 | Multiplier in DSP 18x18 | ✓ |  |
| 23 | MLTSL QA, rr | 16.00 | 16.00 | 0.00 | 0.00 | 279 | Multiplier in DSP 18x18 | ✓ |  |
| 24 | MLTSQ QDE:QA, rr | 24.00 | 24.00 | 0.00 | 0.00 | 418 | Multiplier in DSP 18x18 | n/a | not in the cartridge build (R8064_NO_MD64) |
| 25 | MLTUB HL, u | 16.00 | 16.00 | 0.00 | 0.00 | 279 | Multiplier in DSP 18x18 | ✓ |  |
| 26 | MLTUW HL, BC | 21.00 | 21.00 | 0.00 | 0.00 | 366 | Multiplier in DSP 18x18 | ✓ |  |
| 27 | MLTUW HL, SP | 21.00 | 21.00 | 0.00 | 0.00 | 366 | Multiplier in DSP 18x18 | ✓ |  |
| 28 | MLTUW HL, rr | 21.00 | 21.00 | 0.00 | 0.00 | 366 | Multiplier in DSP 18x18 | ✓ |  |
| 29 | MLTUL EA, rr | 16.00 | 16.00 | 0.00 | 0.00 | 279 | Multiplier in DSP 18x18 | ✓ |  |
| 30 | MLTUQ QA, rr | 19.00 | 19.00 | 0.00 | 0.00 | 331 | Multiplier in DSP 18x18 | n/a | not in the cartridge build (R8064_NO_MD64) |
| 31 | SUBCW rr, rr’ | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ALU 64-bit (1 cycle) | ✓ |  |
| 32 | SUBCL rr, rr’ | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ALU 64-bit (1 cycle) | ✓ |  |
| 33 | SUBCQ rr, rr’ | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ALU 64-bit (1 cycle) | ✓ |  |
| 34 | SUBW rr, rr’ | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ALU 64-bit (1 cycle) | ✓ |  |
| 35 | SUBL rr, rr’ | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ALU 64-bit (1 cycle) | ✓ |  |
| 36 | SUBQ rr, rr’ | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ALU 64-bit (1 cycle) | ✓ |  |
| 37 | CPW rr, rr’ | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ALU 64-bit (1 cycle) | ✓ |  |
| 38 | CPL rr, rr’ | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ALU 64-bit (1 cycle) | ✓ |  |
| 39 | CPQ rr, rr’ | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ALU 64-bit (1 cycle) | ✓ |  |
| 67 | LDW (nnnnnnnn), rr | 15.00 | 12.00 | 0.00 | 3.00 | 261 | Store | ✓ |  |
| 68 | LDW (QIX+dd), rr | 15.00 | 12.00 | 0.00 | 3.00 | 261 | Store | ✓ |  |
| 69 | LDW (QIX+dd), nn | 15.00 | 12.00 | 0.00 | 3.00 | 261 | Store | ✓ |  |
| 72 | LDW (rr), rr’ | 11.00 | 8.00 | 0.00 | 3.00 | 192 | Store | ✓ |  |
| 73 | LDW rr, (QIX+dd) | 11.00 | 8.00 | 0.00 | 3.00 | 192 | Load | ✓ |  |
| 75 | LDW rr, (rr’) | 11.00 | 8.00 | 0.00 | 3.00 | 192 | Load | ✓ |  |
| 76 | LDW rr, nn | 8.00 | 8.00 | 0.00 | 0.00 | 139 | Register/immediate | ✓ |  |
| 77 | LDW rr, rr’ | 8.00 | 8.00 | 0.00 | 0.00 | 139 | Register/immediate | ✓ |  |
| 78 | LDW rr, (nnnnnnnn) | 11.00 | 8.00 | 0.00 | 3.00 | 192 | Load | ✓ |  |
| 79 | LDL (nnnnnnnn), rr | 15.00 | 12.00 | 0.00 | 3.00 | 261 | Store | ✓ |  |
| 80 | LDL (QIX+dd), rr | 15.00 | 12.00 | 0.00 | 3.00 | 261 | Store | ✓ |  |
| 81 | LDL (QIX+dd), nnnn | 15.00 | 12.00 | 0.00 | 3.00 | 261 | Store | ✓ |  |
| 84 | LDL (rr), rr’ | 11.00 | 8.00 | 0.00 | 3.00 | 192 | Store | ✓ |  |
| 85 | LDL rr, (QIX+dd) | 11.00 | 8.00 | 0.00 | 3.00 | 192 | Load | ✓ |  |
| 87 | LDL rr, (rr’) | 11.00 | 8.00 | 0.00 | 3.00 | 192 | Load | ✓ |  |
| 88 | LDL rr, nnnn | 8.00 | 8.00 | 0.00 | 0.00 | 139 | Register/immediate | ✓ |  |
| 89 | LDL rr, rr’ | 8.00 | 8.00 | 0.00 | 0.00 | 139 | Register/immediate | ✓ |  |
| 90 | LDL rr, (nnnnnnnn) | 11.00 | 8.00 | 0.00 | 3.00 | 192 | Load | ✓ |  |
| 91 | LDQ (nnnnnnnn), rr | 15.00 | 12.00 | 0.00 | 3.00 | 261 | Store | ✓ |  |
| 92 | LDQ (QIX+dd), rr | 15.00 | 12.00 | 0.00 | 3.00 | 261 | Store | ✓ |  |
| 93 | LDQ (QIX+dd), nnnnnnnn | 15.00 | 12.00 | 0.00 | 3.00 | 261 | Store | ✓ |  |
| 96 | LDQ (rr), rr’ | 11.00 | 8.00 | 0.00 | 3.00 | 192 | Store | ✓ |  |
| 97 | LDQ rr, (QIX+dd) | 11.00 | 8.00 | 0.00 | 3.00 | 192 | Load | ✓ |  |
| 99 | LDQ rr, (rr’) | 11.00 | 8.00 | 0.00 | 3.00 | 192 | Load | ✓ |  |
| 100 | LDQ rr, nnnnnnnn | 8.00 | 8.00 | 0.00 | 0.00 | 139 | Register/immediate | ✓ |  |
| 101 | LDQ rr, rr’ | 8.00 | 8.00 | 0.00 | 0.00 | 139 | Register/immediate | ✓ |  |
| 102 | LDQ rr, (nnnnnnnn) | 11.00 | 8.00 | 0.00 | 3.00 | 192 | Load | ✓ |  |
| 103 | POPL rr | 16.00 | 13.00 | 0.00 | 3.00 | 279 | Pop | ✓ |  |
| 104 | POPQ rr | 16.00 | 13.00 | 0.00 | 3.00 | 279 | Pop | ✓ |  |
| 105 | PUSHL rr | 15.00 | 12.00 | 0.00 | 3.00 | 261 | Push | ✓ |  |
| 106 | PUSHQ rr | 15.00 | 12.00 | 0.00 | 3.00 | 261 | Push | ✓ |  |
| 107 | ANDW rr, rr’ | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ALU 64-bit (1 cycle) | ✓ |  |
| 108 | ANDL rr, rr’ | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ALU 64-bit (1 cycle) | ✓ |  |
| 109 | ANDQ rr, rr’ | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ALU 64-bit (1 cycle) | ✓ |  |
| 110 | ORW rr, rr’ | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ALU 64-bit (1 cycle) | ✓ |  |
| 111 | ORL rr, rr’ | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ALU 64-bit (1 cycle) | ✓ |  |
| 112 | ORQ rr, rr’ | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ALU 64-bit (1 cycle) | ✓ |  |
| 113 | XORW rr, rr’ | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ALU 64-bit (1 cycle) | ✓ |  |
| 114 | XORL rr, rr’ | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ALU 64-bit (1 cycle) | ✓ |  |
| 115 | XORQ rr, rr’ | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ALU 64-bit (1 cycle) | ✓ |  |
| 116 | CALLL (rr) | 31.00 | 24.00 | 4.00 | 3.00 | 540 | Call | ✓ |  |
| 117 | CALLL cc,(rr) (taken) | 35.00 | 28.00 | 4.00 | 3.00 | 610 | Call | ✓ |  |
| 117 | CALLL cc,(rr) (not taken) | 16.00 | 12.00 | 4.00 | 0.00 | 279 | Call | ✓ |  |
| 118 | CALLL nnnn | 27.75 | 20.00 | 4.75 | 3.00 | 484 | Call | ✓ |  |
| 119 | CALLQ (rr) | 27.00 | 20.00 | 4.00 | 3.00 | 471 | Call | ✓ |  |
| 120 | CALLQ cc,(rr) (taken) | 31.00 | 24.00 | 4.00 | 3.00 | 540 | Call | ✓ |  |
| 120 | CALLQ cc,(rr) (not taken) | 16.00 | 12.00 | 4.00 | 0.00 | 279 | Call | ✓ |  |
| 121 | CALLQ nnnnnnnn | 27.75 | 20.00 | 4.75 | 3.00 | 484 | Call | ✓ |  |
| 122 | RETL cc (taken) | 35.00 | 25.00 | 7.00 | 3.00 | 610 | Return | ✓ | return alone (CALL+RET pair minus CALL) |
| 122 | RETL cc (not taken) | 16.00 | 12.00 | 4.00 | 0.00 | 279 | Return | ✓ | return alone (CALL+RET pair minus CALL) |
| 123 | RETQ cc (taken) | 35.00 | 25.00 | 7.00 | 3.00 | 610 | Return | ✓ | return alone (CALL+RET pair minus CALL) |
| 123 | RETQ cc (not taken) | 16.00 | 12.00 | 4.00 | 0.00 | 279 | Return | ✓ | return alone (CALL+RET pair minus CALL) |
| 124 | RETL | 31.00 | 21.00 | 7.00 | 3.00 | 540 | Return | ✓ | return alone (CALL+RET pair minus CALL) |
| 125 | RETQ | 31.00 | 21.00 | 7.00 | 3.00 | 540 | Return | ✓ | return alone (CALL+RET pair minus CALL) |
| 126 | BITW bbbb, tt | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ALU/bit (1 cycle) | ✓ |  |
| 127 | BITL bbbbb, tt | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ALU/bit (1 cycle) | ✓ |  |
| 128 | RESW bbbb, tt | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ALU/bit (1 cycle) | ✓ |  |
| 129 | RESL bbbbb, tt | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ALU/bit (1 cycle) | ✓ |  |
| 130 | SETW bbbb, tt | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ALU/bit (1 cycle) | ✓ |  |
| 131 | SETL bbbbb, tt | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ALU/bit (1 cycle) | ✓ |  |
| 132 | DJNZW nn | 20.00 | 16.00 | 4.00 | 0.00 | 349 | Branch | ✓ |  |
| 133 | JRW cc, nn (taken) | 17.12 | 12.00 | 5.12 | 0.00 | 298 | Branch | ✓ |  |
| 133 | JRW cc, nn (not taken) | 8.00 | 8.00 | 0.00 | 0.00 | 139 | Branch | ✓ |  |
| 134 | JRW nn | 16.00 | 12.00 | 4.00 | 0.00 | 279 | Branch | ✓ |  |
| 135 | JPL (vv) | 20.00 | 16.00 | 4.00 | 0.00 | 349 | Branch | ✓ |  |
| 136 | JPL cc, (vv) (taken) | 20.00 | 16.00 | 4.00 | 0.00 | 349 | Branch | ✓ |  |
| 136 | JPL cc, (vv) (not taken) | 12.00 | 12.00 | 0.00 | 0.00 | 209 | Branch | ✓ |  |
| 137 | JPL cc, nnnn (taken) | 17.12 | 12.00 | 5.12 | 0.00 | 298 | Branch | ✓ |  |
| 137 | JPL cc, nnnn (not taken) | 8.00 | 8.00 | 0.00 | 0.00 | 139 | Branch | ✓ |  |
| 138 | JPL nnnn | 16.75 | 12.00 | 4.75 | 0.00 | 292 | Branch | ✓ |  |
| 139 | JPQ (vv) | 16.00 | 12.00 | 4.00 | 0.00 | 279 | Branch | ✓ |  |
| 140 | JPQ cc, (vv) (taken) | 16.00 | 12.00 | 4.00 | 0.00 | 279 | Branch | ✓ |  |
| 140 | JPQ cc, (vv) (not taken) | 8.00 | 8.00 | 0.00 | 0.00 | 139 | Branch | ✓ |  |
| 141 | JPQ cc, nnnnnnnn (taken) | 17.12 | 12.00 | 5.12 | 0.00 | 298 | Branch | ✓ |  |
| 141 | JPQ cc, nnnnnnnn (not taken) | 8.00 | 8.00 | 0.00 | 0.00 | 139 | Branch | ✓ |  |
| 142 | JPQ nnnnnnnn | 16.75 | 12.00 | 4.75 | 0.00 | 292 | Branch | ✓ |  |
| 143 | SARB u | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ALU 64-bit (1 cycle) | ✓ |  |
| 144 | SARW rr | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ALU 64-bit (1 cycle) | ✓ |  |
| 145 | SARL rr | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ALU 64-bit (1 cycle) | ✓ |  |
| 146 | SARQ rr | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ALU 64-bit (1 cycle) | ✓ |  |
| 147 | SHLB u | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ALU 64-bit (1 cycle) | ✓ |  |
| 148 | SHLW rr | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ALU 64-bit (1 cycle) | ✓ |  |
| 149 | SHLL rr | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ALU 64-bit (1 cycle) | ✓ |  |
| 150 | SHLQ rr | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ALU 64-bit (1 cycle) | ✓ |  |
| 151 | SHRB u | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ALU 64-bit (1 cycle) | ✓ |  |
| 152 | SHRW rr | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ALU 64-bit (1 cycle) | ✓ |  |
| 153 | SHRL rr | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ALU 64-bit (1 cycle) | ✓ |  |
| 154 | SHRQ rr | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ALU 64-bit (1 cycle) | ✓ |  |
| 156 | RLCW rr | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ALU 64-bit (1 cycle) | ✓ |  |
| 157 | RLCL rr | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ALU 64-bit (1 cycle) | ✓ |  |
| 158 | RLCQ rr | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ALU 64-bit (1 cycle) | ✓ |  |
| 160 | RRCW rr | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ALU 64-bit (1 cycle) | ✓ |  |
| 161 | RRCL rr | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ALU 64-bit (1 cycle) | ✓ |  |
| 162 | RRCQ rr | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ALU 64-bit (1 cycle) | ✓ |  |
| 169 | CPLW rr | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ALU 64-bit (1 cycle) | ✓ |  |
| 170 | CPLL rr | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ALU 64-bit (1 cycle) | ✓ |  |
| 171 | CPLQ rr | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ALU 64-bit (1 cycle) | ✓ |  |
| 172 | NEGW rr | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ALU 64-bit (1 cycle) | ✓ |  |
| 173 | NEGL rr | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ALU 64-bit (1 cycle) | ✓ |  |
| 174 | NEGQ rr | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ALU 64-bit (1 cycle) | ✓ |  |
| 181 | STCR rr, kk | 8.00 | 8.00 | 0.00 | 0.00 | 139 | Control (CR) | ✓ |  |
| 184 | FENCE | 8.00 | 8.00 | 0.00 | 0.00 | 139 | Barrier | ✓ |  |
| 185 | ISYNC | 8.00 | 8.00 | 0.00 | 0.00 | 139 | Barrier | ✓ |  |
| 186 | PGINV (uu) | 8.00 | 8.00 | 0.00 | 0.00 | 139 | MMU | ✓ |  |
| 187 | XCHGL rr, (rr’) | 27.00 | 21.00 | 0.00 | 6.00 | 471 | Atomic | ✓ |  |
| 188 | XCHGQ rr, (rr’) | 27.00 | 21.00 | 0.00 | 6.00 | 471 | Atomic | ✓ |  |
| 189 | CASL (rr’), rr | 35.25 | 29.00 | 0.44 | 5.81 | 614 | Atomic | ✓ |  |
| 190 | CASQ (rr’), rr | 31.25 | 25.00 | 0.44 | 5.81 | 545 | Atomic | ✓ |  |
| 191 | SVCTX (uu) | 180.00 | 132.00 | 0.00 | 48.00 | 3137 | Context | ✓ |  |
| 211 | IN B,(C) | 16.00 | 16.00 | 0.00 | 0.00 | 279 | Z80 ED instruction in native mode | ✓ |  |
| 212 | OUT (C),B | 12.00 | 12.00 | 0.00 | 0.00 | 209 | Z80 ED instruction in native mode | ✓ |  |
| 213 | SBC HL,BC | 8.00 | 8.00 | 0.00 | 0.00 | 139 | Z80 ED instruction in native mode | ✓ |  |
| 214 | LD (nn),BC | 11.00 | 8.00 | 0.00 | 3.00 | 192 | Z80 ED instruction in native mode | ✓ |  |
| 215 | NEG | 8.00 | 8.00 | 0.00 | 0.00 | 139 | Z80 ED instruction in native mode | ✓ |  |
| 216 | RETN | 35.00 | 25.00 | 7.00 | 3.00 | 610 | Z80 ED instruction in native mode | ✓ | return alone (CALL+RET pair minus CALL) |
| 217 | IM 0 | 8.00 | 8.00 | 0.00 | 0.00 | 139 | Z80 ED instruction in native mode | ✓ |  |
| 218 | LD I,A | 8.00 | 8.00 | 0.00 | 0.00 | 139 | Z80 ED instruction in native mode | ✓ |  |
| 219 | IN C,(C) | 16.00 | 16.00 | 0.00 | 0.00 | 279 | Z80 ED instruction in native mode | ✓ |  |
| 220 | OUT (C),C | 8.00 | 8.00 | 0.00 | 0.00 | 139 | Z80 ED instruction in native mode | ✓ |  |
| 221 | ADC HL,BC | 8.00 | 8.00 | 0.00 | 0.00 | 139 | Z80 ED instruction in native mode | ✓ |  |
| 222 | LD BC,(nn) | 11.00 | 8.00 | 0.00 | 3.00 | 192 | Z80 ED instruction in native mode | ✓ |  |
| 223 | NEG | 8.00 | 8.00 | 0.00 | 0.00 | 139 | Z80 ED instruction in native mode | ✓ |  |
| 224 | RETI | 35.00 | 25.00 | 7.00 | 3.00 | 610 | Z80 ED instruction in native mode | ✓ | return alone (CALL+RET pair minus CALL) |
| 225 | IM 0 | 8.00 | 8.00 | 0.00 | 0.00 | 139 | Z80 ED instruction in native mode | ✓ |  |
| 226 | LD R,A | 8.00 | 8.00 | 0.00 | 0.00 | 139 | Z80 ED instruction in native mode | ✓ |  |
| 227 | IN D,(C) | 16.00 | 16.00 | 0.00 | 0.00 | 279 | Z80 ED instruction in native mode | ✓ |  |
| 228 | OUT (C),D | 12.00 | 12.00 | 0.00 | 0.00 | 209 | Z80 ED instruction in native mode | ✓ |  |
| 229 | SBC HL,DE | 8.00 | 8.00 | 0.00 | 0.00 | 139 | Z80 ED instruction in native mode | ✓ |  |
| 230 | LD (nn),DE | 11.00 | 8.00 | 0.00 | 3.00 | 192 | Z80 ED instruction in native mode | ✓ |  |
| 231 | NEG | 8.00 | 8.00 | 0.00 | 0.00 | 139 | Z80 ED instruction in native mode | ✓ |  |
| 232 | RETN | 35.00 | 25.00 | 7.00 | 3.00 | 610 | Z80 ED instruction in native mode | ✓ | return alone (CALL+RET pair minus CALL) |
| 233 | IM 1 | 8.00 | 8.00 | 0.00 | 0.00 | 139 | Z80 ED instruction in native mode | ✓ |  |
| 234 | LD A,I | 16.00 | 16.00 | 0.00 | 0.00 | 279 | Z80 ED instruction in native mode | ✓ |  |
| 235 | IN E,(C) | 16.00 | 16.00 | 0.00 | 0.00 | 279 | Z80 ED instruction in native mode | ✓ |  |
| 236 | OUT (C),E | 8.00 | 8.00 | 0.00 | 0.00 | 139 | Z80 ED instruction in native mode | ✓ |  |
| 237 | ADC HL,DE | 8.00 | 8.00 | 0.00 | 0.00 | 139 | Z80 ED instruction in native mode | ✓ |  |
| 238 | LD DE,(nn) | 11.00 | 8.00 | 0.00 | 3.00 | 192 | Z80 ED instruction in native mode | ✓ |  |
| 239 | NEG | 8.00 | 8.00 | 0.00 | 0.00 | 139 | Z80 ED instruction in native mode | ✓ |  |
| 240 | RETN | 35.00 | 25.00 | 7.00 | 3.00 | 610 | Z80 ED instruction in native mode | ✓ | return alone (CALL+RET pair minus CALL) |
| 241 | IM 2 | 8.00 | 8.00 | 0.00 | 0.00 | 139 | Z80 ED instruction in native mode | ✓ |  |
| 242 | LD A,R | 16.00 | 16.00 | 0.00 | 0.00 | 279 | Z80 ED instruction in native mode | ✓ |  |
| 243 | IN H,(C) | 16.00 | 16.00 | 0.00 | 0.00 | 279 | Z80 ED instruction in native mode | ✓ |  |
| 244 | OUT (C),H | 12.00 | 12.00 | 0.00 | 0.00 | 209 | Z80 ED instruction in native mode | ✓ |  |
| 245 | SBC HL,HL | 8.00 | 8.00 | 0.00 | 0.00 | 139 | Z80 ED instruction in native mode | ✓ |  |
| 246 | LD (nn),HL | 11.00 | 8.00 | 0.00 | 3.00 | 192 | Z80 ED instruction in native mode | ✓ |  |
| 247 | NEG | 8.00 | 8.00 | 0.00 | 0.00 | 139 | Z80 ED instruction in native mode | ✓ |  |
| 248 | RETN | 35.00 | 25.00 | 7.00 | 3.00 | 610 | Z80 ED instruction in native mode | ✓ | return alone (CALL+RET pair minus CALL) |
| 249 | IM 0 | 8.00 | 8.00 | 0.00 | 0.00 | 139 | Z80 ED instruction in native mode | ✓ |  |
| 250 | RRD | 51.00 | 45.00 | 0.00 | 6.00 | 889 | Z80 ED instruction in native mode | ✓ |  |
| 251 | IN L,(C) | 16.00 | 16.00 | 0.00 | 0.00 | 279 | Z80 ED instruction in native mode | ✓ |  |
| 252 | OUT (C),L | 8.00 | 8.00 | 0.00 | 0.00 | 139 | Z80 ED instruction in native mode | ✓ |  |
| 253 | ADC HL,HL | 8.00 | 8.00 | 0.00 | 0.00 | 139 | Z80 ED instruction in native mode | ✓ |  |
| 254 | LD HL,(nn) | 11.00 | 8.00 | 0.00 | 3.00 | 192 | Z80 ED instruction in native mode | ✓ |  |
| 255 | NEG | 8.00 | 8.00 | 0.00 | 0.00 | 139 | Z80 ED instruction in native mode | ✓ |  |
| 256 | RETN | 35.00 | 25.00 | 7.00 | 3.00 | 610 | Z80 ED instruction in native mode | ✓ | return alone (CALL+RET pair minus CALL) |
| 257 | IM 0 | 8.00 | 8.00 | 0.00 | 0.00 | 139 | Z80 ED instruction in native mode | ✓ |  |
| 258 | RLD | 51.00 | 45.00 | 0.00 | 6.00 | 889 | Z80 ED instruction in native mode | ✓ |  |
| 259 | IN F,(C) | 13.00 | 13.00 | 0.00 | 0.00 | 227 | Z80 ED instruction in native mode | ✓ |  |
| 260 | OUT (C),0 | 8.00 | 8.00 | 0.00 | 0.00 | 139 | Z80 ED instruction in native mode | ✓ |  |
| 261 | SBC HL,SP | 8.00 | 8.00 | 0.00 | 0.00 | 139 | Z80 ED instruction in native mode | ✓ |  |
| 262 | LD (nn),SP | 11.00 | 8.00 | 0.00 | 3.00 | 192 | Z80 ED instruction in native mode | ✓ |  |
| 263 | NEG | 8.00 | 8.00 | 0.00 | 0.00 | 139 | Z80 ED instruction in native mode | ✓ |  |
| 264 | RETN | 35.00 | 25.00 | 7.00 | 3.00 | 610 | Z80 ED instruction in native mode | ✓ | return alone (CALL+RET pair minus CALL) |
| 265 | IM 1 | 8.00 | 8.00 | 0.00 | 0.00 | 139 | Z80 ED instruction in native mode | ✓ |  |
| 266 | NOP | 8.00 | 8.00 | 0.00 | 0.00 | 139 | Z80 ED instruction in native mode | ✓ |  |
| 267 | IN A,(C) | 16.00 | 16.00 | 0.00 | 0.00 | 279 | Z80 ED instruction in native mode | ✓ |  |
| 268 | OUT (C),A | 8.00 | 8.00 | 0.00 | 0.00 | 139 | Z80 ED instruction in native mode | ✓ |  |
| 269 | ADC HL,SP | 8.00 | 8.00 | 0.00 | 0.00 | 139 | Z80 ED instruction in native mode | ✓ |  |
| 270 | LD SP,(nn) | 11.00 | 8.00 | 0.00 | 3.00 | 192 | Z80 ED instruction in native mode | ✓ |  |
| 271 | NEG | 8.00 | 8.00 | 0.00 | 0.00 | 139 | Z80 ED instruction in native mode | ✓ |  |
| 272 | RETN | 35.00 | 25.00 | 7.00 | 3.00 | 610 | Z80 ED instruction in native mode | ✓ | return alone (CALL+RET pair minus CALL) |
| 273 | IM 2 | 8.00 | 8.00 | 0.00 | 0.00 | 139 | Z80 ED instruction in native mode | ✓ |  |
| 274 | NOP | 8.00 | 8.00 | 0.00 | 0.00 | 139 | Z80 ED instruction in native mode | ✓ |  |
| 275 | LDI | 31.00 | 25.00 | 0.00 | 6.00 | 540 | Z80 ED instruction in native mode | ✓ |  |
| 276 | CPI | 24.00 | 21.00 | 0.00 | 3.00 | 418 | Z80 ED instruction in native mode | ✓ |  |
| 277 | INI | 24.00 | 21.00 | 0.00 | 3.00 | 418 | Z80 ED instruction in native mode | ✓ |  |
| 278 | OUTI | 24.00 | 21.00 | 0.00 | 3.00 | 418 | Z80 ED instruction in native mode | ✓ |  |
| 279 | LDD | 31.00 | 25.00 | 0.00 | 6.00 | 540 | Z80 ED instruction in native mode | ✓ |  |
| 280 | CPD | 24.00 | 21.00 | 0.00 | 3.00 | 418 | Z80 ED instruction in native mode | ✓ |  |
| 281 | IND | 24.00 | 21.00 | 0.00 | 3.00 | 418 | Z80 ED instruction in native mode | ✓ |  |
| 282 | OUTD | 24.00 | 21.00 | 0.00 | 3.00 | 418 | Z80 ED instruction in native mode | ✓ |  |
| 283 | LDIR | 42.50 | 32.75 | 3.75 | 6.00 | 741 | Z80 ED instruction in native mode | ✓ | per element (16 elements) |
| 284 | CPIR | 35.50 | 28.75 | 3.75 | 3.00 | 619 | Z80 ED instruction in native mode | ✓ | per element (16 elements) |
| 285 | INIR | 35.50 | 28.75 | 3.75 | 3.00 | 619 | Z80 ED instruction in native mode | ✓ | per element (16 elements) |
| 286 | OTIR | 35.50 | 28.75 | 3.75 | 3.00 | 619 | Z80 ED instruction in native mode | ✓ | per element (16 elements) |
| 287 | LDDR | 42.50 | 32.75 | 3.75 | 6.00 | 741 | Z80 ED instruction in native mode | ✓ | per element (16 elements) |
| 288 | CPDR | 35.50 | 28.75 | 3.75 | 3.00 | 619 | Z80 ED instruction in native mode | ✓ | per element (16 elements) |
| 289 | INDR | 35.50 | 28.75 | 3.75 | 3.00 | 619 | Z80 ED instruction in native mode | ✓ | per element (16 elements) |
| 290 | OTDR | 35.50 | 28.75 | 3.75 | 3.00 | 619 | Z80 ED instruction in native mode | ✓ | per element (16 elements) |

### D.2 Z80 base instructions in native mode (examples)

| Instruction | Total | Execution | Fetch wait | Data wait | ns | Board | Note |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CALLL nnnn (no return) | 27.75 | 20.00 | 4.75 | 3.00 | 484 | ✓ | call without return (helper) |
| CALLQ nnnnnnnn (no return) | 27.75 | 20.00 | 4.75 | 3.00 | 484 | ✓ | call without return (helper) |
| CALL nn (no return) | 28.12 | 20.00 | 5.12 | 3.00 | 490 | ✓ | call without return (helper) |
| NOP | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ✓ |  |
| LD A,B | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ✓ |  |
| LD A,n | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ✓ |  |
| LD BC,nn | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ✓ |  |
| ADD A,B | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ✓ |  |
| INC B | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ✓ |  |
| ADD HL,BC | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ✓ |  |
| INC BC | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ✓ |  |
| LD A,(HL) | 11.00 | 8.00 | 0.00 | 3.00 | 192 | ✓ |  |
| LD (HL),A | 11.00 | 8.00 | 0.00 | 3.00 | 192 | ✓ |  |
| LD A,(nn) | 11.00 | 8.00 | 0.00 | 3.00 | 192 | ✓ |  |
| LD HL,(nn) | 11.00 | 8.00 | 0.00 | 3.00 | 192 | ✓ |  |
| LD A,(IX+d) | 11.00 | 8.00 | 0.00 | 3.00 | 192 | ✓ |  |
| LD (IX+d),A | 11.00 | 8.00 | 0.00 | 3.00 | 192 | ✓ |  |
| PUSH BC | 15.00 | 12.00 | 0.00 | 3.00 | 261 | ✓ |  |
| POP DE | 16.00 | 13.00 | 0.00 | 3.00 | 279 | ✓ |  |
| EX DE,HL | 16.00 | 16.00 | 0.00 | 0.00 | 279 | ✓ |  |
| EXX | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ✓ |  |
| EX (SP),HL | 23.00 | 17.00 | 0.00 | 6.00 | 401 | ✓ |  |
| RLCA | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ✓ |  |
| BIT 3,A | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ✓ |  |
| SET 3,(HL) | 30.00 | 24.00 | 0.00 | 6.00 | 523 | ✓ |  |
| JR e (taken) | 16.75 | 12.00 | 4.75 | 0.00 | 292 | ✓ |  |
| JR NZ,e (not taken) | 8.00 | 8.00 | 0.00 | 0.00 | 139 | ✓ |  |
| JR Z,e (taken) | 16.75 | 12.00 | 4.75 | 0.00 | 292 | ✓ |  |
| JP nn | 17.12 | 12.00 | 5.12 | 0.00 | 298 | ✓ |  |
| DJNZ e (taken) | 20.75 | 16.00 | 4.75 | 0.00 | 362 | ✓ |  |
| CALL nn + RET (pair) | 59.12 | 41.00 | 12.12 | 6.00 | 1031 | ✓ |  |
| RET | 31.00 | 21.00 | 7.00 | 3.00 | 540 | ✓ | return alone (CALL+RET pair minus CALL) |

### D.3 Not measured

| ids | Reason |
| --- | --- |
| 40–66, 193–210 | FPU: not in the cartridge build (R8064_NOFPU) |
| 155, 159 | removed from the core |
| 175–180, 182–183 | system/privileged: changes mode, CRs or resets (not measured in a loop) |
| 192 | LDCTX loads the whole register context (not measured in a loop) |
| 70–71, 74, 82–83, 86, 94–95, 98, 163–168 | no separate operand form (encoded by another id) |
<!-- END APPENDIX_D -->
