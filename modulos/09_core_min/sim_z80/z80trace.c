// z80trace.c - gera o traco de referencia (estado apos cada instrucao) para comparar com o nucleo R8064 em modo Z80.
// Usa o modelo 12_z80/ref/z80ref.c. Compilar (na pasta sim_z80):  gcc -O2 -o z80trace z80trace.c
// Uso: z80trace mem.bin N [mascara] > trace.txt     mem.bin = 64 KB; comeca com todos os registradores em 0 e PC = 0 (estado de reset do nucleo).
// Cada linha: pc af bc de hl ix iy sp af' bc' de' hl' mascara.  Tambem grava <mem.bin>.fim (memoria final).
// mascara = bits de F comparados nessa instrucao (FF normalmente; D7 quando X/Y sao nao documentados e o nucleo nao os reproduz: BIT n,(HL), que usa
// o registrador interno WZ, e LDI/LDD/LDIR/LDDR/CPI/CPD/CPIR/CPDR). O testbench copia o F do modelo nesses casos, para os bits ignorados nao se propagarem.
// O traco PARA antes de: opcode ainda nao implementado no nucleo (bits da mascara: 1 = CB, 2 = DD/FD, 4 = ED aceitos), HALT, IN/OUT (o modelo so tem stub),
// ou em codigo automodificavel que o nucleo nao enxerga: um byte escrito e executado em seguida SEM desvio tomado entre a escrita e a execucao
// (a fila de busca de 32 bytes ja teria lido o valor antigo; um desvio tomado esvazia a fila e a nova busca le a memoria atualizada).
#define main z80ref_main
#include "../../12_z80/ref/z80ref.c"
#undef main
static u8 sh[65536], dirty[65536]; static int ndirty; static long ncb,ned,nxy,nxcb;
int main(int argc,char**argv){
  if(argc<3){fprintf(stderr,"uso: z80trace mem.bin N [mascara]\n");return 1;}
  for(int i=0;i<256;i++){ int p=1; for(int b=0;b<8;b++) if(i>>b&1)p^=1; szp[i]=(i&0xA8)|(i==0?FZ:0)|(p?FP:0); }
  FILE*f=fopen(argv[1],"rb"); if(!f||fread(mem,1,65536,f)!=65536){fprintf(stderr,"mem.bin invalido\n");return 1;} fclose(f);
  long n=atol(argv[2]); int mask=argc>3?atoi(argv[3]):0; memset(&z,0,sizeof z); memcpy(sh,mem,65536);
  long k=0; const char*why="limite";
  for(;k<n;k++){
    u8 op=mem[z.pc];
    if(op==0x76){why="HALT";break;} if(op==0xD3||op==0xDB){why="IN/OUT";break;}
    if(op==0xCB&&!(mask&1)){why="prefixo CB";break;} if((op==0xDD||op==0xFD)&&!(mask&2)){why="prefixo DD/FD";break;} if(op==0xED&&!(mask&4)){why="prefixo ED";break;}
    u8 o2=mem[(u16)(z.pc+1)]; int fm=0xFF;
    if(op==0xED){ // so os opcodes ED do Z80 que o nucleo implementa e o modelo reproduz: 40-7F (menos LD A,R: o nucleo nao conta R) e LDI/CPI/LDD/CPD (+ repetidos)
      int okk=(o2>=0x40&&o2<=0x7F&&o2!=0x5F)||((o2&0xE6)==0xA0);
      if(!okk){why="ED fora do subconjunto";break;}
      if((o2&0xE6)==0xA0) fm=0xD7; }
    if(op==0xCB&&(o2&0xC7)==0x46) fm=0xD7;
    if(op==0xDD||op==0xFD){ // o nucleo trata UM prefixo; DD/FD seguido de outro prefixo fica fora do teste. BIT n,(IX+d): X/Y vem do endereco (mascarados)
      if(o2==0xDD||o2==0xFD||o2==0xED){why="prefixos em sequencia";break;}
      if(o2==0x76){why="HALT";break;} if(o2==0xD3||o2==0xDB){why="IN/OUT";break;}
      if(o2==0xCB&&(mem[(u16)(z.pc+3)]&0xC0)==0x40) fm=0xD7; }
    if(op==0xCB)ncb++; else if(op==0xED)ned++; else if(op==0xDD||op==0xFD){ if(o2==0xCB)nxcb++; else nxy++; }
    { int smc0=0; if(ndirty) for(int i=0;i<4;i++) if(dirty[(u16)(z.pc+i)]) smc0=1; if(smc0){why="codigo automodificavel";break;} }
    u16 pc0=z.pc;
    step();
    int smc=0;
    if((u16)(z.pc-pc0)==0||(u16)(z.pc-pc0)>4){ if(ndirty){memset(dirty,0,65536);ndirty=0;} }      // desvio tomado: a fila de busca e esvaziada
    if(memcmp(sh,mem,65536)){ for(int a=0;a<65536;a++) if(mem[a]!=sh[a]){ sh[a]=mem[a]; dirty[a]=1; ndirty++; } }
    printf("%04x %02x%02x %02x%02x %02x%02x %02x%02x %04x %04x %04x %02x%02x %02x%02x %02x%02x %02x%02x %02x\n",z.pc,z.a,z.f,z.b,z.c,z.d,z.e,z.h,z.l,z.ix,z.iy,z.sp,z.a2,z.f2,z.b2,z.c2,z.d2,z.e2,z.h2,z.l2,fm);
    if(smc){why="codigo automodificavel";k++;break;}
  }
  char fn[512]; snprintf(fn,sizeof fn,"%s.fim",argv[1]); f=fopen(fn,"w"); for(int i=0;i<65536;i++)fprintf(f,"%02x\n",mem[i]); fclose(f);
  fprintf(stderr,"%ld instrucoes (%s) | CB %ld  ED %ld  DD/FD %ld  DDCB/FDCB %ld\n",k,why,ncb,ned,nxy,nxcb); return 0; }
