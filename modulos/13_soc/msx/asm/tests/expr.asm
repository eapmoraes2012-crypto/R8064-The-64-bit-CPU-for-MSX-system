; expressions: numbers, operators, precedence, symbols, $
        org 1000h
start:  dq 0, 1, 255, 65535, 12345678901234
        dq 0FFh, 0ffh, 1Fh, 0x1F, 0X10, $1F, &H1F, &h7f
        dq 101b, 0b101, %1011, 0B, 11B, 1Dh, 99d, 0
        dq 'A', "z", ' ', 'a'+1
        dq 1+2*3, (1+2)*3, 10-4-3, 100/7, 100%7, 100 mod 7, 2*3+4*5
        dq 1<<4, 1 shl 63, 256>>4, -1>>60, 0F0h shr 4, 1<<64, 1<<0
        dq 0F0h & 3Ch, 0F0h and 3Ch, 0F0h|0Fh, 1 or 2, 0FFh^0Fh, 5 xor 1
        dq -5, --5, +5, ~0, not 0, !0, !7, -(-(3))
        dq 1==1, 1=2, 1!=2, 1<>1, 2<3, 3<2, -1<0, 2>1, 2<=2, 3>=4, -5>=-6
        dq high 1234h, low 1234h, high(5678h)+1, low 1FFh*2
        dq 0FFFFFFFFFFFFFFFFh+1, 8000000000000000h*2, 12345678h*87654321h
        dq 0FFFFFFFFFFFFFFFFh/3, 7/0FFFFFFFFFFFFFFFFh, 1234567890123/1000
        dq 1|2^3&4==4, 1+2<<3, 6/4*4, 2+3*4-5/2
        dq later, later+1, later-start, $, $+2
        dw $, $, $
        dd 12345678h, -1, start
        db 1,2,-1,-128,255,'x',"str",'it',"",0
        db "a;b",';',',',"(,)"
later:  equ 4000h
lab2    equ later*2
lab3 =  lab2+1
        dq lab2,lab3,_x.y?@
_x.y?@: dq 1
        dq 5 + 3 * ( 2 - 1 )  ,  ( 7 )
