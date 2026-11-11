// mem_arb4.v - arbitro de 4 mestres com o pedido REGISTRADO antes do controlador de SDRAM (sem cadeia combinacional mestre -> arbitro -> FSM da SDRAM).
// Prioridade: m0 (cache D) > m1 (caminhador MMU-D) > m2 (cache I) > m3 (caminhador MMU-I). Cada mestre mantem req ate acc; depois espera done (rvalid ou wdone).
// Latencia: aceite 1 clock apos o req (captura no registrador de pedido); o controlador recebe req registrado e aceita quando ready.
module mem_arb4(
    input  wire clk, rst,
    input  wire [3:0] req, we, input wire [4*19-1:0] addr, input wire [4*64-1:0] wdata, input wire [4*8-1:0] be,
    output wire [3:0] acc, done, output wire [63:0] rdata,
    output wire c_req, c_we, output wire [18:0] c_addr, output wire [63:0] c_wdata, output wire [7:0] c_be,
    input  wire c_ready, c_rvalid, input wire [63:0] c_rdata, input wire c_wdone
);
    reg rv, busy, rwe; reg [1:0] own_r, own_b; reg [18:0] raddr; reg [63:0] rwd; reg [7:0] rbe;
    wire [1:0] pick = req[0] ? 2'd0 : req[1] ? 2'd1 : req[2] ? 2'd2 : 2'd3;
    wire any = |req;
    wire cap = !rv && !busy && any;
    assign acc = cap ? (4'b0001 << pick) : 4'b0000;
    assign c_req = rv; assign c_we = rwe; assign c_addr = raddr; assign c_wdata = rwd; assign c_be = rbe;
    wire go = rv && c_ready;
    wire fin = busy && (rwe ? c_wdone : c_rvalid);
    assign done = fin ? (4'b0001 << own_b) : 4'b0000;
    assign rdata = c_rdata;
    reg rwe_b;
    always @(posedge clk) begin
        if (rst) begin rv <= 0; busy <= 0; rwe <= 0; own_r <= 0; own_b <= 0; end
        else begin
            if (cap) begin rv <= 1; own_r <= pick; rwe <= we[pick]; raddr <= addr[pick*19 +: 19]; rwd <= wdata[pick*64 +: 64]; rbe <= be[pick*8 +: 8]; end
            else if (go) begin rv <= 0; busy <= 1; own_b <= own_r; end
            else if (fin) busy <= 0;
        end
    end
endmodule
