# gen_r64_fumaca.py - programa dirigido das instrucoes R8064 de 16/32/64 bits e os valores esperados (calculados aqui, a mao, sem olhar o RTL).
# Uso (pasta sim_r64): python3 gen_r64_fumaca.py   -> r64_mem.hex (64 KB) e r64_esperado.hex (AX BC DE HL IX IY SP m9000 m9008)
# E um teste de FUMACA: cobre cerca de 20 das instrucoes novas. A verificacao ampla (programas aleatorios contra um modelo) ainda nao existe.
P=[]
def q(v,n=8): return [(v>>(8*i))&255 for i in range(n)]
M=(1<<64)-1
P+=[0x31,0x00,0x80]                                # LD SP,8000h
P+=[0xED,0x39,0x41]+q(0x1122334455667788)          # LDQ BC,nnnnnnnn
P+=[0xED,0x39,0x51]+q(0x0000000100000001)          # LDQ DE,nnnnnnnn
P+=[0xED,0x3E,0x82]                                # ADDQ BC,DE
BC=(0x1122334455667788+0x0000000100000001)&M
P+=[0xED,0x3A,0x61]+q(0xDEADBEEF,4)                # LDE HL,nnnn
P+=[0xED,0x39,0x79]+q(0x9000)                      # LDQ AX,9000h
P+=[0xED,0x39,0xF8]                                # LDQ (AX),BC
P+=[0xED,0x39,0x69]+q(0x9000)                      # LDQ IX,9000h
P+=[0xED,0xDD,0x00,0x08,0x00]                      # LDQ (QIX+8),BC
P+=[0xED,0xDD,0xD6,0x08,0x00]                      # LDQ DE,(QIX+8)
P+=[0xED,0x38,0xC8]                                # PUSHQ BC
P+=[0xED,0x38,0x4C]                                # POPQ HL
P+=[0xED,0x3C,0xA2]                                # SUBQ HL,DE  -> 0, Z
P+=[0xED,0x2A,0x09,0x03,0x00, 0x3E,0x55,0x00]      # JRW Z,+3 (pula LD A,55h / NOP)
sub=0x100
P+=[0xED,0x34]+q(sub)                              # CALLQ 0100h
P+=[0xED,0x31,0xA7]                                # SETE 20,AX
P+=[0xED,0x29,0xC6]                                # SHLQ BC
P+=[0xED,0x3B,0x58]                                # LDW IY,BC
P+=[0xED,0x30,0x8A]                                # RESW 1,DE
P+=[0xED,0x2E,0x00,0x00]                           # DJNZW +0
P+=[0x18,0xFE]                                     # JR $
m=P+[0]*(65536-len(P)); m[sub:sub+5]=[0xED,0x3E,0x01,0xED,0x05]   # 0100h: INCW BC ; RETQ
open('r64_mem.hex','w').write('\n'.join('%02x'%b for b in m)+'\n')
BCi=(BC&~0xFFFF)|((BC+1)&0xFFFF); BCs=(BCi<<1)&M; BCf=(BCs&~0xFFFF)|((BCs-1)&0xFFFF)   # DJNZW: contador = BC (16 bits)
exp=[0x9000|1<<20, BCf, BC&~2, 0, 0x9000, BCs&0xFFFF, 0x8000, BC, BC]
open('r64_esperado.hex','w').write('\n'.join('%016x'%v for v in exp)+'\n')
