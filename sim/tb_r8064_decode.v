// tb_r8064_decode.v - exhaustive testbench of the ED decoder + cycle check against the spreadsheet.
// GENERATED from spreadsheet rev. 5. NOT SIMULATED in the generation environment.
// Run inside rom/ + ref/ (the .mem files must be in the working directory), for example:
//   cp ../rom/*.mem ../ref/*.mem . && iverilog -g2012 -o sim tb_r8064_decode.v r8064_decode.v && vvp sim
`timescale 1ns/1ps
module tb_r8064_decode;
    localparam W_RD_HIT = 4;
    localparam W_WR_HIT = 2;
    localparam W_IO     = 1;
    localparam BR_D     = 2;
    localparam BR_X     = 4;
    localparam BR_M     = 5;

    reg clk = 1'b0;
    always #5 clk = ~clk;                       // 100 MHz

    reg  [7:0] b2, b3;
    wire [9:0] id; wire illegal;
    wire [3:0] len; wire [4:0] nr, nw; wire [1:0] nio; wire [7:0] ex; wire [1:0] pen_code; wire has_cond, is_z80;

    r8064_decode dut(.clk(clk), .b2(b2), .b3(b3), .id(id), .illegal(illegal), .len(len), .nr(nr), .nw(nw),
                     .nio(nio), .ex(ex), .pen_code(pen_code), .has_cond(has_cond), .is_z80(is_z80));

    reg [9:0]  exp_id   [0:65535];
    reg [11:0] exp_clk  [0:511];
    reg [11:0] exp_wait [0:511];
    reg [11:0] exp_pen  [0:511];

    integer i, errs_id, errs_cyc, checked, nf, clk_c, wait_c, pen_c, tmp;
    reg [9:0] id_seen;

    initial begin
        $readmemh("expected_id.mem",    exp_id);
        $readmemh("expected_clock.mem", exp_clk);
        $readmemh("expected_wait.mem",  exp_wait);
        $readmemh("expected_pen.mem",   exp_pen);
        errs_id = 0; errs_cyc = 0; checked = 0;
        b2 = 8'h00; b3 = 8'h00;
        repeat (3) @(posedge clk);
        for (i = 0; i < 65536; i = i + 1) begin
            b2 = i[15:8]; b3 = i[7:0];
            @(posedge clk); #1;                  // valid id (+1 clock)
            id_seen = id;
            if (id_seen !== exp_id[i]) begin
                errs_id = errs_id + 1;
                if (errs_id <= 10) $display("ERROR id: b2=%02h b3=%02h got=%0d expected=%0d", b2, b3, id_seen, exp_id[i]);
            end
            @(posedge clk); #1;                  // campos de controle validos (+2 clocks)
            // checks the cycles of every (b2,b3) combination that decodes a valid instruction
            if (exp_id[i] != 0) begin
                nf     = (len + 7) / 8;           // 64-bit fetch accesses
                tmp    = nf + nr + nw;
                clk_c  = 1;
                if (tmp > clk_c)      clk_c = tmp;
                if (nio > clk_c)      clk_c = nio;
                if (ex  > clk_c)      clk_c = ex;
                wait_c = (nf + nr) * W_RD_HIT + nw * W_WR_HIT + nio * W_IO;
                pen_c  = (pen_code == 2'd0) ? 0 : (pen_code == 2'd1) ? BR_D : (pen_code == 2'd2) ? BR_X : BR_M;
                checked = checked + 1;
                if (clk_c !== exp_clk[exp_id[i]] || wait_c !== exp_wait[exp_id[i]] || pen_c !== exp_pen[exp_id[i]]) begin
                    errs_cyc = errs_cyc + 1;
                    if (errs_cyc <= 10) $display("ERROR cycles: id=%0d clk %0d/%0d wait %0d/%0d pen %0d/%0d",
                        exp_id[i], clk_c, exp_clk[exp_id[i]], wait_c, exp_wait[exp_id[i]], pen_c, exp_pen[exp_id[i]]);
                end
            end
        end
        $display("Vectors (b2,b3): 65536 | id errors: %0d | combinations with cycles checked: %0d | cycle errors: %0d",
                 errs_id, checked, errs_cyc);
        if (errs_id == 0 && errs_cyc == 0) $display("PASS"); else $display("FAIL");
        $finish;
    end
endmodule
