// mem_arb5.v - arbitro de 5 mestres com o pedido REGISTRADO antes do controlador de SDRAM (extensao do mem_arb4 com o DMA como m4).
// Prioridade: m0 (cache D) > m1 (caminhador MMU-D) > m2 (cache I) > m3 (caminhador MMU-I) > m4 (DMA). Cada mestre mantem req ate acc; depois espera done (rvalid ou wdone).
// Latencia: aceite 1 clock apos o req (captura no registrador de pedido); o controlador recebe req registrado e aceita quando ready.
module mem_arb5(
    input  wire clk, rst,
    input  wire [4:0] req, we, input wire [5*20-1:0] addr, input wire [5*64-1:0] wdata, input wire [5*8-1:0] be,
    output wire [4:0] acc, done, output wire [63:0] rdata,
    output wire c_req, c_we, output wire [19:0] c_addr, output wire [63:0] c_wdata, output wire [7:0] c_be,
    input  wire c_ready, c_rvalid, input wire [63:0] c_rdata, input wire c_wdone
);
    reg rv, busy, rwe; reg [2:0] own_r, own_b; reg [19:0] raddr; reg [63:0] rwd; reg [7:0] rbe;
    wire [2:0] pick = req[0] ? 3'd0 : req[1] ? 3'd1 : req[2] ? 3'd2 : req[3] ? 3'd3 : 3'd4;
    wire any = |req;
    wire cap = !rv && !busy && any;
    assign acc = cap ? (5'b00001 << pick) : 5'b00000;
    assign c_req = rv; assign c_we = rwe; assign c_addr = raddr; assign c_wdata = rwd; assign c_be = rbe;
    wire go = rv && c_ready;
    wire fin = busy && (rwe ? c_wdone : c_rvalid);
    assign done = fin ? (5'b00001 << own_b) : 5'b00000;
    assign rdata = c_rdata;
    always @(posedge clk) begin
        if (rst) begin rv <= 0; busy <= 0; rwe <= 0; own_r <= 0; own_b <= 0; end
        else begin
            if (cap) begin rv <= 1; own_r <= pick; rwe <= we[pick]; raddr <= addr[pick*20 +: 20]; rwd <= wdata[pick*64 +: 64]; rbe <= be[pick*8 +: 8]; end
            else if (go) begin rv <= 0; busy <= 1; own_b <= own_r; end
            else if (fin) busy <= 0;
        end
    end
endmodule
