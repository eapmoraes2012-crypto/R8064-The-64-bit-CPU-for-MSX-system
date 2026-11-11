# acrescenta a pagina 7 (aceitacao de interrupcao) a gov_rom.mem: 1792 -> 2048 entradas. Idempotente.
# op 0 da pagina 7: Z80 = 13 T (INTA com 2 waits automaticos; o M1_WAIT do MSX soma +1 no governador), R800 = tempo do RST 38h (a confirmar)
import sys
f=sys.argv[1] if len(sys.argv)>1 else 'gov_rom.mem'
w=[l.strip() for l in open(f) if l.strip()]
w=w[:1792]
rst=int(w[0*256+0xFF],16)
e=13 | 0<<6 | (rst>>12&63)<<12 | (rst>>12&63)<<18 | 0<<24
page=['%08x'%e]+['%08x'%e]*255
open(f,'w').write('\n'.join(w+page)+'\n')
print('pagina 7 op0 = %08x (Z80 13 T, R800 %d ciclos)'%(e,rst>>12&63))
