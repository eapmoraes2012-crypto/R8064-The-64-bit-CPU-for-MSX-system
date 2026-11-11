`timescale 1ns/1ps
module tb_pipe2;
    parameter NTRACE = 1; parameter TRACE_FILE = "trace.mem";
    parameter WRD = 4, WWR = 2, WIO = 1, DEC_D = 1, LEN_LAT = 1, QCAP = 32, TGT_OFF = -1;
    reg clk = 0, rst = 1; always #5 clk = ~clk;
    wire done; wire [31:0] cycles, retired, chk_n, chk_err, f2_stall, wp_fetch, starve, fetches;
    r8064_pipe2 #(.NTRACE(NTRACE), .TRACE_FILE(TRACE_FILE), .WRD(WRD), .WWR(WWR), .WIO(WIO), .DEC_D(DEC_D), .LEN_LAT(LEN_LAT), .QCAP(QCAP), .TGT_OFF(TGT_OFF))
        dut(.clk(clk), .rst(rst), .done(done), .cycles(cycles), .retired(retired), .chk_n(chk_n), .chk_err(chk_err), .f2_stall(f2_stall), .wp_fetch(wp_fetch), .starve(starve), .fetches(fetches));
    integer t;
    initial begin
        #22 rst = 0;
        t = 0;
        while (!done && t < 2000000) begin @(posedge clk); t = t + 1; end
        #1;
        $display("RESULT cycles=%0d retired=%0d chk=%0d chk_err=%0d f2_stall=%0d wp_fetch=%0d starve=%0d fetches=%0d", cycles, retired, chk_n, chk_err, f2_stall, wp_fetch, starve, fetches);
        $finish;
    end
endmodule
