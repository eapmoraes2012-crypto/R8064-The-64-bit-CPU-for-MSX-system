`timescale 1ns/1ps
// msx_mem com mapper de 4 MB (256 segmentos) e MegaRAM de 2 MB (256 bancos de 8 KB), MEGA_BASE = 400000h
module tb_msx_big;
    reg clk = 0, rst = 1; always #5 clk = ~clk;
    reg io_wr = 0, io_rd = 0; reg [7:0] io_addr = 0, io_wdata = 0; wire [7:0] io_rdata; wire io_hit;
    reg mem_rd = 0, mem_wr = 0; reg [15:0] mem_addr = 0; reg [7:0] mem_wdata = 0; wire hit; wire [23:0] pa; wire [7:0] a8; wire wr_ok;
    msx_mem #(.MAP_BITS(8), .MEGA_BITS(8), .MEGA_BASE(24'h400000)) dut(.clk(clk), .rst(rst), .en(1'b1), .io_wr(io_wr), .io_rd(io_rd), .io_addr(io_addr), .io_wdata(io_wdata), .io_rdata(io_rdata), .io_hit(io_hit),
        .mem_rd(mem_rd), .mem_wr(mem_wr), .mem_addr(mem_addr), .mem_wdata(mem_wdata), .hit(hit), .phys_addr(pa), .a8_o(a8), .wr_ok(wr_ok));
    integer errs = 0;
    task chk(input [255:0] n, input [31:0] g, input [31:0] e); if (g !== e) begin errs = errs + 1; $display("ERRO %0s: obtido %h esperado %h", n, g, e); end endtask
    task wio(input [7:0] a, input [7:0] d); begin @(posedge clk); #1 io_addr = a; io_wdata = d; io_wr = 1; @(posedge clk); #1 io_wr = 0; end endtask
    task rio(input [7:0] a); begin @(posedge clk); #1 io_addr = a; io_rd = 1; @(posedge clk); #1 io_rd = 0; end endtask
    initial begin
        repeat (3) @(posedge clk); rst = 0;
        wio(8'hA8, 8'hFF);                                  // todos os slots = 3 (mapper)
        wio(8'hFC, 8'd255); wio(8'hFD, 8'd128); wio(8'hFE, 8'd1); wio(8'hFF, 8'd0);
        #1 mem_addr = 16'h0123; #1 chk("pag0 seg 255 -> 3FC123", pa, 24'h3FC123); chk("hit", hit, 1);
        mem_addr = 16'h4000; #1 chk("pag1 seg 128 -> 200000", pa, 24'h200000);
        mem_addr = 16'h9FFF; #1 chk("pag2 seg 1 -> 5FFF", pa, 24'h005FFF);
        io_rd = 1; io_addr = 8'hFC; #1 chk("leitura FC = 255", io_rdata, 8'hFF); io_rd = 0;
        // MegaRAM no slot 2 das paginas 1 e 2 (A8 = 1010_1010 -> slot 2 em todas)
        wio(8'hA8, 8'hAA);
        wio(8'hFC, 8'd0);
        mem_wr = 0; mem_rd = 1; mem_addr = 16'h4000; #1 chk("MegaRAM banco 0 -> 400000", pa, 24'h400000);
        // modo de escrita (IN 8Eh) e escrita no registrador de banco 6800h (banco de 6000-7FFF) com banco 255
        mem_rd = 0; rio(8'h8E);
        @(posedge clk); #1 mem_wr = 1; mem_addr = 16'h6800; mem_wdata = 8'd255; @(posedge clk); #1 mem_wr = 0;
        mem_rd = 1; mem_addr = 16'h6000; #1 chk("MegaRAM banco 255 em 6000h -> 5FE000", pa, 24'h5FE000);
        mem_addr = 16'h7FFF; #1 chk("topo da MegaRAM -> 5FFFFF", pa, 24'h5FFFFF);
        if (errs == 0) $display("RESULTADO: MSX 4MB+2MB OK"); else $display("RESULTADO: %0d ERROS", errs);
        $finish;
    end
endmodule
