import sys,os; sys.argv=['x']
sys.path.insert(0,'../../../13_soc/fw'); os.environ['ZASM_ORG0']='1'
import zasm_mon, z80rand as zr
zr.build()
src='''
        org 10h
        ld hl,0FFFFh
        push hl
        exx
        pop bc
        exx
        ld de,0400h
        ld bc,16
cr_b:   ld a,(de)
        inc de
        exx
        xor b
        ld l,a
        ld h,08h
        ld e,(hl)
        inc h
        ld a,(hl)
        xor c
        ld b,a
        ld c,e
        exx
        dec bc
        ld a,b
        or c
        jp nz,cr_b
        exx
        push bc
        exx
        pop hl
        ld (0E00h),hl
fim:    jr fim
'''
a=zasm_mon.Asm(src); b=a.assemble(); end=a.sym['fim']
def crc_tab():
    t=[]
    for i in range(256):
        c=i<<8
        for _ in range(8): c=((c<<1)^0x1021)&0xFFFF if c&0x8000 else (c<<1)&0xFFFF
        t.append(c)
    return t
T=crc_tab()
img=bytearray(4096); img[0x10:len(b)]=b[0x10:]
for i in range(256): img[0x800+i]=T[i]&255; img[0x900+i]=T[i]>>8
for i in range(16): img[0x400+i]=(i*7+3)&255
init=dict(r=dict(a=0,b=0,c=0,d=0,e=0,h=0,l=0,f=0),sp=0xC00)
z,n=zr.expected(img,init,end)
R,mem=zr.run_rtl(img,init,200*n+2000)
print('modelo HL=%04x mem=%02x%02x | rtl HL=%x mem=%02x%02x  n=%d'%(z.pr('hl'),z.m[0xE01],z.m[0xE00],R['R3'],mem[0xE01],mem[0xE00],n))
c=0xFFFF
for i in range(16):
    x=c^(((i*7+3)&255)<<8)
    for _ in range(8): x=((x<<1)^0x1021)&0xFFFF if x&0x8000 else (x<<1)&0xFFFF
    c=x
print('referencia crc=%04x'%c)
