`timescale 1ns/1ps
// Teste de msx_mem: duas instancias (R8064 em modo Z80 e Z80 classico) sobre a mesma memoria fisica.
module tb_msx_mem;
    reg clk = 0, rst = 1; always #5 clk = ~clk;
    reg [7:0] pm [0:(1<<22)-1];           // memoria fisica (4 MB) compartilhada
    integer err = 0, k;
    // nucleo A
    reg ioa_wr = 0, ioa_rd = 0; reg [7:0] ioa_a = 0, ioa_d = 0; wire [7:0] ioa_q; wire ioa_hit;
    reg ma_rd = 0, ma_wr = 0; reg [15:0] ma_a = 0; reg [7:0] ma_d = 0; wire a_hit, a_wok; wire [23:0] a_pa;
    msx_mem ua(.clk(clk), .rst(rst), .en(1'b1), .io_wr(ioa_wr), .io_rd(ioa_rd), .io_addr(ioa_a), .io_wdata(ioa_d), .io_rdata(ioa_q), .io_hit(ioa_hit),
               .mem_rd(ma_rd), .mem_wr(ma_wr), .mem_addr(ma_a), .mem_wdata(ma_d), .hit(a_hit), .phys_addr(a_pa), .wr_ok(a_wok));
    // nucleo B
    reg iob_wr = 0, iob_rd = 0; reg [7:0] iob_a = 0, iob_d = 0; wire [7:0] iob_q; wire iob_hit;
    reg mb_rd = 0, mb_wr = 0; reg [15:0] mb_a = 0; reg [7:0] mb_d = 0; wire b_hit, b_wok; wire [23:0] b_pa;
    msx_mem ub(.clk(clk), .rst(rst), .en(1'b1), .io_wr(iob_wr), .io_rd(iob_rd), .io_addr(iob_a), .io_wdata(iob_d), .io_rdata(iob_q), .io_hit(iob_hit),
               .mem_rd(mb_rd), .mem_wr(mb_wr), .mem_addr(mb_a), .mem_wdata(mb_d), .hit(b_hit), .phys_addr(b_pa), .wr_ok(b_wok));
    task ck(input c, input [255:0] msg); begin if (!c) begin err = err + 1; $display("ERRO: %0s", msg); end end endtask
    task out_a(input [7:0] p, input [7:0] v); begin @(negedge clk); ioa_a = p; ioa_d = v; ioa_wr = 1; @(negedge clk); ioa_wr = 0; end endtask
    task in_a(input [7:0] p); begin @(negedge clk); ioa_a = p; ioa_rd = 1; #1; @(negedge clk); ioa_rd = 0; end endtask
    task wr_a(input [15:0] a, input [7:0] v); begin @(negedge clk); ma_a = a; ma_d = v; ma_wr = 1; #1;
        if (a_hit && a_wok) pm[a_pa] = v;
        @(negedge clk); ma_wr = 0; end endtask
    task rd_a(input [15:0] a, output [7:0] v); begin @(negedge clk); ma_a = a; ma_rd = 1; #1; v = a_hit ? pm[a_pa] : 8'hFF; @(negedge clk); ma_rd = 0; end endtask
    reg [7:0] v;
    initial begin
        for (k = 0; k < (1<<22); k = k + 1) pm[k] = 8'h00;
        repeat (3) @(negedge clk); rst = 0;
        // --- mapper: slot 3 em todas as paginas (A8=FF)
        out_a(8'hA8, 8'hFF);
        // reset: pagina0->seg3, pagina3->seg0
        @(negedge clk); ma_a = 16'h0000; #1; ck(a_hit && a_pa == 24'h00C000, "reset pg0->seg3");
        ma_a = 16'hC123; #1; ck(a_hit && a_pa == 24'h000123, "reset pg3->seg0");
        // portas FC..FF
        out_a(8'hFC, 8'd10); out_a(8'hFD, 8'd11); out_a(8'hFE, 8'd12); out_a(8'hFF, 8'd13);
        @(negedge clk); ma_a = 16'h3FFF; #1; ck(a_pa == 24'h0 + (10*16384 + 16'h3FFF), "FC pag0");
        ma_a = 16'h4000; #1; ck(a_pa == 11*16384, "FD pag1");
        ma_a = 16'h8001; #1; ck(a_pa == 12*16384 + 1, "FE pag2");
        ma_a = 16'hFFFF; #1; ck(a_pa == 13*16384 + 16'h3FFF, "FF pag3");
        // leitura das portas (bits acima de MAP_BITS=6 em 1)
        in_a(8'hFD); ck(ioa_hit && ioa_q == (8'd11 | 8'hC0), "leitura FD");
        // escrita/leitura por pagina
        wr_a(16'h0000, 8'hA5); rd_a(16'h0000, v); ck(v == 8'hA5, "RAM pag0");
        out_a(8'hFC, 8'd20); rd_a(16'h0000, v); ck(v == 8'h00, "pag0 outro segmento limpo");
        out_a(8'hFC, 8'd10); rd_a(16'h0000, v); ck(v == 8'hA5, "segmento original preservado");
        // nucleo B ve a mesma memoria fisica, mas registradores proprios
        @(negedge clk); iob_a = 8'hA8; iob_d = 8'hFF; iob_wr = 1; @(negedge clk); iob_wr = 0;
        @(negedge clk); iob_a = 8'hFC; iob_d = 8'd10; iob_wr = 1; @(negedge clk); iob_wr = 0;
        mb_a = 16'h0000; #1; ck(b_hit && pm[b_pa] == 8'hA5, "B ve memoria comum");
        mb_a = 16'h4000; #1; ck(b_pa == 24'h000000 + 2*16384, "B regs proprios");
        // --- slot: pagina 1 para slot 0 -> mapper nao responde
        out_a(8'hA8, 8'hFC); @(negedge clk); ma_a = 16'h0000; #1; ck(!a_hit, "slot errado nao responde");
        // --- MegaRAM no slot 2 (SLOT_MEGA=2): paginas 1 e 2 em slot 2
        out_a(8'hA8, 8'hEB);
        // a8 = 0b11_10_10_11 -> pg0 slot3, pg1 slot2, pg2 slot2, pg3 slot3
        // modo ASCII8: escreve bancos
        wr_a(16'h6000, 8'd5); wr_a(16'h6800, 8'd6); wr_a(16'h7000, 8'd7); wr_a(16'h7800, 8'd8);
        @(negedge clk); ma_a = 16'h4000; #1; ck(a_hit && a_pa == 24'h100000 + 5*8192, "banco 4000");
        ma_a = 16'h5FFF; #1; ck(a_pa == 24'h100000 + 5*8192 + 16'h1FFF, "fim banco 4000");
        ma_a = 16'h6000; #1; ck(a_pa == 24'h100000 + 6*8192, "banco 6000");
        ma_a = 16'h8000; #1; ck(a_pa == 24'h100000 + 7*8192, "banco 8000");
        ma_a = 16'hBFFF; #1; ck(a_pa == 24'h100000 + 8*8192 + 16'h1FFF, "banco A000");
        // ROM mode: escrita nao vai a RAM
        ma_a = 16'h4010; #1; ck(!a_wok, "modo ROM bloqueia escrita");
        // IN 8Eh -> modo escrita
        in_a(8'h8E); @(negedge clk); ma_a = 16'h4010; #1; ck(a_wok, "IN 8E libera escrita");
        wr_a(16'h4010, 8'h77); rd_a(16'h4010, v); ck(v == 8'h77 && pm[24'h100000 + 5*8192 + 16] == 8'h77, "escreve na MegaRAM");
        // troca banco e confirma isolamento
        wr_a(16'h6000, 8'd9); rd_a(16'h4010, v); ck(v == 8'h00, "banco 9 vazio");
        wr_a(16'h6000, 8'd5); rd_a(16'h4010, v); ck(v == 8'h77, "banco 5 conserva");
        // OUT 8Eh -> volta a ROM
        out_a(8'h8E, 8'h00); @(negedge clk); ma_a = 16'h4010; #1; ck(!a_wok, "OUT 8E volta a modo ROM");
        // fora de 4000-BFFF no slot da MegaRAM nao responde (pg0 e pg3 estao no slot 3 = mapper)
        ma_a = 16'h0000; #1; ck(a_hit && a_pa >= 24'h0 && a_pa < 24'h100000, "pg0 continua no mapper");
        if (err == 0) $display("PASS: msx_mem 0 erros"); else $display("FAIL: %0d erros", err);
        $finish;
    end
endmodule
