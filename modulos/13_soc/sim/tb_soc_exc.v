`timescale 1ns/1ps
// Scenarios 1-8: MMU faults as an exception. Scenarios 9-12 (MODELO_PRIVILEGIO.txt): 9 user mode with MMU (SCALL + SYSRT, privileged instruction), 10 interrupt in user mode
// usuario, 11 PROT 1 + RESET, 12 STDBY acordado por interrupcao.
// Full SoC: sequence program (LD SP/PUSH/POP/CALL/RET/OUT/IN) executed from the SDRAM (model with protocol checking) through MMU (bypass) + caches + arbiters.
module tb_soc_exc;
    wire mmu_en_w, mmu_user_w; integer sc = 1; integer nfi = 0, nfd = 0; reg clk = 0, rst = 1; always #5 clk = ~clk;
    reg io_we = 0, io_re = 0; reg [7:0] io_a = 0, io_wd = 0; wire [7:0] io_rd; wire io_oe, iox_we, iox_re; wire [7:0] iox_a, iox_wd;
    wire nat, csel, z80, rom, mbusy, cv, dbg_sig, init_done, fifo_irq, fifo_rst, fbi, fbd, i_fault, d_fault; wire [2:0] ic, dc; wire [63:0] dbg_pc; wire [7:0] dbg_f, fm_rd;
    wire s_cke, s_cs_n, s_ras_n, s_cas_n, s_we_n, s_dq_oe; wire [3:0] s_dqm; wire [1:0] s_ba; wire [10:0] s_a; wire [31:0] s_dq_o, mdq;
    reg [31:0] dq_in; always @* dq_in = mdq; reg irq_r = 1; integer nfall = 0; reg men_q = 0; always @(posedge clk) begin men_q <= mmu_en_w; if (men_q && !mmu_en_w) nfall <= nfall + 1; end
    reg [7:0] ub [0:63]; integer up; reg [63:0] de_antes = 0;
    task uemit(input [7:0] x); begin ub[up] = x; up = up + 1; end endtask
    r8064_soc #(.INIT_CYC(2000)) dut(.clk(clk), .rst(rst), .irq(irq_r),
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
        ldrr(7, 16'h0100); mtcr(5'd15); ldrr(7, 16'h0001); mtcr(5'd14);      // raiz = PPN 100h; MMU ligada
        for (k = 0; k < 64; k = k + 1) ub[k] = 8'h00; up = 0;
        if (sc == 9) begin                                                           // user mode with MMU: user code on page 4000h (PTE with U)
            ldrr(4, 16'h4000); emit(8'hED); emit(8'hB6); emit(8'h18); emit(8'hFE);         // HL=4000 ; JP USER,(HL)
            p = 16'h40; mfcr(5'd11); emit(8'hFE); emit(8'h05); emit(8'h20); emit(8'h02); emit(8'hED); emit(8'hA4);   // handler: AX=cause ; CP 5 ; JR NZ,+2 ; SYSRT (SCALL: returns to user)
            mfcr(5'd12); emit(8'hED); emit(8'h3B); emit(8'h67); mfcr(5'd18); emit(8'h18); emit(8'hFE);               // other cause: HL=CR12 ; AX=CR18 ; loop
            uemit(8'hED); uemit(8'h3B); uemit(8'h41); uemit(8'h34); uemit(8'h12);          // 4000: LDW BC,1234
            uemit(8'hED); uemit(8'h22); uemit(8'h77);                                      // 4005: SCALL 77h
            uemit(8'hED); uemit(8'h3B); uemit(8'h51); uemit(8'hAA); uemit(8'hAA);          // 4008: LDW DE,AAAA
            uemit(8'hF3); uemit(8'h18); uemit(8'hFE);                                      // 400D: DI (privileged in user mode) ; loop
        end else if (sc == 10) begin                                                 // interrupcao em modo usuario
            ldrr(7, 16'h0001); mtcr(5'd10); ldrr(4, 16'h4000); emit(8'hED); emit(8'hB6); emit(8'h18); emit(8'hFE);   // IE=1 ; JP USER,(HL)
            p = 16'h40; mfcr(5'd18); emit(8'h18); emit(8'hFE);                             // handler: AX=CR18 ; loop
            uemit(8'h03); uemit(8'h18); uemit(8'hFD);                                      // 4000: INC BC ; JR 4000
        end else if (sc == 11) begin                                                 // PROT 1 turns the MMU on; RESET turns everything off and restarts at 0
            p = 0; ldrr(7, 16'h0100); mtcr(5'd15); emit(8'hED); emit(8'h01);               // raiz ; PROT 1
            mfcr(5'd5); emit(8'hB7); emit(8'h20); emit(8'h0C);                             // AX=CR5 ; OR A ; JR NZ,segunda passada
            ldrr(7, 16'h0001); mtcr(5'd5); emit(8'hED); emit(8'h25); emit(8'h18); emit(8'hFE);   // CR5=1 ; RESET
            ldrr(2, 16'hCCCC); emit(8'h18); emit(8'hFE);                                   // second pass: DE=CCCC ; loop
        end else if (sc == 12) begin                                                 // STDBY waits for the interrupt (legacy IM: jumps to vector 0040h)
            ldrr(7, 16'h0001); mtcr(5'd10); retpc = p; emit(8'hED); emit(8'h24); ldrr(2, 16'hDDDD); emit(8'h18); emit(8'hFE);
            p = 16'h40; ldrr(2, 16'hBBBB); emit(8'h18); emit(8'hFE);
        end else if (sc == 13 || sc == 14) begin                                     // illegal ED (ED 08): with TE=1 (CR14 bit 2) cause 7/aux 0; with TE=0 it is executed as NOP
            ldrr(7, (sc == 13) ? 16'h0005 : 16'h0001); mtcr(5'd14); retpc = p; emit(8'hED); emit(8'h08); ldrr(2, 16'hAAAA); emit(8'h18); emit(8'hFE);
            p = 16'h40; mfcr(5'd11); emit(8'h18); emit(8'hFE);
        end else
        if (sc >= 4) begin
            emit(8'h31); emit(8'h00); emit(8'h20);                                   // LD SP,2000h (page 1000h-1FFFh is not mapped: stack at 1FFEh faults)
            if (sc == 4) begin ldrr(0, 16'h1234); retpc = p; emit(8'hC5); emit(8'hD1); end                    // BC=1234 ; PUSH BC (fault) ; POP DE
            if (sc == 5) begin retpc = p; emit(8'hCD); emit(8'h30); emit(8'h00); ldrr(2, 16'hAAAA); end       // CALL 0030h (pushes at 1FFEh: fault) ; DE=AAAA
        if (sc == 6) begin ldrr(4, 16'h0FFE); ldrr(2, 16'h0200); ldrr(0, 16'h0004); retpc = p; emit(8'hED); emit(8'hB0);   // LDIR: HL 0FFE.., the read at 1000h faults on the 3rd byte
                               emit(8'h31); emit(8'h00); emit(8'h02); emit(8'hC1); emit(8'hD1); end                  // LD SP,0200 ; POP BC ; POP DE
            if (sc == 7) begin ldrr(4, 16'h0100); ldrr(2, 16'h0FFE); ldrr(0, 16'h0004); retpc = p; emit(8'hED); emit(8'hB0);   // LDIR: DE 0FFE.., the write at 1000h faults on the 3rd byte
                               emit(8'h31); emit(8'hFE); emit(8'h0F); emit(8'hC1); emit(8'hD1); end                  // LD SP,0FFE ; POP BC ; POP DE
            if (sc == 8) begin emit(8'hED); emit(8'h56); emit(8'hFB); retpc = p; end                                  // IM 1 ; EI ; (the INT pushes the PC at 1FFEh: fault on entry)
            emit(8'h18); emit(8'hFE);
            if (sc == 5) begin p = 16'h30; emit(8'hC9); end                                                           // sub-rotina: RET
            p = 16'h40; mfcr(5'd11);
            if (sc == 8) begin emit(8'hFB); emit(8'h18); emit((retpc - 16'h46) & 8'hFF); end                          // exception handler: EI ; JR EPC (the INT is accepted again at the destination)
            else begin emit(8'h18); emit((retpc - 16'h45) & 8'hFF); end                                               // JR to the instruction that faulted
            if (sc == 8) begin p = 16'h38; ldrr(2, 16'hBBBB); emit(8'hC1); emit(8'h18); emit(8'hFE); end              // INT handler (IM 1, 0038h): DE=BBBB ; POP BC (pushed PC) ; loop
        end else
        if (sc == 3) begin emit(8'h31); emit(8'h00); emit(8'h4F); emit(8'hCD); emit(8'h00); emit(8'h20); end      // LD SP,4F00 ; CALL 2000h (fetch on an unmapped page)
        else begin emit(8'h31); emit(8'h00); emit(8'h20); emit(8'hC1 + (sc == 2 ? 4 : 0)); end            // LD SP,2000 ; POP BC (sc1) | PUSH BC (sc2)
        if (sc < 4) begin ldrr(2, 16'hAAAA); emit(8'h18); emit(8'hFE); end
        // handler at 0040h: AX <- CR11 (cause); sc1: returns to the POP (0013h) by JR; others: stays halted
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
        if (sc >= 9) begin mdl.mem[2*((24'h102000>>3)+4)] = 32'h000010DF; for (k = 0; k < 8; k = k + 1) begin mdl.mem[2*(24'h800+k)] = {ub[8*k+3], ub[8*k+2], ub[8*k+1], ub[8*k]}; mdl.mem[2*(24'h800+k)+1] = {ub[8*k+7], ub[8*k+6], ub[8*k+5], ub[8*k+4]}; end end
        if (sc == 10 || sc == 12) irq_r = 0;
        if (sc == 6) begin mdl.mem[2*(24'hFF8>>3)+1] = 32'h4241_0000; end
        if (sc >= 4) begin mdl.mem[2*(24'h6000>>3)] = 32'h00006463; end
        repeat (4) @(posedge clk); rst = 0;
        wait (init_done);
        // +r800: repeats the scenario under the R800 mode (is_z80=0, is_rom=0) and the R800 timing governor (the default after reset is Z80 in ROM)
        if ($test$plusargs("r800")) begin dut.u_sys.u_cpu.u_mode.r6 = 2'b00; dut.u_sys.u_cpu.u_mode.is_z80 = 1'b0; dut.u_sys.u_cpu.u_mode.is_rom = 1'b0; end
        if (sc == 1) begin wait (d_fault); repeat (2) @(posedge clk); mdl.mem[2*((24'h102000>>3)+2)] = 32'h000014CF; end   // the "OS" maps page 2000h -> PA 5000h
        if (sc == 10) begin wait (mmu_user_w); repeat (300) @(posedge clk); irq_r = 1; end
        if (sc == 12) begin repeat (4000) @(posedge clk); de_antes = rf(2); chk("parado no STDBY", dbg_pc, retpc); irq_r = 1; end
        if (sc >= 4 && sc < 9) begin wait (d_fault); repeat (2) @(posedge clk); mdl.mem[2*((24'h102000>>3)+1)] = 32'h000018CF; end   // the "OS" maps page 1000h -> PA 6000h
        repeat (60000) @(posedge clk);
        $display("scenario %0d: CR43=%h CR44=%h CR45=%h BC=%h DE=%h AX=%h SP=%h faults I=%0d D=%0d pc=%h mmu=%0d", sc, r43, r44, r45,
            dut.u_sys.u_cpu.u_core.u_rf1.mem_a[1], dut.u_sys.u_cpu.u_core.u_rf1.mem_a[2], dut.u_sys.u_cpu.u_core.u_rf1.mem_a[0], dut.u_sys.u_cpu.u_core.u_rf1.mem_a[11], nfi, nfd, dbg_pc, mmu_en_w);
        chk("MMU ligada", mmu_en_w, 1);
        if (sc == 1) begin chk("CR43 cause (read, data, page)", r43, 64'h09); chk("CR44", r44, 64'h2000); chk("CR45 EPC", r45, 64'h13);
            chk("BC after restart", dut.u_sys.u_cpu.u_core.u_rf1.mem_a[1], 64'h1234); chk("SP", dut.u_sys.u_cpu.u_core.u_rf1.mem_a[11], 64'h2002);
            chk("DE follows", dut.u_sys.u_cpu.u_core.u_rf1.mem_a[2], 64'hAAAA); chk("AX=cause (MFCR)", dut.u_sys.u_cpu.u_core.u_rf1.mem_a[0], 64'h09); chk("1 D fault", nfd, 1); end
        if (sc == 2) begin chk("CR43", r43, 64'h19); chk("CR44", r44, 64'h1FFE); chk("CR45", r45, 64'h13); chk("DE not executed", dut.u_sys.u_cpu.u_core.u_rf1.mem_a[2], 64'h0); chk("AX", dut.u_sys.u_cpu.u_core.u_rf1.mem_a[0], 64'h19); end
        if (sc == 3) begin chk("CR43", r43, 64'h01); chk("CR44", r44, 64'h2000); chk("CR45", r45, 64'h2000); chk("DE not executed", dut.u_sys.u_cpu.u_core.u_rf1.mem_a[2], 64'h0); chk("AX", dut.u_sys.u_cpu.u_core.u_rf1.mem_a[0], 64'h01); chk("I fault", nfi >= 1, 1); end
        if (sc == 4) begin chk("BC", rf(1), 64'h1234); chk("DE (POP=PUSH)", rf(2), 64'h1234); chk("SP without double decrement", rf(11), 64'h2000); chk("CR44", r44, 64'h1FFE); chk("CR45 EPC", r45, retpc); chk("1 D fault", nfd, 1); end
        if (sc == 5) begin chk("DE after CALL", rf(2), 64'hAAAA); chk("SP", rf(11), 64'h2000); chk("CR44", r44, 64'h1FFE); chk("CR45 EPC", r45, retpc); chk("1 D fault", nfd, 1); end
        if (sc == 6) begin chk("BC (POP)", rf(1), 64'h4241); chk("DE (POP)", rf(2), 64'h6463); chk("HL", rf(3), 64'h1002); chk("SP", rf(11), 64'h0204); chk("CR44", r44, 64'h1000); chk("CR45 EPC", r45, retpc); chk("1 D fault", nfd, 1); end
        if (sc == 7) begin chk("BC (POP)", rf(1), 64'h4241); chk("DE (POP)", rf(2), 64'h4443); chk("HL", rf(3), 64'h0104); chk("SP", rf(11), 64'h1002); chk("CR44", r44, 64'h1000); chk("CR45 EPC", r45, retpc); chk("1 D fault", nfd, 1); end
        if (sc == 8) begin chk("DE INT handler", rf(2), 64'hBBBB); chk("BC=pushed PC", rf(1) & 64'hFFFF, retpc); chk("SP after POP", rf(11), 64'h2000); chk("CR44", r44, 64'h1FFE); chk("CR45 EPC", r45, retpc); chk("1 D fault", nfd, 1); end
        if (sc == 9) begin chk("BC (user)", rf(1), 64'h1234); chk("DE (user, after SYSRT)", rf(2), 64'hAAAA); chk("CR11 cause", r43, 64'h7); chk("CR12 = privileged", r44, 64'h2); chk("CR13 EPC", r45, 64'h400D);
            chk("HL=CR12", rf(3), 64'h2); chk("AX=CR18 (previous = user)", rf(0), 64'h2); chk("supervisor mode", mmu_user_w, 0); chk("no faults", nfi + nfd, 0); end
        if (sc == 10) begin chk("CR11 cause 0", r43, 64'h0); chk("CR12", r44, 64'h0); chk("EPC in the user loop", (r45 >= 64'h4000 && r45 <= 64'h4003), 1); chk("AX=CR18", rf(0), 64'h2); chk("supervisor mode", mmu_user_w, 0);
            chk("BC counted", rf(1) != 0, 1); chk("IFF1=0", dut.u_sys.u_cpu.u_core.ie, 0); chk("IFF2=1", dut.u_sys.u_cpu.u_core.iff2, 1); chk("no faults", nfi + nfd, 0); end
        if (sc == 11) begin chk("DE second pass", rf(2), 64'hCCCC); chk("RESET turned the MMU off 1 time", nfall, 1); chk("no faults", nfi + nfd, 0); end
        if (sc == 13) begin chk("CR11 cause 7 (illegal)", r43, 64'h7); chk("CR12 aux 0", r44, 64'h0); chk("CR13 EPC = ED 08", r45, retpc); chk("DE not executed", rf(2), 64'h0); chk("AX=cause", rf(0), 64'h7); chk("no faults", nfi + nfd, 0); end
        if (sc == 14) begin chk("TE=0: no exception (CR11)", r43, 64'h0); chk("TE=0: DE executed", rf(2), 64'hAAAA); chk("no faults", nfi + nfd, 0); end
        if (sc == 12) begin chk("DE before the INT", de_antes, 64'h0); chk("DE handler", rf(2), 64'hBBBB); end
        $display("violacoes SDRAM=%0d", mdl.viol);
        if (errs == 0) $display("RESULT: SOC EXCEPTIONS OK"); else $display("RESULT: %0d ERRORS", errs);
        $finish;
    end
endmodule
