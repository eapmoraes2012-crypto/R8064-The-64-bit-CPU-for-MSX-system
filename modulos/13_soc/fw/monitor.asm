; monitor.asm - monitor do R8064 (v1, modo Z80). Roda a partir da SDRAM 0 (copiado do buffer no boot).
; Usa so instrucoes que o nucleo REV48 ja executa (sem CB, HALT, RST, DAA, ADD HL,rr, PUSH/POP AF).
; Protocolo MSX<->R8064: ver datasheet (formato: OP, SEQ, parametros / resposta: OP|80, SEQ, ST, dados).
; ST: 00 ok | 01 OP desconhecida | 02 parametro invalido | 03 endereco desalinhado / nao suportado | 04 erro do DMA | 05 modo de EXEC nao suportado
FDATA  equ 0E8h
FSTAT  equ 0E9h
FLENL  equ 0EAh
FLENH  equ 0EBh
FFLG   equ 0ECh
DSTAT  equ 0EEh
SCR_S  equ 2100h      ; 8 bytes alinhados: origem fisica do DMA (bytes 4..7 = 0)
SCR_D  equ 2108h      ; destino fisico do DMA
SCR_C  equ 2110h      ; CTRL do DMA: [0..1] = palavras, [3] = 80h (START), resto 0
V_ADDR equ 2120h      ; 4 bytes
V_REM  equ 2124h      ; 4 bytes
V_CRC  equ 2128h
V_N    equ 212Ah
V_OFF  equ 212Ch
V_W    equ 212Eh
V_SIZE equ 2130h
V_LEN  equ 2132h
V_TMP  equ 2134h
V_EXIT equ 2138h      ; 8 bytes alinhados
MSGB   equ 2200h      ; mensagem recebida (ate 2048 bytes)
STG    equ 3000h      ; area de passagem do DMA (2 KB)
STACK  equ 2FF0h
TLO    equ 0800h      ; tabela do CRC, byte baixo (alinhada a 256)
THI    equ 0900h      ; tabela do CRC, byte alto

        org 0
start:  ld sp,STACK
        ld a,04h
        call setmode          ; monitor em NATIVE64 (sem governador de tempo do Z80)
        ld hl,SCR_S
        ld b,40h
        xor a
clr:    ld (hl),a
        inc hl
        djnz clr
        ld a,80h
        ld (SCR_C+3),a
main:   in a,(FFLG)
        and 01h
        jr z,main
        in a,(FLENL)
        ld c,a
        in a,(FLENH)
        ld b,a
        cp 08h
        jr c,lenok
        ld bc,0800h           ; limita a 2048 bytes
lenok:  ld a,c
        ld (V_LEN),a
        ld a,b
        ld (V_LEN+1),a
        ld hl,MSGB
rd:     ld a,b
        or c
        jr z,rdone
        in a,(FDATA)
        ld (hl),a
        inc hl
        dec bc
        jr rd
rdone:  ld a,03h
        out (FFLG),a          ; limpa START (busy continua 1)
        ld a,(V_LEN+1)
        or a
        jp nz,haveop
        ld a,(V_LEN)
        cp 02h
        jp c,err_par
haveop: ld a,(MSGB)
        or a
        jp z,op_ping
        cp 01h
        jp z,op_hello
        cp 02h
        jp z,op_ping          ; RESET: o estado e todo recriado a cada mensagem
        cp 10h
        jp z,op_wput
        cp 11h
        jp z,op_wget
        cp 12h
        jp z,op_poke
        cp 13h
        jp z,op_peek
        cp 20h
        jp z,op_exec
        cp 21h
        jp z,err_al           ; STOP: sem programa em execucao a ouvir mensagens (v1)
        cp 30h
        jp z,op_crc
        ld a,01h
        jp reply_st
err_par: ld a,02h
        jp reply_st
err_al: ld a,03h
        jp reply_st
err_dma: ld a,04h
        jp reply_st
err_mod: ld a,05h
        jp reply_st
op_ping: xor a
reply_st: call rsph
        ld bc,3
fin:    call finr
        jp main
rsph:   ld c,a                ; A = ST: escreve OP|80, SEQ, ST no FIFO R8064->MSX
        ld a,(MSGB)
        or 80h
        out (FDATA),a
        ld a,(MSGB+1)
        out (FDATA),a
        ld a,c
        out (FDATA),a
        ret
finr:   ld a,c                ; BC = tamanho total: LEN e CONCLUIDO (devolve a janela ao MSX)
        out (FLENL),a
        ld a,b
        out (FLENH),a
        ld a,05h
        out (FFLG),a
        ret
; ---------------------------------------------------------------- HELLO
op_hello: xor a
        call rsph
        ld hl,hello_d
        ld b,11
hl1:    ld a,(hl)
        out (FDATA),a
        inc hl
        djnz hl1
        ld bc,14
        jp fin
hello_d: db 'R8064'
        db 01h,00h,08h,00h,40h,07h   ; versao 1, msg max 2048, bloco 16384, recursos: janela|EXEC|CRC
; ---------------------------------------------------------------- utilitarios
chka:   inc hl                ; HL -> 4 bytes de endereco fisico; Z = valido (8 MB: byte3 = 0, bit 23 = 0)
        inc hl
        ld a,(hl)
        and 80h
        ret nz
        inc hl
        ld a,(hl)
        or a
        ret
ceil8:  ld de,0               ; HL = bytes -> HL = ceil(bytes / 8)
c8l:    ld a,h
        or a
        jr nz,c8s
        ld a,l
        cp 08h
        jr c,c8e
c8s:    ld a,l
        sub 08h
        ld l,a
        ld a,h
        sbc a,0
        ld h,a
        inc de
        jr c8l
c8e:    ld a,l
        or a
        jr z,c8f
        inc de
c8f:    ex de,hl
        ret
dmarun: ld a,l                ; HL = palavras; SCR_S/SCR_D ja preenchidos. NZ no retorno = erro
        ld (SCR_C),a
        ld a,h
        ld (SCR_C+1),a
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        nop
        ld hl,SCR_S
        db 0EDh,39h,3Ch       ; LDQ AX,(HL)
        db 0EDh,0Ch,19        ; MTCR 19 (SRC0)
        ld hl,SCR_D
        db 0EDh,39h,3Ch
        db 0EDh,0Ch,20        ; MTCR 20 (DST0)
        ld hl,SCR_C
        db 0EDh,39h,3Ch
        db 0EDh,0Ch,21        ; MTCR 21 (CTRL0: START)
dwait:  in a,(DSTAT)
        and 06h
        jr z,dwait
        ld c,a
        ld a,01h
        out (DSTAT),a
        ld a,c
        and 04h
        ret
crcrng: ld hl,0FFFFh          ; CRC-16 CCITT-FALSE de V_REM bytes a partir do endereco fisico V_ADDR (alinhado a 8). Resultado em V_CRC; NZ = erro
        ld (V_CRC),hl
cr_l:   ld hl,V_REM
        ld a,(hl)
        inc hl
        or (hl)
        inc hl
        or (hl)
        inc hl
        or (hl)
        jp z,cr_end
        ld a,(V_REM+2)
        ld hl,V_REM+3
        or (hl)
        jp nz,cr_full
        ld a,(V_REM+1)
        cp 08h
        jp nc,cr_full
        ld a,(V_REM)
        ld l,a
        ld a,(V_REM+1)
        ld h,a
        jr cr_n
cr_full: ld hl,0800h
cr_n:   ld (V_N),hl
        call ceil8
        push hl
        ld hl,V_ADDR
        ld de,SCR_S
        ldi
        ldi
        ldi
        ldi
        xor a
        ld (SCR_D),a
        ld (SCR_D+2),a
        ld (SCR_D+3),a
        ld a,30h
        ld (SCR_D+1),a
        pop hl
        call dmarun
        jp nz,cr_err
        ld hl,(V_CRC)
        push hl
        exx
        pop bc                ; BC' = crc
        exx
        ld de,STG
        ld hl,(V_N)
        ld b,h
        ld c,l
cr_b:   ld a,(de)
        inc de
        exx
        xor b
        ld l,a
        ld h,08h
        ld e,(hl)             ; E' = TLO[idx]
        inc h
        ld a,(hl)             ; THI[idx]
        xor c
        ld b,a
        ld c,e
        exx
        dec bc
        ld a,b
        or c
        jr nz,cr_b
        exx
        push bc
        exx
        pop hl
        ld (V_CRC),hl
        ld hl,(V_N)
        ld a,(V_ADDR)
        add a,l
        ld (V_ADDR),a
        ld a,(V_ADDR+1)
        adc a,h
        ld (V_ADDR+1),a
        ld a,(V_ADDR+2)
        adc a,0
        ld (V_ADDR+2),a
        ld a,(V_ADDR+3)
        adc a,0
        ld (V_ADDR+3),a
        ld a,(V_REM)
        sub l
        ld (V_REM),a
        ld a,(V_REM+1)
        sbc a,h
        ld (V_REM+1),a
        ld a,(V_REM+2)
        sbc a,0
        ld (V_REM+2),a
        ld a,(V_REM+3)
        sbc a,0
        ld (V_REM+3),a
        jp cr_l
cr_end: xor a
        ret
cr_err: ld a,01h
        or a
        ret
sendcrc: xor a                ; resposta com ST=0 + CRC (V_CRC)
        call rsph
        ld a,(V_CRC)
        out (FDATA),a
        ld a,(V_CRC+1)
        out (FDATA),a
        ld bc,5
        jp fin
; ---------------------------------------------------------------- WIN_PUT / WIN_GET (10h / 11h): endereco fisico (4), tamanho (2; 0 = 16384)
op_wput: ld hl,MSGB+2
        ld de,SCR_D
        ld a,80h
        ld (SCR_S+2),a
        xor a
        ld (SCR_S),a
        ld (SCR_S+1),a
        ld (SCR_S+3),a
        jr wcommon
op_wget: ld hl,MSGB+2
        ld de,SCR_S
        ld a,80h
        ld (SCR_D+2),a
        xor a
        ld (SCR_D),a
        ld (SCR_D+1),a
        ld (SCR_D+3),a
wcommon: ld a,(V_LEN+1)
        or a
        jp nz,err_par
        ld a,(V_LEN)
        cp 08h
        jp nz,err_par
        push hl
        push de
        call chka
        pop de
        pop hl
        jp nz,err_par
        ld a,(MSGB+2)
        and 07h
        jp nz,err_al
        ldi
        ldi
        ldi
        ldi
        ld hl,(MSGB+6)
        ld a,h
        or l
        jr nz,wp1
        ld hl,4000h
wp1:    ld a,h
        cp 40h
        jr c,wp2
        jp nz,err_par
        ld a,l
        or a
        jp nz,err_par
wp2:    ld (V_SIZE),hl
        call ceil8
        call dmarun
        jp nz,err_dma
        ld hl,MSGB+2
        ld de,V_ADDR
        ldi
        ldi
        ldi
        ldi
        ld hl,(V_SIZE)
        ld (V_REM),hl
        xor a
        ld (V_REM+2),a
        ld (V_REM+3),a
        call crcrng
        jp nz,err_dma
        jp sendcrc
; ---------------------------------------------------------------- CRC (30h): endereco (4, alinhado a 8), tamanho (4)
op_crc: ld a,(V_LEN+1)
        or a
        jp nz,err_par
        ld a,(V_LEN)
        cp 0Ah
        jp nz,err_par
        ld hl,MSGB+2
        call chka
        jp nz,err_par
        ld a,(MSGB+2)
        and 07h
        jp nz,err_al
        ld hl,MSGB+2
        ld de,V_ADDR
        ldi
        ldi
        ldi
        ldi
        ld hl,MSGB+6
        ld de,V_REM
        ldi
        ldi
        ldi
        ldi
        call crcrng
        jp nz,err_dma
        jp sendcrc
; ---------------------------------------------------------------- POKE (12h) / PEEK (13h)
stage:  ld a,(MSGB+2)         ; le para STG a regiao alinhada que cobre [endereco, endereco + V_SIZE). Z = ok
        and 07h
        ld (V_OFF),a
        ld c,a
        ld hl,(V_SIZE)
        ld a,l
        add a,c
        ld l,a
        ld a,h
        adc a,0
        ld h,a
        call ceil8
        ld (V_W),hl
        ld hl,MSGB+2
        ld de,V_ADDR
        ldi
        ldi
        ldi
        ldi
        ld a,(V_ADDR)
        and 0F8h
        ld (V_ADDR),a
        ld hl,V_ADDR
        ld de,SCR_S
        ldi
        ldi
        ldi
        ldi
        xor a
        ld (SCR_D),a
        ld (SCR_D+2),a
        ld (SCR_D+3),a
        ld a,30h
        ld (SCR_D+1),a
        ld hl,(V_W)
        call dmarun
        ret
op_poke: ld a,(V_LEN)
        sub 06h
        ld l,a
        ld a,(V_LEN+1)
        sbc a,0
        ld h,a
        jp c,err_par
        or l
        jp z,err_par
        ld a,h
        cp 08h
        jp nc,err_par
        ld (V_SIZE),hl
        ld hl,MSGB+2
        call chka
        jp nz,err_par
        call stage
        jp nz,err_dma
        ld a,(V_OFF)
        ld e,a
        ld d,30h
        ld hl,(V_SIZE)
        ld b,h
        ld c,l
        ld hl,MSGB+6
        ldir
        ld hl,V_ADDR
        ld de,SCR_D
        ldi
        ldi
        ldi
        ldi
        xor a
        ld (SCR_S),a
        ld (SCR_S+2),a
        ld (SCR_S+3),a
        ld a,30h
        ld (SCR_S+1),a
        ld hl,(V_W)
        call dmarun
        jp nz,err_dma
        xor a
        jp reply_st
op_peek: ld a,(V_LEN+1)
        or a
        jp nz,err_par
        ld a,(V_LEN)
        cp 08h
        jp nz,err_par
        ld hl,(MSGB+6)
        ld a,h
        or l
        jp z,err_par
        ld a,h
        cp 08h
        jp nc,err_par
        ld (V_SIZE),hl
        ld hl,MSGB+2
        call chka
        jp nz,err_par
        call stage
        jp nz,err_dma
        xor a
        call rsph
        ld hl,(V_SIZE)
        ld b,h
        ld c,l
        ld a,(V_OFF)
        ld l,a
        ld h,30h
pe_l:   ld a,(hl)
        out (FDATA),a
        inc hl
        dec bc
        ld a,b
        or c
        jr nz,pe_l
        ld hl,(V_SIZE)
        inc hl
        inc hl
        inc hl
        ld b,h
        ld c,l
        jp fin
; ---------------------------------------------------------------- EXEC (20h): entrada (8), modo (1), argumento (8)
op_exec: ld a,(V_LEN+1)
        or a
        jp nz,err_par
        ld a,(V_LEN)
        cp 13h
        jp nz,err_par
        ld a,(MSGB+10)
        cp 05h
        jp nc,err_par         ; modos 00h..04h
        ld hl,MSGB+4
        ld b,6
        xor a
ex1:    or (hl)
        inc hl
        djnz ex1
        jp nz,err_par         ; v1: entrada < 10000h
        ld hl,(MSGB+2)
        ld (V_TMP),hl
        xor a
        call rsph
        ld bc,3
        call finr
        ld a,(MSGB+10)
        call setmode
        ld hl,ret_a
        push hl
        ld hl,(V_TMP)
        push hl
        ld a,(MSGB+10)
        cp 04h
        jr z,ex64
        ld hl,(MSGB+11)       ; argumento (16 bits)
        ret                   ; "chama" a entrada; o programa volta em ret_a
ex64:   ld de,MSGB+11
        db 0EDh,39h,22h       ; LDQ HL,(DE): argumento de 64 bits
        ret
ret_a:  ld de,V_EXIT
        db 0EDh,39h,0D4h      ; LDQ (DE),HL: codigo de saida (HL)
        ld a,04h
        call setmode
ew:     in a,(FFLG)
        and 04h
        jr nz,ew              ; espera o MSX ler a resposta anterior (CONCLUIDO = 0)
        ld a,0F0h
        out (FDATA),a
        xor a
        out (FDATA),a
        ld a,01h
        out (FDATA),a         ; EVT 01: programa terminou
        ld a,(V_EXIT)
        out (FDATA),a
        ld a,(V_EXIT+1)
        out (FDATA),a
        ld a,(V_EXIT+2)
        out (FDATA),a
        ld a,(V_EXIT+3)
        out (FDATA),a
        ld bc,7
        jp fin
setmode: cp 04h               ; A = modo (00h Z80 ROM, 01h Z80 DRAM, 02h R800 ROM, 03h R800 DRAM, 04h nativo) -> S1990 reg 6 e NATIVE64
        jr z,sm_n
        or a
        ld c,60h
        jr z,sm_w
        cp 01h
        ld c,20h
        jr z,sm_w
        cp 02h
        ld c,40h
        jr z,sm_w
        ld c,00h
sm_w:   ld a,06h
        out (0E4h),a
        ld a,c
        out (0E5h),a
        ld a,0A5h
        out (3Dh),a
        xor a
        out (3Eh),a
        ret
sm_n:   ld a,0A5h
        out (3Dh),a
        ld a,01h
        out (3Eh),a
        ret
codeend:
        org TLO
;@CRCTAB@
