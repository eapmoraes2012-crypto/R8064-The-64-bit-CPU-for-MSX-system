`timescale 1ns/1ps
// 2K FIFO test against a model (software queue): random push/pop on every clock, including when filling/emptying; pop is only accepted with visible data.
module tb_fifo;
    reg clk = 0, rst = 1, clr = 0; always #5 clk = ~clk;
    reg push = 0, pop = 0; reg [7:0] din = 0; wire [7:0] dout; wire empty, full; wire [11:0] level;
    fifo2k f(.clk(clk), .rst(rst), .clr(clr), .push(push), .din(din), .pop(pop), .dout(dout), .empty(empty), .full(full), .level(level));
    reg [7:0] q [0:4095]; integer h = 0, t = 0, n, errs = 0, i, mode, pp, pq; integer maxlvl = 0, pops = 0, pushes = 0;
    always @(posedge clk) if (!rst) begin
        // data and queue are checked BEFORE the edge (current state), then the cycle's operations are applied
        if (!empty && dout !== q[h % 4096]) begin errs = errs + 1; if (errs < 6) $display("ERROR: dout=%h expected=%h h=%0d t=%0d", dout, q[h % 4096], h, t); end
        if (level !== (t - h)) begin errs = errs + 1; if (errs < 6) $display("ERROR: level=%0d expected=%0d", level, t - h); end
        if (full !== ((t - h) == 2048)) begin errs = errs + 1; end
        if (push && !full) begin q[t % 4096] = din; t = t + 1; pushes = pushes + 1; end
        if (pop && !empty) begin h = h + 1; pops = pops + 1; end
        if (t - h > maxlvl) maxlvl = t - h;
    end
    initial begin
        #50 rst = 0;
        for (mode = 0; mode < 6; mode = mode + 1) begin
            pp = (mode == 0) ? 90 : (mode == 1) ? 50 : (mode == 2) ? 20 : (mode == 3) ? 100 : (mode == 4) ? 60 : 30;
            pq = (mode == 0) ? 20 : (mode == 1) ? 50 : (mode == 2) ? 90 : (mode == 3) ? 0 : (mode == 4) ? 100 : 100;
            for (i = 0; i < 12000; i = i + 1) begin
                @(negedge clk); push = ($urandom % 100) < pp; pop = ($urandom % 100) < pq; din = $urandom;
            end
        end
        @(negedge clk); push = 0; pop = 0; repeat (5) @(posedge clk);
        $display("FIFO: pushes=%0d pops=%0d max level=%0d errors=%0d %s", pushes, pops, maxlvl, errs, (errs == 0 && maxlvl == 2048) ? "PASS" : "FAIL");
        $finish;
    end
endmodule
