; every error message (pass 2), the line is skipped
        org 2000h
        ld a,undefined_symbol
        ld a,300
        jr $+200
        ld a,(ix+200)
        bit 8,a
        rst 9
        dq 1/0
        bogus a,b
        ld a,b,c
        ld q,1
dup:    nop
dup:    nop
        org 1000h
        db 3zh
        db 0x
        db (1+2
        db 1+
        dq 'ab'
        addq n0,hl
        addq n0,n4
        ldw n0,(n4)
        include "nofile.inc"
        else
        endif
        if undefined2
        db 1
        endif
        ds undefined3
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa: nop
        ld a,aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
        ldq hl,(ax)
        jpl
        mtcr 32
        im 3
        db 256, -129
        dw 65536
        dd 100000000h
        jrw $+40000h
        ldq (qix+8000h),bc
         equ 5
        db 1,
        nop
