// z80trace.c - generates the reference trace (state after each instruction) to compare with the R8064 core in Z80 mode.
// Uses the model 12_z80/ref/z80ref.c. Compile (in the sim_z80 folder):  gcc -O2 -o z80trace z80trace.c
// Usage: z80trace mem.bin N [mask] > trace.txt     mem.bin = 64 KB; starts with all registers at 0 and PC = 0 (core reset state).
// Each line: pc af bc de hl ix iy sp af' bc' de' hl' mask.  It also writes <mem.bin>.fim (final memory).
// mask = F bits compared in that instruction (FF normally; D7 when X/Y are undocumented and the core does not reproduce them: BIT n,(HL), which uses
// the internal register WZ, and LDI/LDD/LDIR/LDDR/CPI/CPD/CPIR/CPDR). The testbench copies the model's F in these cases, so the ignored bits do not propagate.
// The trace STOPS before: an opcode not yet implemented in the core (mask bits: 1 = CB, 2 = DD/FD, 4 = ED accepted), HALT, IN/OUT (the model only has a stub),
// or in self-modifying code that the core does not see: a byte written and executed next WITHOUT a taken branch between the write and the execution
// (the 32-byte fetch queue would already have read the old value; a taken branch flushes the queue and the new fetch reads the updated memory).
#define main z80ref_main
#include "../../12_z80/ref/z80ref.c"
#undef main
static u8 sh[65536], dirty[65536]; static int ndirty; static long ncb,ned,nxy,nxcb;
int main(int argc,char**argv){
  if(argc<3){fprintf(stderr,"uso: z80trace mem.bin N [mascara]\n");return 1;}
  for(int i=0;i<256;i++){ int p=1; for(int b=0;b<8;b++) if(i>>b&1)p^=1; szp[i]=(i&0xA8)|(i==0?FZ:0)|(p?FP:0); }
  FILE*f=fopen(argv[1],"rb"); if(!f||fread(mem,1,65536,f)!=65536){fprintf(stderr,"invalid mem.bin\n");return 1;} fclose(f);
  long n=atol(argv[2]); int mask=argc>3?atoi(argv[3]):0; memset(&z,0,sizeof z); memcpy(sh,mem,65536);
  long k=0; const char*why="limit";
  for(;k<n;k++){
    u8 op=mem[z.pc];
    if(op==0x76){why="HALT";break;} if(op==0xD3||op==0xDB){why="IN/OUT";break;}
    if(op==0xCB&&!(mask&1)){why="CB prefix";break;} if((op==0xDD||op==0xFD)&&!(mask&2)){why="DD/FD prefix";break;} if(op==0xED&&!(mask&4)){why="ED prefix";break;}
    u8 o2=mem[(u16)(z.pc+1)]; int fm=0xFF;
    if(op==0xED){ // only the Z80 ED opcodes that the core implements and the model reproduces: 40-7F (except LD A,R: the core does not count R) and LDI/CPI/LDD/CPD (+ repeated)
      int okk=(o2>=0x40&&o2<=0x7F&&o2!=0x5F)||((o2&0xE6)==0xA0);
      if(!okk){why="ED outside the subset";break;}
      if((o2&0xE6)==0xA0) fm=0xD7; }
    if(op==0xCB&&(o2&0xC7)==0x46) fm=0xD7;
    if(op==0xDD||op==0xFD){ // the core handles ONE prefix; DD/FD followed by another prefix is left out of the test. BIT n,(IX+d): X/Y comes from the address (masked)
      if(o2==0xDD||o2==0xFD||o2==0xED){why="prefixes in sequence";break;}
      if(o2==0x76){why="HALT";break;} if(o2==0xD3||o2==0xDB){why="IN/OUT";break;}
      if(o2==0xCB&&(mem[(u16)(z.pc+3)]&0xC0)==0x40) fm=0xD7; }
    if(op==0xCB)ncb++; else if(op==0xED)ned++; else if(op==0xDD||op==0xFD){ if(o2==0xCB)nxcb++; else nxy++; }
    { int smc0=0; if(ndirty) for(int i=0;i<4;i++) if(dirty[(u16)(z.pc+i)]) smc0=1; if(smc0){why="self-modifying code";break;} }
    u16 pc0=z.pc;
    step();
    int smc=0;
    if((u16)(z.pc-pc0)==0||(u16)(z.pc-pc0)>4){ if(ndirty){memset(dirty,0,65536);ndirty=0;} }      // taken branch: the fetch queue is flushed
    if(memcmp(sh,mem,65536)){ for(int a=0;a<65536;a++) if(mem[a]!=sh[a]){ sh[a]=mem[a]; dirty[a]=1; ndirty++; } }
    printf("%04x %02x%02x %02x%02x %02x%02x %02x%02x %04x %04x %04x %02x%02x %02x%02x %02x%02x %02x%02x %02x\n",z.pc,z.a,z.f,z.b,z.c,z.d,z.e,z.h,z.l,z.ix,z.iy,z.sp,z.a2,z.f2,z.b2,z.c2,z.d2,z.e2,z.h2,z.l2,fm);
    if(smc){why="self-modifying code";k++;break;}
  }
  char fn[512]; snprintf(fn,sizeof fn,"%s.fim",argv[1]); f=fopen(fn,"w"); for(int i=0;i<65536;i++)fprintf(f,"%02x\n",mem[i]); fclose(f);
  fprintf(stderr,"%ld instructions (%s) | CB %ld  ED %ld  DD/FD %ld  DDCB/FDCB %ld\n",k,why,ncb,ned,nxy,nxcb); return 0; }
