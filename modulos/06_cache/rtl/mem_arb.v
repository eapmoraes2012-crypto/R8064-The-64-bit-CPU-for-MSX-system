// mem_arb.v - 2-master arbiter (D with priority over I) for the 1-request-at-a-time SDRAM controller.
module mem_arb(
    input  wire clk, rst,
    // mestre D
    input  wire d_req, d_we, input wire [18:0] d_addr, input wire [63:0] d_wdata, input wire [7:0] d_be, output wire d_accept, output wire d_done,
    // mestre I
    input  wire i_req, i_we, input wire [18:0] i_addr, input wire [63:0] i_wdata, input wire [7:0] i_be, output wire i_accept, output wire i_done,
    output wire [63:0] rdata,
    // controlador
    output wire c_req, c_we, output wire [18:0] c_addr, output wire [63:0] c_wdata, output wire [7:0] c_be, input wire c_ready, input wire c_rvalid, input wire [63:0] c_rdata, input wire c_wdone
);
    reg busy, owner, bwe; // owner: 0 = D, 1 = I
    wire pick_d = d_req;
    wire go = !busy && c_ready && (d_req || i_req);
    assign c_req   = !busy && (d_req || i_req);
    assign c_we    = pick_d ? d_we : i_we;
    assign c_addr  = pick_d ? d_addr : i_addr;
    assign c_wdata = pick_d ? d_wdata : i_wdata;
    assign c_be    = pick_d ? d_be : i_be;
    assign d_accept = go && pick_d;
    assign i_accept = go && !pick_d;
    wire fin = busy && (bwe ? c_wdone : c_rvalid);
    assign d_done = fin && !owner;
    assign i_done = fin && owner;
    assign rdata  = c_rdata;
    always @(posedge clk) begin
        if (rst) begin busy <= 0; owner <= 0; bwe <= 0; end
        else if (go) begin busy <= 1; owner <= !pick_d; bwe <= c_we; end
        else if (fin) busy <= 0;
    end
endmodule
