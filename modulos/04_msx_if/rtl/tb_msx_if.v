`timescale 1ns/100ps
// Testbench: MSX Z80 model (I/O cycles of 4 T-states at 3.579545 MHz, 21+2 T-states per byte in OTIR/INIR) + R8064 program model (port polling, XOR 5A) + monitors.
module tb_msx_if;
    parameter [7:0] BASE = 8'h40;
    parameter SKEW = 0;                 // random delay (ns) between bus lines
    real T = 279.4;
    reg clk = 0; always #5 clk = ~clk;
    reg iorq_n = 1, rd_n = 1, wr_n = 1, m1_n = 1, reset_n = 1; reg [7:0] a = 8'hFF; reg [7:0] zd = 0; reg z_en = 0;
    wire [7:0] d_out; wire u3_oe_n, u3_dir, wait_buf, int_buf, busdir_buf;
    wire [7:0] bus_val = (!u3_oe_n && u3_dir) ? d_out : (z_en ? zd : 8'hFF);
    reg [7:0] r_port = 0; reg r_rd = 0, r_wr = 0; reg [7:0] r_wdata = 0; wire [7:0] r_rdata; wire r_reset;
    msx_if #(.BASE(BASE)) dut(.clk(clk), .rst_n(1'b1), .iorq_n(iorq_n), .rd_n(rd_n), .wr_n(wr_n), .m1_n(m1_n), .reset_n(reset_n), .a(a), .d_in(bus_val),
        .d_out(d_out), .u3_oe_n(u3_oe_n), .u3_dir(u3_dir), .wait_buf(wait_buf), .int_buf(int_buf), .busdir_buf(busdir_buf),
        .r_port(r_port), .r_rd(r_rd), .r_wr(r_wr), .r_wdata(r_wdata), .r_rdata(r_rdata), .r_reset(r_reset));
    // ---------- monitores
    integer conflicts = 0, wrong_drive = 0, rst_pulses = 0; reg rd_window = 0;
    always @(posedge clk) begin
        if (!u3_oe_n && z_en) conflicts = conflicts + 1;
        if (!u3_oe_n && !rd_window) wrong_drive = wrong_drive + 1;
        if (!busdir_buf && u3_oe_n) wrong_drive = wrong_drive + 1;
        if (r_reset) rst_pulses = rst_pulses + 1;
    end
    // ---------- Z80
    function integer sk(input integer dummy); sk = (SKEW == 0) ? 0 : ($urandom % SKEW); endfunction
    task z_out(input [7:0] ad, input [7:0] dt);
        begin
            #(sk(0)) a = ad; #(40) zd = dt; z_en = 1; #(360) iorq_n = 0; #(80 + sk(0)) wr_n = 0; #(600) wr_n = 1; #(20 + sk(0)) iorq_n = 1; #(50) z_en = 0;
        end
    endtask
    task z_in(input [7:0] ad, output [7:0] dt);
        begin
            #(sk(0)) a = ad; #(400) iorq_n = 0; rd_window = 1; #(80 + sk(0)) rd_n = 0; #(520) dt = bus_val; #(80) rd_n = 1; #(20 + sk(0)) iorq_n = 1; #(150) rd_window = 0;
        end
    endtask
    // ---------- R8064 program: waits for START, reads LEN, reads len bytes, applies XOR 5A, writes the result, signals DONE
    task r_io_rd(input [7:0] p, output [7:0] v);
        begin @(posedge clk); r_port <= p; r_rd <= 1; @(posedge clk); v = r_rdata; r_rd <= 0; r_port <= 0; end
    endtask
    task r_io_wr(input [7:0] p, input [7:0] v);
        begin @(posedge clk); r_port <= p; r_wdata <= v; r_wr <= 1; @(posedge clk); r_wr <= 0; r_port <= 0; end
    endtask
    reg [7:0] rv; reg [15:0] rlen; integer ri; integer jobs = 0; reg r8_en = 1;
    initial begin
        forever begin
            r_io_rd(8'hF4, rv);
            if (r8_en && rv[0]) begin
                r_io_wr(8'hF4, 8'h01);
                r_io_rd(8'hF2, rv); rlen[7:0] = rv; r_io_rd(8'hF3, rv); rlen[15:8] = rv;
                for (ri = 0; ri < rlen; ri = ri + 1) begin
                    rv = 0; while (!rv[0]) r_io_rd(8'hF1, rv);
                    r_io_rd(8'hF0, rv);
                    rv = rv ^ 8'h5A;
                    r_port <= 0; begin : waitsp reg [7:0] f; f = 0; while (!f[1]) r_io_rd(8'hF1, f); end
                    r_io_wr(8'hF0, rv);
                end
                r_io_wr(8'hF2, rlen[7:0]); r_io_wr(8'hF3, rlen[15:8]); r_io_wr(8'hF4, 8'h04); jobs = jobs + 1;
            end
        end
    end
    // ---------- test
    integer errs = 0, i, n, seed0, tstart, tend; reg [7:0] v, st; reg [7:0] exp [0:2047]; reg [31:0] lf;
    task block(input integer len, input integer irq, input integer measure);
        integer k; integer t0, t1, t2;
        begin
            lf = 32'hACE1_2024 + len;
            for (k = 0; k < len; k = k + 1) begin lf = {lf[30:0], lf[31] ^ lf[21] ^ lf[1] ^ lf[0]}; exp[k] = lf[7:0] ^ 8'h5A; end
            lf = 32'hACE1_2024 + len;
            z_out(BASE + 2, len[7:0]); z_out(BASE + 3, len[15:8]);
            t0 = $time;
            for (k = 0; k < len; k = k + 1) begin lf = {lf[30:0], lf[31] ^ lf[21] ^ lf[1] ^ lf[0]}; z_out(BASE, lf[7:0]); #(T * 23 - 1150 > 0 ? T * 23 - 1150 : 1); end
            t1 = $time;
            z_out(BASE + 1, irq ? 8'h05 : 8'h01);
            st = 0; while (!st[3]) begin z_in(BASE + 1, st); end
            if (irq && int_buf !== 1'b0) begin errs = errs + 1; $display("ERROR: INT did not assert"); end
            if (!irq && int_buf !== 1'b1) begin errs = errs + 1; $display("ERROR: INT asserted without enabling"); end
            z_in(BASE + 2, v); n = v; z_in(BASE + 3, v); n = n + (v << 8);
            if (n !== len) begin errs = errs + 1; $display("ERROR: len de retorno %0d != %0d", n, len); end
            t2 = $time;
            for (k = 0; k < len; k = k + 1) begin
                z_in(BASE, v); #(T * 23 - 1150 > 0 ? T * 23 - 1150 : 1);
                if (v !== exp[k]) begin errs = errs + 1; if (errs < 8) $display("ERROR data k=%0d got=%h expected=%h", k, v, exp[k]); end
            end
            z_out(BASE + 1, 8'h84);     // clears DONE/IRQ, keeps IRQ enabled
            z_out(BASE + 1, 8'h00);
            if (int_buf !== 1'b1) begin errs = errs + 1; $display("ERROR: INT did not deassert"); end
            if (measure) $display("VAZAO: %0d bytes: MSX->FPGA %0.0f B/s | FPGA->MSX %0.0f B/s (OTIR/INIR a 23 T-states por byte)", len, len * 1e9 / (t1 - t0), len * 1e9 / ($time - t2));
        end
    endtask
    initial begin
        #200 reset_n = 0; #400 reset_n = 1; #400;
        z_in(BASE + 1, st); if (st !== 8'h02) begin errs = errs + 1; $display("ERROR STATUS after reset = %h (expected 02)", st); end
        // 1) blocks of several sizes (one with IRQ)
        block(1, 0, 0); block(7, 1, 0); block(513, 0, 0);
        // 2) 2048-byte block (FIFOs full) with throughput measurement
        block(2048, 1, 1);
        // 3) estouro e sub-fluxo
        z_out(BASE + 1, 8'h02);                                   // clears FIFOs
        for (i = 0; i < 2049; i = i + 1) begin z_out(BASE, i[7:0]); #(T * 3); end
        z_in(BASE + 1, st); if (st[5] !== 1'b1 || st[1] !== 1'b0) begin errs = errs + 1; $display("ERROR overflow/full STATUS=%h", st); end
        z_out(BASE + 1, 8'h02); #1000;
        z_in(BASE + 1, st); if (st[5] !== 1'b0 || st[1] !== 1'b1) begin errs = errs + 1; $display("ERROR limpeza STATUS=%h", st); end
        z_in(BASE, v); z_in(BASE + 1, st);
        if (v !== 8'h00 || st[6] !== 1'b1) begin errs = errs + 1; $display("ERROR sub-fluxo v=%h STATUS=%h", v, st); end
        z_out(BASE + 1, 8'h02);
        // 4) ports out of range and interrupt acknowledge cycle (M1+IORQ): nothing can be driven or written
        for (i = 0; i < 64; i = i + 1) begin
            if (i != BASE[7:2]) begin z_out(i[7:0] * 4 + 8'h01, 8'hAA); z_in(i[7:0] * 4, v); end
        end
        m1_n = 0; z_out(BASE, 8'h55); z_in(BASE, v); m1_n = 1; #1000;
        z_in(BASE + 1, st); if (st !== 8'h02) begin errs = errs + 1; $display("ERROR: out-of-range port/M1 changed the state STATUS=%h", st); end
        // 5) short pulses (15 ns noise) on WR/RD with valid address: they must not write
        a = BASE; iorq_n = 0; #50 wr_n = 0; #15 wr_n = 1; #50 wr_n = 0; #15 wr_n = 1; #50 iorq_n = 1; a = 8'hFF; #300;
        z_in(BASE + 1, st); if (st !== 8'h02) begin errs = errs + 1; $display("ERROR: ruido em WR escreveu STATUS=%h", st); end
        // 5b) short pulses also on RD (must not enable the buffer) and on WR in the CMD/DATA register (must not change the state)
        a = BASE + 1; iorq_n = 0; #50 rd_n = 0; #15 rd_n = 1; #30 rd_n = 0; #15 rd_n = 1; #50 wr_n = 0; #15 wr_n = 1; #50 iorq_n = 1; a = 8'hFF; #300;
        a = BASE; iorq_n = 0; #50 wr_n = 0; #15 wr_n = 1; #50 iorq_n = 1; a = 8'hFF; #300;
        z_in(BASE + 1, st); if (st !== 8'h02 || dut.fi_lvl !== 0) begin errs = errs + 1; $display("ERROR: noise changed the state STATUS=%h level=%0d", st, dut.fi_lvl); end
        // 6) R8064 restart by CMD b3
        z_out(BASE + 1, 8'h08); #500;
        if (rst_pulses == 0) begin errs = errs + 1; $display("ERROR: r_reset did not pulse"); end
        $display("Summary: errors=%0d bus conflicts=%0d improper buffer drives=%0d R8064 jobs=%0d r_reset=%0d SKEW=%0d", errs, conflicts, wrong_drive, jobs, rst_pulses, SKEW);
        if (errs == 0 && conflicts == 0 && wrong_drive == 0) $display("PASS"); else $display("FAIL");
        $finish;
    end
endmodule
