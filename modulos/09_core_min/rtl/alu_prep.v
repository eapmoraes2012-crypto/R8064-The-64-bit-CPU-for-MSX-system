// alu_prep.v - logica do estagio R: seleciona operandos e decodifica o controle da ALU (registrar a saida antes do estagio X).
// ctl: [0] inv  [1] cin1  [2] cin0  [3] is_sub  [4] keep_c  [5] arith  [6] and  [7] or  [8] xor  [9] cpl
//      [10] shl [11] shr  [12] sar  [13] rol    [14] ror   [15] cp     [16] undef
//      [17] insc (SHL/SHR inserem o C antigo: RL/RR)  [18] ins1 (SHL insere 1: SLL)  [19] daa (ajuste decimal de 8 bits)
//      [20] shl4 / [21] shr4 (deslocamento de 4 bits sem flags: RLD/RRD)
// ci (no nucleo) = cin1 ? (fin[0] ^ cin0) : cin0
module alu_prep(
    input  wire [63:0] a,
    input  wire [63:0] b,
    input  wire [4:0]  op,
    input  wire [1:0]  sz,
    input  wire [7:0]  fin,
    output wire [63:0] xa,     // operando X ja mascarado pelo tamanho
    output wire [63:0] yb,     // operando B mascarado (sem inversao)
    output wire [63:0] yy,     // operando Y do somador (mascarado, com inversao)
    output wire        ci,     // vai-um de entrada ja resolvido
    output reg  [21:0] ctl
);
    reg [63:0] xr, br_;
    localparam ADD=5'd0, ADC=5'd1, SUB=5'd2, SBC=5'd3, AND_=5'd4, OR_=5'd5, XOR_=5'd6, CP=5'd7,
               INC=5'd8, DEC=5'd9, NEG=5'd10, CPL=5'd11, SHL=5'd12, SHR=5'd13, SAR=5'd14, ROL=5'd15, ROR=5'd16,
               RL=5'd17, RR=5'd18, SLL=5'd19, DAA=5'd20, SHL4=5'd21, SHR4=5'd22;
    always @* begin
        xr = a; br_ = b; ctl = 22'd0;
        case (op)
            ADD: ctl[5] = 1'b1;
            ADC: begin ctl[5] = 1'b1; ctl[1] = 1'b1; end
            SUB: begin ctl[5] = 1'b1; ctl[0] = 1'b1; ctl[2] = 1'b1; ctl[3] = 1'b1; end
            CP:  begin ctl[5] = 1'b1; ctl[0] = 1'b1; ctl[2] = 1'b1; ctl[3] = 1'b1; ctl[15] = 1'b1; end
            SBC: begin ctl[5] = 1'b1; ctl[0] = 1'b1; ctl[1] = 1'b1; ctl[2] = 1'b1; ctl[3] = 1'b1; end
            INC: begin ctl[5] = 1'b1; br_ = 64'd1; ctl[4] = 1'b1; end
            DEC: begin ctl[5] = 1'b1; br_ = 64'd1; ctl[0] = 1'b1; ctl[2] = 1'b1; ctl[3] = 1'b1; ctl[4] = 1'b1; end
            NEG: begin ctl[5] = 1'b1; xr = 64'd0; br_ = a; ctl[0] = 1'b1; ctl[2] = 1'b1; ctl[3] = 1'b1; end
            AND_: ctl[6] = 1'b1;
            OR_:  ctl[7] = 1'b1;
            XOR_: ctl[8] = 1'b1;
            CPL:  ctl[9] = 1'b1;
            SHL:  ctl[10] = 1'b1;
            SHR:  ctl[11] = 1'b1;
            SAR:  ctl[12] = 1'b1;
            ROL:  ctl[13] = 1'b1;
            ROR:  ctl[14] = 1'b1;
            RL:   begin ctl[10] = 1'b1; ctl[17] = 1'b1; end
            RR:   begin ctl[11] = 1'b1; ctl[17] = 1'b1; end
            SLL:  begin ctl[10] = 1'b1; ctl[18] = 1'b1; end
            DAA:  ctl[19] = 1'b1;
            SHL4: ctl[20] = 1'b1;
            SHR4: ctl[21] = 1'b1;
            default: ctl[16] = 1'b1;
        endcase
    end
    wire [63:0] m = (sz == 2'd0) ? 64'h0000_0000_0000_00FF :
                    (sz == 2'd1) ? 64'h0000_0000_0000_FFFF :
                    (sz == 2'd2) ? 64'h0000_0000_FFFF_FFFF : 64'hFFFF_FFFF_FFFF_FFFF;
    assign xa = xr & m;
    assign yb = br_ & m;
    assign yy = (br_ ^ {64{ctl[0]}}) & m;
    assign ci = ctl[1] ? (fin[0] ^ ctl[2]) : ctl[2];
endmodule
