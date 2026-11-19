# R8064AS — R8064 Assembler for MSX — User Guide

Version 0.0 Alpha · November 19, 2026

`R8064AS.COM` is an assembler that runs **on the MSX** (MSX-DOS 1 or 2, Z80 or R800) and turns R8064 assembly source
into a binary for the R8064. It knows the **whole R8064 instruction set**: the Z80 set (including the undocumented
instructions), the R800 multiplications and every R8064 extension (16/32/64-bit arithmetic and loads, banks, jumps
and calls, atomics, system, MMU and FPU). It can also send the program to the R8064 cartridge and run it.

| File | Contents |
| --- | --- |
| [`modulos/13_soc/msx/asm/R8064AS.COM`](../modulos/13_soc/msx/asm/R8064AS.COM) | Ready-to-use binary (17 KB) |
| [`r8064as.asm`](../modulos/13_soc/msx/asm/r8064as.asm) | Source (Z80 assembly) |
| [`r8tab.asm`](../modulos/13_soc/msx/asm/r8tab.asm) | Instruction table (245 mnemonics, 495 operand forms), generated |
| [`r8isa.py`](../modulos/13_soc/msx/asm/r8isa.py) | The instruction set definition the table is generated from |
| [`asmref.py`](../modulos/13_soc/msx/asm/asmref.py) | The same assembler in Python (PC cross-assembler and test reference) |

> Status: verified in simulation (section 9). Not yet tested on real hardware.

---

## 1. Usage

```
R8064AS file[.ASM] [/L] [/G[mode]]
```

| Option | Effect |
| --- | --- |
| *(none)* | Assembles `file.ASM` (default extension `.ASM`) into `file.BIN`. |
| `/L` | Also writes `file.LST`: listing with addresses and bytes, error lines, and the symbol table. |
| `/G[mode]` | After an assembly **without errors**, sends `file.BIN` to the R8064 at its start address and executes it, then waits for the end and shows the exit code (any key stops waiting). `mode`: `0` Z80 ROM timing, `1` Z80 DRAM timing (default), `2` R800 ROM, `3` R800 DRAM, `4` native 64-bit. |

The output files go to the same drive as the source. At the end the assembler prints the number of errors, the size
of the binary and its start address:

```
A>R8064AS HELLO /L /G
R8064AS v1.0 - R8064 assembler
0 error(s), 36 bytes at 00004000h
Sending to the R8064.
Running at 00004000h, mode 01 (any key: stop waiting)
Program ended, exit code 000013BAh
```

### The binary file

`file.BIN` is the memory image from the first byte the program generates up to the last one. The start address is
the address of that first byte (normally the first `ORG`). Gaps left by a later `ORG` or by `DS` are filled with 00h.
`ORG` may only move forward once code has been generated.

`/G` loads the image at R8064 **physical** address = start address and executes it at the `END` address (or at the
start address if `END` has no operand). Rules of monitor v1: the image must lie in the 8 MB SDRAM and the entry point
must be below 10000h; the monitor uses 0000h–37FFh, so use `ORG 4000h` (or higher) for programs. The program ends
with `RET` and returns its exit code in HL. The same image can be sent and run later with `R8064 R addr file`
(see the [MSX software guide](R8064_MSX_Software.md)).

## 2. Source format

```
[label[:]]  [instruction or directive  [operands]]  [; comment]
```

- A name that starts in **column 1** is a label (the colon is optional). In other columns a label needs a colon.
  So instructions and directives must not start in column 1.
- Names: letters, digits and `_ . ? @ $`, not starting with a digit, up to 32 characters. Names, instructions,
  registers and directives are **not case sensitive**.
- Comments start with `;` (outside quotes).
- Tabs count as spaces. Lines longer than 255 characters are cut.
- A leading dot is allowed on directives (`.ORG`, `.DB`).

## 3. Numbers and expressions

All arithmetic is **64-bit** (two's complement). Values that do not fit their field cause *value out of range*.

| Form | Example |
| --- | --- |
| Decimal | `100`, `100D` |
| Hexadecimal | `0FFH`, `0x1F`, `$1F`, `&H1F` |
| Binary | `1010B`, `0b1010`, `%1010` |
| Character | `'A'`, `"A"` |
| Current address | `$` (address of the start of the line) |

Operators, from highest to lowest precedence:

| Level | Operators |
| --- | --- |
| unary | `-` `+` `~` (or `NOT`) `!` (logical not) `HIGH` `LOW` `( )` |
| multiplicative | `*` `/` `%` (or `MOD`) — division and modulo are unsigned |
| additive | `+` `-` |
| shift | `<<` (`SHL`) `>>` (`SHR`, logical) |
| relational | `<` `>` `<=` `>=` (signed; result 1 or 0) |
| equality | `==` or `=`, `!=` or `<>` |
| and | `&` (`AND`) |
| xor | `^` (`XOR`) |
| or | `\|` (`OR`) |

Symbols may be used before they are defined (two passes), except where a value is needed in pass 1:
`ORG`, `DS`, `ALIGN`, `IF` and constants such as `IM 1`.

## 4. Directives

| Directive | Meaning |
| --- | --- |
| `ORG expr` | Sets the address. |
| `name EQU expr` / `name = expr` | Defines a constant. |
| `DB` / `DEFB` / `DM` / `DEFM` / `BYTE` / `TEXT` | Bytes and strings: `DB "Text",13,10,0,'x'` |
| `DW` / `DEFW` / `WORD` | 16-bit words (little-endian) |
| `DL` / `DD` / `DWORD` | 32-bit values |
| `DQ` / `QWORD` | 64-bit values |
| `DS n[,fill]` / `DEFS` / `BLOCK` | `n` bytes of `fill` (default 0) |
| `ALIGN n[,fill]` | Fills up to the next multiple of `n` |
| `IF expr` / `IFDEF name` / `IFNDEF name` / `ELSE` / `ENDIF` | Conditional assembly (up to 16 levels) |
| `INCLUDE "file"` | Inserts another source file (up to 3 levels of nesting) |
| `END [entry]` | Ends the source; optional entry point for `/G` |

A data line is generated only if every item on it is correct.

## 5. Instructions

### Z80 and R800

The standard Zilog syntax: `LD A,(IX+5)`, `EX AF,AF'`, `JR NZ,loop`, `OUT (C),A`, etc., including the undocumented
`IXH IXL IYH IYL`, `SLL`/`SLI`, `IN F,(C)`, `OUT (C),0` and the CB forms with copy to a register
(`RES 3,(IY+2),B`). For the ALU, `ADD A,B` and `SUB B` / `SUB A,B` are accepted. R800: `MULUB A,r` / `MLTUB`,
`MULUW HL,BC` / `MULUW HL,SP`.

### R8064 extensions

The size is in the mnemonic: **W** = 16, **L** = 32, **Q** = 64 bits (`ADDQ`, `LDL`, `CMPW`, `PUSHQ`…), as in
chapter A of the [datasheet](R8064_Datasheet.md). The register operand `rr` is one of `BC DE HL IX IY AX`; the
size-prefixed names are accepted as well: `QBC QDE QHL QIX QIY QAX`, `LBC LDE LHL LIX LIY LAX`, and `EA`/`QA`
for `AX`.

```
        ldq hl,1122334455667788h    ; 64-bit immediate
        ldl bc,(hl)                 ; 32-bit load through a register
        ldq (qix+1234h),de          ; 16-bit displacement
        ldq ax,(123456789ABCh)      ; 64-bit absolute address
        addq hl,bc
        cmpq hl,de
        jrw nz,loop                 ; 16-bit relative jump
        jpq (hl)
        callq 0000000000400000h
        bitl 31,ax
        mltuq qa,bc
        divsq qde:qax,bc            ; the implicit operand is optional: DIVSQ BC
        casq (hl),de
        mtcr 17
        fadd st0,st3
        prot on                     ; or PROT 1
```

**Banks.** The bank registers are written by name and the assembler adds the bank prefix (ED 0Eh, ED 0Dh,
ED 0Bh) itself: `N0`–`N3` and `N4`–`N7` (in place of BC, DE, HL, AX) and the shadow registers `BC'`, `DE'`, `HL'`,
`AX'`. Example: `ADDQ N2,N3` → `ED 0E 3E A7`. All banked registers of one instruction must be in the same bank, and
cannot be mixed with the unbanked BC, DE, HL or AX (IX and IY are never banked); otherwise the error is
*bank registers mixed*. Only instructions that accept the prefix (datasheet) can use banked registers.

**FPU:** `ST0`–`ST7`, e.g. `FADD ST0,ST2`, `FXCH ST1`, `FLD64 (HL)`.

## 6. Listing (`/L`)

```
00004000 21 00 00           start:  ld hl,0
0000400E ED 39 81 1C 40 00          ldq bc,(result_q)
00004014 00 00 00 00 00
00000064 =                  N       equ 100
                            ; comment line
*** value out of range
```

Address, up to 6 bytes per line (more bytes continue on the next lines, up to 24 shown; `DS`, `ALIGN` and `ORG`
fill only on the first line), then the source line. An `EQU` line shows its value. Lines with an error are followed by
`*** message`. The symbol table comes at the end, in order of definition.

## 7. Errors

Errors are reported in pass 2 as `FILE.ASM(line): message`; the line is skipped. If there are errors, `/G` is not
done.

| Message | Cause |
| --- | --- |
| `syntax error` | Malformed expression, label or line (missing `)`, empty operand, `EQU` without label…) |
| `bad number` | Invalid digit for the base |
| `undefined symbol` | Name never defined |
| `value out of range` | Value too large for its field, relative jump too far, bit number, RST vector |
| `division by zero` | `/` or `%` by 0 |
| `unknown instruction` | Mnemonic or directive not known |
| `invalid operands` | No form of the instruction accepts these operands |
| `symbol defined twice` | Same label defined again |
| `phase error` | A label got a different address in pass 2 (usually a consequence of an earlier error) |
| `ORG backwards` | `ORG` below the current address after code was generated |
| `IF/ELSE/ENDIF mismatch` | `ELSE`/`ENDIF` without `IF`, or more than 16 levels |
| `value must be known in pass 1` | Forward reference in `ORG`, `DS`, `ALIGN`, `IF` |
| `bank registers mixed` | See *Banks* |
| `include file not found` / `include nesting too deep` | `INCLUDE` problems |
| `name too long` | Name longer than 32 characters |

## 8. Limits

- No macros, local labels or `PHASE`. Names up to 32 characters.
- Symbols live in the free TPA memory: about 29 KB, more than 1,000 symbols.
- Speed: roughly 40 source lines per second on a 3.58 MHz Z80 (two passes); faster on the R800.

## 9. How it was verified

- **R8064 extensions against the RTL.** `verify_rom.py` encodes every accepted operand combination of every R8064
  extension and decodes it with the decode ROMs of the core (`rom_ed_a/amb_idx/rom_ed_b/ctrl_b.mem`): each one must
  give the expected instruction id and length, and every encoding the ROM accepts must be producible. Result: of the
  215 extension ids in the ROM, 211 are produced by extension forms and 2 (MULUW HL,BC / HL,SP) by the R800 forms;
  the other 2 are instructions removed from the core. 0 errors. The register masks of each form are taken from the ROM itself.
- **Z80 set against sjasmplus.** `verify_z80.py` assembles 1,527 Z80 instruction/operand combinations with the
  table and with sjasmplus: identical bytes.
- **The MSX program against the reference.** `crosstest.py` runs `R8064AS.COM` (the real Z80 code, in an MSX-DOS
  model) and `asmref.py` on the same sources and compares the BIN files and the error lists line by line: the full Z80
  set, 15,975 lines with every R8064 extension (all registers, banks, conditions, bit numbers), expressions, directives,
  every error message and include nesting. All identical.
- **`/G`:** `HELLO.ASM` assembled, sent to the cartridge model and executed; exit code 13BAh (5050) as expected.

To rerun everything: `cd modulos/13_soc/msx/asm && sh run_tests.sh` (needs python3, gcc and sjasmplus).

## 10. Building and cross-assembling on the PC

```
python3 gen_table.py                       # only after changing r8isa.py
sjasmplus --raw=R8064AS.COM r8064as.asm
python3 asmref.py prog.asm prog.bin        # the same assembler on the PC
```
