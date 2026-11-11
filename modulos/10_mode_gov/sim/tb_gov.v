`timescale 1ns/1ps
module tb_gov;
    reg clk = 0, rst = 1; always #5 clk = ~clk;
    reg native64 = 0, is_z80 = 1, is_rom = 0, clk_sel = 0;
    reg [2:0] pg = 0; reg [7:0] op = 0, prt = 0; reg [3:0] xc = 0; reg cv = 0, alt = 0;
    wire go; wire [12:0] rem; wire ph; reg romw = 1, aev = 0; reg [4:0] an = 0; integer add_at = 0;
    timing_gov dut(.clk(clk), .rst(rst), .native64(native64), .is_z80(is_z80), .is_rom(is_rom), .clk_sel(clk_sel), .c_page(pg), .c_op(op), .c_port(prt),
        .c_xcyc(xc), .c_romw(romw), .add_ev(aev), .add_n(an), .phase(ph), .cv(cv), .alt_ev(alt), .go(go), .dbg_rem(rem));
    integer errs = 0, t, sp; integer tc = 0, tc1;
    // emite uma instrucao e mede o espaco (em clocks) ate o proximo go; alt_at > 0: gera alt_ev nesse clock apos o commit
    task issue(input [2:0] p, input [7:0] o, input [7:0] port, input integer alt_at, output integer spacing);
        integer k;
        begin
            pg = p; op = o; prt = port; repeat (6) @(posedge clk);
            while (!go) @(posedge clk);
            tc = $time/10; cv = 1; @(posedge clk); cv = 0; pg = 0; op = 0; k = 0;           // commit neste clock
            #1;
            while (!go) begin
                k = k + 1; if (k == alt_at) alt = 1; if (k == add_at) aev = 1; @(posedge clk); #1; alt = 0; aev = 0;
            end
            spacing = k + 1;
        end
    endtask
    task expect_sp(input [255:0] nome, input integer got, input integer exp);
        if (got !== exp) begin errs = errs + 1; $display("ERRO %0s: obtido %0d esperado %0d", nome, got, exp); end
        else $display("ok   %0s = %0d clocks", nome, got);
    endtask
    task expect_rng(input [255:0] nome, input integer got, input integer lo, input integer hi);
        if (got < lo || got > hi) begin errs = errs + 1; $display("ERRO %0s: obtido %0d esperado %0d..%0d", nome, got, lo, hi); end
        else $display("ok   %0s = %0d clocks", nome, got);
    endtask
    integer c, longs, last;
    initial begin
        repeat (4) @(posedge clk); rst = 0;
        // ---- Z80 (qualquer ROM/DRAM) clock A ----
        is_z80 = 1; is_rom = 1; clk_sel = 0; repeat (3) @(posedge clk);
        issue(0, 8'h00, 0, 0, sp); expect_sp("Z80 NOP (4T+1 wait)", sp, 5*32);
        issue(0, 8'h3A, 0, 0, sp); expect_sp("Z80 LD A,(nn) (13T+1)", sp, 14*32);
        issue(2, 8'h44, 0, 0, sp); expect_sp("Z80 NEG ED 44 (8T+2)", sp, 10*32);
        issue(0, 8'h20, 0, 0, sp); expect_sp("Z80 JR NZ tomado (12T+1)", sp, 13*32);
        issue(0, 8'h20, 0, 3, sp); expect_sp("Z80 JR NZ nao tomado (7T+1)", sp, 8*32);
        issue(0, 8'hD3, 8'h98, 0, sp); expect_sp("Z80 OUT (98H),A (11T+1)", sp, 12*32);
        issue(0, 8'hD3, 8'h98, 0, sp); expect_sp("Z80 OUT (98H),A 2x: sem pausa de VDP", sp, 12*32);
        // ---- Z80 clock B ----
        clk_sel = 1; repeat (3) @(posedge clk);
        issue(0, 8'h00, 0, 0, sp); expect_sp("Z80 NOP clock B", sp, 5*24);
        // ---- R800 DRAM clock A ----
        is_z80 = 0; is_rom = 0; clk_sel = 0; repeat (3) @(posedge clk);
        issue(0, 8'h00, 0, 0, sp); expect_sp("R800 DRAM NOP", sp, 1*16);
        issue(0, 8'h3A, 0, 0, sp); expect_sp("R800 DRAM LD A,(nn)", sp, 6*16);
        issue(0, 8'hCD, 0, 0, sp); expect_sp("R800 DRAM CALL nn", sp, 8*16);
        issue(2, 8'hC1, 0, 0, sp); expect_sp("R800 DRAM MULUB A,B", sp, 14*16);
        issue(2, 8'hC3, 0, 0, sp); expect_sp("R800 DRAM MULUW HL,BC", sp, 36*16);
        xc = 1; issue(0, 8'h00, 0, 0, sp); xc = 0; expect_sp("R800 DRAM NOP + 1 quebra de pagina", sp, 2*16);
        issue(0, 8'h20, 0, 2, sp); expect_sp("R800 DRAM JR NZ nao tomado", sp, 2*16);
        // ---- evento tardio de dados e busca fora de ROM ----
        an = 4; add_at = 3; issue(0, 8'h00, 0, 0, sp); add_at = 0; expect_sp("R800 DRAM NOP + acesso externo (+4 ciclos)", sp, 16 + 4*16);
        an = 6; add_at = 3; issue(0, 8'h00, 0, 0, sp); add_at = 0; expect_sp("R800 DRAM NOP + 6 ciclos tardios", sp, 16 + 6*16);
        // ---- R800 ROM ----
        is_rom = 1; repeat (3) @(posedge clk);
        issue(0, 8'h00, 0, 0, sp); expect_sp("R800 ROM NOP (1+3)", sp, 4*16);
        issue(0, 8'h3A, 0, 0, sp); expect_sp("R800 ROM LD A,(nn) (6+3)", sp, 9*16);
        romw = 0; issue(0, 8'h00, 0, 0, sp); romw = 1; expect_sp("R800 ROM NOP com busca em RAM (sem WAIT_ROM)", sp, 1*16);
        is_rom = 0;
        // ---- R800: pausa de 8 us nas portas do VDP (reset para zerar refresh e historico) ----
        rst = 1; repeat (2) @(posedge clk); rst = 0; repeat (6) @(posedge clk);
        issue(0, 8'hD3, 8'h98, 0, sp); tc1 = tc; expect_sp("R800 OUT (98H),A 1o acesso", sp, 10*16);
        issue(0, 8'hD3, 8'h99, 0, sp); expect_rng("VDP 2o acesso (99H): commit >= 917 clocks (8us) apos o 1o", tc - tc1, 917, 921); tc1 = tc;
        issue(0, 8'hD3, 8'h40, 0, sp); expect_rng("R800 OUT (40H),A nao e VDP: sem pausa extra", tc - tc1, 160, 168);
        // clock B: 8us = 688 clocks
        clk_sel = 1; rst = 1; repeat (2) @(posedge clk); rst = 0; repeat (6) @(posedge clk);
        issue(0, 8'hD3, 8'h9A, 0, sp); tc1 = tc; issue(0, 8'hD3, 8'h9B, 0, sp);
        expect_rng("VDP clock B (9AH->9BH) >= 688 clocks", tc - tc1, 688, 692); clk_sel = 0;
        // ---- refresh R800: NOPs seguidos por ~20000 clocks ----
        rst = 1; repeat (2) @(posedge clk); rst = 0; repeat (3) @(posedge clk);
        longs = 0; t = $time/10;
        while ($time/10 - t < 20000) begin issue(0, 8'h00, 0, 0, sp); if (sp > 300) longs = longs + 1; end
        if (longs < 4 || longs > 6) begin errs = errs + 1; $display("ERRO refresh R800: %0d paradas em 20000 clocks (esperado ~5)", longs); end
        else $display("ok   refresh R800: %0d paradas de ~400 clocks em 20000 clocks", longs);
        // Z80: sem refresh
        is_z80 = 1; repeat (3) @(posedge clk); longs = 0; t = $time/10;
        while ($time/10 - t < 20000) begin issue(0, 8'h00, 0, 0, sp); if (sp > 300) longs = longs + 1; end
        if (longs != 0) begin errs = errs + 1; $display("ERRO Z80 teve %0d paradas", longs); end else $display("ok   Z80: sem parada de refresh");
        // ---- nativo: sem governador ----
        native64 = 1; repeat (3) @(posedge clk);
        if (!go) begin errs = errs + 1; $display("ERRO nativo: go=0"); end else $display("ok   nativo: go=1 sempre");
        $display("RESULTADO: %0s", errs == 0 ? "GOVERNADOR OK" : "ERROS");
        $display("erros=%0d", errs); $finish;
    end
endmodule
