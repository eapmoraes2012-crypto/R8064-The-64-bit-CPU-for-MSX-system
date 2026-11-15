// fpu_unit.v - FPU do R8064 vista pelo nucleo: pilha ST0-ST7 (80 bits), marcas de vazio, palavra de estado e o nucleo aritmetico compacto (fpu_seq.v).
// O nucleo manda um comando por vez ('go' com fop/n/din/dhi) e espera 'done'. Especificacao: 09_core_min/MODELO_FPU.txt.
// fop[5:4] = tipo:
//   0  aritmetica, codigo = operacao do fpu_seq: 0 FADD n, 1 FSUB n, 2 FMUL n, 3 FDIV n (ST0 := ST0 op STn), 4 FSQRT, 8 FRINT (ST0 := f(ST0)),
//      5 FCOM n (so C3 C2 C0), 6 FILD, 9 FLD32, 10 FLD64 (empilha a conversao de din), 7 FIST, 11 FST32, 12 FST64 (r0 := conversao de ST0; a pilha fica)
//   1  FCOPP: compara ST0 com ST1 e desempilha os dois (codigo 5)
//   2  sem aritmetica: 0 FLD STn, 1 FXCH n, 2 FSTP STn, 3 FCHS, 4 FABS, 5 FINIT, 6 FLD80 ({dhi, din}), 7 FST80 ({r1, r0} := ST0), 8 desempilha, 9 FSTSW (r0 := byte para F),
//      10 FLD1, 11 FLDZ, 12 FLDPI, 13 FLDL2 (log2 10), 14 FLDLG (log10 2), 15 FLDLN (ln 2)
// Palavra de controle FIXA: arredondamento para o mais proximo, precisao de 64 bits, todas as excecoes mascaradas (resposta padrao do x87; so as marcas ficam).
// Para sintetizar sem a FPU (economiza ~5.000 LUT): defina R8064_SEM_FPU (ver o fim de 09_core_min/MODELO_FPU.txt).
// Pilha: ler registrador vazio ou empilhar sobre ST7 ocupado = IE + SF e o valor vira o INDEFINIDO (C1 = 1 no estouro, 0 na falta).
module fpu_unit(
    input  wire        clk, rst, go,
    input  wire [5:0]  fop,
    input  wire [2:0]  n,
    input  wire [63:0] din,
    input  wire [15:0] dhi,
    output reg         done,
    output reg  [63:0] r0,
    output reg  [15:0] r1,
    output wire [15:0] sw,            // palavra de estado no formato do x87: {B, C3, TOP, C2, C1, C0, ES, SF, PE, UE, OE, ZE, DE, IE}
    output wire [7:0]  empty
);
    localparam [79:0] INDEF = {1'b1, 15'h7FFF, 64'hC000_0000_0000_0000};
`ifdef R8064_SEM_FPU
    // Sintese SEM a FPU (read_verilog -DR8064_SEM_FPU): a unidade some; toda instrucao de FPU termina na hora, devolve zero e nao guarda nada.
    reg [79:0] stk [0:7]; reg [2:0] top; reg [7:0] emp;       // so para os testbenches compilarem
    assign sw = 16'd0; assign empty = 8'hFF;
    always @(posedge clk) begin done <= !rst && go; r0 <= 64'd0; r1 <= 16'd0; end
`else
    reg [79:0] stk [0:7];
    reg [2:0] top; reg [7:0] emp; reg [5:0] exc; reg sf, c3, c2, c1, c0;
    reg [5:0] fr; reg [2:0] nn; reg [63:0] dq;
    reg [1:0] us; localparam U_IDLE = 0, U_EX = 1, U_W = 2, U_X2 = 3;
    wire [2:0] ib = top + nn, im1 = top - 3'd1, ip1 = top + 3'd1;
    wire [79:0] ra = stk[top], rb = stk[ib];
    wire ea = emp[top], eb = emp[ib], full = !emp[im1];
    wire [1:0] kind = fr[5:4]; wire [3:0] code = fr[3:0];
    wire memsrc = (code == 4'd6) || (code == 4'd9) || (code == 4'd10);
    wire needb = (code <= 4'd3) || (code == 4'd5);
    wire wr0 = (code <= 4'd4) || (code == 4'd8);
    reg astart; wire adone; wire [79:0] ares; wire [5:0] afl; wire aup; wire [2:0] acc;
    fpu_seq u_seq(.clk(clk), .rst(rst), .start(astart), .op(code), .rc(2'd0), .pc(2'd3), .a(memsrc ? {16'd0, dq} : ra), .b(rb), .busy(), .done(adone), .res(ares), .flags(afl), .up(aup), .cc(acc));
    reg we; reg [2:0] wi; reg [79:0] wd;
    always @(posedge clk) if (we) stk[wi] <= wd;
    assign sw = {1'b0, c3, top, c2, c1, c0, 1'b0, sf, exc[5], exc[4], exc[3], exc[2], exc[1], exc[0]};
    assign empty = emp;
    wire [79:0] kval = (code == 4'd10) ? {16'h3FFF, 64'h8000_0000_0000_0000} : (code == 4'd11) ? 80'd0 : (code == 4'd12) ? {16'h4000, 64'hC90F_DAA2_2168_C235} :
                       (code == 4'd13) ? {16'h4000, 64'hD49A_784B_CD1B_8AFE} : (code == 4'd14) ? {16'h3FFD, 64'h9A20_9A84_FBCF_F799} : {16'h3FFE, 64'hB172_17F7_D1CF_79AC};
    // empilha v (ou o INDEFINIDO, com IE + SF + C1, se ST7 esta ocupado)
    task push(input [79:0] v); begin
        we <= 1'b1; wi <= im1; wd <= full ? INDEF : v; top <= im1; emp[im1] <= 1'b0;
        if (full) begin exc[0] <= 1'b1; sf <= 1'b1; c1 <= 1'b1; end
    end endtask
    task under; begin exc[0] <= 1'b1; sf <= 1'b1; c1 <= 1'b0; end endtask
    always @(posedge clk) begin
        we <= 1'b0; done <= 1'b0; astart <= 1'b0;
        if (rst) begin us <= U_IDLE; top <= 3'd0; emp <= 8'hFF; exc <= 6'd0; sf <= 1'b0; c3 <= 1'b0; c2 <= 1'b0; c1 <= 1'b0; c0 <= 1'b0; end
        else case (us)
            U_IDLE: if (go) begin fr <= fop; nn <= (fop[5:4] == 2'd1) ? 3'd1 : n; dq <= din; us <= U_EX; end
            U_EX: begin
                us <= U_IDLE; done <= 1'b1;
                if (kind == 2'd2) case (code)
                    4'd0: begin c1 <= 1'b0; if (eb) under; push(eb ? INDEF : rb); end
                    4'd1: begin c1 <= 1'b0; if (ea || eb) under; {r1, r0} <= ea ? INDEF : ra; we <= 1'b1; wi <= top; wd <= eb ? INDEF : rb; emp[top] <= 1'b0; done <= 1'b0; us <= U_X2; end
                    4'd2: begin c1 <= 1'b0; if (ea) under; we <= 1'b1; wi <= ib; wd <= ea ? INDEF : ra; emp[ib] <= 1'b0; emp[top] <= 1'b1; top <= ip1; end
                    4'd3, 4'd4: begin c1 <= 1'b0; if (ea) under; we <= 1'b1; wi <= top; wd <= ea ? INDEF : {(code == 4'd3) ? ~ra[79] : 1'b0, ra[78:0]}; emp[top] <= 1'b0; end
                    4'd5: begin top <= 3'd0; emp <= 8'hFF; exc <= 6'd0; sf <= 1'b0; c3 <= 1'b0; c2 <= 1'b0; c1 <= 1'b0; c0 <= 1'b0; end
                    4'd6: begin c1 <= 1'b0; push({dhi, dq}); end
                    4'd7: begin c1 <= 1'b0; if (ea) under; {r1, r0} <= ea ? INDEF : ra; end
                    4'd8: begin emp[top] <= 1'b1; top <= ip1; end
                    4'd9: r0 <= {56'd0, 1'b0, c3, 3'b000, c2, 1'b0, c0};
                    default: begin c1 <= 1'b0; push(kval); end
                endcase
                else if (memsrc && full) begin c1 <= 1'b0; push(INDEF); end
                else if (!memsrc && (ea || (needb && eb))) begin
                    under;
                    if (wr0) begin we <= 1'b1; wi <= top; wd <= INDEF; emp[top] <= 1'b0; end
                    if (code == 4'd5) begin c3 <= 1'b1; c2 <= 1'b1; c0 <= 1'b1; end
                    r0 <= (code == 4'd7) ? 64'h8000_0000_0000_0000 : (code == 4'd11) ? 64'h0000_0000_FFC0_0000 : 64'hFFF8_0000_0000_0000;
                    if (kind == 2'd1) begin emp[top] <= 1'b1; emp[ip1] <= 1'b1; top <= top + 3'd2; end
                end else begin astart <= 1'b1; done <= 1'b0; us <= U_W; end
            end
            U_W: if (adone) begin
                us <= U_IDLE; done <= 1'b1; exc <= exc | afl; c1 <= aup;
                if (wr0) begin we <= 1'b1; wi <= top; wd <= ares; end
                if (code == 4'd5) begin c3 <= acc[2]; c2 <= acc[1]; c0 <= acc[0]; end
                if (memsrc) push(ares);
                r0 <= ares[63:0];
                if (kind == 2'd1) begin emp[top] <= 1'b1; emp[ip1] <= 1'b1; top <= top + 3'd2; end
            end
            U_X2: begin we <= 1'b1; wi <= ib; wd <= {r1, r0}; emp[ib] <= 1'b0; us <= U_IDLE; done <= 1'b1; end
        endcase
    end
`endif
endmodule
