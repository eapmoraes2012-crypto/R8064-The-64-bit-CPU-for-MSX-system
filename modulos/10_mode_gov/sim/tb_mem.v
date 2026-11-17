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
        if (got !== exp) begin errs = errs + 1; $display("ERROR %0s: got %0d expected %0d", n, got, exp); end else $display("ok   %0s = %0d", n, got);
    endtask
    task dacc(input [15:0] a, input [1:0] sz, input we, output integer ev, output integer n);
        begin da = a; dsz = sz; dwe = we; dev = 1; @(posedge clk); #1 dev = 0; ev = aev; n = an; end
    endtask
    integer e, n;
    initial begin
        repeat (3) @(posedge clk); rst = 0; @(posedge clk); #1;
        pc = 16'h0010; len = 3; @(posedge clk); #1; ck("fetch in ROM: no extra", fx, 0); ck("fetch in ROM: romw", romw, 1);
        pc = 16'h00FD; len = 3; @(posedge clk); #1; ck("fetch FD..FF: no page break", fx, 0);
        pc = 16'h00FE; len = 3; @(posedge clk); #1; ck("fetch FE..100: page break +1", fx, 1);
        pc = 16'h8000; len = 2; phase = 0; @(posedge clk); #1; ck("external fetch phase 0: +4", fx, 4); ck("external fetch: not ROM", romw, 0);
        phase = 1; @(posedge clk); #1; ck("external fetch phase 1: +5", fx, 5);
        pc = 16'h80FF; len = 2; @(posedge clk); #1; ck("external phase 1 + page break", fx, 6);
        a8 = 8'hC0; pc = 16'hC000; len = 1; @(posedge clk); #1; ck("page 3 in slot 3 = internal RAM: 0", fx, 0); ck("RAM: romw 0", romw, 0);
        a8 = 8'h00; active = 0; pc = 16'h8000; @(posedge clk); #1; ck("Z80/native mode (inactive): no extra", fx, 0); active = 1;
        // reprogram: page 0 slot 0 = external
        @(posedge clk); #1 mi = 4'b0000; mv = 2'd2; map_we = 1; @(posedge clk); #1 map_we = 0; pc = 16'h0010; len = 1; phase = 0; @(posedge clk); #1; ck("table reprogrammed: page 0 slot 0 external +4", fx, 4);
        @(posedge clk); #1 mv = 2'd1; map_we = 1; @(posedge clk); #1 map_we = 0;
        // data
        phase = 0; dacc(16'h8000, 0, 0, e, n); ck("external data: event", e, 1); ck("external data: +4", n, 4);
        phase = 1; dacc(16'h8000, 0, 0, e, n); ck("external data phase 1: +5", n, 5);
        phase = 0; dacc(16'h00FF, 1, 0, e, n); ck("2 B read in ROM crossing a page: 3+1", n, 4);
        dacc(16'h0020, 0, 0, e, n); ck("ROM read (ROM mode): +3", n, 3);
        dacc(16'h0020, 0, 1, e, n); ck("write to ROM: no extra, no event", e, 0);
        is_rom = 0; dacc(16'h0020, 0, 0, e, n); ck("ROM read in DRAM mode: no event", e, 0);
        a8 = 8'hC0; dacc(16'hC0FC, 3, 0, e, n); ck("8 B in RAM crossing a page: +1", n, 1);
        active = 0; dacc(16'h8000, 0, 0, e, n); ck("Z80 mode: no event", e, 0);
        $display("RESULT: %0s", errs == 0 ? "CLASSIFIER OK" : "ERRORS"); $display("errors=%0d", errs); $finish;
    end
endmodule
