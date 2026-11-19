# R8064AS — R8064 assembler for MSX

`R8064AS.COM` runs on the MSX (MSX-DOS 1/2) and assembles the full R8064 instruction set (Z80, R800 and all R8064
extensions) into a binary; `/L` writes a listing with symbols, `/G` sends the program to the R8064 cartridge and runs it.

```
R8064AS file[.ASM] [/L] [/G[mode]]
```

Full user guide: [docs/R8064_Assembler.md](../../../../docs/R8064_Assembler.md).

| File | Role |
| --- | --- |
| `R8064AS.COM` | Ready-to-use binary |
| `r8064as.asm` | Source (Z80) — `sjasmplus --raw=R8064AS.COM r8064as.asm` |
| `r8isa.py` | Instruction set definition (single source of truth) |
| `isacore.py` | Pattern compiler, operand masks from the RTL decode ROMs, matching/encoding |
| `gen_table.py` | Generates `r8tab.asm` (the table used by R8064AS.COM) |
| `asmref.py` | Same assembler in Python (PC cross-assembler, test reference) |
| `verify_rom.py` | Checks every extension encoding against the RTL decode ROMs |
| `verify_z80.py` | Checks the Z80 base set against sjasmplus (writes `z80_all.asm`) |
| `crosstest.py`, `tests/`, `tests_go/` | Runs R8064AS.COM in the MSX-DOS model and compares with `asmref.py` |
| `run_tests.sh` | Everything above in one command |
