`timescale 1ns/1ps
module tb_mem;
    reg clk = 0, rst = 1; always #5 clk = ~clk;
    reg active = 1, is_rom = 1, phase = 0; reg [7:0] a8 = 0; reg map_we = 0; reg [3:0] mi = 0; reg [1:0] mv = 0;
    reg [15:0] pc = 0; reg [3:0] len = 1; wire [3:0] fx; wire romw;
    reg dev = 0; reg [15:0] da = 0; reg [1:0] dsz = 0; reg dwe = 0; wire aev; wire [4:0] an;
    mem_class dut(.clk(clk), .rst(rst), .active(active), .is_rom(is_rom), .phase(phase), .a8(a8), .map_we(map_we), .map_idx(mi), .map_val(mv),
        .f_pc(pc), .f_len(len), .f_xcyc(fx), .f_romw(romw), .d_ev(dev), .d_addr(da), .d_size(dsz), .d_we(dwe), .add_ev(aev), .add_n(an));
    integer errs = 0;
    task ck(input [255:0] n, input integer got, input integer exp);
        if (got !== exp) begin errs = errs + 1; $display("ERRO %0s: obtido %0d esperado %0d", n, got, exp); end else $display("ok   %0s = %0d", n, got);
    endtask
    task dacc(input [15:0] a, input [1:0] sz, input we, output integer ev, output integer n);
        begin da = a; dsz = sz; dwe = we; dev = 1; @(posedge clk); #1 dev = 0; ev = aev; n = an; end
    endtask
    integer e, n;
    initial begin
        repeat (3) @(posedge clk); rst = 0; @(posedge clk); #1;
        pc = 16'h0010; len = 3; @(posedge clk); #1; ck("busca em ROM: sem extra", fx, 0); ck("busca em ROM: romw", romw, 1);
        pc = 16'h00FD; len = 3; @(posedge clk); #1; ck("busca FD..FF: sem quebra de pagina", fx, 0);
        pc = 16'h00FE; len = 3; @(posedge clk); #1; ck("busca FE..100: quebra de pagina +1", fx, 1);
        pc = 16'h8000; len = 2; phase = 0; @(posedge clk); #1; ck("busca externa fase 0: +4", fx, 4); ck("busca externa: nao e ROM", romw, 0);
        phase = 1; @(posedge clk); #1; ck("busca externa fase 1: +5", fx, 5);
        pc = 16'h80FF; len = 2; @(posedge clk); #1; ck("externa fase 1 + quebra de pagina", fx, 6);
        a8 = 8'hC0; pc = 16'hC000; len = 1; @(posedge clk); #1; ck("pagina 3 no slot 3 = RAM interna: 0", fx, 0); ck("RAM: romw 0", romw, 0);
        a8 = 8'h00; active = 0; pc = 16'h8000; @(posedge clk); #1; ck("modo Z80/nativo (inativo): sem extra", fx, 0); active = 1;
        // reprogramar: pagina 0 slot 0 = externa
        @(posedge clk); #1 mi = 4'b0000; mv = 2'd2; map_we = 1; @(posedge clk); #1 map_we = 0; pc = 16'h0010; len = 1; phase = 0; @(posedge clk); #1; ck("tabela reprogramada: pag 0 slot 0 externa +4", fx, 4);
        @(posedge clk); #1 mv = 2'd1; map_we = 1; @(posedge clk); #1 map_we = 0;
        // dados
        phase = 0; dacc(16'h8000, 0, 0, e, n); ck("dado externo: evento", e, 1); ck("dado externo: +4", n, 4);
        phase = 1; dacc(16'h8000, 0, 0, e, n); ck("dado externo fase 1: +5", n, 5);
        phase = 0; dacc(16'h00FF, 1, 0, e, n); ck("leitura 2 B em ROM cruzando pagina: 3+1", n, 4);
        dacc(16'h0020, 0, 0, e, n); ck("leitura de ROM (modo ROM): +3", n, 3);
        dacc(16'h0020, 0, 1, e, n); ck("escrita em ROM: sem extra, sem evento", e, 0);
        is_rom = 0; dacc(16'h0020, 0, 0, e, n); ck("leitura de ROM em modo DRAM: sem evento", e, 0);
        a8 = 8'hC0; dacc(16'hC0FC, 3, 0, e, n); ck("8 B em RAM cruzando pagina: +1", n, 1);
        active = 0; dacc(16'h8000, 0, 0, e, n); ck("modo Z80: sem evento", e, 0);
        $display("RESULTADO: %0s", errs == 0 ? "CLASSIFICADOR OK" : "ERROS"); $display("erros=%0d", errs); $finish;
    end
endmodule
