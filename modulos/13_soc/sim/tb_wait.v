`timescale 1ns/1ps
// tb_wait.v - clocks per instruction in NATIVE mode, full SoC (real uop/main ROMs), program in SDRAM through MMU (bypass) + caches + arbiters.
// +k=<kind> selects the loop body (see below); prints clocks/instruction and where the clocks go (fetch starvation, decode phases, holds).
module tb_wait;
    wire mmu_en_w, mmu_user_w; integer sc = 1; integer nfi = 0, nfd = 0; reg clk = 0, rst = 1; always #5 clk = ~clk;
    reg io_we = 0, io_re = 0; reg [7:0] io_a = 0, io_wd = 0; wire [7:0] io_rd; wire io_oe, iox_we, iox_re; wire [7:0] iox_a, iox_wd;
    wire nat, csel, z80, rom, mbusy, cv, dbg_sig, init_done, fifo_irq, fifo_rst, fbi, fbd, i_fault, d_fault; wire [2:0] ic, dc; wire [63:0] dbg_pc; wire [7:0] dbg_f, fm_rd;
    wire s_cke, s_cs_n, s_ras_n, s_cas_n, s_we_n, s_dq_oe; wire [3:0] s_dqm; wire [1:0] s_ba; wire [10:0] s_a; wire [31:0] s_dq_o, mdq;
    reg [31:0] dq_in; always @* dq_in = mdq;
    r8064_soc #(.INIT_CYC(2000)) dut(.clk(clk), .rst(rst), .irq(1'b1),
        .io_we(io_we), .io_re(io_re), .io_a(io_a), .io_wd(io_wd), .io_rd(io_rd), .io_oe(io_oe), .io_x_we(iox_we), .io_x_re(iox_re), .io_x_a(iox_a), .io_x_wd(iox_wd), .io_x_rd(8'h5A), .port_c(8'd0),
        .sb_we(1'b0), .sb_re(1'b0), .sb_a(14'd0), .sb_wd(8'd0), .sb_rd(), .fm_we(1'b0), .fm_re(1'b0), .fm_a(2'd0), .fm_wd(8'd0), .fm_rd(fm_rd), .fifo_irq(fifo_irq), .fifo_rst(fifo_rst),
        .native64(nat), .clk_sel(csel), .is_z80(z80), .is_rom(rom), .mode_busy(mbusy), .dbg_pc(dbg_pc), .dbg_f(dbg_f), .dbg_sig(dbg_sig), .gov_cv(cv),
        .fl_busy_i(fbi), .fl_busy_d(fbd), .mmu_en(mmu_en_w), .mmu_user(mmu_user_w),
        .i_fault(i_fault), .d_fault(d_fault), .i_cause(ic), .d_cause(dc),
        .init_done(init_done), .s_cke(s_cke), .s_cs_n(s_cs_n), .s_ras_n(s_ras_n), .s_cas_n(s_cas_n), .s_we_n(s_we_n), .s_dqm(s_dqm), .s_ba(s_ba), .s_a(s_a),
        .s_dq_o(s_dq_o), .s_dq_oe(s_dq_oe), .s_dq_i(dq_in));
    sdram_model mdl(.clk(clk), .cke(s_cke), .cs_n(s_cs_n), .ras_n(s_ras_n), .cas_n(s_cas_n), .we_n(s_we_n), .dqm(s_dqm), .ba(s_ba), .a(s_a), .dq_i(s_dq_o), .dq_oe(s_dq_oe), .dq_o(mdq));
    integer nwi = 0, nwd = 0; always @(posedge clk) begin if (dut.u_mem.iw_accept) nwi <= nwi + 1; if (dut.u_mem.dw_accept) nwd <= nwd + 1; end
    integer MIX = 8, j, loop0, errs = 0, k, n_ow = 0, n_ir = 0; reg [63:0] ppc = 0; integer it=0, it0, cyc=0, c0; always @(posedge clk) begin cyc <= cyc + 1; ppc <= dbg_pc; if (dbg_pc == loop0 && ppc != loop0) it <= it + 1; end
    reg [15:0] retpc = 0; reg [7:0] lw_a = 0, lw_d = 0; reg [63:0] pm [0:511];
    always @(posedge clk) begin if (iox_we) begin n_ow <= n_ow + 1; lw_a <= iox_a; lw_d <= iox_wd; end if (iox_re) n_ir <= n_ir + 1; end
    function [7:0] pb(input [23:0] pa); reg [31:0] q; begin q = mdl.mem[2*(pa>>3) + ((pa>>2)&1)]; pb = q >> (8*(pa&3)); end endfunction
    task wio(input [7:0] ad, input [7:0] d); begin @(posedge clk); #1 io_a = ad; io_wd = d; io_we = 1; @(posedge clk); #1 io_we = 0; end endtask
    task chk(input [255:0] nome, input [63:0] got, input [63:0] exp);
        if (got !== exp) begin errs = errs + 1; $display("ERROR %0s: got %h expected %h", nome, got, exp); end
    endtask
    reg [7:0] by [0:511]; reg [63:0] w; integer p;
    task emit(input [7:0] x); begin by[p] = x; p = p + 1; end endtask
    task ldrr(input [2:0] rr, input [15:0] v); begin emit(8'hED); emit(8'h3B); emit(8'h40 | (rr << 3) | 8'h01); emit(v[7:0]); emit(v[15:8]); end endtask
    task mtcr(input [4:0] n); begin emit(8'hED); emit(8'h0C); emit(n); end endtask
    task mfcr(input [4:0] n); begin emit(8'hED); emit(8'h0A); emit(n); end endtask
    function [63:0] rf(input integer n); rf = dut.u_sys.u_cpu.u_core.u_rf1.mem_a[n]; endfunction
    always @(posedge clk) begin if (i_fault) nfi <= nfi + 1; if (d_fault) nfd <= nfd + 1; end
    wire [63:0] r43 = dut.u_sys.u_cpu.u_core.u_rf1.mem_a[43], r44 = dut.u_sys.u_cpu.u_core.u_rf1.mem_a[44], r45 = dut.u_sys.u_cpu.u_core.u_rf1.mem_a[45];

    // stall accounting (core front-end)
    integer c_starve = 0, c_dec = 0, c_hold = 0, c_issue = 0, c_ireq = 0, c_dreq = 0, nfetch = 0;
    wire cv_dv = dut.u_sys.u_cpu.u_core.dv, cv_wq = dut.u_sys.u_cpu.u_core.wq_v, cv_hold = dut.u_sys.u_cpu.u_core.hold, cv_issue = dut.u_sys.u_cpu.u_core.issue;
    wire [5:0] cv_q = dut.u_sys.u_cpu.u_core.qcnt;
    reg meas = 0;
    wire c_i_req_w = dut.c_i_req, c_i_ack_w = dut.c_i_ack;
    always @(posedge clk) if (meas) begin
        if (!cv_dv && !cv_wq && cv_q < 13) c_starve <= c_starve + 1;
        if (cv_dv && !cv_issue && !cv_hold) c_dec <= c_dec + 1;
        if (cv_hold) c_hold <= c_hold + 1;
        if (cv_issue) c_issue <= c_issue + 1;
        if (c_i_req_w) c_ireq <= c_ireq + 1;
        if (c_i_req_w && c_i_ack_w) nfetch <= nfetch + 1;
    end
    integer kind = 0, NI = 0, sub = 0;
    task body1; begin
        case (kind)
        0: begin emit(8'h00); NI = NI + 1; end                                   // NOP
        1: begin emit(8'h78); NI = NI + 1; end                                   // LD A,B
        2: begin emit(8'hED); emit(8'h3E); emit(8'hA0); NI = NI + 1; end         // ADDQ HL,BC
        3: begin emit(8'hED); emit(8'h39); emit(8'h22); NI = NI + 1; end         // LDQ HL,(DE)
        4: begin emit(8'hED); emit(8'h39); emit(8'h41); emit(8'h11); emit(8'h22); emit(8'h33); emit(8'h44); emit(8'h55); emit(8'h66); emit(8'h77); emit(8'h88); NI = NI + 1; end // LDQ BC,imm64
        5: begin emit(8'hED); emit(8'h39); emit(8'hC4); NI = NI + 1; end         // LDQ (BC),HL... (store: 11 rr rr' -> (BC)=HL? see table)
        6: begin emit(8'hC5); emit(8'hD1); NI = NI + 2; end                      // PUSH BC ; POP DE
        7: begin emit(8'h09); NI = NI + 1; end                                   // ADD HL,BC
        8: begin emit(8'hED); emit(8'h35); emit(8'h00); emit(8'h00); emit(8'h00); emit(8'h00); NI = NI + 2; end   // CALLL sub (patched) + RETL in sub
        9: begin emit(8'hCD); emit(8'h00); emit(8'h00); NI = NI + 2; end         // CALL sub (patched) + RET in sub
        endcase
    end endtask
    initial begin
        if (!$value$plusargs("k=%d", kind)) kind = 2;
        for (k = 0; k < 512; k = k + 1) by[k] = 8'h00; p = 0;
        ldrr(7, 16'h00A5); emit(8'hD3); emit(8'h3D); ldrr(7, 16'h0001); emit(8'hD3); emit(8'h3E);   // NATIVE mode
        for (k = 0; k < 16; k = k + 1) emit(8'h00);
        emit(8'h31); emit(8'h00); emit(8'h30);        // LD SP,3000h
        ldrr(2, 16'h0100); ldrr(0, 16'h0110);         // DE = 0100h, BC = 0110h (data addresses)
        while (p % 8) emit(8'h00);
        loop0 = p; NI = 0;
        for (j = 0; j < ((kind == 4) ? 8 : 16); j = j + 1) body1;
        emit(8'h18); emit(8'h00); by[p-1] = loop0 - p; NI = NI + 1;   // JR loop0
        sub = p;
        if (kind == 8) begin emit(8'hED); emit(8'h04); end else begin emit(8'hC9); end   // RETL / RET
        for (k = loop0; k < sub - 2; k = k + 1) begin
            if (kind == 8 && by[k] == 8'hED && by[k+1] == 8'h35) begin by[k+2] = sub[7:0]; by[k+3] = sub[15:8]; end
            if (kind == 9 && by[k] == 8'hCD) begin by[k+1] = sub[7:0]; by[k+2] = sub[15:8]; end
        end
        for (k = 0; k < 64; k = k + 1) begin
            w = {by[8*k+7], by[8*k+6], by[8*k+5], by[8*k+4], by[8*k+3], by[8*k+2], by[8*k+1], by[8*k]};
            mdl.mem[2*k] = w[31:0]; mdl.mem[2*k + 1] = w[63:32];
        end
        repeat (4) @(posedge clk); rst = 0;
        wait (init_done);
        repeat (20000) @(posedge clk); it0 = it; c0 = cyc; meas = 1; repeat (40000) @(posedge clk); meas = 0; it = it - it0; cyc = cyc - c0;
        $display("kind=%0d native=%b  instr/iter=%0d  iter=%0d  cycles=%0d  CPI=%0.2f", kind, nat, NI, it, cyc, 1.0*cyc/(it*NI));
        $display("  per instr: starve(fetch)=%0.2f decode=%0.2f hold=%0.2f issue=%0.2f | fetches/instr=%0.2f clocks/fetch=%0.2f",
                 1.0*c_starve/(it*NI), 1.0*c_dec/(it*NI), 1.0*c_hold/(it*NI), 1.0*c_issue/(it*NI), 1.0*nfetch/(it*NI), 1.0*c_ireq/(nfetch>0?nfetch:1));
        if (kind == 4) begin $display("  pc=%h loop0=%h qcnt=%0d dv=%b ds=%0d BC=%h", dbg_pc, loop0, cv_q, cv_dv, dut.u_sys.u_cpu.u_core.ds, rf(1)); end
        $finish;
    end
endmodule
