# R8064 MSX Software — User Guide

Version 0.0 Alpha · November 17, 2026

This guide covers the two MSX-side programs that send and read data and programs to/from the R8064 cartridge:

| Program | File | What it is |
| --- | --- | --- |
| **R8064.COM** | [`modulos/13_soc/msx/R8064.COM`](../modulos/13_soc/msx/R8064.COM) (source [`r8064.asm`](../modulos/13_soc/msx/r8064.asm)) | Ready-to-use MSX-DOS command-line tool |
| **r8064io driver** | [`modulos/13_soc/msx/r8064io.asm`](../modulos/13_soc/msx/r8064io.asm) | Z80 assembly routines to include in your own MSX programs |

Both use the MSX ↔ R8064 message protocol (REV46, chapter 8 of the [datasheet](R8064_Datasheet.md)) through I/O ports
**0Bh, 0Ch and 0Dh only**. That is all the V9968_Cartridge board provides (A0–A7, D0–D7, /IORQ, /RD, /WR); the
8000h–BFFFh exchange window is not used. The code is plain Z80 and also runs on the R800 (MSX turbo R).

> Status: tested in simulation (17 cases, see section 5). Not yet tested on real hardware.

---

## 1. Requirements

- An MSX with the R8064 cartridge (V9968_Cartridge board, R8064 bitstream loaded).
- MSX-DOS 1 or MSX-DOS 2 (only the MSX-DOS 1 FCB calls are used).
- Ports 0Bh–0Dh must not be used by another device in the machine.

## 2. Installation

Copy `R8064.COM` to the MSX-DOS disk (or SD card / disk image). Run it from the `A>` prompt. No configuration is needed.

To rebuild it from source:

```
sjasmplus --raw=R8064.COM r8064.asm
```

## 3. R8064.COM — command reference

```
R8064 <command> [parameters]
```

All numbers are **hexadecimal** (an `H` suffix is optional: `4000` and `4000H` are the same). File names use the
MSX-DOS 8.3 format and may start with a drive (`B:PROG.BIN`). Running `R8064` with no parameters prints a short help.

| Command | Syntax | Description |
| --- | --- | --- |
| **I** | `R8064 I` | Detects the cartridge and shows the protocol version, maximum message size, block size and features (HELLO). |
| **P** | `R8064 P` | Checks that the R8064 monitor answers (PING). |
| **B** | `R8064 B` | Restarts the R8064 and waits until the monitor answers again. |
| **S** | `R8064 S addr file` | **Sends** a file to the R8064 memory starting at physical address `addr`. If `addr` is a multiple of 8, the CRC-16 computed by the R8064 is compared with the CRC of the file. |
| **G** | `R8064 G addr size file` | **Gets** `size` bytes of R8064 memory starting at `addr` and writes them to a new file. |
| **D** | `R8064 D addr [size]` | Hex/ASCII **dump** of R8064 memory, 8 bytes per line (fits a 40-column screen). Default size 80h, maximum 7F8h (2,040). |
| **X** | `R8064 X addr [mode [arg]]` | **Executes** the program at `addr` and waits for it to end; then prints its exit code. Press any key to stop waiting (the program keeps running on the R8064). |
| **R** | `R8064 R addr file [mode [arg]]` | **Runs** a program: same as `S` followed by `X`. |

### Parameters

| Parameter | Meaning |
| --- | --- |
| `addr` | R8064 physical address, 0–7FFFFFh (8 MB SDRAM). |
| `size` | Number of bytes (up to 8 hex digits). |
| `mode` | CPU mode for EXEC: `0` Z80 ROM timing, `1` Z80 DRAM timing (**default**), `2` R800 ROM, `3` R800 DRAM, `4` native 64-bit. |
| `arg` | Argument passed to the program in register HL (default 0). |

### Rules for programs run with X / R

- In monitor v1 the entry address must be **below 10000h**.
- With the slot register A8h = 00h (reset value) the R8064 logical address equals the physical address. The monitor uses
  0000h–37FFh, so **load your programs at 4000h–FFFFh**. The other areas of the 8 MB (up to 7FFFFFh) can hold data.
- The monitor calls the program as a subroutine. The program receives `arg` in HL, ends with **RET** and returns its
  exit code in HL. R8064.COM shows it as `Program ended, exit code xxxxxxxxh`.
- If the program faults, R8064.COM shows `EXCEPTION, cause xx, EPC xxxxxxxxxxxxxxxx`.

### Examples

Send a data file, run a program that adds the bytes of that data, then look at the result it stored at 4100h:

```
A>R8064 I
R8064 found: protocol v01, max message 0800h, block 4000h
Features: window EXEC CRC
OK

A>R8064 S 5000 DATA.BIN
Sending...
00001388h bytes written at 00005000h
CRC ok: 5C4D
OK

A>R8064 R 4000 TPROG.BIN 1 1000
Sending.
0000001Ah bytes written at 00004000h
CRC ok: 6322
Running at 4000h, mode 01 (any key: stop waiting)
Program ended, exit code 0000D4BCh
OK

A>R8064 D 4100 2
004100 BC D4                   ..
```

Read 64 KB of R8064 memory back into a file, and run an already loaded program in R800 mode with argument 10h:

```
A>R8064 G 600000 10000 RESULT.BIN
A>R8064 X 4000 3 10
```

### Messages

| Message | Meaning / what to do |
| --- | --- |
| `No R8064 cartridge found (port 0Bh)` | Port 0Bh reads FFh: cartridge missing, not powered or bitstream not loaded. |
| `The R8064 does not answer (timeout)` | No reply after 4 attempts (about 1–2 s each). Try `R8064 B`. |
| `Unexpected reply from the R8064` | The reply was shorter than expected or had the wrong signature. |
| `R8064 error nn: ...` | The R8064 rejected the request (ST code): 01 unknown command, 02 invalid parameter, 03 address outside SDRAM / not aligned, 04 busy, 05 window unavailable, 06 execution error, 07 timeout in the R8064. |
| `CRC MISMATCH: R8064 xxxx, file yyyy` | The data in the R8064 differs from the file. Send it again. |
| `CRC check skipped (address not 8-aligned)` | The data was sent; the R8064 CRC command only works on 8-aligned addresses. |
| `Address outside the 8 MB SDRAM` | `addr` is 800000h or above. |
| `EXEC entry must be below 10000h` | Limitation of monitor v1. |
| `File not found` / `Cannot create the file` / `Disk write error` | MSX-DOS file errors. |

## 4. r8064io driver — programming reference

Include the driver in your Z80 program:

```
        include "r8064io.asm"
R8_CRCTAB equ 0C000h          ; only if you use crc_mktab/crc_upd: 512 bytes, 256-aligned
```

The driver variables are at the end of `r8064io.asm` (about 100 bytes). In a ROM build, move them to RAM.

### Return convention

| Result | Meaning |
| --- | --- |
| Cy = 0, A = 0, Z = 1 | Success. |
| Cy = 0, A ≠ 0 | The R8064 replied with an error: A = ST code (see the table above). |
| Cy = 1 | Transport error: A = FFh no card, FEh timeout after the retries, FDh unexpected reply. |

All registers may change, unless stated otherwise.

### Variables used as parameters

| Variable | Size | Use |
| --- | --- | --- |
| `r8_addr` | 4 bytes | Physical address for `r8_write`, `r8_read`, `r8_crc`; entry point for `r8_exec`. Advanced by `r8_write`/`r8_read`. |
| `r8_size` | 4 bytes | Length for `r8_crc`. |
| `r8_arg` | 4 bytes | Argument for `r8_exec` (goes to HL). |
| `r8_info` | 11 bytes | HELLO reply: `"R8064"`, protocol version, max message (2), block size (2), features. |
| `r8_evt`, `r8_evlen`, `r8_evf` | 13 + 1 + 1 bytes | Last event: type, data (up to 12 bytes), data length, flag (clear `r8_evf` after use). |
| `r8_tmo` | 1 byte | Reply timeout in units of about 1 s on a 3.58 MHz Z80 (default 2). |

### Routines

| Routine | Input | Output / effect |
| --- | --- | --- |
| `r8_detect` | — | Cy = 1 if there is no cartridge. |
| `r8_open` | — | Detects the card, clears the FIFOs, acknowledges a pending reply and forgets old events. Call it first. |
| `r8_reboot` | — | Restarts the R8064 and waits until the monitor answers PING. |
| `r8_ping` | — | PING. |
| `r8_hello` | — | HELLO; fills `r8_info` and checks the `"R8064"` signature. |
| `r8_write` | HL = MSX source, BC = byte count, `r8_addr` | Writes MSX memory to the R8064 (POKE messages of up to 2,040 bytes). |
| `r8_read` | DE = MSX destination, BC = byte count, `r8_addr` | Reads R8064 memory into the MSX (PEEK messages of up to 2,040 bytes). |
| `r8_crc` | `r8_addr` (8-aligned), `r8_size` | HL = CRC-16 CCITT-FALSE computed by the R8064. |
| `r8_exec` | A = mode, `r8_addr` = entry, `r8_arg` | Starts the program; the reply arrives when it starts. Its end arrives later as an event. |
| `r8_pollevt` | — | Non-blocking. NZ when an event is stored in `r8_evt` (type 01 = program ended, data = exit code (4); 02 = exception, data = cause (1) + EPC (8); 03 = message from the program). |
| `crc_mktab` | — | Builds the CRC table at `R8_CRCTAB` (once). |
| `crc_init` | — | Local CRC = FFFFh (`r8_lcrc`). |
| `crc_upd` | HL = data, BC = count | Updates `r8_lcrc`. |

### Example: send a program, run it and wait for the result

```
        call r8_open
        jr c,error
        call r8_hello
        jr c,error              ; transport error (A = FFh/FEh/FDh)
        jr nz,error             ; the R8064 replied with ST <> 0
        ld hl,0
        ld (r8_addr+2),hl
        ld hl,4000h             ; physical address 00004000h
        ld (r8_addr),hl
        ld hl,myprog            ; send the program
        ld bc,myprog_end-myprog
        call r8_write
        jr c,error
        jr nz,error
        ld hl,4000h             ; entry point
        ld (r8_addr),hl
        ld hl,0                 ; argument
        ld (r8_arg),hl
        ld (r8_arg+2),hl
        ld a,1                  ; mode 01h: Z80, DRAM timing
        call r8_exec
        jr c,error
        jr nz,error
wait:   call r8_pollevt
        jr z,wait
        xor a
        ld (r8_evf),a
        ld a,(r8_evt)           ; 01h = ended
        ld hl,(r8_evt+1)        ; exit code, low 16 bits
```

To read results back: set `r8_addr`, then `ld de,buffer` / `ld bc,count` / `call r8_read`.

### Speed

Data goes through the FIFOs with OTIR/INIR: about 14 ms per 2,040-byte message on a 3.58 MHz Z80, plus the R8064
processing time (well below 1 ms). Sending 5,000 bytes, including the local CRC, takes about 0.23 s.

## 5. Testing without hardware

[`modulos/13_soc/msx/sim`](../modulos/13_soc/msx/sim) contains a test bench that runs `R8064.COM` on the Z80
reference model of module 12, with an MSX-DOS 1 emulation and a model of the cartridge (ports and STATUS bits as in
`r8064_fifo_if.v` / `r8064_slot_dec.v`, message checks as in `fw/monitor.asm`; EXEC runs the program on a second Z80):

```
cd modulos/13_soc/msx/sim
sh run_tests.sh            # set SJASM=/path/to/sjasmplus if it is not on the PATH
```

The 17 cases cover HELLO, PING, no card, send/get at aligned and unaligned addresses with CRC, dump, send + execute
with the result read back, R800 mode, a lost message recovered by retry, an unsolicited event, restart, timeout after
the retries and parameter checks.
