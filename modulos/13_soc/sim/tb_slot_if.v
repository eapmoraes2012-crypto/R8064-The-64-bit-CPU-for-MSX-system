`timescale 1ns/1ps
// r8064_slot_if + r8064_fifo_if: Z80 I/O cycles of the MSX (3.579545 MHz, 1 I/O wait) on ports 0Bh/0Ch/0Dh, with the SoC clock at 57.27 MHz.
// Checks: one FIFO pop per read, data stable during /RD, late sampling of the write (data still "rising" at the start of /WR),
// alternating length pointer, INT, no bus/DIR drive outside ports 0Bh-0Dh, and writes/reads of foreign ports ignored.
module tb_slot_if;
    reg clk = 0; always #8.73 clk = ~clk;            // 57,27 MHz
    reg rst = 1;
    reg iorq_n = 1, rd_n = 1, wr_n = 1; reg [7:0] a = 8'h00; reg [7:0] dv = 8'h00; reg dv_oe = 0;
    wire [7:0] slot_d; assign slot_d = dv_oe ? dv : 8'bz; pullup(slot_d[0]);
    wire [7:0] d_o; wire d_oe, dir, slot_wait, slot_int; wire fm_we, fm_re; wire [1:0] fm_a; wire [7:0] fm_wd, fm_rd; wire irq;
    r8064_slot_if dut(.clk(clk), .rst(rst), .slot_iorq_n(iorq_n), .slot_rd_n(rd_n), .slot_wr_n(wr_n), .slot_a(a), .slot_d_i(slot_d), .slot_d_o(d_o), .slot_d_oe(d_oe),
        .slot_data_dir(dir), .slot_wait(slot_wait), .slot_int(slot_int), .fm_we(fm_we), .fm_re(fm_re), .fm_a(fm_a), .fm_wd(fm_wd), .fm_rd(fm_rd), .irq(irq));
    assign slot_d = d_oe ? d_o : 8'bz;
    // R8064 side of the FIFO
    reg r_we = 0, r_re = 0; reg [7:0] r_a = 0, r_wd = 0; wire [7:0] r_rd; wire r_hit, rrst;
    r8064_fifo_if fifo(.clk(clk), .rst(rst), .r_we(r_we), .r_re(r_re), .r_a(r_a), .r_wd(r_wd), .r_rd(r_rd), .r_hit(r_hit),
        .m_we(fm_we), .m_re(fm_re), .m_a(fm_a), .m_wd(fm_wd), .m_rd(fm_rd), .m_irq(irq), .r8064_rst(rrst), .win(),
        .d_pop(1'b0), .d_push(1'b0), .d_wd(8'd0), .a_avail(), .a_q(), .b_space());
    integer errs = 0, nre = 0, nwe = 0, drv_bad = 0; reg [7:0] v;
    always @(posedge clk) begin if (fm_re) nre = nre + 1; if (fm_we) nwe = nwe + 1; end
    task chk(input [255:0] n, input [31:0] g, input [31:0] e); if (g !== e) begin errs = errs + 1; $display("ERROR %0s: got %h expected %h", n, g, e); end endtask
    // Z80 write cycle: address, /IORQ, /WR 100 ns later, data still 'rising' (wrong value) in the first 60 ns of /WR; /WR lasts 560 ns
    task zout(input [7:0] port, input [7:0] d); begin
        a = port; #40 iorq_n = 0; dv_oe = 1; dv = d ^ 8'h03; #100 wr_n = 0; #60 dv = d; #500 wr_n = 1; #20 iorq_n = 1; #30 dv_oe = 0; #100;
    end endtask
    // read cycle: /RD 100 ns after /IORQ; sampled at the end of 760 ns; checks data stability
    task zin(input [7:0] port, output [7:0] d); reg [7:0] s1; begin
        a = port; #40 iorq_n = 0; #100 rd_n = 0; #300 s1 = slot_d; #360 d = slot_d; if (s1 !== d) begin errs = errs + 1; $display("ERROR unstable data %h %h", s1, d); end
        #10 rd_n = 1; #20 iorq_n = 1; #100;
    end endtask
    task rw(input [7:0] ad, input [7:0] d); begin @(posedge clk); #1 r_a = ad; r_wd = d; r_we = 1; @(posedge clk); #1 r_we = 0; end endtask
    task rr(input [7:0] ad, output [7:0] d); begin @(posedge clk); #1 r_a = ad; r_re = 1; #1 d = r_rd; @(posedge clk); #1 r_re = 0; end endtask
    // bus monitor: the cartridge must not drive D or DIR outside a read of ports 0Bh-0Dh
    always @(posedge clk) if (!rst) begin
        if ((d_oe || dir) && !(iorq_n == 0 && rd_n == 0 && (a == 8'h0B || a == 8'h0C || a == 8'h0D))) drv_bad = drv_bad + 1;
    end
    initial begin
        repeat (6) @(posedge clk); rst = 0; repeat (6) @(posedge clk);
        zin(8'h0B, v); chk("initial STATUS (space + WINDOW)", v, 8'h22);
        chk("no pop from reading STATUS? (1 pulse per read)", nre, 1);
        // write 3 bytes to 0Ch, length to 0Dh (L then H), START to 0Bh
        zout(8'h0C, 8'h11); zout(8'h0C, 8'h22); zout(8'h0C, 8'h33);
        chk("3 writes -> 3 fm_we pulses", nwe, 3);
        zout(8'h0D, 8'h03); zout(8'h0D, 8'h00); zout(8'h0B, 8'h01);
        rr(8'hEA, v); chk("LEN_L no R8064", v, 3); rr(8'hEB, v); chk("LEN_H no R8064", v, 0);
        rr(8'hEC, v); chk("FLAGS: START + busy", v & 8'h07, 8'h03);
        rr(8'hE8, v); chk("dado 1 no R8064", v, 8'h11); rr(8'hE8, v); chk("dado 2", v, 8'h22); rr(8'hE8, v); chk("dado 3", v, 8'h33);
        zin(8'h0B, v); chk("STATUS: busy", v & 8'h1C, 8'h04);
        // R8064 responds with 2 bytes and sets DONE
        rw(8'hE8, 8'hA1); rw(8'hE8, 8'hB2); rw(8'hEA, 8'h02); rw(8'hEB, 8'h00); rw(8'hEC, 8'h04);
        repeat (4) @(posedge clk);
        chk("slot INT active", slot_int, 0);   // INT only with enable (CMD.b2)
        zout(8'h0B, 8'h04);
        repeat (4) @(posedge clk); chk("slot INT (enabled)", slot_int, 1);
        zin(8'h0B, v); chk("STATUS: data, space, done, IRQ, window", v, 8'h3B);
        zin(8'h0D, v); chk("LEN_L on the MSX", v, 2); zin(8'h0D, v); chk("LEN_H on the MSX (alternating pointer)", v, 0);
        zin(8'h0C, v); chk("byte A1", v, 8'hA1); zin(8'h0C, v); chk("byte B2", v, 8'hB2);
        zin(8'h0B, v); chk("no data", v[0], 0);
        zout(8'h0B, 8'h84); repeat (4) @(posedge clk); chk("INT cleared", slot_int, 0);
        // cycles of another device (ports 0Ah, 0Eh, 98h): ignored
        nre = 0; nwe = 0; zout(8'h98, 8'h55); zout(8'h0E, 8'h66); zin(8'h0A, v); zin(8'h98, v);
        chk("foreign ports do not generate pulses", nre + nwe, 0);
        chk("bus/DIR driven outside the read of 0Bh-0Dh", drv_bad, 0);
        // restart by command (CMD.b3) and WAIT always released
        chk("WAIT solto", slot_wait, 0);
        $display("errors=%0d", errs); if (errs == 0) $display("RESULT: SLOT IF OK"); else $display("RESULT: %0d ERRORS", errs);
        $finish;
    end
endmodule
