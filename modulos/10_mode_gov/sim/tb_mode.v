`timescale 1ns/1ps
module tb_mode;
    reg clk = 0, rst = 1; always #5 clk = ~clk;
    reg we = 0, re = 0; reg [7:0] a = 0, wd = 0; wire [7:0] rd; wire oe;
    reg bnd = 0; wire nat, csel, z80, rom, busy; wire [7:0] idx; wire ow;
    r8064_mode dut(.clk(clk), .rst(rst), .io_we(we), .io_re(re), .io_a(a), .io_wd(wd), .io_rd(rd), .io_oe(oe), .boundary(bnd),
        .native64(nat), .clk_sel(csel), .is_z80(z80), .is_rom(rom), .busy(busy), .s1990_idx(idx), .s1990_other_we(ow));
    integer errs = 0;
    task wr(input [7:0] ad, input [7:0] d); begin @(posedge clk); #1 a = ad; wd = d; we = 1; @(posedge clk); #1 we = 0; end endtask
    task rdp(input [7:0] ad, output [7:0] d); begin #1 a = ad; re = 1; #1 d = rd; re = 0; end endtask
    task ck(input [255:0] n, input [31:0] got, input [31:0] exp);
        if (got !== exp) begin errs = errs + 1; $display("ERROR %0s: got %h expected %h", n, got, exp); end else $display("ok   %0s = %h", n, got);
    endtask
    reg [7:0] v;
    initial begin
        repeat (3) @(posedge clk); rst = 0; repeat (2) @(posedge clk);
        ck("reset: Z80", z80, 1); ck("reset: ROM", rom, 1); ck("reset: native", nat, 0);
        rdp(8'h3D, v); ck("ID (IN 3DH)", v, 8'h64);
        // write to 3EH without the key: ignored
        wr(8'h3E, 8'h01); bnd = 1; repeat (2) @(posedge clk); ck("no key: native stays 0", nat, 0);
        // wrong key
        wr(8'h3D, 8'h5A); wr(8'h3E, 8'h01); repeat (2) @(posedge clk); ck("wrong key: native 0", nat, 0);
        // right key
        bnd = 0; wr(8'h3D, 8'hA5); wr(8'h3E, 8'h05);          // NATIVE64 + CLK=10 (campo reservado: so guarda o bit)
        rdp(8'h3E, v); ck("busy until the boundary", v[3], 1); ck("not yet native", nat, 0);
        bnd = 1; repeat (2) @(posedge clk); bnd = 0;
        ck("native after boundary", nat, 1); ck("clk_sel (1x -> B)", csel, 1);
        rdp(8'h3E, v); ck("read 3EH (clk B, native)", v, 8'h03);
        // the key disarms after a write
        wr(8'h3E, 8'h00); bnd = 1; repeat (2) @(posedge clk); bnd = 0; ck("2nd write without re-arming: ignored", nat, 1);
        wr(8'h3D, 8'hA5); wr(8'h3E, 8'h00); bnd = 1; repeat (2) @(posedge clk); bnd = 0; ck("volta ao classico", nat, 0); ck("clk A", csel, 0);
        // S1990 reg 6: R800 DRAM = 00H
        wr(8'hE4, 8'h06); wr(8'hE5, 8'h00); bnd = 1; repeat (2) @(posedge clk); bnd = 0; ck("R800", z80, 0); ck("DRAM", rom, 0);
        rdp(8'hE5, v); ck("read E5H (reg 6)", v, 8'h00);
        wr(8'hE5, 8'h40); bnd = 1; repeat (2) @(posedge clk); bnd = 0; ck("R800 ROM: z80", z80, 0); ck("R800 ROM: rom", rom, 1);
        wr(8'hE5, 8'h20); bnd = 1; repeat (2) @(posedge clk); bnd = 0; ck("Z80 DRAM: z80", z80, 1); ck("Z80 DRAM: rom", rom, 0);
        wr(8'hE5, 8'h60); bnd = 1; repeat (2) @(posedge clk); bnd = 0; ck("Z80 ROM: z80", z80, 1); ck("Z80 ROM: rom", rom, 1);
        // another S1990 register does not change the mode and is flagged
        wr(8'hE4, 8'h07); @(posedge clk); #1 a = 8'hE5; wd = 8'h00; we = 1; #1 ck("other reg: other_we", ow, 1); @(posedge clk); #1 we = 0;
        bnd = 1; repeat (2) @(posedge clk); ck("other reg does not change mode", z80 & rom, 1);
        $display("RESULT: %0s", errs == 0 ? "MODE OK" : "ERRORS"); $display("errors=%0d", errs); $finish;
    end
endmodule
