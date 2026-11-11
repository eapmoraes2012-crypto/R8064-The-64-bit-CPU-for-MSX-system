`timescale 1ns/1ps
// SoC completo: programa de sequencias (LD SP/PUSH/POP/CALL/RET/OUT/IN) executado a partir da SDRAM (modelo com verificacao de protocolo) atraves de MMU (bypass) + caches + arbitros.
module tb_soc_exc;
    wire mmu_en_w, mmu_user_w; integer sc = 1; integer nfi = 0, nfd = 0; reg clk = 0, rst = 1; always #5 clk = ~clk;
    reg io_we = 0, io_re = 0; reg [7:0] io_a = 0, io_wd = 0; wire [7:0] io_rd; wire io_oe, iox_we, iox_re; wire [7:0] iox_a, iox_wd;
    wire nat, csel, z80, rom, mbusy, cv, dbg_sig, init_done, fifo_irq, fifo_rst, fbi, fbd, i_fault, d_fault; wire [2:0] ic, dc; wire [63:0] dbg_pc; wire [7:0] dbg_f, fm_rd;
    wire s_cke, s_cs_n, s_ras_n, s_cas_n, s_we_n, s_dq_oe; wire [3:0] s_dqm; wire [1:0] s_ba; wire [10:0] s_a; wire [31:0] s_dq_o, mdq;
    reg [31:0] dq_in; always @* dq_in = mdq;
    r8064_soc #(.INIT_CYC(2000)) dut(.clk(clk), .rst(rst), .irq(1'b1),
        .io_we(io_we), .io_re(io_re), .io_a(io_a), .io_wd(io_wd), .io_rd(io_rd), .io_oe(io_oe), .io_x_we(iox_we), .io_x_re(iox_re), .io_x_a(iox_a), .io_x_wd(iox_wd), .io_x_rd(8'h5A), .port_c(8'd0),
        .fm_we(1'b0), .fm_re(1'b0), .fm_a(2'd0), .fm_wd(8'd0), .fm_rd(fm_rd), .fifo_irq(fifo_irq), .fifo_rst(fifo_rst),
        .native64(nat), .clk_sel(csel), .is_z80(z80), .is_rom(rom), .mode_busy(mbusy), .dbg_pc(dbg_pc), .dbg_f(dbg_f), .dbg_sig(dbg_sig), .gov_cv(cv),
        .fl_busy_i(fbi), .fl_busy_d(fbd), .mmu_en(mmu_en_w), .mmu_user(mmu_user_w),
        .i_fault(i_fault), .d_fault(d_fault), .i_cause(ic), .d_cause(dc),
        .init_done(init_done), .s_cke(s_cke), .s_cs_n(s_cs_n), .s_ras_n(s_ras_n), .s_cas_n(s_cas_n), .s_we_n(s_we_n), .s_dqm(s_dqm), .s_ba(s_ba), .s_a(s_a),
        .s_dq_o(s_dq_o), .s_dq_oe(s_dq_oe), .s_dq_i(dq_in));
    sdram_model mdl(.clk(clk), .cke(s_cke), .cs_n(s_cs_n), .ras_n(s_ras_n), .cas_n(s_cas_n), .we_n(s_we_n), .dqm(s_dqm), .ba(s_ba), .a(s_a), .dq_i(s_dq_o), .dq_oe(s_dq_oe), .dq_o(mdq));
    integer nwi = 0, nwd = 0; always @(posedge clk) begin if (dut.u_mem.iw_accept) nwi <= nwi + 1; if (dut.u_mem.dw_accept) nwd <= nwd + 1; end
    integer errs = 0, k, n_ow = 0, n_ir = 0; reg [15:0] retpc = 0; reg [7:0] lw_a = 0, lw_d = 0; reg [63:0] pm [0:511];
    always @(posedge clk) begin if (iox_we) begin n_ow <= n_ow + 1; lw_a <= iox_a; lw_d <= iox_wd; end if (iox_re) n_ir <= n_ir + 1; end
    task wio(input [7:0] ad, input [7:0] d); begin @(posedge clk); #1 io_a = ad; io_wd = d; io_we = 1; @(posedge clk); #1 io_we = 0; end endtask
    task chk(input [255:0] nome, input [63:0] got, input [63:0] exp);
        if (got !== exp) begin errs = errs + 1; $display("ERRO %0s: obtido %h esperado %h", nome, got, exp); end
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
        ldrr(7, 16'h0100); mtcr(5'd15); ldrr(7, 16'h0001); mtcr(5'd14);      // raiz = PPN 100h; MMU ligada
        if (sc >= 4) begin
            emit(8'h31); emit(8'h00); emit(8'h20);                                   // LD SP,2000h (a pagina 1000h-1FFFh nao esta mapeada: pilha em 1FFEh falta)
            if (sc == 4) begin ldrr(0, 16'h1234); retpc = p; emit(8'hC5); emit(8'hD1); end                    // BC=1234 ; PUSH BC (falta) ; POP DE
            if (sc == 5) begin retpc = p; emit(8'hCD); emit(8'h30); emit(8'h00); ldrr(2, 16'hAAAA); end       // CALL 0030h (empilha em 1FFEh: falta) ; DE=AAAA
            if (sc == 6) begin ldrr(4, 16'h0FFE); ldrr(2, 16'h0200); ldrr(0, 16'h0004); retpc = p; emit(8'hED); emit(8'hB0);   // LDIR: HL 0FFE.., a leitura em 1000h falta no 3o byte
                               emit(8'h31); emit(8'h00); emit(8'h02); emit(8'hC1); emit(8'hD1); end                  // LD SP,0200 ; POP BC ; POP DE
            if (sc == 7) begin ldrr(4, 16'h0100); ldrr(2, 16'h0FFE); ldrr(0, 16'h0004); retpc = p; emit(8'hED); emit(8'hB0);   // LDIR: DE 0FFE.., a escrita em 1000h falta no 3o byte
                               emit(8'h31); emit(8'hFE); emit(8'h0F); emit(8'hC1); emit(8'hD1); end                  // LD SP,0FFE ; POP BC ; POP DE
            if (sc == 8) begin emit(8'hED); emit(8'h56); emit(8'hFB); retpc = p; end                                  // IM 1 ; EI ; (a INT empilha o PC em 1FFEh: falta na entrada)
            emit(8'h18); emit(8'hFE);
            if (sc == 5) begin p = 16'h30; emit(8'hC9); end                                                           // sub-rotina: RET
            p = 16'h40; mfcr(5'd11);
            if (sc == 8) begin emit(8'hFB); emit(8'h18); emit((retpc - 16'h46) & 8'hFF); end                          // tratador de excecao: EI ; JR EPC (a INT volta a ser aceita no destino)
            else begin emit(8'h18); emit((retpc - 16'h45) & 8'hFF); end                                               // JR para a instrucao que faltou
            if (sc == 8) begin p = 16'h38; ldrr(2, 16'hBBBB); emit(8'hC1); emit(8'h18); emit(8'hFE); end              // tratador da INT (IM 1, 0038h): DE=BBBB ; POP BC (PC empilhado) ; laco
        end else
        if (sc == 3) begin emit(8'h31); emit(8'h00); emit(8'h4F); emit(8'hCD); emit(8'h00); emit(8'h20); end      // LD SP,4F00 ; CALL 2000h (busca em pagina nao mapeada)
        else begin emit(8'h31); emit(8'h00); emit(8'h20); emit(8'hC1 + (sc == 2 ? 4 : 0)); end            // LD SP,2000 ; POP BC (sc1) | PUSH BC (sc2)
        if (sc < 4) begin ldrr(2, 16'hAAAA); emit(8'h18); emit(8'hFE); end
        // tratador em 0040h: AX <- CR11 (causa); sc1: volta ao POP (0013h) por JR; demais: fica parado
        if (sc < 4) begin p = 16'h40; mfcr(5'd11);
        if (sc == 1) begin emit(8'h18); emit(8'hCE); end else begin emit(8'h18); emit(8'hFE); end end
        if (sc == 7) begin by[16'h100]=8'h41; by[16'h101]=8'h42; by[16'h102]=8'h43; by[16'h103]=8'h44; end
        for (k = 0; k < 64; k = k + 1) begin
            w = {by[8*k+7], by[8*k+6], by[8*k+5], by[8*k+4], by[8*k+3], by[8*k+2], by[8*k+1], by[8*k]};
            mdl.mem[2*k] = w[31:0]; mdl.mem[2*k + 1] = w[63:32];
        end
        mdl.mem[2*(24'h100000>>3)] = 32'h00040401; mdl.mem[2*(24'h101000>>3)] = 32'h00040801;
        mdl.mem[2*(24'h102000>>3)] = 32'h000000CF; mdl.mem[2*((24'h102000>>3)+4)] = 32'h000010CF;   // VA 0000h e 4000h mapeadas; 1000h-3FFFh invalidas
        mdl.mem[2*(24'h5000>>3)] = 32'h1234;
        if (sc == 6) begin mdl.mem[2*(24'hFF8>>3)+1] = 32'h4241_0000; end
        if (sc >= 4) begin mdl.mem[2*(24'h6000>>3)] = 32'h00006463; end
        repeat (4) @(posedge clk); rst = 0;
        wait (init_done);
        if (sc == 1) begin wait (d_fault); repeat (2) @(posedge clk); mdl.mem[2*((24'h102000>>3)+2)] = 32'h000014CF; end   // o "SO" mapeia a pagina 2000h -> PA 5000h
        if (sc >= 4) begin wait (d_fault); repeat (2) @(posedge clk); mdl.mem[2*((24'h102000>>3)+1)] = 32'h000018CF; end   // o "SO" mapeia a pagina 1000h -> PA 6000h
        repeat (60000) @(posedge clk);
        $display("cenario %0d: CR43=%h CR44=%h CR45=%h BC=%h DE=%h AX=%h SP=%h faltas I=%0d D=%0d pc=%h mmu=%0d", sc, r43, r44, r45,
            dut.u_sys.u_cpu.u_core.u_rf1.mem_a[1], dut.u_sys.u_cpu.u_core.u_rf1.mem_a[2], dut.u_sys.u_cpu.u_core.u_rf1.mem_a[0], dut.u_sys.u_cpu.u_core.u_rf1.mem_a[11], nfi, nfd, dbg_pc, mmu_en_w);
        chk("MMU ligada", mmu_en_w, 1);
        if (sc == 1) begin chk("CR43 causa (leitura, dado, pag.)", r43, 64'h09); chk("CR44", r44, 64'h2000); chk("CR45 EPC", r45, 64'h13);
            chk("BC apos reinicio", dut.u_sys.u_cpu.u_core.u_rf1.mem_a[1], 64'h1234); chk("SP", dut.u_sys.u_cpu.u_core.u_rf1.mem_a[11], 64'h2002);
            chk("DE segue", dut.u_sys.u_cpu.u_core.u_rf1.mem_a[2], 64'hAAAA); chk("AX=causa (MFCR)", dut.u_sys.u_cpu.u_core.u_rf1.mem_a[0], 64'h09); chk("1 falta D", nfd, 1); end
        if (sc == 2) begin chk("CR43", r43, 64'h19); chk("CR44", r44, 64'h1FFE); chk("CR45", r45, 64'h13); chk("DE nao executado", dut.u_sys.u_cpu.u_core.u_rf1.mem_a[2], 64'h0); chk("AX", dut.u_sys.u_cpu.u_core.u_rf1.mem_a[0], 64'h19); end
        if (sc == 3) begin chk("CR43", r43, 64'h01); chk("CR44", r44, 64'h2000); chk("CR45", r45, 64'h2000); chk("DE nao executado", dut.u_sys.u_cpu.u_core.u_rf1.mem_a[2], 64'h0); chk("AX", dut.u_sys.u_cpu.u_core.u_rf1.mem_a[0], 64'h01); chk("falta I", nfi >= 1, 1); end
        if (sc == 4) begin chk("BC", rf(1), 64'h1234); chk("DE (POP=PUSH)", rf(2), 64'h1234); chk("SP sem decr. duplo", rf(11), 64'h2000); chk("CR44", r44, 64'h1FFE); chk("CR45 EPC", r45, retpc); chk("1 falta D", nfd, 1); end
        if (sc == 5) begin chk("DE apos CALL", rf(2), 64'hAAAA); chk("SP", rf(11), 64'h2000); chk("CR44", r44, 64'h1FFE); chk("CR45 EPC", r45, retpc); chk("1 falta D", nfd, 1); end
        if (sc == 6) begin chk("BC (POP)", rf(1), 64'h4241); chk("DE (POP)", rf(2), 64'h6463); chk("HL", rf(3), 64'h1002); chk("SP", rf(11), 64'h0204); chk("CR44", r44, 64'h1000); chk("CR45 EPC", r45, retpc); chk("1 falta D", nfd, 1); end
        if (sc == 7) begin chk("BC (POP)", rf(1), 64'h4241); chk("DE (POP)", rf(2), 64'h4443); chk("HL", rf(3), 64'h0104); chk("SP", rf(11), 64'h1002); chk("CR44", r44, 64'h1000); chk("CR45 EPC", r45, retpc); chk("1 falta D", nfd, 1); end
        if (sc == 8) begin chk("DE tratador INT", rf(2), 64'hBBBB); chk("BC=PC empilhado", rf(1) & 64'hFFFF, retpc); chk("SP apos POP", rf(11), 64'h2000); chk("CR44", r44, 64'h1FFE); chk("CR45 EPC", r45, retpc); chk("1 falta D", nfd, 1); end
        $display("violacoes SDRAM=%0d", mdl.viol);
        if (errs == 0) $display("RESULTADO: EXCECOES SOC OK"); else $display("RESULTADO: %0d ERROS", errs);
        $finish;
    end
endmodule
