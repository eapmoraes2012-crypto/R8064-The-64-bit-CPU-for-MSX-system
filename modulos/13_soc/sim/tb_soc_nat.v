`timescale 1ns/1ps
// Full SoC: sequence program (LD SP/PUSH/POP/CALL/RET/OUT/IN) executed from the SDRAM (model with protocol checking) through MMU (bypass) + caches + arbiters.
module tb_soc_nat;
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
    integer errs = 0, k, n_ow = 0, n_ir = 0; reg [15:0] retpc = 0; reg [7:0] lw_a = 0, lw_d = 0; reg [63:0] pm [0:511];
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
    initial begin
        if (!$value$plusargs("sc=%d", sc)) sc = 1;
        for (k = 0; k < 512; k = k + 1) by[k] = 8'h00; p = 0;
        ldrr(7, 16'h0006); emit(8'hD3); emit(8'hE4); ldrr(7, 16'h0000); emit(8'hD3); emit(8'hE5);   // NATIVE mode
        for (k = 0; k < 16; k = k + 1) emit(8'h00);
        // MMU off. A8h=E8h (page 1,2 = slot 2 MegaRAM; page 3 = slot 3 mapper). Writes by PUSH, reads by POP (the minimal core has no LD (nn),A).
        ldrr(7, 16'h00E8); emit(8'hD3); emit(8'hA8);
        ldrr(7, 16'h0005); emit(8'hD3); emit(8'hFF);                                   // page3 = segment 5
        ldrr(0, 16'h0077); emit(8'h31); emit(8'h02); emit(8'hC0); emit(8'hC5);         // PUSH BC em C000h -> PA 014000h
        ldrr(7, 16'h0006); emit(8'hD3); emit(8'hFF);                                   // page3 = segment 6
        ldrr(0, 16'h0088); emit(8'h31); emit(8'h02); emit(8'hC0); emit(8'hC5);         // -> PA 018000h
        ldrr(7, 16'h0005); emit(8'hD3); emit(8'hFF);                                   // back to segment 5
        emit(8'h31); emit(8'h00); emit(8'hC0); emit(8'hD1);                            // POP DE (le C000h) -> 0077
        emit(8'h31); emit(8'h02); emit(8'h30); emit(8'hD5);                            // PUSH DE at 3000h (page 0, no translation)
        emit(8'hDB); emit(8'h8E);                                                      // IN A,(8Eh): MegaRAM in write mode
        ldrr(0, 16'h0303); emit(8'h31); emit(8'h02); emit(8'h60); emit(8'hC5);         // writes 03 at 6000/6001 -> bank of the 4000h window = 3
        ldrr(0, 16'h9999); emit(8'h31); emit(8'h02); emit(8'h40); emit(8'hC5);         // 99 em 4000h -> PA 406000h
        ldrr(7, 16'h0000); emit(8'hD3); emit(8'h8E);                                   // OUT (8Eh): ASCII8 mode (read-only)
        ldrr(0, 16'hAAAA); emit(8'h31); emit(8'h02); emit(8'h40); emit(8'hC5);         // must be ignored
        emit(8'h31); emit(8'h00); emit(8'h40); emit(8'hD1);                            // POP DE (le 4000h) -> 9999
        emit(8'h31); emit(8'h04); emit(8'h30); emit(8'hD5);                            // PUSH DE em 3002h
        emit(8'h18); emit(8'hFE);
        for (k = 0; k < 64; k = k + 1) begin
            w = {by[8*k+7], by[8*k+6], by[8*k+5], by[8*k+4], by[8*k+3], by[8*k+2], by[8*k+1], by[8*k]};
            mdl.mem[2*k] = w[31:0]; mdl.mem[2*k + 1] = w[63:32];
        end
        repeat (4) @(posedge clk); rst = 0;
        wait (init_done);
        repeat (90000) @(posedge clk);
        chk("pag3 seg5 (PA 014000h)", pb(24'h014000), 8'h77);
        chk("pag3 seg6 (PA 018000h)", pb(24'h018000), 8'h88);
        chk("read via mapper seg5 -> 3000h", pb(24'h003000), 8'h77);
        chk("MegaRAM bank 3 (PA 406000h) = 99h", pb(24'h406000), 8'h99);
        chk("MegaRAM ASCII8: write ignored, read -> 3002h", pb(24'h003002), 8'h99);
        chk("R800 mode (not native)", nat, 0); chk("R800", z80, 0);
        $display("pc=%h a8=%h mreg3=%h breg0=%h z80=%b rom=%b nwd=%0d AX=%h SP=%h BC=%h DE=%h", dbg_pc, dut.u_sys.u_mmd.a8, dut.u_sys.u_mmd.mreg[3], dut.u_sys.u_mmd.breg[0], z80, rom, nwd, rf(0), rf(11), rf(1), rf(2));
        if (errs == 0) $display("RESULT: NATIVE MAPPER+MEGARAM OK"); else $display("RESULT: %0d ERRORS", errs);
        $finish;
    end
endmodule
