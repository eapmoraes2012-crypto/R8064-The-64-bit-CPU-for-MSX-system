; ============================================================================
; r8064.asm - R8064.COM, MSX-DOS tool to send and read data and programs
;             to/from the R8064 cartridge (protocol REV46, layer 1: ports 0Bh-0Dh)
; ----------------------------------------------------------------------------
; Build:   sjasmplus --raw=R8064.COM r8064.asm
; Runs on MSX-DOS 1 and 2 (uses only the CP/M-style FCB calls of MSX-DOS 1).
;
;   R8064 I                         card info (HELLO)
;   R8064 P                         PING
;   R8064 B                         restart the R8064 and wait for the monitor
;   R8064 S addr file               send a file to the R8064 memory (+ CRC check)
;   R8064 G addr size file          get an R8064 memory area into a file
;   R8064 D addr [size]             hex dump (default 80h bytes, max 2040)
;   R8064 X addr [mode [arg]]       execute at addr and wait for the end (EVT)
;   R8064 R addr file [mode [arg]]  send the file, then execute it at addr
;
; Numbers are hexadecimal (an "H" suffix is accepted). addr is the R8064
; physical address (0..7FFFFFh, 8 MB SDRAM). mode: 0 Z80 ROM, 1 Z80 DRAM
; (default), 2 R800 ROM, 3 R800 DRAM, 4 native 64-bit. arg goes to the
; program in HL. In v1 of the monitor the EXEC entry must be below 10000h:
; with A8h = 00h the R8064 logical address = physical address, and the monitor
; itself uses 0000h-37FFh, so load programs at 4000h-FFFFh. The program ends
; with RET and returns its exit code in HL.
; ============================================================================

BDOS    equ 0005h
CMDLEN  equ 0080h
CMDTXT  equ 0081h

        org 0100h

start:  call crc_mktab
        ld a,(CMDLEN)           ; terminate the command line with 0
        ld l,a
        ld h,0
        ld de,CMDTXT
        add hl,de
        ld (hl),0
        ld hl,CMDTXT
        call skipsp
        ld a,(hl)
        or a
        jp z,usage
        call upcase
        inc hl
        ld c,a
        ld a,(hl)               ; the command is a single letter
        cp ' '+1
        jp nc,usage
        ld (lineptr),hl
        ld de,cmdtab
dsp_l:  ld a,(de)               ; HL = routine, then the letter
        inc de
        ld l,a
        ld a,(de)
        inc de
        ld h,a
        or l
        jp z,usage              ; end of the table
        ld a,(de)
        inc de
        cp c
        jr nz,dsp_l
        push hl                 ; "jump" to the routine with HL = rest of the line
        ld hl,(lineptr)
        ret

cmdtab: dw cmd_info
        db 'I'
        dw cmd_ping
        db 'P'
        dw cmd_boot
        db 'B'
        dw cmd_send
        db 'S'
        dw cmd_get
        db 'G'
        dw cmd_dump
        db 'D'
        dw cmd_exec
        db 'X'
        dw cmd_run
        db 'R'
        dw 0

; ---------------------------------------------------------------- I / P / B
cmd_info:
        call connect
        call pmsg
        db "R8064 found: protocol v",0
        ld a,(r8_info+5)
        call phex8
        call pmsg
        db ", max message ",0
        ld hl,(r8_info+6)
        call phex16
        call pmsg
        db "h, block ",0
        ld hl,(r8_info+8)
        call phex16
        call pmsg
        db "h",13,10,"Features:",0
        ld a,(r8_info+10)
        ld c,a
        bit 0,c
        call nz,pmsg_w
        bit 1,c
        call nz,pmsg_x
        bit 2,c
        call nz,pmsg_c
        jp done

pmsg_w: call pmsg
        db " window",0
        ret
pmsg_x: call pmsg
        db " EXEC",0
        ret
pmsg_c: call pmsg
        db " CRC",0
        ret

cmd_ping:
        call r8_open
        call chk
        call r8_ping
        call chk
        call pmsg
        db "PING ok",0
        jp done

cmd_boot:
        call r8_reboot
        call chk
        call pmsg
        db "R8064 restarted, monitor answering",0
        jp done

; ---------------------------------------------------------------- S / R
cmd_send:
        call getaddr
        call getname
        call endline
        call connect
        call do_send
        jp done

cmd_run:
        call getaddr
        call chkentry
        call getname
        call getmode
        call endline
        call connect
        call do_send
        call crlf
        call do_exec
        jp done

do_send:
        ld de,fcb               ; open the file
        ld c,0Fh
        call BDOS
        or a
        jp nz,e_nofile
        call fcb_rnd
        ld hl,saddr
        ld de,r8_addr
        ld bc,4
        ldir
        ld hl,0
        ld (total),hl
        ld (total+2),hl
        call crc_init
        call pmsg
        db "Sending",0
sn_l:   ld de,buf
        ld c,1Ah                ; DTA
        call BDOS
        ld de,fcb
        ld hl,R8_CHUNK
        ld c,27h                ; random block read, HL = bytes read
        call BDOS
        ld a,h
        or l
        jr z,sn_end
        ld (nbytes),hl
        ld b,h
        ld c,l
        ld hl,buf
        call crc_upd
        ld hl,buf
        ld bc,(nbytes)
        call r8_write
        call chk
        ld de,(nbytes)
        call addtot
        ld a,'.'
        call putc
        ld hl,(nbytes)
        ld de,R8_CHUNK
        or a
        sbc hl,de
        jr z,sn_l
sn_end: ld de,fcb
        ld c,10h
        call BDOS
        call crlf
        ld hl,total
        call phex32
        call pmsg
        db "h bytes written at ",0
        ld hl,saddr
        call phex32
        call pmsg
        db "h",13,10,0
        ld hl,(total)           ; empty file: nothing to verify
        ld a,h
        or l
        ld hl,(total+2)
        or h
        or l
        ret z
        ld a,(saddr)            ; the R8064 CRC needs an 8-aligned start
        and 07h
        jr z,sn_crc
        call pmsg
        db "CRC check skipped (address not 8-aligned)",0
        ret
sn_crc: ld hl,saddr
        ld de,r8_addr
        ld bc,4
        ldir
        ld hl,total
        ld de,r8_size
        ld bc,4
        ldir
        call r8_crc
        call chk
        ld de,(r8_lcrc)
        push hl
        or a
        sbc hl,de
        pop hl
        jr nz,sn_bad
        call pmsg
        db "CRC ok: ",0
        jp phex16
sn_bad: push de
        call pmsg
        db "CRC MISMATCH: R8064 ",0
        call phex16
        call pmsg
        db ", file ",0
        pop hl
        call phex16
        jp fail

; ---------------------------------------------------------------- G
cmd_get:
        call getaddr
        call gethex             ; size (4 bytes)
        jp c,usage
        push hl
        ld hl,val
        ld de,gsize
        ld bc,4
        ldir
        pop hl
        call getname
        call endline
        call connect
        ld de,fcb
        ld c,16h                ; create
        call BDOS
        or a
        jp nz,e_create
        call fcb_rnd
        ld hl,saddr
        ld de,r8_addr
        ld bc,4
        ldir
        ld de,buf
        ld c,1Ah
        call BDOS
        call pmsg
        db "Reading",0
gt_l:   ld hl,(gsize)
        ld de,(gsize+2)
        ld a,h
        or l
        or d
        or e
        jr z,gt_end
        ld a,d                  ; n = min(gsize, R8_CHUNK)
        or e
        ld hl,R8_CHUNK
        jr nz,gt_n
        ld hl,(gsize)
        ld de,R8_CHUNK
        or a
        sbc hl,de
        ld hl,R8_CHUNK
        jr nc,gt_n
        ld hl,(gsize)
gt_n:   ld (nbytes),hl
        ld b,h
        ld c,l
        ld de,buf
        call r8_read
        call chk
        ld de,fcb
        ld hl,(nbytes)
        ld c,26h                ; random block write
        call BDOS
        or a
        jp nz,e_write
        ld hl,(gsize)           ; gsize -= n
        ld de,(nbytes)
        or a
        sbc hl,de
        ld (gsize),hl
        ld hl,(gsize+2)
        ld de,0
        sbc hl,de
        ld (gsize+2),hl
        ld a,'.'
        call putc
        jr gt_l
gt_end: ld de,fcb
        ld c,10h
        call BDOS
        call crlf
        call pmsg
        db "File written",0
        jp done

; ---------------------------------------------------------------- D
cmd_dump:
        call getaddr
        ld de,80h
        call getopt
        jr z,du_s
        push hl
        ld a,(val+2)            ; size, at most R8_CHUNK
        ld hl,val+3
        or (hl)
        jp nz,usage
        ld de,(val)
        ld hl,R8_CHUNK
        or a
        sbc hl,de
        jp c,usage
        ld a,d
        or e
        jp z,usage
        pop hl
du_s:   ld (nbytes),de
        call endline
        call r8_open
        call chk
        ld hl,saddr
        ld de,r8_addr
        ld bc,4
        ldir
        ld de,buf
        ld bc,(nbytes)
        call r8_read
        call chk
        ld ix,buf
du_ln:  ld hl,saddr             ; address (6 digits)
        ld a,(hl)
        inc hl
        ld e,(hl)
        inc hl
        ld a,(hl)
        call phex8
        ld a,e
        call phex8
        ld a,(saddr)
        call phex8
        ld a,' '
        call putc
        ld hl,(nbytes)          ; B = bytes on this line (max 8)
        ld a,h
        or a
        ld b,8
        jr nz,du_b
        ld a,l
        cp 8
        jr nc,du_b
        ld b,l
du_b:   push bc
        push ix
du_h:   ld a,(ix+0)
        call phex8
        ld a,' '
        call putc
        inc ix
        djnz du_h
        pop ix
        pop bc
        ld a,8                  ; pad a short last line
        sub b
        jr z,du_a
        ld c,a
du_p:   call pmsg
        db "   ",0
        dec c
        jr nz,du_p
du_a:   ld a,(ix+0)             ; ASCII
        cp ' '
        jr c,du_dot
        cp 7Fh
        jr c,du_c
du_dot: ld a,'.'
du_c:   call putc
        inc ix
        push bc
        ld hl,saddr             ; address += 1
        call inc32
        ld hl,(nbytes)
        dec hl
        ld (nbytes),hl
        pop bc
        djnz du_a
        call crlf
        ld hl,(nbytes)
        ld a,h
        or l
        jr nz,du_ln
        ld c,0
        jp BDOS

; ---------------------------------------------------------------- X
cmd_exec:
        call getaddr
        call chkentry
        call getmode
        call endline
        call connect
        call do_exec
        jp done

do_exec:
        ld hl,saddr
        ld de,r8_addr
        ld bc,4
        ldir
        ld hl,argv
        ld de,r8_arg
        ld bc,4
        ldir
        ld a,(mode)
        call r8_exec
        call chk
        call pmsg
        db "Running at ",0
        ld hl,(saddr)
        call phex16
        call pmsg
        db "h, mode ",0
        ld a,(mode)
        call phex8
        call pmsg
        db " (any key: stop waiting)",13,10,0
ex_w:   call r8_pollevt
        jr nz,ex_ev
        ld e,0FFh               ; direct console input, no wait
        ld c,06h
        call BDOS
        or a
        jr z,ex_w
        call pmsg
        db "Stopped waiting; the program may still be running",0
        jp fail
ex_ev:  xor a
        ld (r8_evf),a
        ld a,(r8_evt)
        cp R8EV_END
        jr nz,ex_e2
        call pmsg
        db "Program ended, exit code ",0
        ld hl,r8_evt+1
        call phex32
        ld a,'h'
        call putc
        ret
ex_e2:  cp R8EV_EXC
        jr nz,ex_e3
        call pmsg
        db "EXCEPTION, cause ",0
        ld a,(r8_evt+1)
        call phex8
        call pmsg
        db "h, EPC ",0
        ld hl,r8_evt+6
        call phex32
        ld hl,r8_evt+2
        call phex32
        ld a,'h'
        call putc
        jp fail
ex_e3:  push af
        call pmsg
        db "Event ",0
        pop af
        call phex8
        ld a,':'
        call putc
        ld a,(r8_evlen)
        or a
        ret z
        ld b,a
        ld hl,r8_evt+1
ex_b:   ld a,' '
        call putc
        ld a,(hl)
        call phex8
        inc hl
        djnz ex_b
        ret

; ---------------------------------------------------------------- common pieces
connect:                        ; open + HELLO, errors end the program
        call r8_open
        call chk
        call r8_hello
        jp chk

chk:    jr c,ck_f               ; Cy = 0 and A = 0: ok
        or a
        ret z
ck_f:   push af
        call crlf
        pop af
        jr c,ck_t
        push af
        call pmsg
        db "R8064 error ",0
        pop af
        push af
        call phex8
        call pmsg
        db ": ",0
        pop af
        ld hl,st_tab
        cp 08h
        jr c,ck_s
        xor a
ck_s:   add a,a
        ld e,a
        ld d,0
        add hl,de
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        call pstr
        jp fail
ck_t:   ld hl,m_nocard
        cp R8E_NOCARD
        jr z,ck_p
        ld hl,m_tmo
        cp R8E_TIMEOUT
        jr z,ck_p
        ld hl,m_short
ck_p:   call pstr
        jp fail

st_tab: dw m_st0,m_st1,m_st2,m_st3,m_st4,m_st5,m_st6,m_st7
m_st0:  db "unknown",0
m_st1:  db "unknown command",0
m_st2:  db "invalid parameter",0
m_st3:  db "address outside SDRAM / not aligned",0
m_st4:  db "busy",0
m_st5:  db "window unavailable",0
m_st6:  db "execution error",0
m_st7:  db "timeout in the R8064",0
m_nocard: db "No R8064 cartridge found (port 0Bh)",0
m_tmo:  db "The R8064 does not answer (timeout)",0
m_short: db "Unexpected reply from the R8064",0

e_nofile:
        call pmsg
        db "File not found",0
        jp fail
e_create:
        call pmsg
        db "Cannot create the file",0
        jp fail
e_write:
        call crlf
        call pmsg
        db "Disk write error",0
        jp fail

usage:  call pmsg
        db "R8064.COM - MSX <-> R8064 transfer tool",13,10
        db "R8064 I                    card info",13,10
        db "R8064 P                    ping",13,10
        db "R8064 B                    restart R8064",13,10
        db "R8064 S addr file          send file",13,10
        db "R8064 G addr size file     get to file",13,10
        db "R8064 D addr [size]        dump",13,10
        db "R8064 X addr [mode [arg]]  execute",13,10
        db "R8064 R addr file [mode [arg]]",13,10
        db "                           send + exec",13,10
        db "Hex numbers. mode: 0 Z80 ROM, 1 Z80 DRAM,",13,10
        db "2 R800 ROM, 3 R800 DRAM, 4 native",0
        jp exit

done:   call crlf
        call pmsg
        db "OK",0
fail:
exit:   call crlf
        ld c,0
        jp BDOS

; ---------------------------------------------------------------- parsing
; getaddr: hex address -> saddr (must be < 800000h)
getaddr:
        call gethex
        jp c,usage
        ld a,(val+3)
        or a
        jp nz,e_range
        ld a,(val+2)
        and 80h
        jp nz,e_range
        push hl
        ld hl,val
        ld de,saddr
        ld bc,4
        ldir
        pop hl
        ret
e_range: call pmsg
        db "Address outside the 8 MB SDRAM",0
        jp fail

chkentry:                       ; EXEC entry below 10000h (monitor v1)
        ld a,(saddr+2)
        or a
        ret z
        call pmsg
        db "EXEC entry must be below 10000h",0
        jp fail

; getmode: [mode [arg]] -> mode (default 1), argv (default 0)
getmode:
        ld de,1
        call getopt
        jr z,gm_1
        ld a,(val+1)
        or a
        jp nz,usage
        ld a,(val)
        cp 05h
        jp nc,usage
        ld e,a
gm_1:   ld a,e
        ld (mode),a
        ld de,0
        ld (val),de
        ld (val+2),de
        call getopt
        push hl
        ld hl,val
        ld de,argv
        ld bc,4
        ldir
        pop hl
        ret

; getopt: optional hex number. Z = absent (DE unchanged); NZ = present in val
getopt: call skipsp
        ld a,(hl)
        or a
        ret z
        push de
        call gethex
        pop de
        jp c,usage
        or 1                    ; NZ
        ret

endline:
        call skipsp
        ld a,(hl)
        or a
        ret z
        jp usage

; gethex: HL = text -> val (4 bytes). Cy = 1 if there is no valid number
gethex: call skipsp
        xor a
        ld (val),a
        ld (val+1),a
        ld (val+2),a
        ld (val+3),a
        ld c,a                  ; C = digit count
gh_l:   ld a,(hl)
        call hexdig
        jr c,gh_e
        inc c
        ld b,4                  ; val <<= 4
        push hl
gh_s:   ld hl,val
        sla (hl)
        inc hl
        rl (hl)
        inc hl
        rl (hl)
        inc hl
        rl (hl)
        djnz gh_s
        ld hl,val
        or (hl)
        ld (hl),a
        pop hl
        inc hl
        jr gh_l
gh_e:   ld a,c
        or a
        scf
        ret z                   ; no digits
        cp 9
        ccf
        ret c                   ; more than 8 digits
        ld a,(hl)
        call upcase
        cp 'H'
        jr nz,gh_t
        inc hl
gh_t:   ld a,(hl)               ; must end at a blank
        or a
        ret z
        cp ' '+1
        ccf
        ret

hexdig: call upcase             ; A = '0'..'9','A'..'F' -> 0..15; Cy = 1 if not hex
        sub '0'
        ret c
        cp 10
        ccf
        ret nc
        sub 'A'-'0'
        ret c
        cp 6
        ccf
        ret c
        add a,10
        ret

upcase: cp 'a'
        ret c
        cp 'z'+1
        ret nc
        sub 20h
        ret

skipsp: ld a,(hl)
        cp ' '
        jr z,sk_n
        cp 9
        ret nz
sk_n:   inc hl
        jr skipsp

; getname: file name -> fcb (drive optional, 8.3)
getname:
        call skipsp
        ld a,(hl)
        or a
        jp z,usage
        push hl
        ld hl,fcb               ; clear the FCB, blank name and extension
        ld de,fcb+1
        ld bc,36
        ld (hl),0
        ldir
        ld hl,fcb+1
        ld de,fcb+2
        ld bc,10
        ld (hl),' '
        ldir
        pop hl
        inc hl
        ld a,(hl)
        dec hl
        cp ':'
        jr nz,gn_n
        ld a,(hl)
        call upcase
        sub 'A'-1
        ld (fcb),a
        inc hl
        inc hl
gn_n:   ld de,fcb+1
        ld b,8
        call gn_part
        ld a,(hl)
        cp '.'
        ret nz
        inc hl
        ld de,fcb+9
        ld b,3
gn_part:
        ld a,(hl)
        or a
        ret z
        cp ' '+1
        ret c
        cp '.'
        ret z
        inc hl
        inc b                   ; characters beyond B are skipped
        dec b
        jr z,gn_part
        call upcase
        ld (de),a
        inc de
        dec b
        jr gn_part

fcb_rnd:                        ; record size 1, random record 0
        ld hl,1
        ld (fcb+0Eh),hl
        ld hl,0
        ld (fcb+21h),hl
        ld (fcb+23h),hl
        ret

; ---------------------------------------------------------------- arithmetic
addtot: ld hl,(total)           ; total += DE
        add hl,de
        ld (total),hl
        ld hl,(total+2)
        ld de,0
        adc hl,de
        ld (total+2),hl
        ret

inc32:  inc (hl)                ; (HL) 4 bytes += 1
        ret nz
        inc hl
        inc (hl)
        ret nz
        inc hl
        inc (hl)
        ret nz
        inc hl
        inc (hl)
        ret

; ---------------------------------------------------------------- output
putc:   push af
        push bc
        push de
        push hl
        push ix
        ld e,a
        ld c,02h
        call BDOS
        pop ix
        pop hl
        pop de
        pop bc
        pop af
        ret

pstr:   ld a,(hl)               ; HL = 0-terminated text
        or a
        ret z
        call putc
        inc hl
        jr pstr

pmsg:   ex (sp),hl              ; text follows the CALL
        call pstr
        inc hl
        ex (sp),hl
        ret

crlf:   call pmsg
        db 13,10,0
        ret

phex32: inc hl                  ; (HL) 4 bytes, little-endian
        inc hl
        inc hl
        ld b,4
p32_l:  ld a,(hl)
        call phex8
        dec hl
        djnz p32_l
        ret

phex16: ld a,h
        call phex8
        ld a,l
phex8:  push af
        rrca
        rrca
        rrca
        rrca
        call phex4
        pop af
phex4:  and 0Fh
        add a,90h
        daa
        adc a,40h
        daa
        jp putc

        include "r8064io.asm"

; ---------------------------------------------------------------- variables
saddr:  ds 4
val:    ds 4
gsize:  ds 4
total:  ds 4
argv:   ds 4
nbytes: dw 0
lineptr: dw 0
mode:   db 0
fcb:    ds 37
endprog:
; outside the .COM file (free TPA memory after the program):
R8_CRCTAB equ (endprog+255) & 0FF00h     ; 512-byte CRC table, 256-aligned
buf     equ R8_CRCTAB+512                ; R8_CHUNK-byte transfer buffer
