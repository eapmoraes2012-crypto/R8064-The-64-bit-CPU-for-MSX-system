`timescale 1ns/1ps
// SoC completo: programa de sequencias (LD SP/PUSH/POP/CALL/RET/OUT/IN) executado a partir da SDRAM (modelo com verificacao de protocolo) atraves de MMU (bypass) + caches + arbitros.
module tb_soc;
    reg clk = 0, rst = 1; always #5 clk = ~clk;
    reg io_we = 0, io_re = 0; reg [7:0] io_a = 0, io_wd = 0; wire [7:0] io_rd; wire io_oe, iox_we, iox_re; wire [7:0] iox_a, iox_wd;
    wire nat, csel, z80, rom, mbusy, cv, dbg_sig, init_done, fifo_irq, fifo_rst, fbi, fbd, i_fault, d_fault; wire [2:0] ic, dc; wire [63:0] dbg_pc; wire [7:0] dbg_f, fm_rd;
    wire s_cke, s_cs_n, s_ras_n, s_cas_n, s_we_n, s_dq_oe; wire [3:0] s_dqm; wire [1:0] s_ba; wire [10:0] s_a; wire [31:0] s_dq_o, mdq;
    reg [31:0] dq_in; always @* dq_in = mdq;
    r8064_soc #(.INIT_CYC(2000)) dut(.clk(clk), .rst(rst), .irq(1'b1),
        .io_we(io_we), .io_re(io_re), .io_a(io_a), .io_wd(io_wd), .io_rd(io_rd), .io_oe(io_oe), .io_x_we(iox_we), .io_x_re(iox_re), .io_x_a(iox_a), .io_x_wd(iox_wd), .io_x_rd(8'h5A), .port_c(8'd0),
        .fm_we(1'b0), .fm_re(1'b0), .fm_a(2'd0), .fm_wd(8'd0), .fm_rd(fm_rd), .fifo_irq(fifo_irq), .fifo_rst(fifo_rst),
        .native64(nat), .clk_sel(csel), .is_z80(z80), .is_rom(rom), .mode_busy(mbusy), .dbg_pc(dbg_pc), .dbg_f(dbg_f), .dbg_sig(dbg_sig), .gov_cv(cv),
        .fl_busy_i(fbi), .fl_busy_d(fbd), .mmu_en(), .mmu_user(),
        .i_fault(i_fault), .d_fault(d_fault), .i_cause(ic), .d_cause(dc),
        .init_done(init_done), .s_cke(s_cke), .s_cs_n(s_cs_n), .s_ras_n(s_ras_n), .s_cas_n(s_cas_n), .s_we_n(s_we_n), .s_dqm(s_dqm), .s_ba(s_ba), .s_a(s_a),
        .s_dq_o(s_dq_o), .s_dq_oe(s_dq_oe), .s_dq_i(dq_in));
    sdram_model mdl(.clk(clk), .cke(s_cke), .cs_n(s_cs_n), .ras_n(s_ras_n), .cas_n(s_cas_n), .we_n(s_we_n), .dqm(s_dqm), .ba(s_ba), .a(s_a), .dq_i(s_dq_o), .dq_oe(s_dq_oe), .dq_o(mdq));
    integer nwi = 0, nwd = 0; always @(posedge clk) begin if (dut.u_mem.iw_accept) nwi <= nwi + 1; if (dut.u_mem.dw_accept) nwd <= nwd + 1; end
    integer errs = 0, k, n_ow = 0, n_ir = 0; reg [7:0] lw_a = 0, lw_d = 0; reg [63:0] pm [0:511];
    always @(posedge clk) begin if (iox_we) begin n_ow <= n_ow + 1; lw_a <= iox_a; lw_d <= iox_wd; end if (iox_re) n_ir <= n_ir + 1; end
    task wio(input [7:0] ad, input [7:0] d); begin @(posedge clk); #1 io_a = ad; io_wd = d; io_we = 1; @(posedge clk); #1 io_we = 0; end endtask
    task chk(input [255:0] nome, input [63:0] got, input [63:0] exp);
        if (got !== exp) begin errs = errs + 1; $display("ERRO %0s: obtido %h esperado %h", nome, got, exp); end
    endtask
    reg [63:0] w;
    initial begin
        $readmemh("prog_seq.mem", pm);
        // o nucleo comeca a buscar em 0000h antes de o mapeador ser programado: o mesmo programa tambem e carregado no fisico 0000h
        // pre-carga: endereco fisico 4000h + 8k -> palavra de 64 bits 800h+k -> modelo[2*(800h+k)] (baixa) e [+1] (alta)
        for (k = 0; k < 512; k = k + 1) begin mdl.mem[2*k] = pm[k][31:0]; mdl.mem[2*k + 1] = pm[k][63:32]; mdl.mem[2*(16'h0800 + k)] = pm[k][31:0]; mdl.mem[2*(16'h0800 + k) + 1] = pm[k][63:32]; end
        if (0) begin
            // tabelas Sv39 na SDRAM (PA 100000h, 101000h, 102000h): VA 0000h-0FFFh -> PA 0000h e VA 4000h-4FFFh -> PA 4000h (folhas V R W X A D = CFh)
            mdl.mem[2*(24'h100000>>3)] = 32'h00040401; mdl.mem[2*(24'h101000>>3)] = 32'h00040801;
            mdl.mem[2*(24'h102000>>3)] = 32'h000000CF; mdl.mem[2*((24'h102000>>3)+4)] = 32'h000010CF;
        end
        repeat (4) @(posedge clk); rst = 0;
        wait (init_done);
        wio(8'hA8, 8'hFF); wio(8'hFC, 8'h01);
        repeat (300000) @(posedge clk);
        chk("BC", dut.u_sys.u_cpu.u_core.u_rf1.mem_a[1], 64'h33); chk("DE", dut.u_sys.u_cpu.u_core.u_rf1.mem_a[2], 64'h22);
        chk("HL", dut.u_sys.u_cpu.u_core.u_rf1.mem_a[3], 64'h22); chk("AX", dut.u_sys.u_cpu.u_core.u_rf1.mem_a[0], 64'h5A);
        chk("SP", dut.u_sys.u_cpu.u_core.u_rf1.mem_a[11], 64'h0F00);
        w = {mdl.mem[2*(16'h4EFE>>3) + 1], mdl.mem[2*(16'h4EFE>>3)]};
        chk("pilha na SDRAM: retorno (byte 6..7 da palavra)", w[63:48], 64'h0008);
        chk("OUT porta 77h", lw_a, 64'h77); chk("OUT dado", lw_d, 64'h41); chk("1 OUT externo", n_ow, 1); chk("1 IN externo", n_ir, 1);
        chk("sem falta I", i_fault, 0); chk("sem falta D", d_fault, 0);
        if ($test$plusargs("mmu")) $display("leituras de tabela de paginas: MMU-I=%0d MMU-D=%0d", nwi, nwd);
        $display("violacoes SDRAM=%0d | dbg_pc=%h | modo z80=%0d rom=%0d", mdl.viol, dbg_pc, z80, rom);
        if (errs == 0) $display("RESULTADO: SOC OK"); else $display("RESULTADO: %0d ERROS", errs);
        $finish;
    end
endmodule
