`timescale 1ns/1ps
// teste isolado da interface de FIFOs: dois lados, STATUS, LEN, FLAGS, CMD, IRQ, FIFO cheio (2048) e limpeza
module tb_fifo;
    reg clk = 0, rst = 1; always #5 clk = ~clk;
    reg r_we = 0, r_re = 0; reg [7:0] r_a = 0, r_wd = 0; wire [7:0] r_rd; wire r_hit;
    reg m_we = 0, m_re = 0; reg [1:0] m_a = 0; reg [7:0] m_wd = 0; wire [7:0] m_rd; wire m_irq, rrst;
    r8064_fifo_if dut(.clk(clk), .rst(rst), .r_we(r_we), .r_re(r_re), .r_a(r_a), .r_wd(r_wd), .r_rd(r_rd), .r_hit(r_hit),
        .m_we(m_we), .m_re(m_re), .m_a(m_a), .m_wd(m_wd), .m_rd(m_rd), .m_irq(m_irq), .r8064_rst(rrst));
    integer errs = 0, i; reg [7:0] v;
    task chk(input [255:0] n, input [31:0] g, input [31:0] e); if (g !== e) begin errs = errs + 1; $display("ERRO %0s: obtido %h esperado %h", n, g, e); end endtask
    task mw(input [1:0] a, input [7:0] d); begin @(posedge clk); #1 m_a = a; m_wd = d; m_we = 1; @(posedge clk); #1 m_we = 0; end endtask
    task mr(input [1:0] a, output [7:0] d); begin @(posedge clk); #1 m_a = a; m_re = 1; #1 d = m_rd; @(posedge clk); #1 m_re = 0; end endtask
    task rw(input [7:0] a, input [7:0] d); begin @(posedge clk); #1 r_a = a; r_wd = d; r_we = 1; @(posedge clk); #1 r_we = 0; end endtask
    task rr(input [7:0] a, output [7:0] d); begin @(posedge clk); #1 r_a = a; r_re = 1; #1 d = r_rd; @(posedge clk); #1 r_re = 0; end endtask
    initial begin
        repeat (4) @(posedge clk); rst = 0;
        chk("hit E8", {31'd0, 1'b0}, 0); r_a = 8'hE8; #1 chk("hit em E8", r_hit, 1); r_a = 8'hE4; #1 chk("sem hit em E4", r_hit, 0);
        r_a = 8'hF3; #1 chk("sem hit em F3 (porta antiga)", r_hit, 0); r_a = 8'hF4; #1 chk("sem hit em F4", r_hit, 0); r_a = 8'hED; #1 chk("sem hit em ED", r_hit, 0);
        mr(1, v); chk("STATUS MSX inicial: espaco", v, 8'h02); rr(8'hE9, v); chk("STATUS R8064 inicial: espaco, sem dado", v, 8'h02);
        // MSX envia LEN=3 e 3 bytes, depois INICIAR
        mw(2, 8'd3); mw(3, 8'd0); mw(0, 8'h11); mw(0, 8'h22); mw(0, 8'h33);
        repeat (3) @(posedge clk);
        rr(8'hE9, v); chk("R8064 ve dado", v[0], 1); rr(8'hEA, v); chk("LEN_L no R8064", v, 3); rr(8'hEB, v); chk("LEN_H no R8064", v, 0);
        mw(1, 8'h05);   // INICIAR + habilita IRQ
        rr(8'hEC, v); chk("FLAGS: INICIAR recebido + ocupado", v & 8'h07, 8'h03); mr(1, v); chk("STATUS MSX: ocupado, sem concluido", v & 8'h1C, 8'h04);
        rw(8'hEC, 8'h01);   // limpa INICIAR
        rr(8'hEC, v); chk("INICIAR limpo", v[0], 0);
        rr(8'hE8, v); chk("dado 1", v, 8'h11); rr(8'hE8, v); chk("dado 2", v, 8'h22); rr(8'hE8, v); chk("dado 3", v, 8'h33);
        rr(8'hE9, v); chk("FIFO MSX->R8064 vazio", v[0], 0);
        // R8064 devolve 2 bytes e marca CONCLUIDO
        rw(8'hEA, 8'd2); rw(8'hE8, 8'hA1); rw(8'hE8, 8'hB2); repeat (3) @(posedge clk); rw(8'hEC, 8'h04);
        mr(1, v); chk("STATUS MSX: dado, espaco, concluido, IRQ", v, 8'h1B & ~8'h04 | 8'h00 ); // b0 b1 b3 b4 (b2 ocupado = 0)
        chk("INT ativo", m_irq, 1); mr(2, v); chk("LEN_L no MSX = 2", v, 2);
        mr(0, v); chk("MSX le A1", v, 8'hA1); mr(0, v); chk("MSX le B2", v, 8'hB2); mr(1, v); chk("sem dado", v[0], 0);
        mw(1, 8'h84); chk("CONCLUIDO limpo", m_irq, 0); mr(1, v); chk("STATUS apos limpar", v & 8'h18, 0);
        // encher o FIFO MSX->R8064 (2048) e transbordar
        for (i = 0; i < 2050; i = i + 1) mw(0, i[7:0]);
        repeat (3) @(posedge clk); mr(1, v); chk("FIFO cheio: sem espaco", v[1], 0);
        for (i = 0; i < 2048; i = i + 1) begin rr(8'hE8, v); if (v !== i[7:0]) begin errs = errs + 1; if (errs < 6) $display("ERRO fifo[%0d]=%h", i, v); end end
        rr(8'hE9, v); chk("esvaziou", v[0], 0);
        // limpar FIFOs
        mw(0, 8'h77); mw(1, 8'h02); repeat (3) @(posedge clk); rr(8'hE9, v); chk("CMD limpa FIFOs", v[0], 0);
        // reinicio do R8064
        mw(1, 8'h08); chk("pulso de reset do R8064", rrst, 1); @(posedge clk); #1 chk("pulso curto", rrst, 0);
        $display("erros=%0d", errs); if (errs == 0) $display("RESULTADO: FIFO OK"); else $display("RESULTADO: %0d ERROS", errs);
        $finish;
    end
endmodule
