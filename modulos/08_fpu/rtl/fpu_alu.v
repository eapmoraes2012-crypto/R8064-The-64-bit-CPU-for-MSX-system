// fpu_alu.v - nucleo aritmetico da FPU de 80 bits (x87 estendido) do R8064.
// Operacoes (op): 0 ADD, 1 SUB, 2 MUL, 3 DIV, 4 SQRT, 5 CMP, 6 FILD(int64), 7 FIST(int64), 8 RNDINT, 9 LD32, 10 LD64, 11 ST32, 12 ST64.
// a = ST0 (ou dado de memoria), b = segundo operando. rc: 0 nearest-even, 1 -inf, 2 +inf, 3 zero. pc: 0=24, 2=53, 3=64 bits (so ADD/SUB/MUL/DIV/SQRT).
// Resultado: res, flags {PE,UE,OE,ZE,DE,IE}, up (arredondou para cima = C1), cc {c3,c2,c0} (so CMP). Excecoes mascaradas = resposta padrao; quem mascara/propaga e a pilha (fpu_top).
module fpu_alu(
    input  wire        clk, rst, start,
    input  wire [3:0]  op,
    input  wire [1:0]  rc, pc,
    input  wire [79:0] a, b,
    output wire        busy,
    output reg         done,
    output reg  [79:0] res,
    output reg  [5:0]  flags,
    output reg         up,
    output reg  [2:0]  cc
);
    localparam OP_ADD = 0, OP_SUB = 1, OP_MUL = 2, OP_DIV = 3, OP_SQRT = 4, OP_CMP = 5, OP_FILD = 6, OP_FIST = 7, OP_RND = 8, OP_LD32 = 9, OP_LD64 = 10, OP_ST32 = 11, OP_ST64 = 12;
    localparam C_ZERO = 0, C_NORM = 1, C_DEN = 2, C_INF = 3, C_QNAN = 4, C_SNAN = 5, C_UNS = 6;
    localparam [5:0] S_IDLE = 0, S_U1 = 1, S_U2 = 2, S_OP = 3, S_FIN = 4,
        S_AD1 = 5, S_AD2 = 6, S_AD3 = 7, S_AD4 = 8, S_AD5 = 9,
        S_ML0 = 10, S_ML1 = 11, S_ML2 = 12, S_DV0 = 13, S_DV1 = 14, S_DV2 = 15,
        S_SQ0 = 16, S_SQ1 = 17, S_SQ2 = 18, S_CMP = 19,
        S_TI1 = 20, S_TI2 = 21, S_TI3 = 22, S_CV0 = 23, S_CV1 = 24, S_CV2 = 25,
        S_STL = 26, S_R1 = 27, S_R2 = 28, S_R3 = 29, S_DV3 = 30, S_U3 = 31, S_U4 = 32, S_TI0 = 33, S_CV3 = 34, S_AD0 = 35, S_TI4 = 36, S_AD4B = 37, S_AD4A = 38, S_CV2A = 39, S_CV4 = 40, S_U5 = 41, S_U6 = 42, S_U7 = 43, S_U8 = 44, S_SP = 45, S_AD4C = 46, S_CV5 = 47, S_AD2W = 48, S_TI1W = 49, S_R1W = 50, S_R1V = 51, S_CVP = 52;
    reg [67:0] sh_in; reg [6:0] sh_amt; reg [67:0] lf_in; reg [6:0] lf_amt;
    reg r_tiny0;
    reg c32_fz, c32_z, c32_e0, c32_ff, c64_fz, c64_z, c64_e0, c64_ff, c_z64;
    reg [16:0] nz; reg [33:0] nl;
    integer ni;
    always @(posedge clk) for (ni = 0; ni < 17; ni = ni + 1) begin
        nz[ni] <= (lf_in[67-4*ni -: 4] == 4'd0);
        nl[2*ni +: 2] <= lf_in[67-4*ni] ? 2'd0 : lf_in[66-4*ni] ? 2'd1 : lf_in[65-4*ni] ? 2'd2 : 2'd3;
    end
    reg [7:0] lz_nb;
    always @* begin : lzsel
        integer j; reg found;
        lz_nb = 8'd68; found = 1'b0;
        for (j = 0; j < 17; j = j + 1) if (!found && !nz[j]) begin lz_nb = 4*j + nl[2*j +: 2]; found = 1'b1; end
    end

    localparam signed [17:0] EMIN80 = -18'sd16382, EMAX80 = 18'sd16383;
    reg [5:0] st;
    assign busy = (st != S_IDLE);
    reg [3:0] op_r; reg [1:0] rc_r, pc_r; reg [79:0] A_r, B_r;
    reg f_ie, f_de, f_ze, f_oe, f_ue, f_pe, f_up;
    // ---------------- decodificacao
    function [2:0] cls(input [79:0] x);
        reg [14:0] ex; reg [63:0] m;
        begin
            ex = x[78:64]; m = x[63:0];
            if (ex == 0) cls = (m == 0) ? C_ZERO : m[63] ? C_UNS : C_DEN;
            else if (ex == 15'h7FFF) cls = !m[63] ? C_UNS : (m[62:0] == 0) ? C_INF : m[62] ? C_QNAN : C_SNAN;
            else cls = m[63] ? C_NORM : C_UNS;
        end
    endfunction
    function [6:0] lzc64(input [63:0] x);
        reg [63:0] y; reg [6:0] n;
        begin
            y = x; n = 0;
            if (y[63:32] == 0) begin n = n + 32; y = y << 32; end
            if (y[63:48] == 0) begin n = n + 16; y = y << 16; end
            if (y[63:56] == 0) begin n = n + 8;  y = y << 8;  end
            if (y[63:60] == 0) begin n = n + 4;  y = y << 4;  end
            if (y[63:62] == 0) begin n = n + 2;  y = y << 2;  end
            if (y[63] == 0)    begin n = n + 1;  y = y << 1;  end
            lzc64 = (!y[63]) ? 7'd64 : n;
        end
    endfunction
    function [7:0] lzc68(input [67:0] x);
        reg [6:0] t;
        begin
            if (x[67:4] != 0) lzc68 = {1'b0, lzc64(x[67:4])};
            else if (x[3]) lzc68 = 8'd64; else if (x[2]) lzc68 = 8'd65; else if (x[1]) lzc68 = 8'd66; else if (x[0]) lzc68 = 8'd67; else lzc68 = 8'd68;
        end
    endfunction
    reg [2:0] a_c, b_c; reg a_s, b_s; reg [63:0] a_m, b_m; reg signed [17:0] a_E, b_E; reg [6:0] a_lz, b_lz;
    wire a_nan = (a_c == C_QNAN) || (a_c == C_SNAN), b_nan = (b_c == C_QNAN) || (b_c == C_SNAN);
    // ---------------- deslocadores compartilhados (carregados no estado anterior, consumidos no seguinte)
    function [67:0] shr_st(input [67:0] x, input [6:0] n);
        reg [67:0] y; reg st1;
        begin
            y = x; st1 = 0;
            if (n[6]) begin st1 = st1 | (|y[63:0]); y = y >> 64; end
            if (n[5]) begin st1 = st1 | (|y[31:0]); y = y >> 32; end
            if (n[4]) begin st1 = st1 | (|y[15:0]); y = y >> 16; end
            if (n[3]) begin st1 = st1 | (|y[7:0]);  y = y >> 8;  end
            if (n[2]) begin st1 = st1 | (|y[3:0]);  y = y >> 4;  end
            if (n[1]) begin st1 = st1 | (|y[1:0]);  y = y >> 2;  end
            if (n[0]) begin st1 = st1 | y[0];       y = y >> 1;  end
            shr_st = {y[67:1], y[0] | st1};
        end
    endfunction
    wire [67:0] sh_o = shr_st(sh_in, sh_amt);
    reg [67:0] sh_out; always @(posedge clk) sh_out <= sh_o;
    wire [67:0] lf_out  = lf_in << lf_amt;
    reg [67:0] lf_r; always @(posedge clk) lf_r <= lf_out;
    // ---------------- arredondamento (R1..R3)
    reg r_s; reg signed [17:0] r_E, r_emin, r_emax; reg [63:0] r_m; reg r_g, r_st; reg [6:0] r_p; reg [1:0] r_fmt, r_rc;
    reg [65:0] r1_F; reg signed [17:0] r1_E; reg r1_tiny;
    reg [63:0] r2_m; reg signed [17:0] r2_E; reg r2_inex, r2_inc, r2_tiny;
    // ---------------- soma
    reg ad_ssub, ad_bs; reg signed [17:0] ad_bE; reg [63:0] ad_bm, ad_sm; reg [7:0] ad_d; reg [66:0] ad_x; reg [67:0] ad_sum; reg [7:0] ad_lz; reg ad_sign;
    // ---------------- mul / div
    reg mu_in; wire mu_ready, mu_ov; wire [127:0] mu_p; reg [127:0] ml_p;
    mul_unit u_mul(.clk(clk), .rst(rst), .in_valid(mu_in), .sz(2'd3), .sgn(1'b0), .a(a_m), .b(b_m), .ready(mu_ready), .out_valid(mu_ov), .prod(mu_p));
    reg dv_start; wire dv_busy, dv_done, dv_err; wire [63:0] dv_q, dv_r; reg [63:0] dv_hi, dv_lo; reg dv_ge; reg [63:0] dq, dr;
    div_unit u_div(.clk(clk), .rst(rst), .start(dv_start), .sz(2'd3), .sgn(1'b0), .hi(dv_hi), .lo(dv_lo), .d(b_m), .busy(dv_busy), .done(dv_done), .q(dv_q), .r(dv_r), .err(dv_err));
    // ---------------- raiz
    reg [129:0] sq_rad; reg [66:0] sq_rem; reg [64:0] sq_q; reg [6:0] sq_cnt;
    wire [66:0] sq_rn = {sq_rem[64:0], sq_rad[129:128]};
    wire [66:0] sq_tr = {sq_q, 2'b01};
    wire [67:0] sq_df = {1'b0, sq_rn} - {1'b0, sq_tr};
    wire        sq_ge = !sq_df[67];
    // ---------------- conversao inteiro/float, para inteiro
    reg cv_s; reg [63:0] cv_mag; reg signed [17:0] cv_bias; reg [6:0] cv_lz; reg cv_rnd; // cv_rnd: veio de RNDINT
    reg [63:0] ti_I; reg ti_rb, ti_st; reg [64:0] ti_k; reg ti_inex, ti_inc, ti_ovfI;
    // ---------------- comparacao e especiais
    reg spr; reg [79:0] sp_resr; reg [5:0] sp_flr; reg [2:0] sp_ccr;
    reg sp; reg [79:0] sp_res; reg [5:0] sp_fl; reg [2:0] sp_cc;
    wire [79:0] indef = {1'b1, 15'h7FFF, 64'hC000000000000000};
    wire [79:0] qa = {a_s, 15'h7FFF, a_m | 64'h4000000000000000};
    wire [79:0] qb = {b_s, 15'h7FFF, b_m | 64'h4000000000000000};
    wire        pickb = b_nan && (!a_nan || ((b_m | 64'h4000000000000000) > (a_m | 64'h4000000000000000)));
    wire [79:0] qsel = pickb ? qb : qa;
    wire        bsgn = (op_r == OP_SUB) ? ~b_s : b_s;
    wire        two = (op_r == OP_ADD) || (op_r == OP_SUB) || (op_r == OP_MUL) || (op_r == OP_DIV) || (op_r == OP_CMP);
    wire        a_den = (a_c == C_DEN), b_den = two && (b_c == C_DEN);
    wire        ieee_op = (op_r == OP_ST32) || (op_r == OP_ST64);
    wire [31:0] ind32 = 32'hFFC00000; wire [63:0] ind64 = 64'hFFF8000000000000;
    always @* begin
        sp = 0; sp_res = 0; sp_fl = 0; sp_cc = 0;
        if (a_den || b_den) sp_fl = sp_fl | 6'd2;
        case (op_r)
        OP_ADD, OP_SUB, OP_MUL, OP_DIV: begin
            if (a_c == C_UNS || b_c == C_UNS) begin sp = 1; sp_res = indef; sp_fl[0] = 1; end
            else if (a_nan || b_nan) begin sp = 1; sp_res = qsel; sp_fl[0] = ((a_c == C_SNAN) || (b_c == C_SNAN)); end
            else case (op_r)
              OP_ADD, OP_SUB: begin
                if (a_c == C_INF && b_c == C_INF) begin sp = 1; if (a_s != bsgn) begin sp_res = indef; sp_fl[0] = 1; end else sp_res = {a_s, 15'h7FFF, 64'h8000000000000000}; end
                else if (a_c == C_INF) begin sp = 1; sp_res = {a_s, 15'h7FFF, 64'h8000000000000000}; end
                else if (b_c == C_INF) begin sp = 1; sp_res = {bsgn, 15'h7FFF, 64'h8000000000000000}; end
                else if (a_c == C_ZERO && b_c == C_ZERO) begin sp = 1; sp_res = {(a_s == bsgn) ? a_s : (rc_r == 2'd1), 79'd0}; end
              end
              OP_MUL: begin
                if ((a_c == C_INF && b_c == C_ZERO) || (a_c == C_ZERO && b_c == C_INF)) begin sp = 1; sp_res = indef; sp_fl[0] = 1; end
                else if (a_c == C_INF || b_c == C_INF) begin sp = 1; sp_res = {a_s ^ b_s, 15'h7FFF, 64'h8000000000000000}; end
                else if (a_c == C_ZERO || b_c == C_ZERO) begin sp = 1; sp_res = {a_s ^ b_s, 79'd0}; end
              end
              default: begin // DIV
                if ((a_c == C_INF && b_c == C_INF) || (a_c == C_ZERO && b_c == C_ZERO)) begin sp = 1; sp_res = indef; sp_fl[0] = 1; end
                else if (b_c == C_ZERO) begin sp = 1; sp_res = {a_s ^ b_s, 15'h7FFF, 64'h8000000000000000}; sp_fl[2] = 1; end
                else if (a_c == C_INF) begin sp = 1; sp_res = {a_s ^ b_s, 15'h7FFF, 64'h8000000000000000}; end
                else if (b_c == C_INF || a_c == C_ZERO) begin sp = 1; sp_res = {a_s ^ b_s, 79'd0}; end
              end
            endcase
        end
        OP_SQRT: begin
            if (a_c == C_UNS) begin sp = 1; sp_res = indef; sp_fl[0] = 1; end
            else if (a_nan) begin sp = 1; sp_res = qa; sp_fl[0] = (a_c == C_SNAN); end
            else if (a_c == C_ZERO) begin sp = 1; sp_res = {a_s, 79'd0}; end
            else if (a_s) begin sp = 1; sp_res = indef; sp_fl[0] = 1; end
            else if (a_c == C_INF) begin sp = 1; sp_res = {1'b0, 15'h7FFF, 64'h8000000000000000}; end
        end
        OP_CMP: begin
            if (a_c == C_UNS || b_c == C_UNS || a_nan || b_nan) begin sp = 1; sp_fl[0] = 1; sp_cc = 3'b111; end
        end
        OP_FIST: begin
            if (a_c == C_UNS || a_nan || a_c == C_INF) begin sp = 1; sp_res = 80'h8000000000000000; sp_fl[0] = 1; end
            else if (a_c == C_ZERO) begin sp = 1; sp_res = 0; end
        end
        OP_RND: begin
            if (a_c == C_UNS) begin sp = 1; sp_res = indef; sp_fl[0] = 1; end
            else if (a_nan) begin sp = 1; sp_res = qa; sp_fl[0] = (a_c == C_SNAN); end
            else if (a_c == C_ZERO || a_c == C_INF) begin sp = 1; sp_res = A_r; end
        end
        OP_ST32, OP_ST64: begin
            if (a_c == C_UNS) begin sp = 1; sp_res = (op_r == OP_ST32) ? {48'd0, ind32} : {16'd0, ind64}; sp_fl[0] = 1; end
            else if (a_nan) begin
                sp = 1; sp_fl[0] = (a_c == C_SNAN);
                if (op_r == OP_ST32) sp_res = {48'd0, a_s, 8'hFF, 1'b1, a_m[61:40]};
                else sp_res = {16'd0, a_s, 11'h7FF, 1'b1, a_m[61:11]};
            end
            else if (a_c == C_INF) begin sp = 1; sp_res = (op_r == OP_ST32) ? {48'd0, a_s, 8'hFF, 23'd0} : {16'd0, a_s, 11'h7FF, 52'd0}; end
            else if (a_c == C_ZERO) begin sp = 1; sp_res = (op_r == OP_ST32) ? {48'd0, a_s, 31'd0} : {16'd0, a_s, 63'd0}; end
        end
        default: ;
        endcase
    end
    // ---------------- carga de registradores de arredondamento
    task load_round(input s, input signed [17:0] e, input [63:0] m, input g, input stk, input [6:0] p, input signed [17:0] emn, input signed [17:0] emx, input [1:0] fmt);
        begin r_s <= s; r_E <= e; r_m <= m; r_g <= g; r_st <= stk; r_p <= p; r_emin <= emn; r_emax <= emx; r_fmt <= fmt; r_rc <= rc_r;
              sh_in <= {2'b00, m, g, stk}; end
    endtask
    wire [6:0] pbits = (pc_r == 2'd0) ? 7'd24 : (pc_r == 2'd2) ? 7'd53 : 7'd64;
    // R1: desnormalizacao
    // R2: arredondamento
    reg [65:0] r2_lsbm; reg [64:0] r2_incv;
    always @* case (r_p) 7'd24: begin r2_lsbm = 66'd1 << 42; r2_incv = 65'd1 << 40; end 7'd53: begin r2_lsbm = 66'd1 << 13; r2_incv = 65'd1 << 11; end default: begin r2_lsbm = 66'd1 << 2; r2_incv = 65'd1; end endcase
    wire [65:0] r2_rbm  = r2_lsbm >> 1;
    wire [65:0] r2_lowm = r2_rbm - 66'd1;
    wire r2_lsb = |(r1_F & r2_lsbm), r2_rb = |(r1_F & r2_rbm), r2_stk = |(r1_F & r2_lowm);
    wire r2_incw = (r_rc == 2'd0) ? (r2_rb && (r2_stk || r2_lsb)) : (r_rc == 2'd1) ? ((r2_rb || r2_stk) && r_s) : (r_rc == 2'd2) ? ((r2_rb || r2_stk) && !r_s) : 1'b0;
    wire [65:0] r2_keep = r1_F & ~(r2_lsbm - 66'd1);
    wire [64:0] r2_sum = {1'b0, r2_keep[65:2]} + (r2_incw ? r2_incv : 65'd0);
    // R3: empacotamento
    wire r3_ovf = (r2_E > r_emax) && (r2_m != 0);
    wire r3_inf = (r_rc == 2'd0) || (r_rc == 2'd2 && !r_s) || (r_rc == 2'd1 && r_s);
    wire [63:0] r3_maxm = (r_p == 7'd24) ? 64'hFFFFFF0000000000 : (r_p == 7'd53) ? 64'hFFFFFFFFFFFFF800 : 64'hFFFFFFFFFFFFFFFF;
    // ---------------- soma: estagio AD1
    reg ad_bigr; reg signed [18:0] ad_ddr;
    wire a_big = ad_bigr;
    wire signed [18:0] ad_dd = ad_ddr;
    wire [66:0] ad_big67 = {ad_bm, 3'd0};
    wire [67:0] ad_s_sum = ad_ssub ? ({1'b0, ad_big67} - {1'b0, ad_x}) : ({1'b0, ad_big67} + {1'b0, ad_x});
    // ---------------- CMP
    // ---------------- escrita de resultado final
    always @(posedge clk) begin
        done <= 0; mu_in <= 0; dv_start <= 0;
        if (rst) st <= S_IDLE;
        else case (st)
        S_IDLE: if (start) begin
            op_r <= op; rc_r <= rc; pc_r <= pc; A_r <= a; B_r <= b; f_ie <= 0; f_de <= 0; f_ze <= 0; f_oe <= 0; f_ue <= 0; f_pe <= 0; f_up <= 0; cc <= 0;
            st <= (op == OP_FILD || op == OP_LD32 || op == OP_LD64) ? S_CVP : S_U1;
        end
        S_U1: begin
            a_c <= cls(A_r); a_s <= A_r[79]; a_m <= A_r[63:0]; a_E <= $signed({3'b0, A_r[78:64]}) - 18'sd16383;
            b_c <= cls(B_r); b_s <= B_r[79]; b_m <= B_r[63:0]; b_E <= $signed({3'b0, B_r[78:64]}) - 18'sd16383;
            st <= S_U2;
        end
        S_U2: begin
            if (a_c == C_ZERO) a_E <= -18'sd60000;
            if (b_c == C_ZERO) b_E <= -18'sd60000;
            if (a_c == C_DEN) begin lf_in <= {4'd0, a_m}; st <= S_U5; end
            else if (b_c == C_DEN) begin lf_in <= {4'd0, b_m}; st <= S_U6; end
            else st <= S_SP;
        end
        S_U5: st <= S_U7;
        S_U7: begin a_lz <= lz_nb[6:0] - 7'd4; lf_amt <= lz_nb[6:0] - 7'd4; st <= S_U3; end
        S_U6: st <= S_U8;
        S_U8: begin b_lz <= lz_nb[6:0] - 7'd4; lf_amt <= lz_nb[6:0] - 7'd4; st <= S_U4; end
        S_U3: begin
            a_m <= lf_out[63:0]; a_E <= EMIN80 - $signed({11'd0, a_lz});
            if (b_c == C_DEN) begin lf_in <= {4'd0, b_m}; st <= S_U6; end
            else st <= S_SP;
        end
        S_U4: begin b_m <= lf_out[63:0]; b_E <= EMIN80 - $signed({11'd0, b_lz}); st <= S_SP; end
        S_SP: begin spr <= sp; sp_resr <= sp_res; sp_flr <= sp_fl; sp_ccr <= sp_cc; st <= S_OP; end
        S_OP: begin
            f_ie <= sp_flr[0]; f_de <= sp_flr[1]; f_ze <= sp_flr[2];
            if (spr) begin res <= sp_resr; cc <= sp_ccr; st <= S_FIN; end
            else case (op_r)
                OP_ADD, OP_SUB: st <= S_AD0;
                OP_MUL: st <= S_ML0;
                OP_DIV: st <= S_DV0;
                OP_SQRT: st <= S_SQ0;
                OP_CMP: st <= S_CMP;
                OP_FIST, OP_RND: begin sh_in <= {2'b00, a_m, 2'b00}; sh_amt <= ((18'sd63 - a_E) > 66) ? 7'd66 : (18'sd63 - a_E); st <= S_TI1; end
                default: st <= S_STL;
            endcase
        end
        // ---- ADD / SUB
        S_AD0: begin
            ad_bigr <= (b_E > a_E) ? 1'b0 : (b_E < a_E) ? 1'b1 : (a_m >= b_m);
            ad_ddr <= (b_E > a_E) ? (b_E - a_E) : (a_E - b_E);
            st <= S_AD1;
        end
        S_AD1: begin
            ad_bs <= a_big ? a_s : bsgn; ad_bE <= a_big ? a_E : b_E; ad_bm <= a_big ? a_m : b_m; ad_sm <= a_big ? b_m : a_m;
            ad_ssub <= (a_s != bsgn); sh_in <= {1'b0, (a_big ? b_m : a_m), 3'd0}; sh_amt <= (ad_dd > 67) ? 7'd67 : ad_dd[6:0]; st <= S_AD2;
        end
        S_AD2: st <= S_AD2W;
        S_AD2W: begin
            ad_x <= sh_out[66:0];
            st <= S_AD3;
        end
        S_AD3: begin ad_sum <= ad_s_sum; st <= S_AD4; end
        S_AD4: begin
            ad_sign <= ad_bs; lf_in <= ad_sum;
            if (ad_sum == 0) begin res <= {(rc_r == 2'd1), 79'd0}; st <= S_FIN; end
            else st <= S_AD4A;
        end
        S_AD4A: st <= S_AD4B;
        S_AD4B: begin ad_lz <= lz_nb; lf_amt <= (lz_nb == 8'd0) ? 7'd0 : (lz_nb[6:0] - 7'd1); st <= S_AD4C; end
        S_AD4C: st <= S_AD5;
        S_AD5: begin : ad5
            reg [67:0] n; reg signed [17:0] e;
            if (ad_lz == 0) begin n = {1'b0, ad_sum[67:2], ad_sum[1] | ad_sum[0]}; e = ad_bE + 18'sd1; end
            else begin n = lf_r; e = ad_bE - $signed({10'd0, ad_lz}) + 18'sd1; end
            // n[66:0] com MSB em n[66]
            load_round(ad_sign, e, n[66:3], n[2], n[1] | n[0], pbits, EMIN80, EMAX80, 2'd0);
            st <= S_R1;
        end
        // ---- MUL
        S_ML0: if (mu_ready) begin mu_in <= 1; st <= S_ML1; end
        S_ML1: if (mu_ov) begin ml_p <= mu_p; st <= S_ML2; end
        S_ML2: begin
            if (ml_p[127]) load_round(a_s ^ b_s, a_E + b_E + 18'sd1, ml_p[127:64], ml_p[63], |ml_p[62:0], pbits, EMIN80, EMAX80, 2'd0);
            else load_round(a_s ^ b_s, a_E + b_E, ml_p[126:63], ml_p[62], |ml_p[61:0], pbits, EMIN80, EMAX80, 2'd0);
            st <= S_R1;
        end
        // ---- DIV
        S_DV0: begin
            dv_ge <= (a_m >= b_m);
            if (a_m >= b_m) begin dv_hi <= {1'b0, a_m[63:1]}; dv_lo <= {a_m[0], 63'd0}; end
            else begin dv_hi <= a_m; dv_lo <= 64'd0; end
            st <= S_DV1;
        end
        S_DV1: if (!dv_busy) begin dv_start <= 1; st <= S_DV3; end
        S_DV3: if (dv_done) begin dq <= dv_q; dr <= dv_r; st <= S_DV2; end
        S_DV2: begin : dv2
            reg [65:0] df;
            df = {1'b0, dr, 1'b0} - {2'b0, b_m};
            load_round(a_s ^ b_s, a_E - b_E - (dv_ge ? 18'sd0 : 18'sd1), dq, !df[65], !df[65] ? (df != 0) : (dr != 0), pbits, EMIN80, EMAX80, 2'd0);
            st <= S_R1;
        end
        // ---- SQRT
        S_SQ0: begin
            sq_rad <= a_E[0] ? ({66'd0, a_m} << 66) : ({66'd0, a_m} << 65);
            sq_rem <= 0; sq_q <= 0; sq_cnt <= 7'd65; st <= S_SQ1;
        end
        S_SQ1: begin
            sq_rad <= {sq_rad[127:0], 2'b00};
            if (sq_ge) begin sq_rem <= sq_df[66:0]; sq_q <= {sq_q[63:0], 1'b1}; end
            else begin sq_rem <= sq_rn; sq_q <= {sq_q[63:0], 1'b0}; end
            sq_cnt <= sq_cnt - 1;
            if (sq_cnt == 7'd1) st <= S_SQ2;
        end
        S_SQ2: begin
            load_round(1'b0, a_E >>> 1, sq_q[64:1], sq_q[0], sq_rem != 0, pbits, EMIN80, EMAX80, 2'd0);
            st <= S_R1;
        end
        // ---- CMP
        S_CMP: begin
            cc <= 3'b000;
            if (a_c == C_ZERO && b_c == C_ZERO) cc <= 3'b100;
            else begin
                // sinal efetivo (zero conta como positivo)
                if ((a_c == C_ZERO ? 1'b0 : a_s) != (b_c == C_ZERO ? 1'b0 : b_s)) cc <= (b_c == C_ZERO ? 1'b0 : b_s) ? 3'b000 : 3'b001;
                else begin : cmpm
                    reg [1:0] ra, rb; reg gt, eq;
                    ra = (a_c == C_ZERO) ? 2'd0 : (a_c == C_INF) ? 2'd2 : 2'd1;
                    rb = (b_c == C_ZERO) ? 2'd0 : (b_c == C_INF) ? 2'd2 : 2'd1;
                    if (ra != rb) begin gt = (ra > rb); eq = 0; end
                    else if (ra == 2'd1) begin
                        if (a_E != b_E) begin gt = (a_E > b_E); eq = 0; end
                        else if (a_m != b_m) begin gt = (a_m > b_m); eq = 0; end
                        else begin gt = 0; eq = 1; end
                    end else begin gt = 0; eq = 1; end
                    // gt refere-se aos modulos; com sinal negativo inverte
                    if (eq) cc <= 3'b100;
                    else if ((a_c == C_ZERO ? 1'b0 : a_s)) cc <= gt ? 3'b001 : 3'b000;
                    else cc <= gt ? 3'b000 : 3'b001;
                end
            end
            res <= 0; st <= S_FIN;
        end
        // ---- para inteiro (FIST / RNDINT)
        S_TI1: st <= S_TI1W;
        S_TI1W: begin : ti1
            reg signed [18:0] sh;
            sh = 19'sd63 - a_E;
            if (op_r == OP_RND && a_E >= 18'sd63) begin res <= A_r; st <= S_FIN; end
            else if (op_r == OP_FIST && a_E >= 18'sd63) begin
                // so -2^63 exato e valido
                if (a_s && a_E == 18'sd63 && a_m == 64'h8000000000000000) begin res <= 80'h8000000000000000; st <= S_FIN; end
                else begin res <= 80'h8000000000000000; f_ie <= 1; st <= S_FIN; end
            end else begin
                ti_I <= sh_out[65:2]; ti_rb <= sh_out[1]; ti_st <= sh_out[0]; st <= S_TI2;
            end
        end
        S_TI2: begin
            ti_inex <= ti_rb | ti_st;
            ti_inc <= (rc_r == 2'd0) ? (ti_rb && (ti_st || ti_I[0])) : (rc_r == 2'd1) ? ((ti_rb | ti_st) && a_s) : (rc_r == 2'd2) ? ((ti_rb | ti_st) && !a_s) : 1'b0;
            st <= S_TI3;
        end
        S_TI3: begin
            ti_k <= {1'b0, ti_I} + (ti_inc ? 65'd1 : 65'd0);
            f_up <= ti_inc && ti_inex;
            st <= S_TI4;
        end
        S_TI4: begin : ti4
            reg [64:0] k;
            k = ti_k;
            if (op_r == OP_FIST) begin
                if ((!a_s && k > 65'h7FFFFFFFFFFFFFFF) || (a_s && k > 65'h8000000000000000)) begin res <= 80'h8000000000000000; f_ie <= 1; f_up <= 0; end
                else begin res <= {16'd0, a_s ? (~k[63:0] + 64'd1) : k[63:0]}; f_pe <= ti_inex; end
                st <= S_FIN;
            end else begin
                f_pe <= ti_inex;
                if (k == 0) begin res <= {a_s, 79'd0}; st <= S_FIN; end
                else begin cv_s <= a_s; cv_mag <= k[63:0]; cv_bias <= 18'sd0; cv_rnd <= 1; st <= S_CV2; end
            end
        end
        // ---- FILD / LD32 / LD64
        S_CVP: begin
            c32_fz <= (A_r[22:0] == 0); c32_z <= (A_r[30:0] == 0); c32_e0 <= (A_r[30:23] == 0); c32_ff <= (A_r[30:23] == 8'hFF);
            c64_fz <= (A_r[51:0] == 0); c64_z <= (A_r[62:0] == 0); c64_e0 <= (A_r[62:52] == 0); c64_ff <= (A_r[62:52] == 11'h7FF); c_z64 <= (A_r[63:0] == 0);
            st <= S_CV0;
        end
        S_CV0: begin : cv0
            reg [63:0] mg; reg s; reg signed [17:0] bi; reg zz;
            case (op_r)
            OP_FILD: begin
                s = A_r[63]; mg = A_r[63] ? (~A_r[63:0] + 64'd1) : A_r[63:0]; bi = 18'sd0;
                if (c_z64) begin res <= 0; cc <= 0; f_ie <= 0; st <= S_FIN; end
                else begin cv_s <= s; cv_mag <= mg; cv_bias <= bi; cv_rnd <= 0; st <= S_CV2; end
            end
            OP_LD32: begin
                s = A_r[31];
                if (c32_ff) begin
                    res <= (c32_fz) ? {s, 15'h7FFF, 64'h8000000000000000} : {s, 15'h7FFF, 1'b1, 1'b1, A_r[21:0], 40'd0};
                    f_ie <= (!c32_fz) && !A_r[22]; st <= S_FIN;
                end else if (c32_z) begin res <= {s, 79'd0}; st <= S_FIN; end
                else if (c32_e0) begin f_de <= 1; cv_s <= s; cv_mag <= {41'd0, A_r[22:0]}; cv_bias <= -18'sd149; cv_rnd <= 0; st <= S_CV2; end
                else begin cv_s <= s; cv_mag <= {40'd0, 1'b1, A_r[22:0]}; cv_bias <= $signed({10'd0, A_r[30:23]}) - 18'sd150; cv_rnd <= 0; st <= S_CV2; end
            end
            default: begin // LD64
                s = A_r[63];
                if (c64_ff) begin
                    res <= (c64_fz) ? {s, 15'h7FFF, 64'h8000000000000000} : {s, 15'h7FFF, 1'b1, 1'b1, A_r[50:0], 11'd0};
                    f_ie <= (!c64_fz) && !A_r[51]; st <= S_FIN;
                end else if (c64_z) begin res <= {s, 79'd0}; st <= S_FIN; end
                else if (c64_e0) begin f_de <= 1; cv_s <= s; cv_mag <= {12'd0, A_r[51:0]}; cv_bias <= -18'sd1074; cv_rnd <= 0; st <= S_CV2; end
                else begin cv_s <= s; cv_mag <= {11'd0, 1'b1, A_r[51:0]}; cv_bias <= $signed({7'd0, A_r[62:52]}) - 18'sd1075; cv_rnd <= 0; st <= S_CV2; end
            end
            endcase
        end
        S_CV2: begin lf_in <= {4'd0, cv_mag}; st <= S_CV2A; end
        S_CV2A: st <= S_CV4;
        S_CV4: begin lf_amt <= lz_nb[6:0] - 7'd4; cv_lz <= lz_nb[6:0] - 7'd4; st <= S_CV5; end
        S_CV5: st <= S_CV3;
        S_CV3: begin
            // mantissa normalizada e expoente (63 - lz + bias); exato (g=s=0), precisao 64
            load_round(cv_s, 18'sd63 - $signed({11'd0, cv_lz}) + cv_bias, lf_r[63:0], 1'b0, 1'b0, 7'd64, EMIN80, EMAX80, 2'd0);
            st <= S_R1;
        end
        // ---- ST32 / ST64: arredondar mantissa normalizada para o formato IEEE
        S_STL: begin
            if (op_r == OP_ST32) load_round(a_s, a_E, a_m, 1'b0, 1'b0, 7'd24, -18'sd126, 18'sd127, 2'd1);
            else load_round(a_s, a_E, a_m, 1'b0, 1'b0, 7'd53, -18'sd1022, 18'sd1023, 2'd2);
            st <= S_R1;
        end
        // ---- arredondamento e empacotamento
        S_R1: begin
            sh_amt <= ((r_emin - r_E) <= 0) ? 7'd0 : ((r_emin - r_E) > 66) ? 7'd66 : (r_emin - r_E); r_tiny0 <= ((r_emin - r_E) > 0); st <= S_R1V;
        end
        S_R1V: st <= S_R1W;
        S_R1W: begin
            r1_F <= sh_out[65:0];
            r1_E <= r_tiny0 ? r_emin : r_E; r1_tiny <= r_tiny0; st <= S_R2;
        end
        S_R2: begin
            if (r2_sum[64]) begin r2_m <= 64'h8000000000000000; r2_E <= r1_E + 18'sd1; end
            else begin r2_m <= r2_sum[63:0]; r2_E <= r1_E; end
            r2_inex <= r2_rb | r2_stk; r2_inc <= r2_incw; r2_tiny <= r1_tiny; st <= S_R3;
        end
        S_R3: begin
            if (r3_ovf) begin
                f_oe <= 1; f_pe <= 1; f_up <= r3_inf;
                case (r_fmt)
                2'd0: res <= r3_inf ? {r_s, 15'h7FFF, 64'h8000000000000000} : {r_s, 15'h7FFE, r3_maxm};
                2'd1: res <= {48'd0, r3_inf ? {r_s, 8'hFF, 23'd0} : {r_s, 8'hFE, r3_maxm[62:40]}};
                default: res <= {16'd0, r3_inf ? {r_s, 11'h7FF, 52'd0} : {r_s, 11'h7FE, r3_maxm[62:11]}};
                endcase
            end else begin
                if (r2_inex) f_pe <= 1;
                if (r2_inex && r2_tiny) f_ue <= 1;
                f_up <= f_up | (r2_inex && r2_inc);
                case (r_fmt)
                2'd0: res <= {r_s, r2_m[63] ? (r2_E[14:0] + 15'd16383) : 15'd0, r2_m};
                2'd1: res <= {48'd0, r_s, r2_m[63] ? (r2_E[7:0] + 8'd127) : 8'd0, r2_m[62:40]};
                default: res <= {16'd0, r_s, r2_m[63] ? (r2_E[10:0] + 11'd1023) : 11'd0, r2_m[62:11]};
                endcase
                if (r2_m == 0) res <= (r_fmt == 2'd0) ? {r_s, 79'd0} : (r_fmt == 2'd1) ? {48'd0, r_s, 31'd0} : {16'd0, r_s, 63'd0};
            end
            st <= S_FIN;
        end
        S_FIN: begin
            flags <= {f_pe, f_ue, f_oe, f_ze, f_de, f_ie}; up <= f_up; done <= 1; st <= S_IDLE;
        end
        default: st <= S_IDLE;
        endcase
    end
endmodule
