# adds page 7 (interrupt acceptance) to gov_rom.mem: 1792 -> 2048 entries. Idempotent.
# op 0 of page 7: Z80 = 13 T (INTA with 2 automatic waits; the MSX M1_WAIT adds +1 in the governor), R800 = RST 38h timing (to be confirmed)
import sys
f=sys.argv[1] if len(sys.argv)>1 else 'gov_rom.mem'
w=[l.strip() for l in open(f) if l.strip()]
w=w[:1792]
rst=int(w[0*256+0xFF],16)
e=13 | 0<<6 | (rst>>12&63)<<12 | (rst>>12&63)<<18 | 0<<24
page=['%08x'%e]+['%08x'%e]*255
open(f,'w').write('\n'.join(w+page)+'\n')
print('page 7 op0 = %08x (Z80 13 T, R800 %d cycles)'%(e,rst>>12&63))
