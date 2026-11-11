// regmap.v - campo rr (3 bits) -> indice fisico, com troca de banco (EXX / EX AF,AF') e bancos de prefixo.
// rr: 000 BC, 010 DE, 011 IY, 100 HL, 101 IX, 111 AX; 001 e 110 NAO sao registradores (valid=0).
// bank: 00 normal | 01 sombra (ED 0B: inverte swap_main/swap_af = EXX; instr; EXX) | 10 N0-N3 (ED 0E) | 11 N4-N7 (ED 0D)
//   N0..N7 = indices fisicos 16..23. codigos BC/DE/HL/AX -> N(0/1/2/3 + 4*bank[0]). IX/IY/SP/PC nunca sao bancados (valid=0 com banco != 0).
module regmap_b(
    input  wire [2:0] rr,
    input  wire       swap_main,   // EXX: BC/DE/HL <-> BC'/DE'/HL'
    input  wire       swap_af,     // EX AF,AF': AX <-> AX'
    input  wire [1:0] bank,
    output reg  [5:0] idx,
    output reg        valid
);
    wire sm = (bank == 2'b01) ? ~swap_main : swap_main;
    wire sa = (bank == 2'b01) ? ~swap_af   : swap_af;
    wire nb = bank[1];                 // banco N
    wire hi = bank[0];                 // 0: N0-N3, 1: N4-N7
    always @* begin
        valid = 1'b1;
        case (rr)
            3'b000: idx = nb ? {3'b010, hi, 2'd0} : (sm ? 6'd6 : 6'd1);   // BC  -> N0 / N4
            3'b010: idx = nb ? {3'b010, hi, 2'd1} : (sm ? 6'd7 : 6'd2);   // DE  -> N1 / N5
            3'b100: idx = nb ? {3'b010, hi, 2'd2} : (sm ? 6'd8 : 6'd3);   // HL  -> N2 / N6
            3'b111: idx = nb ? {3'b010, hi, 2'd3} : (sa ? 6'd5 : 6'd0);   // AX  -> N3 / N7
            3'b011: begin idx = 6'd10; valid = (bank == 2'b00); end                // IY
            3'b101: begin idx = 6'd9;  valid = (bank == 2'b00); end                // IX
            default: begin idx = 6'd0; valid = 1'b0; end
        endcase
    end
endmodule
