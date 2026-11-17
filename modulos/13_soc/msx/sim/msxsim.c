// msxsim.c - test bench for R8064.COM: Z80 (module 12 reference model) + MSX-DOS 1 shim (FCB calls)
// + behavioural model of the R8064 cartridge (ports 0Bh-0Dh as in r8064_fifo_if/r8064_slot_dec, and the
// REV46 monitor message handling as in fw/monitor.asm). EXEC runs the loaded program on a second Z80
// context over the 64 KB at physical 0 (mode 00h-03h: logical = physical with A8h = 00h).
// Build: python3 mk_core.py ../../../12_z80/ref/z80ref.c z80core.c && gcc -O2 -o msxsim msxsim.c
// Use:   ./msxsim [options] R8064.COM args...      options: -nocard  -lose N (drop message N, 1-based)  -dead (drop all)
//        -evt N (an unsolicited EVT 03 is sent at the N-th STATUS read)  -sd file (8 MB image in/out)  -v (trace)
#include "z80core.c"

static u8 *sd;                                   // 8 MB SDRAM
static int nocard, lose_n = -1, verbose, msgno;
// ---- cartridge: FIFOs and registers
static u8 fa[2048], fb[2048]; static int fa_r, fa_n, fb_r, fb_n;
static u8 len_l, len_h; static int lenptr, busy, done, err, irq_en, pend, evt_cnt; static u8 evt_buf[16]; static int evt_len;
static void fb_push(u8 v){ if (fb_n == 2048) { err = 1; return; } fb[(fb_r + fb_n++) & 2047] = v; }
static u8 fa_pop(void){ if (!fa_n) { err = 1; return 0xFF; } u8 v = fa[fa_r]; fa_r = (fa_r + 1) & 2047; fa_n--; return v; }
static void clr_fifos(void){ fa_r = fa_n = fb_r = fb_n = 0; lenptr = 0; err = 0; }
static void finish(int n){ len_l = n; len_h = n >> 8; done = 1; busy = 0; }
static u16 crc16(u32 a, u32 n){ u16 c = 0xFFFF; while (n--) { c ^= sd[a++ & 0x7FFFFF] << 8; for (int i = 0; i < 8; i++) c = c & 0x8000 ? (c << 1) ^ 0x1021 : c << 1; } return c; }

static u64 r8_steps; static u32 r8_exit;
static void run_r8064(u16 entry, u16 arg){       // runs the program as the monitor does (CALL entry, HL = arg, RET -> exit code in HL)
    static u8 save[65536]; Z zs = z; int prs = pr; memcpy(save, mem, 65536); memcpy(mem, sd, 65536);
    memset(&z, 0, sizeof z); z.sp = 0x2FF0; push(0x0002); z.pc = entry; setHL(arg); r8_steps = 0;
    while (z.pc != 0x0002 && r8_steps < 50000000) { step(); r8_steps++; }
    r8_exit = HL; if (z.pc != 0x0002) r8_exit = 0xDEAD;
    memcpy(sd, mem, 65536); memcpy(mem, save, 65536); z = zs; pr = prs;
}

static void monitor(void){                       // one message, as fw/monitor.asm
    static u8 m[2048]; int n = len_l | len_h << 8; if (n > 2048) n = 2048;
    for (int i = 0; i < n; i++) m[i] = fa_pop();
    msgno++;
    if (verbose) { fprintf(stderr, "[R8064] msg %d len %d:", msgno, n); for (int i = 0; i < n && i < 12; i++) fprintf(stderr, " %02X", m[i]); fprintf(stderr, "\n"); }
    if (msgno == lose_n || lose_n == 0) { if (verbose) fprintf(stderr, "[R8064] message lost (fault injection)\n"); busy = 1; return; }
    u8 op = m[0], st = 0; int rl = 3;
    #define CHKA(p) (!((p)[2] & 0x80) && (p)[3] == 0)
    if (n < 2) { st = 2; goto reply; }
    u32 ad = m[2] | m[3] << 8 | m[4] << 16 | (u32)m[5] << 24;
    switch (op) {
    case 0x00: case 0x02: break;
    case 0x01: { const u8 h[11] = {'R','8','0','6','4',1,0x00,0x08,0x00,0x40,0x07}; fb_push(op | 0x80); fb_push(m[1]); fb_push(0); for (int i = 0; i < 11; i++) fb_push(h[i]); finish(14); return; }
    case 0x12: { int sz = n - 6; if (sz <= 0 || sz >= 0x800 || !CHKA(m + 2)) { st = 2; break; } memcpy(sd + ad, m + 6, sz); break; }
    case 0x13: { int sz = m[6] | m[7] << 8; if (n != 8 || sz == 0 || sz >= 0x800 || !CHKA(m + 2)) { st = 2; break; }
                 fb_push(op | 0x80); fb_push(m[1]); fb_push(0); for (int i = 0; i < sz; i++) fb_push(sd[ad + i]); finish(sz + 3); return; }
    case 0x30: { if (n != 10 || !CHKA(m + 2)) { st = 2; break; } if (m[2] & 7) { st = 3; break; }
                 u32 sz = m[6] | m[7] << 8 | m[8] << 16 | (u32)m[9] << 24; u16 c = crc16(ad, sz);
                 fb_push(op | 0x80); fb_push(m[1]); fb_push(0); fb_push(c); fb_push(c >> 8); finish(5); return; }
    case 0x20: { if (n != 19 || m[10] >= 5) { st = 2; break; } for (int i = 4; i < 10; i++) if (m[i]) st = 2; if (st) break;
                 fb_push(op | 0x80); fb_push(m[1]); fb_push(0); finish(3);
                 run_r8064(m[2] | m[3] << 8, m[11] | m[12] << 8);
                 if (verbose) fprintf(stderr, "[R8064] program ran %llu instructions, HL = %04X\n", (unsigned long long)r8_steps, r8_exit);
                 evt_buf[0] = 0xF0; evt_buf[1] = 0; evt_buf[2] = 1; for (int i = 0; i < 4; i++) evt_buf[3 + i] = r8_exit >> (8 * i); evt_len = 7; evt_cnt = 500; return; }
    case 0x21: st = 3; break;
    default: st = 1;
    }
reply:
    fb_push(op | 0x80); fb_push(m[1]); fb_push(st); finish(rl);
}

static void tick(void){                          // R8064 side progress, one step per STATUS read
    if (pend && --pend == 0) monitor();
    if (evt_cnt && !done && !busy && --evt_cnt == 0) { for (int i = 0; i < evt_len; i++) fb_push(evt_buf[i]); finish(evt_len); if (verbose) fprintf(stderr, "[R8064] EVT %02X sent\n", evt_buf[2]); }
}
static u8 io_in(u8 p){
    if (nocard) return 0xFF;
    switch (p) {
    case 0x0B: tick(); return (fb_n ? 1 : 0) | (fa_n < 2048 ? 2 : 0) | busy << 2 | done << 3 | (done && irq_en) << 4 | (!busy) << 5 | err << 6;
    case 0x0C: { if (!fb_n) { err = 1; return 0xFF; } u8 v = fb[fb_r]; fb_r = (fb_r + 1) & 2047; fb_n--; return v; }
    case 0x0D: { u8 v = lenptr ? len_h : len_l; lenptr ^= 1; return v; }
    }
    return 0xFF;
}
static void io_out(u8 p, u8 v){
    if (nocard) return;
    switch (p) {
    case 0x0B:
        if (v & 0x08) { clr_fifos(); busy = done = 0; pend = evt_cnt = 0; len_l = len_h = 0; if (verbose) fprintf(stderr, "[R8064] restart\n"); }
        if (v & 0x02) clr_fifos();
        irq_en = (v >> 2) & 1;
        if (v & 0x01) { busy = 1; done = 0; pend = 40; }
        if (v & 0x80) done = 0;
        break;
    case 0x0C: if (fa_n == 2048) err = 1; else fa[(fa_r + fa_n++) & 2047] = v; break;
    case 0x0D: if (lenptr) len_h = v; else len_l = v; lenptr ^= 1; break;
    }
}

// ---- MSX-DOS 1 shim
static FILE *fp; static u16 dta = 0x80;
static void fname(u16 f, char *o){ int k = 0; for (int i = 1; i <= 8; i++) if (mem[f + i] != ' ') o[k++] = mem[f + i];
    if (mem[f + 9] != ' ') { o[k++] = '.'; for (int i = 9; i <= 11; i++) if (mem[f + i] != ' ') o[k++] = mem[f + i]; } o[k] = 0; }
static int bdos_call(void){                      // returns 1 at program end
    u16 f = DE; char nm[16]; u8 a = 0;
    switch (z.c) {
    case 0x00: return 1;
    case 0x02: putchar(z.e); break;
    case 0x06: a = 0; break;                     // no key pressed
    case 0x09: { u16 p = DE; while (mem[p] != '$') putchar(mem[p++]); break; }
    case 0x0B: a = 0; break;
    case 0x0F: fname(f, nm); fp = fopen(nm, "rb"); if (!fp) { a = 0xFF; break; }
               fseek(fp, 0, SEEK_END); { long s = ftell(fp); for (int i = 0; i < 4; i++) mem[f + 0x10 + i] = s >> (8 * i); }
               mem[f + 0x0C] = 0; mem[f + 0x0E] = 0x80; mem[f + 0x0F] = 0; break;
    case 0x16: fname(f, nm); fp = fopen(nm, "w+b"); a = fp ? 0 : 0xFF; mem[f + 0x0E] = 0x80; mem[f + 0x0F] = 0; break;
    case 0x10: if (fp) fclose(fp); fp = 0; break;
    case 0x1A: dta = DE; break;
    case 0x26: case 0x27: {
        int rs = mem[f + 0x0E] | mem[f + 0x0F] << 8; u32 rr = mem[f + 0x21] | mem[f + 0x22] << 8 | mem[f + 0x23] << 16 | (rs < 64 ? (u32)mem[f + 0x24] << 24 : 0);
        int nrec = HL; fseek(fp, (long)rr * rs, SEEK_SET); int got;
        if (z.c == 0x27) { memset(mem + dta, 0, nrec * rs); int b = fread(mem + dta, 1, nrec * rs, fp); got = (b + rs - 1) / rs; a = got < nrec; }
        else { fwrite(mem + dta, 1, nrec * rs, fp); got = nrec; }
        rr += got; for (int i = 0; i < 4; i++) mem[f + 0x21 + i] = rr >> (8 * i); setHL(got); break; }
    default: fprintf(stderr, "[DOS] function %02X not emulated\n", z.c); return 1;
    }
    z.a = a; if (z.c != 0x26 && z.c != 0x27) z.l = a; fflush(stdout); z.pc = pop(); return 0;
}

int main(int argc, char **argv){
    for (int i = 0; i < 256; i++) { int p = 1; for (int b = 0; b < 8; b++) if (i >> b & 1) p ^= 1; szp[i] = (i & 0xA8) | (i == 0 ? FZ : 0) | (p ? FP : 0); }
    sd = calloc(1, 8 << 20); const char *sdf = 0; int k = 1;
    for (; k < argc && argv[k][0] == '-'; k++) {
        if (!strcmp(argv[k], "-nocard")) nocard = 1; else if (!strcmp(argv[k], "-v")) verbose = 1;
        else if (!strcmp(argv[k], "-lose")) lose_n = atoi(argv[++k]); else if (!strcmp(argv[k], "-sd")) sdf = argv[++k];
        else if (!strcmp(argv[k], "-dead")) lose_n = 0;
        else if (!strcmp(argv[k], "-evt")) { const u8 e[] = {0xF0, 0, 3, 0x11, 0x22}; memcpy(evt_buf, e, 5); evt_len = 5; evt_cnt = atoi(argv[++k]); }
    }
    if (sdf) { FILE *s = fopen(sdf, "rb"); if (s) { fread(sd, 1, 8 << 20, s); fclose(s); } }
    FILE *f = fopen(argv[k++], "rb"); if (!f) { fprintf(stderr, "no .COM\n"); return 2; } fread(mem + 0x100, 1, 0xC000, f); fclose(f);
    char line[128] = ""; for (; k < argc; k++) { strcat(line, " "); strcat(line, argv[k]); }
    mem[0x80] = strlen(line); memcpy(mem + 0x81, line, strlen(line));
    mem[0] = 0xC3; mem[1] = 0; mem[2] = 0; mem[5] = 0xC9; mem[6] = 0x00; mem[7] = 0xD0;
    z.pc = 0x100; z.sp = 0xD000; push(0x0000);
    u64 n = 0;
    while (n < 2000000000ULL) {
        if (z.pc == 5) { if (bdos_call()) break; continue; }
        if (z.pc == 0) break;
        z.t += step(); n++;
    }
    fprintf(stderr, "[sim] MSX: %llu instructions, %.3f s at 3.58 MHz; R8064 messages: %d\n", (unsigned long long)n, z.t / 3579545.0, msgno);
    if (sdf) { FILE *s = fopen(sdf, "wb"); fwrite(sd, 1, 8 << 20, s); fclose(s); }
    return 0;
}
