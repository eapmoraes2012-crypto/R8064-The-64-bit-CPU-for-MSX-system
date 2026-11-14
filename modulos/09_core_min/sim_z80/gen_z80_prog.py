# gen_z80_prog.py - programa aleatorio de 64 KB para o teste do nucleo em modo Z80.
# Uso: python3 gen_z80_prog.py <semente> <saida.bin> [paginas]    paginas: soma de 1 = CB, 2 = DD/FD, 4 = ED (prefixos permitidos; padrao 0 = so a pagina principal)
# Toda a memoria recebe bytes aleatorios tirados dos opcodes permitidos (um desvio para qualquer endereco cai em codigo valido). Ficam de fora: HALT (76),
# OUT/IN (D3/DB: o modelo de referencia so tem stub) e os prefixos nao pedidos. O inicio carrega todos os registradores com valores aleatorios.
import random,sys
seed=int(sys.argv[1]); out=sys.argv[2]; pages=int(sys.argv[3]) if len(sys.argv)>3 else 0
r=random.Random(seed)
bad={0x76,0xD3,0xDB,0xCB,0xDD,0xFD,0xED}     # os prefixos so entram junto com um segundo byte valido
ok=[b for b in range(256) if b not in bad]
ED=[b for b in range(0x40,0x80) if b!=0x5F]+[0xA0,0xA1,0xA8,0xA9,0xB0,0xB1,0xB8,0xB9]      # ED do Z80 aceitos pelo teste
m=bytearray()
while len(m)<65536:
    k=r.random()
    if pages&1 and k<.18: m+=bytes([0xCB,r.randrange(256)])
    elif pages&4 and k<.36: m+=bytes([0xED,r.choice(ED)])
    elif pages&2 and k<.60:
        m.append(r.choice([0xDD,0xFD]))
        if r.random()<.25: m+=bytes([0xCB,r.randrange(256),r.randrange(256)])     # DD CB d op
        else: m.append(r.choice(ok))
    else: m.append(r.choice(ok))
m=m[:65536]
w=lambda: [r.choice(ok),r.choice(ok)]
pre=[0x31]+w()+[0x01]+w()+[0xC5,0xF1,0x08]            # LD SP,nn ; LD BC,nn ; PUSH BC ; POP AF ; EX AF,AF'
pre+=[0x01]+w()+[0x11]+w()+[0x21]+w()+[0xD9]          # LD BC/DE/HL,nn ; EXX
pre+=[0x01]+w()+[0xC5,0xF1,0x01]+w()+[0x11]+w()+[0x21]+w()   # AF, BC, DE, HL principais
m[0:len(pre)]=bytes(pre)
open(out,'wb').write(m)
open(out+'.hex','w').write('\n'.join('%02x'%b for b in m)+'\n')
