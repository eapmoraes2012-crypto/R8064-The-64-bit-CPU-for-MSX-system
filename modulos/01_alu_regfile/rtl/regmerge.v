// regmerge.v - escrita parcial: mescla "novo" no valor antigo do registrador (o upper e preservado).
// wsz: 0 = byte baixo [7:0], 1 = byte alto [15:8], 2 = 16 bits, 3 = 32 bits, 4 = 64 bits.
module regmerge(
    input  wire [63:0] old,
    input  wire [63:0] newv,
    input  wire [2:0]  wsz,
    output reg  [63:0] out
);
    always @* begin
        case (wsz)
            3'd0:    out = {old[63:8],  newv[7:0]};
            3'd1:    out = {old[63:16], newv[7:0], old[7:0]};
            3'd2:    out = {old[63:16], newv[15:0]};
            3'd3:    out = {old[63:32], newv[31:0]};
            default: out = newv;
        endcase
    end
endmodule
