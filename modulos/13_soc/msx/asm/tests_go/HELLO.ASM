; HELLO.ASM - small R8064 program (Z80 mode): adds 1..N, keeps the sum, also uses a
; 64-bit R8064 load. Its exit code (HL = 5050 = 13BAh) is returned to the MSX.
;   R8064AS HELLO /L /G      assembles, sends to the R8064 and runs it
        org 4000h
N       equ 100
start:  ld hl,0
        ld b,N
loop:   ld e,b
        ld d,0
        add hl,de               ; HL = 1 + 2 + ... + N
        djnz loop
        ld (result),hl
        ldq bc,(result_q)       ; 64-bit load (R8064 extension)
        ret                     ; exit code in HL
result:   dw 0
result_q: dq 1122334455667788h
        end start
