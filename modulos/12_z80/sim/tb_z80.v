`timescale 1ns/1ps
// tb_z80.v - compara o RTL com o modelo C (z80ref -d) a cada instrucao: PC, A F BC DE HL IX IY SP WZ, sombra, I R, IFF, IM, T acumulado.
// plusargs: +mem=mem.hex +regs=regs.txt +trace=trace.txt +n=20000 +wait=0/1 (wait=1: ce lento + WAIT aleatorio, sem comparar T)
module tb_z80;
  reg clk=0, rst_n=0; always #5 clk=~clk;
  reg [7:0] mem [0:65535];
  wire [15:0] a; wire [7:0] dout; reg [7:0] din; wire mreq, rd, wr, iorq, m1, rfsh, halt, busak, instr_done;
  reg ce=0; reg wait_n=1; reg go=0;
  z80_core dut(.clk(clk), .ce(ce), .rst_n(rst_n), .addr(a), .dout(dout), .din(din), .mreq(mreq), .rd(rd), .wr(wr), .iorq(iorq),
     .m1(m1), .rfsh(rfsh), .wait_n(wait_n), .int_n(1'b1), .nmi_n(1'b1), .busrq_n(1'b1), .msx_w(1'b0), .halt(halt), .busak(busak), .bus_oe(), .instr_done(instr_done), .tick());
  integer waitmode=0; integer rnd=32'h1234567;
  always @(posedge clk) begin
    rnd <= rnd*1103515245 + 12345;
    if (waitmode) begin ce <= go & (rnd[17:16]==2'd0); wait_n <= rnd[21]; end else begin ce <= go; wait_n <= 1'b1; end
  end
  always @(negedge clk or a or iorq or rd) begin
    if (iorq && rd) din = a[7:0] ^ a[15:8] ^ 8'h5A; else din = mem[a];
  end
  always @(posedge clk) if (wr && mreq) mem[a] <= dout;
  integer tc=0; always @(posedge clk) if (dut.tick) tc <= tc + 1;

  integer fd, fr, nmax, ninstr, errs, rc, i, tmode;
  reg [8*200-1:0] fmem, fregs, ftrace;
  reg [31:0] v [0:31];
  reg [15:0] e_pc, e_af, e_bc, e_de, e_hl, e_ix, e_iy, e_sp, e_wz, e_af2, e_bc2, e_de2, e_hl2, e_ir;
  reg [11:0] e_if; reg [63:0] e_t;
  initial begin
    if (!$value$plusargs("mem=%s", fmem)) fmem="mem.hex";
    if (!$value$plusargs("regs=%s", fregs)) fregs="regs.txt";
    if (!$value$plusargs("trace=%s", ftrace)) ftrace="trace.txt";
    if (!$value$plusargs("n=%d", nmax)) nmax=20000;
    if (!$value$plusargs("wait=%d", waitmode)) waitmode=0;
    $readmemh(fmem, mem);
    fr=$fopen(fregs,"r"); for (i=0;i<26;i=i+1) rc=$fscanf(fr,"%h",v[i]); $fclose(fr);
    fd=$fopen(ftrace,"r");
    ninstr=0; errs=0;
    repeat (4) @(posedge clk);
    @(negedge clk); rst_n = 1;
    repeat (60) @(posedge clk);   // rotina de RESET termina e o 1o ciclo M1 fica aguardando ce
    @(negedge clk);
    wr8(7, v[0][7:0]); dut.f=v[1][7:0];
    wr8(0, v[2][7:0]); wr8(1, v[3][7:0]); wr8(2, v[4][7:0]); wr8(3, v[5][7:0]); wr8(4, v[6][7:0]); wr8(5, v[7][7:0]);
    wr8(16, v[8][15:8]); wr8(17, v[8][7:0]); wr8(18, v[9][15:8]); wr8(19, v[9][7:0]);
    wr8(20, v[10][15:8]); wr8(21, v[10][7:0]); wr8(22, v[11][15:8]); wr8(23, v[11][7:0]);
    dut.caddr=v[11][15:0]; dut.ri=v[12][7:0]; dut.rr=v[13][7:0];
    wr8(15, v[14][7:0]); dut.f2=v[15][7:0];
    wr8(8, v[16][7:0]); wr8(9, v[17][7:0]); wr8(10, v[18][7:0]); wr8(11, v[19][7:0]); wr8(12, v[20][7:0]); wr8(13, v[21][7:0]);
    dut.iff1=v[22][0]; dut.iff2=v[23][0]; dut.im=v[24][1:0]; dut.wh=v[25][15:8]; dut.wl=v[25][7:0];
    tc = 0;
    go = 1;
  end
  task wr8; input integer k; input [7:0] val; begin dut.rfa[k] = val; dut.rfb[k] = val; end endtask
  // comparacao no negedge (valores estaveis)
  always @(negedge clk) if (rst_n && instr_done && ninstr < nmax) begin
    rc = $fscanf(fd, "%h %h %h %h %h %h %h %h %h %h %h %h %h %h %h", e_pc, e_af, e_bc, e_de, e_hl, e_ix, e_iy, e_sp, e_wz, e_af2, e_bc2, e_de2, e_hl2, e_ir, e_if);
    if (rc != 15) begin $display("PASS: %0d instrucoes identicas ao modelo (fim do traco: HALT no modelo)", ninstr); $finish; end
    rc = $fscanf(fd, "%h", e_t);
    ninstr = ninstr + 1;
    if ({dut.dbg_pc, dut.dbg_a, dut.f, dut.dbg_bc, dut.dbg_de, dut.dbg_hl, dut.dbg_ix, dut.dbg_iy, dut.dbg_sp, dut.dbg_wz} !== {e_pc, e_af, e_bc, e_de, e_hl, e_ix, e_iy, e_sp, e_wz}
        || {dut.dbg_a2, dut.f2, dut.dbg_bc2, dut.dbg_de2, dut.dbg_hl2} !== {e_af2, e_bc2, e_de2, e_hl2}
        || {dut.ri, dut.rr} !== e_ir || {dut.iff1, dut.iff2, dut.im} !== {e_if[8], e_if[4], e_if[1:0]}
        || (!waitmode && tc !== e_t)) begin
      errs = errs + 1;
      if (errs <= 8) begin
        $display("DIVERGE instr #%0d  opcode-prev: mem[%h]=%h", ninstr, e_pc, mem[e_pc]);
        $display("  RTL: pc=%h af=%h%h bc=%h de=%h hl=%h ix=%h iy=%h sp=%h wz=%h af'=%h%h ir=%h%h iff=%b%b im=%0d T=%0d", dut.dbg_pc, dut.dbg_a, dut.f, dut.dbg_bc, dut.dbg_de, dut.dbg_hl, dut.dbg_ix, dut.dbg_iy, dut.dbg_sp, dut.dbg_wz, dut.dbg_a2, dut.f2, dut.ri, dut.rr, dut.iff1, dut.iff2, dut.im, tc);
        $display("  REF: pc=%h af=%h bc=%h de=%h hl=%h ix=%h iy=%h sp=%h wz=%h af'=%h ir=%h iff=%h T=%0d", e_pc, e_af, e_bc, e_de, e_hl, e_ix, e_iy, e_sp, e_wz, e_af2, e_ir, e_if, e_t);
      end
      if (errs >= 1) begin $display("FAIL: %0d instrucoes comparadas ate a 1a divergencia", ninstr); $finish; end
    end
    if (ninstr == nmax) begin
      $display("PASS: %0d instrucoes identicas ao modelo (T-states %s)", ninstr, waitmode ? "nao comparados" : "comparados");
      $finish;
    end
  end
  initial begin #2000000000; $display("TIMEOUT instr=%0d", ninstr); $finish; end
endmodule
