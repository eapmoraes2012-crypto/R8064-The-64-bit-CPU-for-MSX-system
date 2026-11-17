`timescale 1ns/1ps
module tb_clkgen;
    reg x = 0, x27 = 0, x57 = 0; integer err = 0;
    wire c0, l0, r0, c1, l1, r1, c2, l2, r2, c3, l3, r3, s1, s0, s2, s3;
    reg x14 = 0;
    always #(1000.0/(2*14.31818)) x14 = ~x14;
    r8064_clkgen #(.SRC(3)) d(.clk_in(x14), .rst_in(1'b0), .clk(c3), .clk_sdram(s3), .locked(l3), .rst(r3));
    r8064_clkgen #(.SRC(0)) a(.clk_in(x27), .rst_in(1'b0), .clk(c0), .clk_sdram(s0), .locked(l0), .rst(r0));
    r8064_clkgen #(.SRC(1)) b(.clk_in(x), .rst_in(1'b0), .clk(c1), .clk_sdram(s1), .locked(l1), .rst(r1));
    r8064_clkgen #(.SRC(2)) c(.clk_in(x57), .rst_in(1'b0), .clk(c2), .clk_sdram(s2), .locked(l2), .rst(r2));
    always #(1000.0/(2*27.0)) x27 = ~x27;
    always #(1000.0/(2*3.579545)) x = ~x;
    always #(1000.0/(2*57.272727)) x57 = ~x57;
    // measures the frequency of each output over 20 us
    integer n0, n1, n2, n3; reg meas = 0;
    always @(posedge c3) if (meas) n3 = n3 + 1;
    // phase of clk_sdram (SRC1): average delay between the clk and clk_sdram edges must be ~ 1/4 of the period (17.46 ns -> ~4.4 ns)
    real tck, dph; integer ndph; initial begin ndph = 0; dph = 0; end
    always @(posedge c1) tck = $realtime;
    always @(posedge s1) if (meas && tck > 0) begin dph = dph + ($realtime - tck); ndph = ndph + 1; end
    always @(posedge c0) if (meas) n0 = n0 + 1;
    always @(posedge c1) if (meas) n1 = n1 + 1;
    always @(posedge c2) if (meas) n2 = n2 + 1;
    real f0, f1, f2, f3;
    initial begin
        n0 = 0; n1 = 0; n2 = 0; n3 = 0; tck = 0;
        #10000;
        if (!(l0 && l1 && l2 && l3)) begin $display("ERROR: PLL did not lock"); err = err + 1; end
        if (!(r0 === 1'b0 || r0 === 1'b1)) err = err + 1;
        wait (r0 == 0 && r1 == 0);
        meas = 1; #20000; meas = 0;
        f0 = n0 / 20.0; f1 = n1 / 20.0; f2 = n2 / 20.0; f3 = n3 / 20.0;
        $display("SRC0 (27 MHz x17/8)  = %f MHz", f0);
        $display("SRC1 (3,579545 x16)  = %f MHz", f1);
        $display("SRC2 (direto)        = %f MHz", f2);
        $display("SRC3 (14,318 x4)      = %f MHz", f3);
        $display("SRC1 clk_sdram average delay = %f ns (expected ~4.4)", dph / ndph);
        if (f3 < 57.15 || f3 > 57.40) begin $display("ERROR SRC3"); err = err + 1; end
        if (dph / ndph < 3.6 || dph / ndph > 5.2) begin $display("ERROR fase sdram"); err = err + 1; end
        if (f0 < 57.2 || f0 > 57.55) begin $display("ERROR SRC0"); err = err + 1; end
        if (f1 < 57.15 || f1 > 57.40) begin $display("ERROR SRC1"); err = err + 1; end
        if (f2 < 57.15 || f2 > 57.40) begin $display("ERROR SRC2"); err = err + 1; end
        if (r2 !== 1'b0) begin $display("ERROR rst SRC2"); err = err + 1; end
        if (err == 0) $display("RESULT: CLKGEN OK"); else $display("RESULT: %0d ERRORS", err);
        $finish;
    end
endmodule
