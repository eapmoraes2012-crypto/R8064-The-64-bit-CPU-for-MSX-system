// fpu_seq.v - nucleo aritmetico COMPACTO da FPU de 80 bits (x87 estendido) do R8064. Mesma interface e mesmos resultados do fpu_alu.v (bit a bit, vetores do
// fpref.py), mas sequencial: um registrador de trabalho de 68 bits, deslocamentos de 16/4/1 bits por clock, raiz bit a bit, e o multiplicador 64x64 e o divisor
// 128/64 ficam FORA (portas mul_* / div_*: no nucleo sao as unidades do modulo 03, as mesmas das instrucoes MLT/DIV).
// Operacoes (op): 0 ADD, 1 SUB, 2 MUL, 3 DIV, 4 SQRT, 5 CMP, 6 FILD(int64), 7 FIST(int64), 8 RNDINT, 9 LD32, 10 LD64, 11 ST32, 12 ST64.
// a = ST0 (ou dado de memoria), b = segundo operando; a, b, op, rc e pc devem ficar ESTAVEIS de 'start' ate 'done' (nao sao registrados aqui).
// rc: 0 mais proximo/par, 1 -inf, 2 +inf, 3 zero. pc: 0 = 24, 2 = 53, outros = 64 bits (so ADD/SUB/MUL/DIV/SQRT).
// Saidas (validas a partir de 'done', ate o proximo 'start'): res, flags {PE,UE,OE,ZE,DE,IE}, up (arredondou para cima = C1), cc {c3,c2,c0} (so CMP).
// Registrador X: [67] vai-um, [66:3] significando (bit 66 = bit inteiro), [2] guarda, [1] arredondamento, [0] "sticky".
module fpu_seq(
    input  wire        clk, rst, start,
    input  wire [3:0]  op,
    input  wire [1:0]  rc, pc,
    input  wire [79:0] a, b,
    output wire        busy,
    output reg         done,
    output reg  [79:0] res,
    output reg  [5:0]  flags,
    output reg         up,
    output reg  [2:0]  cc,
    output reg         mul_go,
    output wire [63:0] mul_a, mul_b,
    input  wire        mul_dn,
    input  wire [127:0] mul_p,
    output reg         div_go,
    output wire [63:0] div_hi, div_lo, div_d,
    input  wire        div_dn,
    input  wire [63:0] div_q, div_r
);
    localparam OP_ADD = 0, OP_SUB = 1, OP_MUL = 2, OP_DIV = 3, OP_SQRT = 4, OP_CMP = 5, OP_FILD = 6, OP_FIST = 7, OP_RND = 8, OP_LD32 = 9, OP_LD64 = 10, OP_ST32 = 11, OP_ST64 = 12;
    localparam [79:0] INDEF = {1'b1, 15'h7FFF, 64'hC000_0000_0000_0000};
    localparam [4:0] S_IDLE = 0, S_DEC = 1, S_UA = 2, S_UA2 = 3, S_UB = 4, S_UB2 = 5, S_OP = 6, S_SHR = 7, S_NRM = 8, S_AD1 = 9, S_AD2 = 10, S_ML1 = 11, S_DV1 = 12,
                     S_SQ1 = 13, S_SQ2 = 14, S_RI = 15, S_RI2 = 16, S_RP0 = 17, S_RP1 = 18, S_RP2 = 19, S_RP3 = 20, S_PK = 21, S_FIN = 22;
    reg [4:0] st, ret;
    reg [67:0] X; reg [64:0] MA; reg [65:0] MB; reg signed [17:0] EA, EB; reg [6:0] cn;
    reg sr, nb, subr, bigb, tiny;
    assign busy = (st != S_IDLE);
    // ---- classificacao (combinacional sobre as entradas estaveis) ----
    wire sa = a[79], sb = b[79]; wire [14:0] xa = a[78:64], xb = b[78:64]; wire [63:0] ma = a[63:0], mb = b[63:0];
    wire za = (xa == 0) && (ma == 0), zb = (xb == 0) && (mb == 0);
    wire da = (xa == 0) && !ma[63] && (ma != 0), db = (xb == 0) && !mb[63] && (mb != 0);
    wire ua = (xa == 0) ? ma[63] : !ma[63], ub = (xb == 0) ? mb[63] : !mb[63];
    wire ia = (xa == 15'h7FFF) && ma[63] && (ma[62:0] == 0), ib = (xb == 15'h7FFF) && mb[63] && (mb[62:0] == 0);
    wire na = (xa == 15'h7FFF) && ma[63] && (ma[62:0] != 0), nbn = (xb == 15'h7FFF) && mb[63] && (mb[62:0] != 0);
    wire two = (op == OP_ADD) || (op == OP_SUB) || (op == OP_MUL) || (op == OP_DIV) || (op == OP_CMP);
    wire one = (op == OP_SQRT) || (op == OP_FIST) || (op == OP_RND) || (op == OP_ST32) || (op == OP_ST64);
    wire ari = (op == OP_ADD) || (op == OP_SUB) || (op == OP_MUL) || (op == OP_DIV) || (op == OP_SQRT) || (op == OP_RND);
    wire fde = (one && da) || (two && (da || db));
    wire sbe = sb ^ (op == OP_SUB);
    wire u_any = ua || (two && ub), n_any = na || (two && nbn);
    wire [63:0] qa = ma | 64'h4000_0000_0000_0000, qb = mb | 64'h4000_0000_0000_0000;
    wire pick_b = two && nbn && (!na || (qb > qa));
    wire [79:0] nanres = pick_b ? {sb, 15'h7FFF, qb} : {sa, 15'h7FFF, qa};
    wire nan_ie = (na && !ma[62]) || (two && nbn && !mb[62]);
    wire mag_gt = {xa, ma} > {xb, mb}, mag_eq = {xa, ma} == {xb, mb};
    // formatos de memoria (LD32 / LD64)
    wire l64 = (op == OP_LD64);
    wire ls = l64 ? a[63] : a[31]; wire [10:0] le = l64 ? a[62:52] : {3'd0, a[30:23]}; wire [51:0] lf = l64 ? a[51:0] : {a[22:0], 29'd0};   // fracao alinhada a esquerda
    wire le_max = l64 ? (le == 11'h7FF) : (le[7:0] == 8'hFF), le_z = (le == 0), lf_z = (lf == 0);
    // ---- parametros do arredondamento ----
    wire [1:0] psel = (op == OP_ST32) ? 2'd0 : (op == OP_ST64) ? 2'd1 : (op == OP_FIST || op == OP_RND) ? 2'd2 : (pc == 2'd0) ? 2'd0 : (pc == 2'd2) ? 2'd1 : 2'd2;
    wire signed [17:0] emin = (op == OP_ST32) ? -18'sd126 : (op == OP_ST64) ? -18'sd1022 : -18'sd16382;
    wire signed [17:0] emax = (op == OP_ST32) ? 18'sd127 : (op == OP_ST64) ? 18'sd1023 : 18'sd16383;
    wire rb  = (psel == 2'd0) ? X[42] : (psel == 2'd1) ? X[13] : X[2];
    wire stk = (psel == 2'd0) ? |X[41:0] : (psel == 2'd1) ? |X[12:0] : |X[1:0];
    wire lsb = (psel == 2'd0) ? X[43] : (psel == 2'd1) ? X[14] : X[3];
    wire inex = rb | stk;
    wire inc = (rc == 2'd0) ? (rb && (stk || lsb)) : (rc == 2'd1) ? (inex && sr) : (rc == 2'd2) ? (inex && !sr) : 1'b0;
    wire [67:0] one_l = (psel == 2'd0) ? (68'd1 << 43) : (psel == 2'd1) ? (68'd1 << 14) : (68'd1 << 3);
    wire [67:0] msk_l = (psel == 2'd0) ? {25'h1FFFFFF, 43'd0} : (psel == 2'd1) ? {54'h3FFFFFFFFFFFFF, 14'd0} : {65'h1FFFFFFFFFFFFFFFF, 3'd0};
    wire [67:0] xrnd = (X + (inc ? one_l : 68'd0)) & msk_l;
    wire [63:0] maxm = (psel == 2'd0) ? {24'hFFFFFF, 40'd0} : (psel == 2'd1) ? {53'h1FFFFFFFFFFFFF, 11'd0} : 64'hFFFF_FFFF_FFFF_FFFF;
    wire inf_r = (rc == 2'd0) || (rc == 2'd2 && !sr) || (rc == 2'd1 && sr);
    // ---- soma / comparacoes ----
    wire signed [17:0] dexp = EA - EB;
    wire m_lt = MA[63:0] < MB[63:0];
    wire [17:0] dabs = dexp[17] ? -dexp : dexp;
    wire [67:0] bigx = bigb ? {1'b0, MB[63:0], 3'd0} : {1'b0, MA[63:0], 3'd0};
    wire signed [17:0] dmin = emin - EA;
    // divisao: quociente de 64 bits com o bit 63 = 1, mais um bit de guarda tirado do resto
    wire dge = MA[63:0] >= MB[63:0];
    assign div_hi = dge ? {1'b0, MA[63:1]} : MA[63:0]; assign div_lo = dge ? {MA[0], 63'd0} : 64'd0; assign div_d = MB[63:0];
    assign mul_a = MA[63:0]; assign mul_b = MB[63:0];
    wire [65:0] dt = {1'b0, div_r, 1'b0} - {2'b00, MB[63:0]};
    wire dg = !dt[65]; wire drz = dg ? (dt == 0) : (div_r == 0);
    // raiz: um bit por clock (X = resto, MA = raiz, MB = radicando saindo de 2 em 2 bits)
    wire [67:0] srem = {X[65:0], MB[65:64]}; wire [67:0] stri = {1'b0, MA[64:0], 2'b01}; wire sge = srem >= stri;
    wire [63:0] iabs = a[63] ? (~a[63:0] + 64'd1) : a[63:0];
    wire [63:0] kneg = ~X[66:3] + 64'd1;
    wire [17:0] ebias = EA + 18'd16383, e64 = EA + 18'd1023, e32 = EA + 18'd127;
    task fin(input [79:0] r, input [5:0] f); begin res <= r; flags <= f; st <= S_FIN; end endtask
    always @(posedge clk) begin
        mul_go <= 1'b0; div_go <= 1'b0; done <= 1'b0;
        if (rst) begin st <= S_IDLE; done <= 1'b0; res <= 0; flags <= 0; up <= 0; cc <= 0; end
        else case (st)
            S_IDLE: if (start) begin st <= S_DEC; up <= 1'b0; cc <= 3'd0; flags <= 6'd0; tiny <= 1'b0; nb <= 1'b0; end
            S_DEC: begin
                flags <= {4'd0, fde, 1'b0}; sr <= sa; st <= S_UA;
                if (ari && u_any) fin(INDEF, {4'd0, fde, 1'b1});
                else if (ari && n_any) fin(nanres, {4'd0, fde, nan_ie});
                else case (op)
                    OP_ADD, OP_SUB: begin
                        if (ia && ib) begin if (sa != sbe) fin(INDEF, {4'd0, fde, 1'b1}); else fin({sa, 15'h7FFF, 64'h8000_0000_0000_0000}, {4'd0, fde, 1'b0}); end
                        else if (ia) fin({sa, 15'h7FFF, 64'h8000_0000_0000_0000}, {4'd0, fde, 1'b0});
                        else if (ib) fin({sbe, 15'h7FFF, 64'h8000_0000_0000_0000}, {4'd0, fde, 1'b0});
                        else if (za && zb) fin({(sa == sbe) ? sa : (rc == 2'd1), 79'd0}, {4'd0, fde, 1'b0});
                        else if (za) begin sr <= sbe; st <= S_UB; end
                    end
                    OP_MUL: begin
                        sr <= sa ^ sb;
                        if ((ia && zb) || (za && ib)) fin(INDEF, {4'd0, fde, 1'b1});
                        else if (ia || ib) fin({sa ^ sb, 15'h7FFF, 64'h8000_0000_0000_0000}, {4'd0, fde, 1'b0});
                        else if (za || zb) fin({sa ^ sb, 79'd0}, {4'd0, fde, 1'b0});
                    end
                    OP_DIV: begin
                        sr <= sa ^ sb;
                        if ((ia && ib) || (za && zb)) fin(INDEF, {4'd0, fde, 1'b1});
                        else if (zb) fin({sa ^ sb, 15'h7FFF, 64'h8000_0000_0000_0000}, {3'd0, 1'b1, fde, 1'b0});
                        else if (ia) fin({sa ^ sb, 15'h7FFF, 64'h8000_0000_0000_0000}, {4'd0, fde, 1'b0});
                        else if (ib || za) fin({sa ^ sb, 79'd0}, {4'd0, fde, 1'b0});
                    end
                    OP_SQRT: begin
                        sr <= 1'b0;
                        if (za) fin({sa, 79'd0}, {4'd0, fde, 1'b0});
                        else if (sa) fin(INDEF, {4'd0, fde, 1'b1});
                        else if (ia) fin({1'b0, 15'h7FFF, 64'h8000_0000_0000_0000}, {4'd0, fde, 1'b0});
                    end
                    OP_CMP: begin
                        if (ua || ub || na || nbn) begin cc <= 3'd7; fin(80'd0, {4'd0, fde, 1'b1}); end
                        else begin
                            cc <= ((za && zb) || (sa == sb && mag_eq)) ? 3'd4 : (sa != sb) ? {2'b00, sa} : {2'b00, mag_gt ? sa : !sa};
                            fin(80'd0, {4'd0, fde, 1'b0});
                        end
                    end
                    OP_FILD: begin
                        if (a[63:0] == 0) fin(80'd0, 6'd0);
                        else begin X <= {1'b0, iabs, 3'd0}; EA <= 18'sd63; sr <= a[63]; ret <= S_PK; st <= S_NRM; end
                    end
                    OP_FIST: begin
                        if (ua || na || ia) fin({16'd0, 64'h8000_0000_0000_0000}, {4'd0, fde, 1'b1});
                        else if (za) fin(80'd0, {4'd0, fde, 1'b0});
                    end
                    OP_RND: if (ia || za) fin(a, {4'd0, fde, 1'b0});
                    OP_LD32, OP_LD64: begin
                        flags <= 6'd0; sr <= ls;
                        if (le_max) begin
                            if (lf_z) fin({ls, 15'h7FFF, 64'h8000_0000_0000_0000}, 6'd0);
                            else fin({ls, 15'h7FFF, 2'b11, lf[50:0], 11'd0}, {5'd0, !lf[51]});
                        end else if (le_z && lf_z) fin({ls, 79'd0}, 6'd0);
                        else if (le_z) begin X <= {2'b00, lf, 14'd0}; EA <= l64 ? -18'sd1022 : -18'sd126; flags <= 6'b000010; ret <= S_PK; st <= S_NRM; end
                        else begin X <= {2'b01, lf, 14'd0}; EA <= $signed({7'd0, le}) - (l64 ? 18'sd1023 : 18'sd127); st <= S_PK; end
                    end
                    OP_ST32, OP_ST64: begin
                        if (ua) fin((op == OP_ST32) ? {48'd0, 32'hFFC0_0000} : {16'd0, 64'hFFF8_0000_0000_0000}, {4'd0, fde, 1'b1});
                        else if (na) fin((op == OP_ST32) ? {48'd0, sa, 8'hFF, 1'b1, ma[61:40]} : {16'd0, sa, 11'h7FF, 1'b1, ma[61:11]}, {4'd0, fde, !ma[62]});
                        else if (ia) fin((op == OP_ST32) ? {48'd0, sa, 8'hFF, 23'd0} : {16'd0, sa, 11'h7FF, 52'd0}, {4'd0, fde, 1'b0});
                        else if (za) fin((op == OP_ST32) ? {48'd0, sa, 31'd0} : {16'd0, sa, 63'd0}, {4'd0, fde, 1'b0});
                    end
                    default: fin(INDEF, 6'd1);
                endcase
            end
            // ---- desempacota (normalizando os denormais) ----
            S_UA: begin X <= {1'b0, ma, 3'd0}; EA <= da ? -18'sd16382 : $signed({3'd0, xa}) - 18'sd16383; nb <= 1'b0; ret <= S_UA2; st <= da ? S_NRM : S_UA2; end
            S_UA2: begin MA <= {1'b0, X[66:3]}; st <= (two && !zb) ? S_UB : S_OP; end
            S_UB: begin X <= {1'b0, mb, 3'd0}; EB <= db ? -18'sd16382 : $signed({3'd0, xb}) - 18'sd16383; nb <= 1'b1; ret <= S_UB2; st <= db ? S_NRM : S_UB2; end
            S_UB2: begin MB <= {2'b00, X[66:3]}; nb <= 1'b0; st <= S_OP; end
            S_OP: case (op)
                OP_ADD, OP_SUB: begin
                    if (za) begin EA <= EB; st <= S_RP0; end                                       // 0 + b: X ja tem b
                    else if (zb) begin X <= {1'b0, MA[63:0], 3'd0}; st <= S_RP0; end                  // a + 0
                    else begin
                        bigb <= dexp[17] || (dexp == 0 && m_lt); subr <= (sa != sbe);
                        if (dexp[17] || (dexp == 0 && m_lt)) begin X <= {1'b0, MA[63:0], 3'd0}; sr <= sbe; EA <= EB; end
                        else begin X <= {1'b0, MB[63:0], 3'd0}; sr <= sa; end
                        cn <= (dabs > 18'd68) ? 7'd68 : dabs[6:0]; ret <= S_AD1; st <= S_SHR;
                    end
                end
                OP_MUL: begin mul_go <= 1'b1; EA <= EA + EB + 18'sd1; st <= S_ML1; end
                OP_DIV: begin div_go <= 1'b1; EA <= dge ? (EA - EB) : (EA - EB - 18'sd1); st <= S_DV1; end
                OP_SQRT: begin
                    MB <= EA[0] ? {MA[63:0], 2'b00} : {1'b0, MA[63:0], 1'b0}; MA <= 65'd0; X <= 68'd0;
                    EA <= {EA[17], EA[17:1]}; cn <= 7'd65; st <= S_SQ1;
                end
                OP_FIST, OP_RND: begin
                    X <= {1'b0, MA[63:0], 3'd0};
                    if (EA >= 18'sd63) begin
                        if (op == OP_RND) fin(a, flags);
                        else if (EA == 18'sd63 && sa && MA[63:0] == 64'h8000_0000_0000_0000) fin({16'd0, 64'h8000_0000_0000_0000}, flags);
                        else fin({16'd0, 64'h8000_0000_0000_0000}, flags | 6'd1);
                    end else begin cn <= ((18'sd63 - EA) > 18'sd68) ? 7'd68 : (7'd63 - EA[6:0]); ret <= S_RI; st <= S_SHR; end
                end
                default: begin X <= {1'b0, MA[63:0], 3'd0}; st <= S_RP0; end                           // ST32 / ST64
            endcase
            // ---- rotinas: X >> cn (com sticky) e normalizacao a esquerda ----
            S_SHR: begin
                if (cn >= 7'd16) begin X <= {16'd0, X[67:17], |X[16:0]}; cn <= cn - 7'd16; end
                else if (cn >= 7'd4) begin X <= {4'd0, X[67:5], |X[4:0]}; cn <= cn - 7'd4; end
                else if (cn != 7'd0) begin X <= {1'b0, X[67:2], |X[1:0]}; cn <= cn - 7'd1; end
                else st <= ret;
            end
            S_NRM: begin
                if (X[66] || X[66:0] == 67'd0) st <= ret;
                else if (X[66:51] == 16'd0) begin X <= {1'b0, X[50:0], 16'd0}; if (nb) EB <= EB - 18'sd16; else EA <= EA - 18'sd16; end
                else if (X[66:63] == 4'd0) begin X <= {1'b0, X[62:0], 4'd0}; if (nb) EB <= EB - 18'sd4; else EA <= EA - 18'sd4; end
                else begin X <= {1'b0, X[65:0], 1'b0}; if (nb) EB <= EB - 18'sd1; else EA <= EA - 18'sd1; end
            end
            // ---- soma / subtracao ----
            S_AD1: begin X <= subr ? (bigx - X) : (bigx + X); st <= S_AD2; end
            S_AD2: begin
                if (subr && X == 68'd0) fin({(rc == 2'd1), 79'd0}, flags);
                else begin ret <= S_RP1; st <= X[67] ? S_RP0 : S_NRM; end
            end
            S_ML1: if (mul_dn) begin X <= {1'b0, mul_p[127:62], |mul_p[61:0]}; ret <= S_RP1; st <= S_NRM; end
            S_DV1: if (div_dn) begin X <= {1'b0, div_q, dg, 1'b0, !drz}; st <= S_RP1; end
            S_SQ1: begin
                X <= sge ? (srem - stri) : srem; MA <= {MA[63:0], sge}; MB <= {MB[63:0], 2'b00}; cn <= cn - 7'd1;
                if (cn == 7'd1) st <= S_SQ2;
            end
            S_SQ2: begin X <= {1'b0, MA[64:0], 1'b0, (X != 68'd0)}; st <= S_RP1; end
            // ---- FIST / RNDINT: arredonda para inteiro ----
            S_RI: begin X <= xrnd; if (inex) flags <= flags | 6'b100000; up <= inc && inex; st <= S_RI2; end
            S_RI2: begin
                if (op == OP_FIST) begin
                    if (!sa && X[66]) begin up <= 1'b0; fin({16'd0, 64'h8000_0000_0000_0000}, {4'd0, fde, 1'b1}); end
                    else fin({16'd0, sa ? kneg : X[66:3]}, flags);
                end else if (X[66:3] == 64'd0) fin({sa, 79'd0}, flags);
                else begin EA <= 18'sd63; ret <= S_PK; st <= S_NRM; end
            end
            // ---- arredonda e empacota ----
            S_RP0: begin if (X[67]) begin X <= {1'b0, X[67:2], |X[1:0]}; EA <= EA + 18'sd1; end st <= S_RP1; end
            S_RP1: begin
                if (EA < emin) begin tiny <= 1'b1; cn <= (dmin > 18'sd68) ? 7'd68 : dmin[6:0]; EA <= emin; ret <= S_RP2; st <= S_SHR; end
                else st <= S_RP2;
            end
            S_RP2: begin X <= xrnd; flags <= flags | {inex, tiny && inex, 4'd0}; up <= inc && inex; st <= S_RP3; end
            S_RP3: begin
                if (X[67]) begin X <= {1'b0, X[67:1]}; EA <= EA + 18'sd1; end
                else if (X[66:3] == 64'd0) fin((op == OP_ST32) ? {48'd0, sr, 31'd0} : (op == OP_ST64) ? {16'd0, sr, 63'd0} : {sr, 79'd0}, flags);
                else if (X[66] && EA > emax) begin
                    up <= inf_r;
                    if (inf_r) fin((op == OP_ST32) ? {48'd0, sr, 8'hFF, 23'd0} : (op == OP_ST64) ? {16'd0, sr, 11'h7FF, 52'd0} : {sr, 15'h7FFF, 64'h8000_0000_0000_0000}, flags | 6'b101000);
                    else fin((op == OP_ST32) ? {48'd0, sr, 8'hFE, 23'h7FFFFF} : (op == OP_ST64) ? {16'd0, sr, 11'h7FE, 52'hFFFFFFFFFFFFF} : {sr, 15'h7FFE, maxm}, flags | 6'b101000);
                end else st <= S_PK;
            end
            S_PK: begin
                if (op == OP_ST32) res <= {48'd0, sr, X[66] ? e32[7:0] : 8'd0, X[65:43]};
                else if (op == OP_ST64) res <= {16'd0, sr, X[66] ? e64[10:0] : 11'd0, X[65:14]};
                else res <= {sr, X[66] ? ebias[14:0] : 15'd0, X[66:3]};
                st <= S_FIN;
            end
            S_FIN: begin done <= 1'b1; st <= S_IDLE; end
            default: st <= S_IDLE;
        endcase
    end
endmodule
