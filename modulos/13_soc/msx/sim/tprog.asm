; tprog.asm - test program for the R8064 (Z80 mode): HL = byte count of the block at 5000h.
; Returns HL = 16-bit sum of the bytes and also stores it at 4100h.
        org 4000h
        ld b,h
        ld c,l
        ld de,5000h
        ld hl,0
lp:     ld a,b
        or c
        jr z,fin
        ld a,(de)
        add a,l
        ld l,a
        jr nc,nc1
        inc h
nc1:    inc de
        dec bc
        jr lp
fin:    ld (4100h),hl
        ret
