; directives: ORG gaps, DS, ALIGN, IF/ELSE/ENDIF, IFDEF, labels, INCLUDE, END
        .org 100h
first:  db 1
        ds 3
        ds 2,0AAh
        defs 1,55h
        block 2
        align 8
        align 16,0EEh
a1:     align 4
        org 140h
        db 2
        ORG 150H
        BYTE 3
        defb 4
        defm "m"
        text "t"
        word 1234h
        defw 5678h
        dword 9ABCDEF0h
        qword 1
VERSION equ 2
        if VERSION == 2
        db 22h
        if VERSION > 5
        db 0FFh
        else
        db 33h
        endif
        else
        db 0EEh
        endif
        if 0
        db 0BAh
        bogus instruction here
        else
        db 44h
        endif
        ifdef first
        db 55h
        endif
        ifndef nothing
        db 66h
        endif
        ifdef nothing
        db 0BBh
        else
        db 77h
        endif
  lbl1: db 1
lbl2:   db 2
lbl3    db 3
  lbl4:
        dw lbl1, lbl2, lbl3, lbl4
        include "a.inc"
        db inc_sym
        nop
        ld a,(hl) ; comment ld b,c
        ld a,';'
        ex af,af'  ; '
        end
        db 0FFh, "not assembled"
