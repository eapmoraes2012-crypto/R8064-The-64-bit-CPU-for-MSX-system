#!/usr/bin/env python3
"""Checks the ROMs (.mem) against expected_id.mem and the control words against expected_*.mem.
Uso: python3 ref/verify_roms.py   (a partir da pasta R8064_rtl_pack)"""
import sys
rd=lambda p:[int(x,16) for x in open(p).read().split()]
A=rd('rom/rom_ed_a.mem'); AM=rd('rom/amb_idx.mem'); B=rd('rom/rom_ed_b.mem'); C=rd('rom/ctrl.mem')
G=rd('ref/expected_id.mem'); EC=rd('ref/expected_clock.mem'); EW=rd('ref/expected_wait.mem'); EP=rd('ref/expected_pen.mem')
W_RD,W_WR,W_IO,BRD,BRX,BRM=4,2,1,2,4,5
bad=0
for b2 in range(256):
    for b3 in range(256):
        a=A[b2]; i=B[AM[b2]*256+b3] if a>>10&1 else a&0x3FF
        bad+=i!=G[b2*256+b3]
cb=0
for i in sorted(set(G)-{0}):
    w=C[i]; ln=w&15; nr=w>>4&31; nw=w>>9&31; nio=w>>14&3; ex=w>>16&255; pc=w>>24&3
    nf=(ln+7)//8; clk=max(1,nf+nr+nw,nio,ex); wt=(nf+nr)*W_RD+nw*W_WR+nio*W_IO; pen=[0,BRD,BRX,BRM][pc]
    cb+=(clk,wt,pen)!=(EC[i],EW[i],EP[i])
print('id divergences:',bad,'| cycle divergences:',cb); sys.exit(1 if bad or cb else 0)
