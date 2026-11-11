// z80ref.c - modelo de referencia Z80 (instrucoes completas incl. nao documentadas, T-states, MEMPTR) + shim CP/M para ZEXDOC/ZEXALL
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
typedef uint8_t u8; typedef uint16_t u16; typedef uint32_t u32; typedef uint64_t u64;
enum {FC=1,FN=2,FP=4,FX=8,FH=16,FY=32,FZ=64,FS=128};
static u8 mem[65536]; static u8 szp[256];
typedef struct { u8 a,f,b,c,d,e,h,l; u8 a2,f2,b2,c2,d2,e2,h2,l2; u16 ix,iy,sp,pc,wz; u8 i,r; u8 iff1,iff2,im,halt; u64 t; } Z;
static Z z;
static u8 rd(u16 a){return mem[a];}
static void wr(u16 a,u8 v){mem[a]=v;}
static u16 rd16(u16 a){return rd(a)|rd(a+1)<<8;}
static void wr16(u16 a,u8 lo_hi_dummy){}
static void w16(u16 a,u16 v){wr(a,v&255);wr(a+1,v>>8);}
#define BC ((z.b<<8)|z.c)
#define DE ((z.d<<8)|z.e)
#define HL ((z.h<<8)|z.l)
#define AF ((z.a<<8)|z.f)
static void setBC(u16 v){z.b=v>>8;z.c=v;} static void setDE(u16 v){z.d=v>>8;z.e=v;} static void setHL(u16 v){z.h=v>>8;z.l=v;}
static u8 fetch(){u8 v=rd(z.pc++);z.r=(z.r&0x80)|((z.r+1)&0x7f);return v;}
static u8 fetchd(){return rd(z.pc++);}
static u16 fetch16(){u16 v=rd16(z.pc);z.pc+=2;return v;}
static int pr=0; // prefix: 0, 0xDD, 0xFD
static u16 idx(){return pr==0xDD?z.ix:z.iy;}
static void setidx(u16 v){if(pr==0xDD)z.ix=v;else z.iy=v;}
static u8 *r8p(int r){ switch(r){case 0:return &z.b;case 1:return &z.c;case 2:return &z.d;case 3:return &z.e;case 4:return &z.h;case 5:return &z.l;case 7:return &z.a;} return 0;}
static u8 getr(int r,int undoc){ // r!=6; undoc: usa IXH/IXL
  if(pr&&undoc){ if(r==4)return idx()>>8; if(r==5)return idx()&255; } return *r8p(r); }
static void setr(int r,u8 v,int undoc){ if(pr&&undoc){ if(r==4){setidx((idx()&255)|v<<8);return;} if(r==5){setidx((idx()&0xff00)|v);return;} } *r8p(r)=v; }
static u16 getrp(int p){switch(p){case 0:return BC;case 1:return DE;case 2:return pr?idx():HL;default:return z.sp;}}
static void setrp(int p,u16 v){switch(p){case 0:setBC(v);break;case 1:setDE(v);break;case 2:if(pr)setidx(v);else setHL(v);break;default:z.sp=v;}}
static u16 getrp2(int p){switch(p){case 0:return BC;case 1:return DE;case 2:return pr?idx():HL;default:return AF;}}
static void setrp2(int p,u16 v){switch(p){case 0:setBC(v);break;case 1:setDE(v);break;case 2:if(pr)setidx(v);else setHL(v);break;default:z.a=v>>8;z.f=v;}}
static void push(u16 v){z.sp-=2;w16(z.sp,v);} static u16 pop(){u16 v=rd16(z.sp);z.sp+=2;return v;}
static int cond(int c){switch(c){case 0:return !(z.f&FZ);case 1:return z.f&FZ;case 2:return !(z.f&FC);case 3:return z.f&FC;case 4:return !(z.f&FP);case 5:return z.f&FP;case 6:return !(z.f&FS);default:return z.f&FS;}}
static void alu(int op,u8 v){
  u8 a=z.a; int r; switch(op){
  case 0: r=a+v; z.f=(r&0x80)|((r&255)==0?FZ:0)|(r&0x28)|((a^v^r)&FH)|((~(a^v)&(a^r)&0x80)?FP:0)|((r>>8)&1); z.a=r; break;
  case 1: { int c=z.f&1; r=a+v+c; z.f=(r&0x80)|((r&255)==0?FZ:0)|(r&0x28)|((a^v^r)&FH)|((~(a^v)&(a^r)&0x80)?FP:0)|((r>>8)&1); z.a=r; break;}
  case 2: r=a-v; z.f=(r&0x80)|((r&255)==0?FZ:0)|(r&0x28)|((a^v^r)&FH)|(((a^v)&(a^r)&0x80)?FP:0)|FN|((r>>8)&1); z.a=r; break;
  case 3: { int c=z.f&1; r=a-v-c; z.f=(r&0x80)|((r&255)==0?FZ:0)|(r&0x28)|((a^v^r)&FH)|(((a^v)&(a^r)&0x80)?FP:0)|FN|((r>>8)&1); z.a=r; break;}
  case 4: z.a=a&v; z.f=szp[z.a]|FH; break;
  case 5: z.a=a^v; z.f=szp[z.a]; break;
  case 6: z.a=a|v; z.f=szp[z.a]; break;
  case 7: r=a-v; z.f=(r&0x80)|((r&255)==0?FZ:0)|(v&0x28)|((a^v^r)&FH)|(((a^v)&(a^r)&0x80)?FP:0)|FN|((r>>8)&1); break;
  } }
static u8 inc8(u8 v){u8 r=v+1; z.f=(z.f&FC)|(r&0xA8)|(r==0?FZ:0)|((v&15)==15?FH:0)|(v==0x7f?FP:0); return r;}
static u8 dec8(u8 v){u8 r=v-1; z.f=(z.f&FC)|(r&0xA8)|(r==0?FZ:0)|((v&15)==0?FH:0)|(v==0x80?FP:0)|FN; return r;}
static u16 add16(u16 a,u16 b){u32 r=a+b; z.f=(z.f&(FS|FZ|FP))|((r>>8)&0x28)|(((a^b^r)>>8)&FH)|((r>>16)&1); z.wz=a+1; return r;}
static u16 adc16(u16 a,u16 b){u32 c=z.f&1,r=a+b+c; z.f=((r>>8)&0x80)|((r&0xffff)==0?FZ:0)|((r>>8)&0x28)|(((a^b^r)>>8)&FH)|((~(a^b)&(a^r)&0x8000)?FP:0)|((r>>16)&1); z.wz=a+1; return r;}
static u16 sbc16(u16 a,u16 b){u32 c=z.f&1,r=a-b-c; z.f=((r>>8)&0x80)|((r&0xffff)==0?FZ:0)|((r>>8)&0x28)|(((a^b^r)>>8)&FH)|(((a^b)&(a^r)&0x8000)?FP:0)|FN|((r>>16)&1); z.wz=a+1; return r;}
static u8 rot(int op,u8 v){u8 c,r; switch(op){
 case 0: c=v>>7; r=v<<1|c; break; case 1: c=v&1; r=v>>1|c<<7; break;
 case 2: c=v>>7; r=v<<1|(z.f&1); break; case 3: c=v&1; r=v>>1|(z.f&1)<<7; break;
 case 4: c=v>>7; r=v<<1; break; case 5: c=v&1; r=(v>>1)|(v&0x80); break;
 case 6: c=v>>7; r=v<<1|1; break; default: c=v&1; r=v>>1; }
 z.f=szp[r]|c; return r;}
static const int MAXT=0;
static u8 cbexec(u8 op,u8 v,int *wrback){ int x=op>>6,y=(op>>3)&7; *wrback=0;
  if(x==0){*wrback=1;return rot(y,v);} 
  if(x==1){ u8 f=(z.f&FC)|FH|(v&(1<<y)?0:(FZ|FP)); if(y==7&&(v&0x80))f|=FS; z.f=f|(v&0x28); return v;}
  *wrback=1; return x==2? v&~(1<<y) : v|(1<<y); }
static void daa(){u8 a=z.a,t=0,c=z.f&FC; if((z.f&FH)||(a&15)>9)t|=6; if(c||a>0x99){t|=0x60;c=1;}
  u8 r; int n=z.f&FN; if(n)r=a-t; else r=a+t; u8 h; if(n)h=((z.f&FH)&&(a&15)<6)?FH:0; else h=((a&15)>9)?FH:0;
  z.f=szp[r]|c|n|h; z.a=r;}
static void block_ld(int dir,int rep,u8 *t){ u8 v=rd(HL); wr(DE,v); setHL(HL+dir); setDE(DE+dir); setBC(BC-1); u8 n=v+z.a;
  z.f=(z.f&(FS|FZ|FC))|(n&8)|((n&2)<<4)|(BC?FP:0); }
static u32 tcount;
// executa uma instrucao; retorna T-states (tabela verificada separadamente; aqui calculo por classe)
static int step(){
  int t=0; pr=0; u8 op;
  if(z.halt){ z.r=(z.r&0x80)|((z.r+1)&0x7f); return 4; }
  op=fetch(); 
  while(op==0xDD||op==0xFD){ pr=op; t+=4; op=fetch(); if(op!=0xDD&&op!=0xFD)break; }
  if(op==0xED){ pr=0; t+=4; op=fetch(); int x=op>>6,y=(op>>3)&7,zz=op&7,p=y>>1,q=y&1;
    if(x==1){ switch(zz){
      case 0: { u8 v=0xff; z.f=(z.f&FC)|szp[v]; if(y!=6) setr(y,v,0); t+=8; return t; } // IN r,(C): sem perifericos retorna FF
      case 1: t+=8; return t; // OUT (C),r
      case 2: if(q==0) setHL(sbc16(HL,getrp(p))), pr=0; else setHL(adc16(HL,getrp(p))); return t+11;
      case 3: { u16 a=fetch16(); if(q==0){ w16(a,getrp(p)); } else { setrp(p,rd16(a)); } z.wz=a+1; return t+16; }
      case 4: { u8 a=z.a; z.a=0; alu(2,a); return t+4; }
      case 5: z.pc=pop(); z.iff1=z.iff2; z.wz=z.pc; return t+10;
      case 6: z.im=(y&3)==2?1:((y&3)==3?2:0); return t+4;
      case 7: switch(y){ case 0: z.i=z.a; return t+5; case 1: z.r=z.a; return t+5;
        case 2: z.a=z.i; z.f=(z.f&FC)|szp[z.a]&~FP|(z.iff2?FP:0); return t+5;
        case 3: z.a=z.r; z.f=(z.f&FC)|szp[z.a]&~FP|(z.iff2?FP:0); return t+5;
        case 4: { u8 m=rd(HL); wr(HL,(z.a<<4)|(m>>4)); z.a=(z.a&0xf0)|(m&15); z.f=(z.f&FC)|szp[z.a]; z.wz=HL+1; return t+14; }
        case 5: { u8 m=rd(HL); wr(HL,(m<<4)|(z.a&15)); z.a=(z.a&0xf0)|(m>>4); z.f=(z.f&FC)|szp[z.a]; z.wz=HL+1; return t+14; }
        default: return t+4; } } }
    if(x==2&&zz<4&&y>=4){ int k=y&3; // LDI/LDD/LDIR/LDDR, CPI.., INI.., OUTI..
      int dir=(k&1)?-1:1, rep=k>>1;
      if(zz==0){ block_ld(dir,rep,0); if(rep&&BC){z.pc-=2;z.wz=z.pc+1;return t+17;} return t+12; }
      if(zz==1){ u8 v=rd(HL),r=z.a-v; u8 h=((z.a^v^r)&FH); u8 f=(z.f&FC)|FN|h|(r&0x80)|(r==0?FZ:0); setHL(HL+dir); setBC(BC-1); if(BC)f|=FP; u8 n=r-(h?1:0); f|=(n&8)|((n&2)<<4); z.f=f; z.wz+=dir;
        if(rep&&BC&&r){z.pc-=2;z.wz=z.pc+1;return t+17;} return t+12; }
      if(zz==2){ u8 v=0xff; wr(HL,v); z.b--; setHL(HL+dir); z.f=szp[z.b]&~FP; z.f&=~FP; z.f=(z.b&0xA8)|(z.b==0?FZ:0)|FN; if(rep&&z.b){z.pc-=2;return t+17;} return t+12; }
      { u8 v=rd(HL); z.b--; setHL(HL+dir); z.f=(z.b&0xA8)|(z.b==0?FZ:0)|FN; if(rep&&z.b){z.pc-=2;return t+17;} return t+12; } }
    return t+4; // NOP* ED
  }
  if(op==0xCB){ // prefixo CB (com DD/FD: CB d op)
    if(pr){ int8_t d=(int8_t)fetchd(); u8 o2=rd(z.pc++); u16 a=idx()+d; z.wz=a; u8 v=rd(a); int wb; u8 r=cbexec(o2,v,&wb);
      if((o2>>6)==1){ z.f=(z.f&FC)|FH|(v&(1<<((o2>>3)&7))?0:(FZ|FP))|((a>>8)&0x28); if(((o2>>3)&7)==7&&(v&(1<<7)))z.f|=FS; return t+16; }
      wr(a,r); int rr=o2&7; if(rr!=6) *r8p(rr)=r; return t+19; }
    z.r=(z.r&0x80)|((z.r+1)&0x7f); u8 o2=fetch(); int rr=o2&7,wb; 
    if(rr==6){ u8 v=rd(HL); u8 r=cbexec(o2,v,&wb); if((o2>>6)==1){ z.f=(z.f&FC)|FH|(v&(1<<((o2>>3)&7))?0:(FZ|FP))|((z.wz>>8)&0x28); if(((o2>>3)&7)==7&&(v&0x80))z.f|=FS; return t+12;} wr(HL,r); return t+15; }
    u8 v=*r8p(rr); u8 r=cbexec(o2,v,&wb); if(wb)*r8p(rr)=r; return t+8; }
  int x=op>>6,y=(op>>3)&7,zz=op&7,p=y>>1,q=y&1;
  // acesso a (HL)/(IX+d)
  u16 ea=0; int hasd=0;
  #define MEMOP ((pr)?(hasd=1, ea=idx()+(int8_t)fetchd(), z.wz=ea, 1):(ea=HL,1))
  if(x==1){ if(op==0x76){z.halt=1; z.pc--; return t+4;}
    if(y==6){ MEMOP; wr(ea, getr(zz,0)); return t+(pr?15:7); }
    if(zz==6){ MEMOP; setr(y,rd(ea),0); return t+(pr?15:7); }
    setr(y,getr(zz,1),1); return t+4; }
  if(x==2){ if(zz==6){ MEMOP; alu(y,rd(ea)); return t+(pr?15:7);} alu(y,getr(zz,1)); return t+4; }
  if(x==0) switch(zz){
    case 0: switch(y){ case 0: return t+4; case 1: { u8 s=z.a;z.a=z.a2;z.a2=s;s=z.f;z.f=z.f2;z.f2=s;return t+4;}
      case 2: { int8_t d=fetchd(); z.b--; if(z.b){z.pc+=d;z.wz=z.pc;return t+13;} return t+8;}
      case 3: { int8_t d=fetchd(); z.pc+=d; z.wz=z.pc; return t+12; }
      default: { int8_t d=fetchd(); if(cond(y-4)){z.pc+=d;z.wz=z.pc;return t+12;} return t+7; } }
    case 1: if(q==0){ setrp(p,fetch16()); return t+10; } else { u16 r=add16(pr?idx():HL,getrp(p)); if(pr)setidx(r); else setHL(r); return t+11; }
    case 2: switch(y){ case 0: wr(BC,z.a); z.wz=((BC+1)&255)|z.a<<8; return t+7; case 1: z.a=rd(BC); z.wz=BC+1; return t+7;
      case 2: wr(DE,z.a); z.wz=((DE+1)&255)|z.a<<8; return t+7; case 3: z.a=rd(DE); z.wz=DE+1; return t+7;
      case 4: { u16 a=fetch16(); w16(a,pr?idx():HL); z.wz=a+1; return t+16; }
      case 5: { u16 a=fetch16(); u16 v=rd16(a); if(pr)setidx(v); else setHL(v); z.wz=a+1; return t+16; }
      case 6: { u16 a=fetch16(); wr(a,z.a); z.wz=((a+1)&255)|z.a<<8; return t+13; }
      default: { u16 a=fetch16(); z.a=rd(a); z.wz=a+1; return t+13; } }
    case 3: { if(p==2&&pr){ setidx(idx()+(q?-1:1)); return t+6; } setrp(p,getrp(p)+(q?-1:1)); return t+6; }
    case 4: if(y==6){ MEMOP; wr(ea,inc8(rd(ea))); return t+(pr?19:11);} { u8 v=getr(y,1); setr(y,inc8(v),1); return t+4; }
    case 5: if(y==6){ MEMOP; wr(ea,dec8(rd(ea))); return t+(pr?19:11);} { u8 v=getr(y,1); setr(y,dec8(v),1); return t+4; }
    case 6: if(y==6){ if(pr){ ea=idx()+(int8_t)fetchd(); z.wz=ea; u8 n=fetchd(); wr(ea,n); return t+15;} wr(HL,fetchd()); return t+10; } setr(y,fetchd(),1); return t+7;
    default: switch(y){
      case 0: { u8 a=z.a,c=a>>7; z.a=a<<1|c; z.f=(z.f&(FS|FZ|FP))|(z.a&0x28)|c; return t+4;}
      case 1: { u8 a=z.a,c=a&1; z.a=a>>1|c<<7; z.f=(z.f&(FS|FZ|FP))|(z.a&0x28)|c; return t+4;}
      case 2: { u8 a=z.a,c=a>>7; z.a=a<<1|(z.f&1); z.f=(z.f&(FS|FZ|FP))|(z.a&0x28)|c; return t+4;}
      case 3: { u8 a=z.a,c=a&1; z.a=a>>1|(z.f&1)<<7; z.f=(z.f&(FS|FZ|FP))|(z.a&0x28)|c; return t+4;}
      case 4: daa(); return t+4;
      case 5: z.a=~z.a; z.f=(z.f&(FS|FZ|FP|FC))|FH|FN|(z.a&0x28); return t+4;
      case 6: z.f=(z.f&(FS|FZ|FP))|(z.a&0x28)|FC; return t+4;
      default: { u8 c=z.f&FC; z.f=(z.f&(FS|FZ|FP))|(z.a&0x28)|(c?FH:FC); return t+4; } } }
  // x==3
  switch(zz){
    case 0: if(cond(y)){ z.pc=pop(); z.wz=z.pc; return t+11;} return t+5;
    case 1: if(q==0){ setrp2(p,pop()); return t+10;} switch(p){ case 0: z.pc=pop(); z.wz=z.pc; return t+10; case 1: { u8 s;s=z.b;z.b=z.b2;z.b2=s;s=z.c;z.c=z.c2;z.c2=s;s=z.d;z.d=z.d2;z.d2=s;s=z.e;z.e=z.e2;z.e2=s;s=z.h;z.h=z.h2;z.h2=s;s=z.l;z.l=z.l2;z.l2=s; return t+4; }
      case 2: z.pc=pr?idx():HL; return t+4; default: z.sp=pr?idx():HL; return t+6; }
    case 2: { u16 a=fetch16(); z.wz=a; if(cond(y))z.pc=a; return t+10; }
    case 3: switch(y){ case 0: z.pc=fetch16(); z.wz=z.pc; return t+10; case 2: fetchd(); return t+11; case 3: fetchd(); z.a|=0; return t+11;
      case 4: { u16 v=rd16(z.sp); w16(z.sp,pr?idx():HL); if(pr)setidx(v); else setHL(v); z.wz=v; return t+19; }
      case 5: { u16 d=DE,h=HL; setDE(h); setHL(d); return t+4; }
      case 6: z.iff1=z.iff2=0; return t+4; default: z.iff1=z.iff2=1; return t+4; }
    case 4: { u16 a=fetch16(); z.wz=a; if(cond(y)){ push(z.pc); z.pc=a; return t+17;} return t+10; }
    case 5: if(q==0){ push(getrp2(p)); return t+11;} { u16 a=fetch16(); push(z.pc); z.pc=a; z.wz=a; return t+17; }
    case 6: alu(y,fetchd()); return t+7;
    default: push(z.pc); z.pc=y*8; z.wz=z.pc; return t+11; }
}
// CP/M shim
static int bdos(){ // PC==5
  switch(z.c){ case 2: putchar(z.e); break; case 9: { u16 a=DE; while(mem[a]!='$')putchar(mem[a++]); break; } }
  fflush(stdout); z.pc=pop(); return 1; }

static int tmode(){
  // dump: pagina op fT fN  (menor/maior T entre cenarios: F=00,FF; BC/B=2 e 1)
  const char *pg[]={"00","CB","ED","DD","FD","DDCB","FDCB"};
  for(int p=0;p<7;p++) for(int op=0;op<256;op++){
    int tmin=9999,tmax=0;
    for(int sc=0;sc<6;sc++){
      memset(mem,0,65536); memset(&z,0,sizeof z); z.pc=0x8000; z.sp=0xC000; z.a=0x55; z.f=(sc&1)?0xFF:0x00; z.b=(sc>>1)==0?2:((sc>>1)==1?1:0); z.c=(sc>>1)==0?2:1; z.h=0x40; z.l=0; z.d=0x41; z.e=0; z.ix=0x4000; z.iy=0x4000;
      u8*m=mem+0x8000; int n=0;
      if(p==0) m[n++]=op; else if(p==1){m[n++]=0xCB;m[n++]=op;} else if(p==2){m[n++]=0xED;m[n++]=op;}
      else if(p==3){m[n++]=0xDD;m[n++]=op;} else if(p==4){m[n++]=0xFD;m[n++]=op;}
      else if(p==5){m[n++]=0xDD;m[n++]=0xCB;m[n++]=0;m[n++]=op;} else {m[n++]=0xFD;m[n++]=0xCB;m[n++]=0;m[n++]=op;}
      if(p==0&&op==0x76)continue;
      if(p==0&&(op==0xDD||op==0xFD||op==0xED||op==0xCB))continue;
      if(p>=3&&p<=4&&(op==0xDD||op==0xFD||op==0xED))continue;
      int t=step(); if(t<tmin)tmin=t; if(t>tmax)tmax=t; }
    if(tmax) printf("%s %02X %d %d\n",pg[p],op,tmax,tmin);
  } return 0; }

int main(int argc,char**argv){
  if(argc>1&&!strcmp(argv[1],"-t")){ for(int i=0;i<256;i++){ int p=1; for(int b=0;b<8;b++) if(i>>b&1)p^=1; szp[i]=(i&0xA8)|(i==0?FZ:0)|(p?FP:0); } return tmode(); }
  for(int i=0;i<256;i++){ int p=1; for(int b=0;b<8;b++) if(i>>b&1)p^=1; szp[i]=(i&0xA8)|(i==0?FZ:0)|(p?FP:0); }
  if(argc<2){fprintf(stderr,"uso: z80ref prog.com [maxinst]\n");return 1;}
  FILE*f=fopen(argv[1],"rb"); int n=fread(mem+0x100,1,0xF000,f); fclose(f);
  u64 maxi=argc>2?strtoull(argv[2],0,10):~0ULL;
  mem[0]=0x76; mem[5]=0xC9; mem[6]=0x00; mem[7]=0xF0; // topo da memoria F000 -> SP
  memset(&z,0,sizeof z); z.pc=0x100; z.sp=0xF000; z.a=z.f=0xff; z.iff1=z.iff2=0;
  u64 ni=0;
  while(ni<maxi){
    if(z.pc==5){ bdos(); }
    else if(z.pc==0){ printf("\n[fim: jp 0] instrucoes=%llu T=%llu\n",(unsigned long long)ni,(unsigned long long)z.t); return 0; }
    z.t+=step(); ni++; }
  printf("\n[limite] instrucoes=%llu\n",(unsigned long long)ni); return 0; }
