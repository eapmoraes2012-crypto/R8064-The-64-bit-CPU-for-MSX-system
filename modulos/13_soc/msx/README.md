# MSX side: R8064.COM and the r8064io driver

Z80 software that runs **on the MSX** to send and read data and programs to/from the R8064 cartridge,
using the REV46 message protocol (chapter 8 of the datasheet). It uses only layer 1 (the message FIFOs on
I/O ports 0Bh–0Dh), so it works on the V9968_Cartridge board, which has only A0–A7, D0–D7, /IORQ, /RD and /WR
(the 8000h–BFFFh window needs /SLTSL, A8–A15 and /MREQ and is not used). Plain Z80 code: it also runs on the R800.

| File | Contents |
| --- | --- |
| `r8064io.asm` | Driver (include file): detection, transaction with SEQ, 1 s timeout and 3 retries, POKE/PEEK in 2,040-byte messages, HELLO, PING, CRC, EXEC, events (EVT), restart, local CRC-16 CCITT-FALSE |
| `r8064.asm` | `R8064.COM`, MSX-DOS 1/2 command-line tool built on the driver |
| `R8064.COM` | Ready-to-use binary (3.9 KB) |
| `sim/` | Test bench: Z80 model (module 12) + MSX-DOS 1 shim + cartridge/monitor model; `run_tests.sh`, `tprog.asm` |

## R8064.COM

```
R8064 I                         card info (HELLO)
R8064 P                         PING
R8064 B                         restart the R8064 and wait for the monitor
R8064 S addr file               send a file to the R8064 memory (+ CRC check)
R8064 G addr size file          get an R8064 memory area into a file
R8064 D addr [size]             hex dump (default 80h bytes, max 2040)
R8064 X addr [mode [arg]]       execute at addr and wait for the end (EVT 01)
R8064 R addr file [mode [arg]]  send the file, then execute it at addr
```

- Numbers are hexadecimal (an `H` suffix is accepted). `addr` is the R8064 physical address, 0–7FFFFFh (8 MB SDRAM).
- `mode`: 0 Z80 ROM, 1 Z80 DRAM (default), 2 R800 ROM, 3 R800 DRAM, 4 native 64-bit. `arg` reaches the program in HL.
- In monitor v1 the EXEC entry must be below 10000h. With A8h = 00h the R8064 logical address is the physical address,
  and the monitor itself uses 0000h–37FFh, so **load programs at 4000h–FFFFh**. The program ends with `RET` and returns
  its exit code in HL; the tool prints it when the EVT 01 arrives (any key stops waiting).
- `S` and `R` compare the CRC-16 computed by the R8064 (op 30h) with the CRC of the file when the address is 8-aligned.

Example (program `TPROG.BIN` adds the bytes of a block at 5000h):

```
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

## Using the driver in your own program

Include `r8064io.asm` and define `R8_CRCTAB` (a 256-aligned 512-byte area) if you use the local CRC. Message routines
return Cy = 0 with A = ST (Z when ST = 0) when the R8064 replied, or Cy = 1 with A = local error (FFh no card,
FEh timeout, FDh unexpected reply).

```
        call r8_open            ; detect, clear FIFOs, forget old events
        call r8_hello           ; check the "R8064" signature
        ld hl,0                 ; r8_addr = 00004000h (physical)
        ld (r8_addr+2),hl
        ld hl,4000h
        ld (r8_addr),hl
        ld hl,myprog            ; send BC bytes from HL
        ld bc,myprog_len
        call r8_write
        ld hl,4000h             ; entry
        ld (r8_addr),hl
        ld a,1                  ; mode 01h: Z80 DRAM
        call r8_exec
wait:   call r8_pollevt         ; NZ when r8_evt holds an event (type, data)
        jr z,wait
```

`r8_read` (DE = destination, BC = count) reads back in the same way. Large transfers are split into POKE/PEEK messages
of up to 2,040 bytes (about 14 ms each on a 3.58 MHz Z80 with OTIR/INIR).

## Build and test

```
sjasmplus --raw=R8064.COM r8064.asm
cd sim && sh run_tests.sh          # SJASM=/path/to/sjasmplus if it is not on the PATH
```

`run_tests.sh` runs 17 cases against the cartridge model: HELLO, PING, no card, send/get 5,000 bytes at aligned and
unaligned addresses with CRC, dump, send + EXEC (the program runs on a second Z80 over the R8064 memory and its result
is read back), R800 mode, lost message with retry, unsolicited EVT, restart, timeout after the retries, and argument
checks. The cartridge model follows `r8064_fifo_if.v`/`r8064_slot_dec.v` (STATUS bits, shared LEN with the L/H pointer,
2,048-byte FIFOs) and the message checks of `fw/monitor.asm`. Not yet tested on hardware.
