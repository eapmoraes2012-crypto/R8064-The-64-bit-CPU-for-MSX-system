// sdram_byte_if.v - adaptador: acesso de 1 byte (endereco fisico de 24 bits) -> sdram_ctrl (palavra de 64 bits + byte-enable).
// Protocolo do lado do Z80: req fica em 1 ate 'ack' (pulso de 1 clock; rdata valido nesse clock); depois req cai e um novo pedido pode ser feito.
// Enderecos acima de 4 MB (addr[23:22] != 0) dao alias (sao ignorados).
module sdram_byte_if(
    input  wire        clk, rst,
    input  wire        req, we,
    input  wire [23:0] addr,
    input  wire [7:0]  wdata,
    output reg  [7:0]  rdata,
    output reg         ack,
    // lado sdram_ctrl
    output wire        s_req, s_we,
    output wire [18:0] s_addr,
    output wire [63:0] s_wdata,
    output wire [7:0]  s_be,
    input  wire        s_ready, s_rvalid,
    input  wire [63:0] s_rdata,
    input  wire        s_wdone
);
    localparam [1:0] IDLE = 2'd0, ISSUE = 2'd1, WAITR = 2'd2, DONE = 2'd3;
    reg [1:0]  st;
    reg        l_we; reg [21:0] l_addr; reg [7:0] l_wd;
    assign s_req   = (st == ISSUE);
    assign s_we    = l_we;
    assign s_addr  = l_addr[21:3];
    assign s_wdata = {8{l_wd}};
    assign s_be    = 8'd1 << l_addr[2:0];
    always @(posedge clk) begin
        ack <= 1'b0;
        if (rst) st <= IDLE;
        else case (st)
            IDLE:  if (req) begin l_we <= we; l_addr <= addr[21:0]; l_wd <= wdata; st <= ISSUE; end
            ISSUE: if (s_ready) st <= WAITR;
            WAITR: if (l_we ? s_wdone : s_rvalid) begin
                       rdata <= s_rdata >> {l_addr[2:0], 3'b000}; ack <= 1'b1; st <= DONE;
                   end
            default: if (!req) st <= IDLE;
        endcase
    end
endmodule
