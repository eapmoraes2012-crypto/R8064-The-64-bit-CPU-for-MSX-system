# mk_core.py - builds z80core.c from the module 12 reference model (12_z80/ref/z80ref.c),
# adding I/O hooks (io_in / io_out) and removing its main(). Usage: python3 mk_core.py <z80ref.c> <z80core.c>
import sys
s = open(sys.argv[1]).read()
rep = [
 ("case 0: { u8 v=0xff; z.f=(z.f&FC)|szp[v];", "case 0: { u8 v=io_in(z.c); z.f=(z.f&FC)|szp[v];"),           # IN r,(C)
 ("case 1: t+=8; return t; // OUT (C),r", "case 1: io_out(z.c, y==6?0:*r8p(y)); t+=8; return t; // OUT (C),r"),
 ("if(zz==2){ u8 v=0xff; wr(HL,v);", "if(zz==2){ u8 v=io_in(z.c); wr(HL,v);"),                                   # INI/INIR/IND/INDR
 ("{ u8 v=rd(HL); z.b--; setHL(HL+dir);", "{ u8 v=rd(HL); z.b--; io_out(z.c,v); setHL(HL+dir);"),                 # OUTI/OTIR/OUTD/OTDR
 ("case 2: fetchd(); return t+11; case 3: fetchd(); z.a|=0; return t+11;",
  "case 2: { u8 n=fetchd(); io_out(n,z.a); return t+11; } case 3: { u8 n=fetchd(); z.a=io_in(n); return t+11; }"),
 ("int main(int argc,char**argv){", "int ref_main(int argc,char**argv){"),
 ("static Z z;", "static Z z;\nstatic u8 io_in(u8 port); static void io_out(u8 port, u8 v);"),
]
for a, b in rep:
    assert s.count(a) == 1, a
    s = s.replace(a, b)
open(sys.argv[2], 'w').write(s)
