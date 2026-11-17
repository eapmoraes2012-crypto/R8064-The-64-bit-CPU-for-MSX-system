`timescale 1ns/1ps
module tb_mdu;
  reg clk=0, rst=1; always #5 clk=~clk;
  reg ld_b=0, ld_h=0, start=0; reg [63:0] d_ld=0, d_a=0; reg [1:0] d_w=0, op=0;
  wire busy; wire [127:0] r; wire [63:0] rhi; wire [7:0] fl; wire inv;
  r8064_mdu u(.clk(clk),.rst(rst),.ld_b(ld_b),.ld_h(ld_h),.d_ld(d_ld),.d_w(d_w),.start(start),.op(op),.d_a(d_a),.busy(busy),.r(r),.rhi(rhi),.fl(fl),.inv(inv));
  integer f, n, code; reg [63:0] a,h,b; reg [3:0] o; reg [3:0] w; integer cyc, maxc;
  initial begin
    f=$fopen("vec.txt","r"); maxc=0;
    repeat(3) @(posedge clk); rst=0;
    while (!$feof(f)) begin
      code=$fscanf(f,"%h %h %h %h %h\n",o,w,a,h,b);
      if (code==5) begin
        @(negedge clk); ld_b=1; d_ld=b; d_w=w[1:0]; @(negedge clk); ld_b=0; ld_h=1; d_ld=h; @(negedge clk); ld_h=0;
        start=1; d_a=a; op=o[1:0]; @(negedge clk); start=0; cyc=0;
        while (busy) begin @(negedge clk); cyc=cyc+1; end
        if (cyc>maxc) maxc=cyc;
        $display("R %h %h %h %h", r, rhi, fl, inv);
      end
    end
    $display("MAXCYC %0d", maxc); $finish;
  end
endmodule
