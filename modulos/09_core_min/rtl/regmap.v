// regmap.v - campo rr (3 bits) -> indice fisico, com troca de banco (EXX / EX AF,AF').
// rr: 000 BC, 010 DE, 011 IY, 100 HL, 101 IX, 111 AX; 001 e 110 NAO sao registradores (valid=0).
module regmap(
    input  wire [2:0] rr,
    input  wire       swap_main,   // EXX: BC/DE/HL <-> BC'/DE'/HL'
    input  wire       swap_af,     // EX AF,AF': AX <-> AX'
    output reg  [5:0] idx,
    output reg        valid
);
    always @* begin
        valid = 1'b1;
        case (rr)
            3'b000: idx = swap_main ? 6'd6 : 6'd1;   // BC
            3'b010: idx = swap_main ? 6'd7 : 6'd2;   // DE
            3'b011: idx = 6'd10;                     // IY
            3'b100: idx = swap_main ? 6'd8 : 6'd3;   // HL
            3'b101: idx = 6'd9;                      // IX
            3'b111: idx = swap_af   ? 6'd5 : 6'd0;   // AX
            default: begin idx = 6'd0; valid = 1'b0; end
        endcase
    end
endmodule
