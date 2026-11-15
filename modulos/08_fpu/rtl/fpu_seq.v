// fpu_seq.v - nucleo aritmetico COMPACTO da FPU de 80 bits (x87 estendido) do R8064. Mesma interface e mesmos resultados do fpu_alu.v (bit a bit, vetores do
// fpref.py), mas feito para ser pequeno: UM somador de 68 bits, tres registradores (X, MA, MB), deslocamentos de 4/1 bits por clock, e multiplicacao, divisao
// e raiz bit a bit nesse mesmo somador (nada de multiplicador ou divisor externo).
// Operacoes (op): 0 ADD, 1 SUB, 2 MUL, 3 DIV, 4 SQRT, 5 CMP, 6 FILD(int64), 7 FIST(int64), 8 RNDINT, 9 LD32, 10 LD64, 11 ST32, 12 ST64.
// a = ST0 (ou dado de memoria), b = segundo operando; a, b, op, rc e pc devem ficar ESTAVEIS de 'start' ate o proximo 'start' (nao sao registrados aqui e
// 'res' e montado direto dos registradores de trabalho).
// rc: 0 mais proximo/par, 1 -inf, 2 +inf, 3 zero. pc: 0 = 24, 2 = 53, outros = 64 bits (so ADD/SUB/MUL/DIV/SQRT).
// Saidas (validas de 'done' ate o proximo 'start'): res, flags {PE,UE,OE,ZE,DE,IE}, up (arredondou para cima = C1), cc {c3,c2,c0} (so CMP).
// Registrador X: [67] vai-um, [66:3] significando (bit 66 = bit inteiro), [2] guarda, [1] arredondamento, [0] "sticky".
module fpu_seq(
    input  wire        clk, rst, start,
    input  wire [3:0]  op,
    input  wire [1:0]  rc, pc,
    input  wire [79:0] a, b,
    output wire        busy,
    output reg         done,
    output wire [79:0] res,
    output reg  [5:0]  flags,
    output reg         up,
    output reg  [2:0]  cc
);
    localparam OP_ADD = 0, OP_SUB = 1, OP_MUL = 2, OP_DIV = 3, OP_SQRT = 4, OP_CMP = 5, OP_FILD = 6, OP_FIST = 7, OP_RND = 8, OP_LD32 = 9, OP_LD64 = 10, OP_ST32 = 11, OP_ST64 = 12;
    localparam [4:0] S_IDLE = 0, S_LD = 1, S_C = 2, S_DEC = 3, S_UA = 4, S_UA2 = 5, S_UB = 6, S_UB2 = 7, S_OP = 8, S_SHR = 9, S_NRM = 10, S_AD0 = 11, S_AD1 = 12, S_AD2 = 13,
                     S_ML = 14, S_DV = 15, S_DV2 = 16, S_SQ1 = 17, S_SQ2 = 18, S_RI = 19, S_RI2 = 20, S_NEG = 21, S_RP0 = 22, S_RP1 = 23, S_RP2 = 24, S_RP3 = 25, S_FIN = 26;
    localparam [67:0] XIND = {1'b0, 64'hC000_0000_0000_0000, 3'd0}, XINF = {1'b0, 64'h8000_0000_0000_0000, 3'd0};
    reg [4:0] st, ret;
    reg [67:0] X; reg [65:0] MA, MB; reg signed [17:0] EA, EB; reg [6:0] cn;
    reg sr, nb, subr, bigb, tiny, mlt, meq; reg [1:0] emode;      // emode: 0 expoente = EA (ou 0 se denormal/zero), 1 expoente todo 1, 2 inteiro cru
    assign busy = (st != S_IDLE);
    // ---- classificacao (combinacional sobre as entradas estaveis) ----
    wire sa = a[79], sb = b[79]; wire [14:0] xa = a[78:64], xb = b[78:64]; wire [63:0] ma = a[63:0], mb = b[63:0];
    wire xa0 = (xa == 0), xb0 = (xb == 0), xa1 = (xa == 15'h7FFF), xb1 = (xb == 15'h7FFF), fa0 = (ma[62:0] == 0), fb0 = (mb[62:0] == 0);
    wire za = xa0 && !ma[63] && fa0, zb = xb0 && !mb[63] && fb0;
    wire da = xa0 && !ma[63] && !fa0, db = xb0 && !mb[63] && !fb0;
    wire ua = xa0 ? ma[63] : !ma[63], ub = xb0 ? mb[63] : !mb[63];
    wire ia = xa1 && ma[63] && fa0, ib = xb1 && mb[63] && fb0;
    wire na = xa1 && ma[63] && !fa0, nbn = xb1 && mb[63] && !fb0;
    wire two = (op == OP_ADD) || (op == OP_SUB) || (op == OP_MUL) || (op == OP_DIV) || (op == OP_CMP);
    wire one = (op == OP_SQRT) || (op == OP_FIST) || (op == OP_RND) || (op == OP_ST32) || (op == OP_ST64);
    wire ari = (op == OP_ADD) || (op == OP_SUB) || (op == OP_MUL) || (op == OP_DIV) || (op == OP_SQRT) || (op == OP_RND);
    wire fde = (one && da) || (two && (da || db));
    wire sbe = sb ^ (op == OP_SUB);
    wire u_any = ua || (two && ub), n_any = na || (two && nbn);
    wire nq = ari && n_any;                                            // comparando dois NaN: com o bit "quieto" ja ligado
    wire pick_b = two && nbn && (!na || mlt);
    wire nan_ie = (na && !ma[62]) || (two && nbn && !mb[62]);
    wire xlt = xa < xb, xeq = (xa == xb);
    wire mag_gt = xeq ? (!mlt && !meq) : !xlt, mag_eq = xeq && meq;
    wire l64 = (op == OP_LD64);
    wire ls = l64 ? a[63] : a[31]; wire [10:0] le = l64 ? a[62:52] : {3'd0, a[30:23]}; wire [51:0] lf = l64 ? a[51:0] : {a[22:0], 29'd0};
    wire le_max = l64 ? (le == 11'h7FF) : (le[7:0] == 8'hFF), le_z = (le == 0), lf_z = (lf == 0);
    // ---- parametros do arredondamento ----
    wire st32 = (op == OP_ST32), st64 = (op == OP_ST64);
    wire [1:0] psel = st32 ? 2'd0 : st64 ? 2'd1 : (op == OP_FIST || op == OP_RND) ? 2'd2 : (pc == 2'd0) ? 2'd0 : (pc == 2'd2) ? 2'd1 : 2'd2;
    wire signed [17:0] emin = st32 ? -18'sd126 : st64 ? -18'sd1022 : -18'sd16382;
    wire signed [17:0] emax = st32 ? 18'sd127 : st64 ? 18'sd1023 : 18'sd16383;
    wire rb  = (psel == 2'd0) ? X[42] : (psel == 2'd1) ? X[13] : X[2];
    wire stk = (psel == 2'd0) ? |X[41:0] : (psel == 2'd1) ? |X[12:0] : |X[1:0];
    wire lsb = (psel == 2'd0) ? X[43] : (psel == 2'd1) ? X[14] : X[3];
    wire inex = rb | stk;
    wire inc = (rc == 2'd0) ? (rb && (stk || lsb)) : (rc == 2'd1) ? (inex && sr) : (rc == 2'd2) ? (inex && !sr) : 1'b0;
    wire [67:0] one_l = (psel == 2'd0) ? (68'd1 << 43) : (psel == 2'd1) ? (68'd1 << 14) : (68'd1 << 3);
    wire [67:0] msk_l = (psel == 2'd0) ? {25'h1FFFFFF, 43'd0} : (psel == 2'd1) ? {54'h3FFFFFFFFFFFFF, 14'd0} : {65'h1FFFFFFFFFFFFFFFF, 3'd0};
    wire [63:0] maxm = (psel == 2'd0) ? {24'hFFFFFF, 40'd0} : (psel == 2'd1) ? {53'h1FFFFFFFFFFFFF, 11'd0} : 64'hFFFF_FFFF_FFFF_FFFF;
    wire inf_r = (rc == 2'd0) || (rc == 2'd2 && !sr) || (rc == 2'd1 && sr);
    wire signed [17:0] dexp = EA - EB;
    wire [17:0] dabs = dexp[17] ? -dexp : dexp;
    wire signed [17:0] dmin = emin - EA;
    // ---- o somador unico: SUM = L +/- R (na subtracao SUM[68] = 1 quando L >= R) ----
    wire [67:0] xma = {1'b0, MA[63] , MA[62] | nq, MA[61:0], 3'd0}, xmb = {1'b0, MB[63], MB[62] | nq, MB[61:0], 3'd0};
    wire [67:0] srem = {X[65:0], MB[65:64]};
    reg [67:0] L, R; reg sub;
    always @* begin
        L = X; R = 68'd0; sub = 1'b0;
        case (st)
            S_C:   begin L = xma; R = xmb; sub = 1'b1; end
            S_DEC: begin L = 68'd0; R = xma; sub = a[63]; end                 // FILD: |inteiro|
            S_AD1: begin L = bigb ? xmb : xma; R = X; sub = subr; end
            S_ML:  begin R = MB[0] ? xma : 68'd0; end
            S_DV:  begin R = xmb; sub = 1'b1; end
            S_SQ1: begin L = srem; R = {1'b0, MA[64:0], 2'b01}; sub = 1'b1; end
            S_NEG: begin L = 68'd0; R = X; sub = 1'b1; end
            default: R = inc ? one_l : 68'd0;                                  // arredondamento (S_RI, S_RP2)
        endcase
    end
    wire [68:0] SUM = {1'b0, L} + {1'b0, sub ? ~R : R} + {68'd0, sub};
    wire ge = SUM[68];
    // ---- resultado: montado dos registradores (X, EA, sr, emode) ----
    wire [17:0] eb80 = EA + 18'd16383, eb64 = EA + 18'd1023, eb32 = EA + 18'd127;
    wire [14:0] ef = (emode == 2'd1) ? 15'h7FFF : X[66] ? (st32 ? {7'd0, eb32[7:0]} : st64 ? {4'd0, eb64[10:0]} : eb80[14:0]) : 15'd0;
    assign res = (emode == 2'd2) ? {16'd0, X[66:3]} : st32 ? {48'd0, sr, ef[7:0], X[65:43]} : st64 ? {16'd0, sr, ef[10:0], X[65:14]} : {sr, ef, X[66:3]};
    always @(posedge clk) begin
        done <= 1'b0;
        if (rst) begin st <= S_IDLE; flags <= 0; up <= 0; cc <= 0; emode <= 0; X <= 0; sr <= 0; EA <= 0; end
        else case (st)
            S_IDLE: if (start) begin st <= S_LD; up <= 1'b0; cc <= 3'd0; flags <= 6'd0; tiny <= 1'b0; nb <= 1'b0; emode <= 2'd0; end
            S_LD: begin MA <= {2'b00, ma}; MB <= {2'b00, mb}; EA <= {3'd0, xa}; EB <= {3'd0, xb}; ret <= S_DEC; st <= S_C; end
            S_C: begin mlt <= !ge; meq <= (SUM[67:0] == 68'd0); st <= ret; end
            S_DEC: begin
                flags <= {4'd0, fde, 1'b0}; sr <= sa; st <= S_UA;
                if (ari && u_any) begin sr <= 1'b1; X <= XIND; emode <= 2'd1; flags <= {4'd0, fde, 1'b1}; st <= S_FIN; end
                else if (ari && n_any) begin sr <= pick_b ? sb : sa; X <= pick_b ? xmb : xma; emode <= 2'd1; flags <= {4'd0, fde, nan_ie}; st <= S_FIN; end
                else case (op)
                    OP_ADD, OP_SUB: begin
                        if (ia || ib) begin
                            st <= S_FIN; emode <= 2'd1; X <= XINF; sr <= ia ? sa : sbe;
                            if (ia && ib && sa != sbe) begin sr <= 1'b1; X <= XIND; flags <= {4'd0, fde, 1'b1}; end
                        end else if (za && zb) begin sr <= (sa == sbe) ? sa : (rc == 2'd1); X <= 68'd0; st <= S_FIN; end
                        else if (za) begin sr <= sbe; st <= S_UB; end
                    end
                    OP_MUL: begin
                        sr <= sa ^ sb;
                        if ((ia && zb) || (za && ib)) begin sr <= 1'b1; X <= XIND; emode <= 2'd1; flags <= {4'd0, fde, 1'b1}; st <= S_FIN; end
                        else if (ia || ib) begin X <= XINF; emode <= 2'd1; st <= S_FIN; end
                        else if (za || zb) begin X <= 68'd0; st <= S_FIN; end
                    end
                    OP_DIV: begin
                        sr <= sa ^ sb;
                        if ((ia && ib) || (za && zb)) begin sr <= 1'b1; X <= XIND; emode <= 2'd1; flags <= {4'd0, fde, 1'b1}; st <= S_FIN; end
                        else if (zb) begin X <= XINF; emode <= 2'd1; flags <= {3'd0, 1'b1, fde, 1'b0}; st <= S_FIN; end
                        else if (ia) begin X <= XINF; emode <= 2'd1; st <= S_FIN; end
                        else if (ib || za) begin X <= 68'd0; st <= S_FIN; end
                    end
                    OP_SQRT: begin
                        sr <= 1'b0;
                        if (za) begin sr <= sa; X <= 68'd0; st <= S_FIN; end
                        else if (sa) begin sr <= 1'b1; X <= XIND; emode <= 2'd1; flags <= {4'd0, fde, 1'b1}; st <= S_FIN; end
                        else if (ia) begin X <= XINF; emode <= 2'd1; st <= S_FIN; end
                    end
                    OP_CMP: begin
                        st <= S_FIN; X <= 68'd0; sr <= 1'b0;                              // res = 0 (so cc interessa)
                        if (ua || ub || na || nbn) begin cc <= 3'd7; flags <= {4'd0, fde, 1'b1}; end
                        else cc <= ((za && zb) || (sa == sb && mag_eq)) ? 3'd4 : (sa != sb) ? {2'b00, sa} : {2'b00, mag_gt ? sa : !sa};
                    end
                    OP_FILD: begin
                        flags <= 6'd0; sr <= a[63]; X <= {1'b0, SUM[66:0]}; EA <= 18'sd63; ret <= S_FIN; st <= (ma == 64'd0) ? S_FIN : S_NRM;
                        if (ma == 64'd0) sr <= 1'b0;
                    end
                    OP_FIST: begin
                        if (ua || na || ia) begin X <= XINF; emode <= 2'd2; flags <= {4'd0, fde, 1'b1}; st <= S_FIN; end
                        else if (za) begin X <= 68'd0; emode <= 2'd2; st <= S_FIN; end
                    end
                    OP_RND: begin
                        if (ia) begin X <= XINF; emode <= 2'd1; st <= S_FIN; end
                        else if (za) begin X <= 68'd0; st <= S_FIN; end
                    end
                    OP_LD32, OP_LD64: begin
                        flags <= 6'd0; sr <= ls; st <= S_FIN;
                        if (le_max) begin
                            emode <= 2'd1;
                            if (lf_z) X <= XINF; else begin X <= {1'b0, 2'b11, lf[50:0], 14'd0}; flags <= {5'd0, !lf[51]}; end
                        end else if (le_z && lf_z) X <= 68'd0;
                        else if (le_z) begin X <= {2'b00, lf, 14'd0}; EA <= l64 ? -18'sd1022 : -18'sd126; flags <= 6'b000010; ret <= S_FIN; st <= S_NRM; end
                        else begin X <= {2'b01, lf, 14'd0}; EA <= $signed({7'd0, le}) - (l64 ? 18'sd1023 : 18'sd127); end
                    end
                    OP_ST32, OP_ST64: begin
                        if (ua) begin sr <= 1'b1; X <= XIND; emode <= 2'd1; flags <= {4'd0, fde, 1'b1}; st <= S_FIN; end
                        else if (na) begin X <= {1'b0, ma[63], 1'b1, ma[61:0], 3'd0}; emode <= 2'd1; flags <= {4'd0, fde, !ma[62]}; st <= S_FIN; end
                        else if (ia) begin X <= XINF; emode <= 2'd1; st <= S_FIN; end
                        else if (za) begin X <= 68'd0; st <= S_FIN; end
                    end
                    default: begin sr <= 1'b1; X <= XIND; emode <= 2'd1; flags <= 6'd1; st <= S_FIN; end
                endcase
            end
            // ---- desempacota (normalizando os denormais) ----
            S_UA: begin
                EA <= da ? -18'sd16382 : EA - 18'sd16383; X <= {1'b0, MA[63:0], 3'd0}; nb <= 1'b0; ret <= S_UA2;
                st <= da ? S_NRM : (two && !zb) ? S_UB : S_OP;
            end
            S_UA2: begin MA <= {2'b00, X[66:3]}; st <= (two && !zb) ? S_UB : S_OP; end
            S_UB: begin
                EB <= db ? -18'sd16382 : EB - 18'sd16383; X <= {1'b0, MB[63:0], 3'd0}; nb <= 1'b1; ret <= S_UB2;
                st <= db ? S_NRM : S_OP;
            end
            S_UB2: begin MB <= {2'b00, X[66:3]}; nb <= 1'b0; st <= S_OP; end
            S_OP: begin
                nb <= 1'b0;
                case (op)
                    OP_ADD, OP_SUB: begin
                        if (za) begin X <= {1'b0, MB[63:0], 3'd0}; EA <= EB; st <= S_RP0; end
                        else if (zb) begin X <= {1'b0, MA[63:0], 3'd0}; st <= S_RP0; end
                        else begin ret <= S_AD0; st <= S_C; end
                    end
                    OP_MUL: begin X <= 68'd0; cn <= 7'd64; EA <= EA + EB + 18'sd1; st <= S_ML; end
                    OP_DIV: begin X <= {1'b0, MA[63:0], 3'd0}; MA <= 66'd0; cn <= 7'd66; EA <= EA - EB; st <= S_DV; end
                    OP_SQRT: begin
                        MB <= EA[0] ? {MA[63:0], 2'b00} : {1'b0, MA[63:0], 1'b0}; MA <= 66'd0; X <= 68'd0;
                        EA <= {EA[17], EA[17:1]}; cn <= 7'd65; st <= S_SQ1;
                    end
                    OP_FIST, OP_RND: begin
                        X <= {1'b0, MA[63:0], 3'd0};
                        if (EA >= 18'sd63) begin
                            st <= S_FIN;
                            if (op == OP_FIST) begin
                                X <= XINF; emode <= 2'd2;
                                if (!(EA == 18'sd63 && sa && MA[63:0] == 64'h8000_0000_0000_0000)) flags <= flags | 6'd1;
                            end
                        end else begin cn <= ((18'sd63 - EA) > 18'sd68) ? 7'd68 : (7'd63 - EA[6:0]); ret <= S_RI; st <= S_SHR; end
                    end
                    default: begin X <= {1'b0, MA[63:0], 3'd0}; st <= S_RP0; end
                endcase
            end
            // ---- rotinas: X >> cn (com sticky) e normalizacao a esquerda ----
            S_SHR: begin
                if (cn >= 7'd4) begin X <= {4'd0, X[67:5], |X[4:0]}; cn <= cn - 7'd4; end
                else if (cn != 7'd0) begin X <= {1'b0, X[67:2], |X[1:0]}; cn <= cn - 7'd1; end
                else st <= ret;
            end
            S_NRM: begin
                if (X[66] || X[66:0] == 67'd0) st <= ret;
                else if (X[66:63] == 4'd0) begin X <= {1'b0, X[62:0], 4'd0}; if (nb) EB <= EB - 18'sd4; else EA <= EA - 18'sd4; end
                else begin X <= {1'b0, X[65:0], 1'b0}; if (nb) EB <= EB - 18'sd1; else EA <= EA - 18'sd1; end
            end
            // ---- soma / subtracao ----
            S_AD0: begin
                bigb <= dexp[17] || (dexp == 0 && mlt); subr <= (sa != sbe);
                if (dexp[17] || (dexp == 0 && mlt)) begin X <= {1'b0, MA[63:0], 3'd0}; sr <= sbe; EA <= EB; end
                else begin X <= {1'b0, MB[63:0], 3'd0}; sr <= sa; end
                cn <= (dabs > 18'd68) ? 7'd68 : dabs[6:0]; ret <= S_AD1; st <= S_SHR;
            end
            S_AD1: begin X <= SUM[67:0]; st <= S_AD2; end
            S_AD2: begin
                if (subr && X == 68'd0) begin sr <= (rc == 2'd1); st <= S_FIN; end
                else begin ret <= S_RP1; st <= X[67] ? S_RP0 : S_NRM; end
            end
            // ---- multiplicacao (soma e desloca), divisao e raiz (um bit por clock) ----
            S_ML: begin
                X <= {1'b0, SUM[67:2], SUM[1] | SUM[0]}; MB <= {1'b0, MB[65:1]}; cn <= cn - 7'd1;
                if (cn == 7'd1) begin ret <= S_RP1; st <= S_NRM; end
            end
            S_DV: begin
                X <= ge ? {SUM[66:0], 1'b0} : {X[66:0], 1'b0}; MA <= {MA[64:0], ge}; cn <= cn - 7'd1;
                if (cn == 7'd1) st <= S_DV2;
            end
            S_DV2: begin X <= {1'b0, MA[65:0], (X != 68'd0)}; ret <= S_RP1; st <= S_NRM; end
            S_SQ1: begin
                X <= ge ? SUM[67:0] : srem; MA <= {MA[64:0], ge}; MB <= {MB[63:0], 2'b00}; cn <= cn - 7'd1;
                if (cn == 7'd1) st <= S_SQ2;
            end
            S_SQ2: begin X <= {1'b0, MA[64:0], 1'b0, (X != 68'd0)}; st <= S_RP1; end
            // ---- FIST / RNDINT: arredonda para inteiro ----
            S_RI: begin X <= SUM[67:0] & msk_l; if (inex) flags <= flags | 6'b100000; up <= inc && inex; st <= S_RI2; end
            S_RI2: begin
                st <= S_FIN;
                if (op == OP_FIST) begin
                    emode <= 2'd2;
                    if (!sa && X[66]) begin up <= 1'b0; X <= XINF; flags <= {4'd0, fde, 1'b1}; end
                    else if (sa) st <= S_NEG;
                end else if (X[66:3] != 64'd0) begin EA <= 18'sd63; ret <= S_FIN; st <= S_NRM; end
            end
            S_NEG: begin X <= {1'b0, SUM[66:0]}; st <= S_FIN; end
            // ---- arredonda e empacota ----
            S_RP0: begin if (X[67]) begin X <= {1'b0, X[67:2], |X[1:0]}; EA <= EA + 18'sd1; end st <= S_RP1; end
            S_RP1: begin
                if (EA < emin) begin tiny <= 1'b1; cn <= (dmin > 18'sd68) ? 7'd68 : dmin[6:0]; EA <= emin; ret <= S_RP2; st <= S_SHR; end
                else st <= S_RP2;
            end
            S_RP2: begin X <= SUM[67:0] & msk_l; flags <= flags | {inex, tiny && inex, 4'd0}; up <= inc && inex; st <= S_RP3; end
            S_RP3: begin
                if (X[67]) begin X <= {1'b0, X[67:1]}; EA <= EA + 18'sd1; end
                else if (X[66] && EA > emax) begin
                    up <= inf_r; flags <= flags | 6'b101000; st <= S_FIN;
                    if (inf_r) begin X <= XINF; emode <= 2'd1; end else begin X <= {1'b0, maxm, 3'd0}; EA <= emax; end
                end else st <= S_FIN;
            end
            S_FIN: begin done <= 1'b1; st <= S_IDLE; end
            default: st <= S_IDLE;
        endcase
    end
endmodule
