; ============================================================================
; r8064io.asm - MSX-side driver for the R8064 cartridge (protocol REV46, layer 1)
; ----------------------------------------------------------------------------
; Plain Z80 code (runs on Z80 and R800). Talks to the R8064 only through the
; message FIFOs on I/O ports 0Bh-0Dh, so it works on the V9968_Cartridge board
; (A0-A7, D0-D7, /IORQ, /RD, /WR only: no 8000h-BFFFh window, no slot switching).
;
;   Port 0Bh  read : STATUS  b0 DATA  b1 SPACE  b2 BUSY  b3 DONE  b4 IRQ
;                            b5 WINDOW  b6 ERROR  b7 always 0 (FFh = no card)
;             write: COMMAND b0 START  b1 clear FIFOs/LEN pointer/ERROR
;                            b2 enable /INT  b3 restart R8064  b7 clear DONE/IRQ
;   Port 0Ch  DATA   write: MSX->R8064 FIFO   read: R8064->MSX FIFO (2048 bytes each)
;   Port 0Dh  LEN    LEN_L then LEN_H (alternating pointer; always access in pairs)
;
; Message:  request  OP, SEQ, parameters...        (little-endian)
;           reply    OP|80h, SEQ, ST, data...       ST = 0 ok
;           event    F0h, 00h, type, data...        (sent by the R8064)
;
; Public routines (all registers may change unless stated):
;   r8_detect   Cy=1 if no card (A = R8E_NOCARD)
;   r8_open     detect + clear FIFOs + ack DONE + forget events
;   r8_reboot   restart the R8064 and wait until the monitor answers PING
;   r8_ping     PING
;   r8_hello    HELLO; r8_info = "R8064", ver, maxmsg(2), block(2), features
;   r8_write    write BC bytes from HL (MSX) to physical address r8_addr
;   r8_read     read  BC bytes from physical address r8_addr into DE (MSX)
;               (both split into POKE/PEEK messages of up to R8_CHUNK bytes
;                and advance r8_addr)
;   r8_crc      CRC-16 (R8064 side) of r8_size bytes at r8_addr (8-aligned) -> HL
;   r8_exec     EXEC: entry = r8_addr (< 10000h in v1), A = mode, arg = r8_arg
;   r8_pollevt  non-blocking: NZ if an event is waiting in r8_evt
;   crc_init / crc_upd   local CRC-16 CCITT-FALSE (table based)
;
; Return convention of the message routines:
;   Cy=0 : the R8064 replied; A = ST (0 = ok, see R8ST_*), Z set when ST = 0
;   Cy=1 : transport error; A = R8E_* (no card, timeout after retries)
; ============================================================================

R8_STAT     equ 0Bh
R8_DATA     equ 0Ch
R8_LEN      equ 0Dh

R8C_START   equ 01h
R8C_CLEAR   equ 02h
R8C_RESET   equ 08h
R8C_ACK     equ 80h

R8S_DATA    equ 01h
R8S_SPACE   equ 02h
R8S_BUSY    equ 04h
R8S_DONE    equ 08h
R8S_ERROR   equ 40h

R8_CHUNK    equ 2040        ; bytes of data per POKE/PEEK message
R8_TRIES    equ 4           ; 1 try + 3 retries
R8_TMO_STD  equ 2           ; timeout units (1 unit ~ 1 s on a 3.58 MHz Z80)
R8_TMO_LONG equ 30          ; CRC over large areas

R8OP_PING   equ 00h
R8OP_HELLO  equ 01h
R8OP_RESET  equ 02h
R8OP_POKE   equ 12h
R8OP_PEEK   equ 13h
R8OP_EXEC   equ 20h
R8OP_STOP   equ 21h
R8OP_CRC    equ 30h
R8OP_EVT    equ 0F0h

R8ST_OK     equ 00h         ; R8064 status codes (ST)
R8ST_UNK    equ 01h
R8ST_PARAM  equ 02h
R8ST_ADDR   equ 03h
R8ST_BUSY   equ 04h
R8ST_WIN    equ 05h
R8ST_EXEC   equ 06h
R8ST_TMO    equ 07h

R8E_NOCARD  equ 0FFh        ; local (transport) errors, returned with Cy=1
R8E_TIMEOUT equ 0FEh
R8E_SHORT   equ 0FDh        ; reply shorter than expected

R8EV_END    equ 01h         ; event types
R8EV_EXC    equ 02h
R8EV_MSG    equ 03h

; ---------------------------------------------------------------- detect / open
r8_detect:
        in a,(R8_STAT)
        and 80h                 ; bit 7 is always 0 on the card; FFh = empty bus
        ret z
        ld a,R8E_NOCARD
        scf
        ret

r8_open:
        call r8_detect
        ret c
        ld a,R8C_CLEAR
        out (R8_STAT),a
        ld a,R8C_ACK
        out (R8_STAT),a
        xor a
        ld (r8_evf),a
        ld a,R8_TMO_STD
        ld (r8_tmo),a
        xor a
        ret

; restart the R8064 (COMMAND bit 3), then PING until it answers
r8_reboot:
        call r8_detect
        ret c
        ld a,R8C_RESET
        out (R8_STAT),a
        ld b,0                  ; ~0.15 s pause (the monitor boots from SDRAM)
rb_d:   push bc
        ld b,0
rb_d2:  djnz rb_d2
        pop bc
        djnz rb_d
        call r8_open
        ret c
        ; fall into r8_ping (it already retries R8_TRIES times)

; ---------------------------------------------------------------- PING / HELLO
r8_ping:
        ld a,R8OP_PING
        ld b,2
        call r8_hdr0
        jp r8_xfer

r8_hello:
        ld a,R8OP_HELLO
        ld b,3
        call r8_hdr0
        ld a,1                  ; host protocol version
        ld (r8_hdr+2),a
        ld hl,r8_info
        ld (r8_rp),hl
        ld hl,11
        ld (r8_rmax),hl
        call r8_xfer
        ret c
        ret nz
        ld hl,(r8_rlen)         ; expect 11 bytes and the "R8064" signature
        ld de,11
        or a
        sbc hl,de
        jr c,r8_short
        ld hl,r8_info
        ld de,r8_sig
        ld b,5
he_c:   ld a,(de)
        cp (hl)
        jr nz,r8_short
        inc hl
        inc de
        djnz he_c
        xor a
        ret
r8_short:
        ld a,R8E_SHORT
        scf
        ret
r8_sig: db "R8064"

; A = OP, B = header length. Clears payload/reply descriptors.
r8_hdr0:
        ld (r8_hdr),a
        ld a,b
        ld (r8_hlen),a
        ld hl,0
        ld (r8_pl),hl
        ld (r8_rmax),hl
        ret

; copy the 4-byte r8_addr into r8_hdr+2..5
r8_hdra:
        ld hl,r8_addr
        ld de,r8_hdr+2
        ld bc,4
        ldir
        ret

; ---------------------------------------------------------------- write / read memory
; r8_write: HL = MSX source, BC = byte count, r8_addr = physical destination
r8_write:
        ld (r8_ptr),hl
        ld (r8_cnt),bc
wr_l:   ld hl,(r8_cnt)
        ld a,h
        or l
        ret z                   ; done: A = 0, Z, Cy = 0
        call r8_take            ; HL = min(count, R8_CHUNK)
        ld (r8_pl),hl
        ld a,R8OP_POKE
        ld (r8_hdr),a
        ld a,6
        ld (r8_hlen),a
        call r8_hdra
        ld hl,(r8_ptr)
        ld (r8_pp),hl
        ld hl,0
        ld (r8_rmax),hl
        call r8_xfer
        ret c
        ret nz
        ld hl,(r8_pl)
        call r8_adv
        jr wr_l

; r8_read: DE = MSX destination, BC = byte count, r8_addr = physical source
r8_read:
        ld (r8_ptr),de
        ld (r8_cnt),bc
rd_l:   ld hl,(r8_cnt)
        ld a,h
        or l
        ret z
        call r8_take
        ld (r8_rmax),hl
        ld (r8_hdr+6),hl        ; size (2)
        ld a,R8OP_PEEK
        ld (r8_hdr),a
        ld a,8
        ld (r8_hlen),a
        call r8_hdra
        ld hl,0
        ld (r8_pl),hl
        ld hl,(r8_ptr)
        ld (r8_rp),hl
        call r8_xfer
        ret c
        ret nz
        ld hl,(r8_rlen)         ; the reply must carry all the bytes asked for
        ld de,(r8_rmax)
        or a
        sbc hl,de
        jp nz,r8_short
        ld hl,(r8_rmax)
        call r8_adv
        jr rd_l

; HL = min(r8_cnt, R8_CHUNK)
r8_take:
        ld hl,(r8_cnt)
        ld de,R8_CHUNK
        or a
        sbc hl,de
        jr c,tk_s
        ex de,hl                ; HL = R8_CHUNK
        ret
tk_s:   ld hl,(r8_cnt)
        ret

; advance pointer, count and the 32-bit address by HL bytes
r8_adv:
        ex de,hl
        ld hl,(r8_ptr)
        add hl,de
        ld (r8_ptr),hl
        ld hl,(r8_cnt)
        or a
        sbc hl,de
        ld (r8_cnt),hl
        ld hl,(r8_addr)
        add hl,de
        ld (r8_addr),hl
        ld hl,(r8_addr+2)
        ld de,0
        adc hl,de
        ld (r8_addr+2),hl
        ret

; ---------------------------------------------------------------- CRC (R8064 side)
; r8_addr = start (8-aligned), r8_size = 4-byte length -> HL = CRC-16
r8_crc:
        ld a,R8OP_CRC
        ld b,10
        call r8_hdr0
        call r8_hdra
        ld hl,r8_size
        ld de,r8_hdr+6
        ld bc,4
        ldir
        ld hl,r8_crcr
        ld (r8_rp),hl
        ld hl,2
        ld (r8_rmax),hl
        ld a,R8_TMO_LONG
        ld (r8_tmo),a
        call r8_xfer
        push af
        ld a,R8_TMO_STD
        ld (r8_tmo),a
        pop af
        ret c
        ret nz
        ld hl,(r8_rlen)
        ld a,h
        or a
        jr nz,cr_ok
        ld a,l
        cp 2
        jp c,r8_short
cr_ok:  ld hl,(r8_crcr)
        xor a
        ret

; ---------------------------------------------------------------- EXEC
; r8_addr = entry (low 16 bits used in v1), A = mode (00h Z80 ROM, 01h Z80 DRAM,
; 02h R800 ROM, 03h R800 DRAM, 04h native 64), r8_arg = argument (4 bytes, goes in HL)
; Reply comes when the program starts; its end arrives later as EVT 01 (r8_pollevt).
r8_exec:
        push af
        ld a,R8OP_EXEC
        ld b,19
        call r8_hdr0
        ld hl,r8_hdr+2          ; zero entry(8), mode(1), arg(8)
        ld de,r8_hdr+3
        ld bc,16
        ld (hl),0
        ldir
        call r8_hdra            ; entry, low 4 bytes
        pop af
        ld (r8_hdr+10),a
        ld hl,r8_arg
        ld de,r8_hdr+11
        ld bc,4
        ldir
        xor a
        ld (r8_evf),a           ; a new program: forget older events
        jp r8_xfer

; ---------------------------------------------------------------- events
; non-blocking. NZ (A = 1) when an event is stored in r8_evt:
;   r8_evt+0 = type, r8_evt+1.. = data (up to 12 bytes), r8_evlen = data length
r8_pollevt:
        ld a,(r8_evf)
        or a
        ret nz
        in a,(R8_STAT)
        and R8S_DONE
        ret z
        call r8_drain1
        ld a,(r8_evf)
        or a
        ret

; ---------------------------------------------------------------- core: one transaction
; In:  r8_hdr (OP first; SEQ is filled here), r8_hlen, r8_pp/r8_pl (payload sent
;      after the header), r8_rp/r8_rmax (where to keep the reply data)
; Out: see the convention at the top; r8_rhdr = OP,SEQ,ST; r8_rlen = data length
r8_xfer:
        ld a,R8_TRIES
        ld (r8_try),a
xf_try: call r8_drain           ; collect anything left (an EVT, a late reply)
        ld a,(r8_seq)           ; new SEQ on each try (1..255; 0 belongs to EVT)
        inc a
        jr nz,xf_s
        inc a
xf_s:   ld (r8_seq),a
        ld (r8_hdr+1),a
        ld hl,r8_hdr            ; header
        ld a,(r8_hlen)
        ld b,a
        ld c,R8_DATA
        otir
        ld hl,(r8_pp)           ; payload
        ld de,(r8_pl)
        call r8_outblk
        ld a,(r8_hlen)          ; LEN = header + payload
        ld l,a
        ld h,0
        ld de,(r8_pl)
        add hl,de
        ld a,l
        out (R8_LEN),a
        ld a,h
        out (R8_LEN),a
        ld a,R8C_START
        out (R8_STAT),a
xf_w:   call r8_wait
        jr c,xf_tmo
        call r8_rxmsg
        ld a,(r8_rhdr)          ; is it the reply to this request?
        ld b,a
        ld a,(r8_hdr)
        or 80h
        cp b
        jr nz,xf_w              ; EVT or stale reply: keep waiting
        ld a,(r8_rhdr+1)
        ld b,a
        ld a,(r8_seq)
        cp b
        jr nz,xf_w
        ld a,(r8_rhdr+2)        ; ST
        or a                    ; Cy = 0, Z if ST = 0
        ret
xf_tmo: ld a,R8C_CLEAR          ; no reply: clear FIFOs and LEN pointer, retry
        out (R8_STAT),a
        ld hl,r8_try
        dec (hl)
        jr nz,xf_try
        ld a,R8E_TIMEOUT
        scf
        ret

; wait for DONE. Cy = 1 on timeout (r8_tmo units of ~1 s on a 3.58 MHz Z80)
r8_wait:
        ld a,(r8_tmo)
        ld b,a
        ld de,0
wt_l:   in a,(R8_STAT)
        and R8S_DONE
        ret nz                  ; Cy = 0
        dec de
        ld a,d
        or e
        jr nz,wt_l
        djnz wt_l
        scf
        ret

; read everything that is waiting (DONE = 1) without keeping reply data
r8_drain:
        in a,(R8_STAT)
        and R8S_DONE
        ret z
r8_drain1:
        ld hl,(r8_rmax)
        push hl
        ld hl,0
        ld (r8_rmax),hl
        call r8_rxmsg
        pop hl
        ld (r8_rmax),hl
        ret

; read one message from the R8064 (DONE = 1) and acknowledge it.
; Header -> r8_rhdr (OP = 0 if the message is shorter than 3 bytes).
; EVT data -> r8_evt (sets r8_evf); other data -> (r8_rp), at most r8_rmax bytes,
; the rest is discarded. r8_rlen = full data length of a reply.
r8_rxmsg:
        in a,(R8_LEN)
        ld l,a
        in a,(R8_LEN)
        ld h,a                  ; HL = message length
        ld de,3
        or a
        sbc hl,de
        jr nc,rx_3
        add hl,de               ; short message: discard it
        ex de,hl
        call r8_skip
        xor a
        ld (r8_rhdr),a
        jr rx_ack
rx_3:   push hl
        ld hl,r8_rhdr
        ld b,3
        ld c,R8_DATA
        inir
        pop hl                  ; HL = data length
        ld a,(r8_rhdr)
        cp R8OP_EVT
        jr z,rx_ev
        ld (r8_rlen),hl
        ld de,(r8_rp)
        ld bc,(r8_rmax)
        jr rx_d
rx_ev:  ld a,(r8_rhdr+2)        ; EVT: F0, 00, type, data
        ld (r8_evt),a
        ld a,l                  ; data length, at most 12 kept
        cp 13
        jr c,rx_e1
        ld a,12
rx_e1:  ld (r8_evlen),a
        ld a,1
        ld (r8_evf),a
        ld de,r8_evt+1
        ld bc,12
rx_d:   ; HL = length, DE = destination, BC = max kept
        push hl
        or a
        sbc hl,bc
        jr nc,rx_big            ; length >= max: keep BC, skip HL - BC
        pop bc                  ; length < max: keep all, skip nothing
        ld hl,0
        jr rx_k
rx_big: pop af                  ; drop the saved length (HL = bytes to skip)
rx_k:   push hl
        ex de,hl                ; HL = destination, DE = bytes to keep
        ld d,b
        ld e,c
        call r8_inblk
        pop de                  ; bytes to skip
        call r8_skip
rx_ack: ld a,R8C_ACK
        out (R8_STAT),a
        ret

; OTIR / INIR / skip for 16-bit counts. HL = buffer, DE = count
r8_outblk:
        ld a,d
        or e
        ret z
        ld b,e
        dec de
        inc d
        ld c,R8_DATA
ob_l:   otir
        dec d
        jr nz,ob_l
        ret

r8_inblk:
        ld a,d
        or e
        ret z
        ld b,e
        dec de
        inc d
        ld c,R8_DATA
ib_l:   inir
        dec d
        jr nz,ib_l
        ret

r8_skip:
        ld a,d
        or e
        ret z
sk_l:   in a,(R8_DATA)
        dec de
        ld a,d
        or e
        jr nz,sk_l
        ret

; ---------------------------------------------------------------- local CRC-16 CCITT-FALSE
; crc_mktab: build the 512-byte table at R8_CRCTAB (must be 256-aligned)
; crc_init : crc = FFFFh            crc_upd: HL = data, BC = count
crc_mktab:
        ld c,0                  ; C = index
mk_l:   ld d,c                  ; DE = index << 8
        ld e,0
        ld b,8
mk_b:   sla e
        rl d
        jr nc,mk_n
        ld a,d
        xor 10h
        ld d,a
        ld a,e
        xor 21h
        ld e,a
mk_n:   djnz mk_b
        ld h,R8_CRCTAB/256
        ld l,c
        ld (hl),e               ; low byte table
        inc h
        ld (hl),d               ; high byte table
        inc c
        jr nz,mk_l
        ret

crc_init:
        ld hl,0FFFFh
        ld (r8_lcrc),hl
        ret

; crc = (crc << 8) ^ T[(crc >> 8) ^ byte]
crc_upd:
        ld a,b
        or c
        ret z
        ld de,(r8_lcrc)
cu_l:   ld a,(hl)
        xor d                   ; index = (crc >> 8) ^ byte
        push hl
        ld l,a
        ld h,R8_CRCTAB/256
        ld a,(hl)               ; T low
        inc h
        ld d,(hl)               ; T high
        ld l,a
        ld a,d
        xor e                   ; new high = crc low ^ T high
        ld d,a
        ld e,l                  ; new low  = T low
        pop hl
        inc hl
        dec bc
        ld a,b
        or c
        jr nz,cu_l
        ld (r8_lcrc),de
        ret

; ---------------------------------------------------------------- variables (RAM)
; In a ROM build, move this block to RAM (e.g. with an ORG in page 3) and
; initialise r8_tmo / r8_seq / r8_evf by calling r8_open.
r8_seq:   db 0
r8_tmo:   db R8_TMO_STD
r8_try:   db 0
r8_hlen:  db 0
r8_hdr:   ds 24                 ; request header (OP, SEQ, parameters)
r8_pp:    dw 0                  ; request payload pointer / length
r8_pl:    dw 0
r8_rp:    dw 0                  ; reply data destination / maximum kept
r8_rmax:  dw 0
r8_rlen:  dw 0                  ; reply data length (bytes after OP, SEQ, ST)
r8_rhdr:  ds 3                  ; reply OP, SEQ, ST
r8_evf:   db 0                  ; 1 = event stored
r8_evlen: db 0
r8_evt:   ds 13                 ; type, data (up to 12 bytes)
r8_addr:  ds 4                  ; physical address (POKE/PEEK/CRC/EXEC entry)
r8_size:  ds 4                  ; CRC length
r8_arg:   ds 4                  ; EXEC argument
r8_ptr:   dw 0
r8_cnt:   dw 0
r8_info:  ds 11                 ; HELLO reply
r8_crcr:  dw 0
r8_lcrc:  dw 0                  ; local CRC accumulator
