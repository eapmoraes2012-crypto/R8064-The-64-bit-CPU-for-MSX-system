// fpu_stk.v - hardware residual da FPU x87 (medida A: aritmetica em firmware): pilha ST0-ST7 (80 bits), tags, palavras de controle (CW) e estado (SW).
// Comandos (um por ciclo quando 'go'; XCH leva 2 ciclos, 'busy'=1 ate terminar):
//  0 NOP 1 INIT(FINIT) 2 PUSH(wdata) 3 POP 4 XCH(troca ST(ra_idx) com ST(rb_idx); mantenha ra_idx/rb_idx estaveis) 5 WRST(idx,wdata) 6 INCSTP 7 DECSTP 8 SETCW(wdata) 9 CLREX 10 ORFLG(flags) 11 SETCC(wdata[3:0]=C0..C3)
//  12 SETSW(wdata) 13 SETTW(wdata) 14 FREE(idx)
// Leitura combinacional de ST(ra_idx) e ST(rb_idx), com tags. FXAM classifica ST(ra_idx) (use ra_idx=0 para FXAM de ST0). Excecao de pilha (IE+SF, C1=1 em estouro): IM mascarado -> escreve INDEFINIDO e move TOP; desmascarado -> so sinaliza.
// Classificacao de tag na escrita: 0 valido, 1 zero, 2 especial (inf/NaN/denormal/nao normalizado), 3 vazio.
module fpu_stk(
    input  wire        clk, rst,
    input  wire        go,
    input  wire [3:0]  cmd,
    input  wire [2:0]  idx,
    input  wire [79:0] wdata,
    input  wire [5:0]  flags_in,
    input  wire [2:0]  ra_idx, rb_idx,
    output wire [79:0] ra, rb,
    output wire [1:0]  tag_a, tag_b,
    output wire [15:0] cw, sw, tw,
    output wire [3:0]  fxam,          // {C3,C2,C1,C0} de ST0
    output wire        es,
    output reg         busy
);
    localparam [79:0] INDEF = {1'b1, 15'h7FFF, 64'hC000_0000_0000_0000};
    reg [79:0] st [0:7];
    reg [1:0]  tg [0:7];
    reg [2:0]  top;
    reg [15:0] cwr;
    reg [6:0]  exc;                    // IE DE ZE OE UE PE SF
    reg        c0, c1, c2, c3;
    reg [79:0] tmp; reg [1:0] tmp_t; reg [2:0] xi;      // XCH, ciclo 2
    function [1:0] ctag(input [79:0] v);
        begin
            if (v[78:64] == 15'd0 && v[63:0] == 64'd0) ctag = 2'd1;
            else if (v[78:64] == 15'h7FFF) ctag = 2'd2;
            else if (v[78:64] == 15'd0) ctag = 2'd2;
            else if (!v[63]) ctag = 2'd2;
            else ctag = 2'd0;
        end
    endfunction
    wire [2:0] pa = top + ra_idx, pb = top + rb_idx;
    assign ra = st[pa]; assign rb = st[pb]; assign tag_a = tg[pa]; assign tag_b = tg[pb];
    assign cw = cwr;
    assign es = |(exc[5:0] & ~cwr[5:0]);
    assign sw = {es, c3, top, c2, c1, c0, es, exc};
    assign tw = {tg[7], tg[6], tg[5], tg[4], tg[3], tg[2], tg[1], tg[0]};
    // FXAM de ST(ra_idx): usa a porta A (evita uma 3a porta de leitura)
    wire [79:0] s0 = ra; wire s0e = (tag_a == 2'd3);
    wire s0_z = (s0[78:64] == 15'd0) && (s0[63:0] == 64'd0);
    wire s0_i = (s0[78:64] == 15'h7FFF) && s0[63] && (s0[62:0] == 63'd0);
    wire s0_n = (s0[78:64] == 15'h7FFF) && s0[63] && (s0[62:0] != 63'd0);
    wire s0_d = (s0[78:64] == 15'd0) && !s0[63] && (s0[62:0] != 63'd0);
    wire s0_v = (s0[78:64] != 15'd0) && (s0[78:64] != 15'h7FFF) && s0[63];
    wire f_c3 = s0e | (!s0e & (s0_z | s0_d));
    wire f_c2 = !s0e & (s0_i | s0_d | s0_v);
    wire f_c0 = s0e | (!s0e & (s0_i | s0_n));
    assign fxam = {f_c3, f_c2, s0[79], f_c0};
    wire [2:0] ntop = top - 3'd1;
    wire [2:0] pi_ = top + idx;
    always @(posedge clk) begin
        if (rst) begin
            top <= 0; cwr <= 16'h037F; exc <= 0; {c3, c2, c1, c0} <= 0; busy <= 0;
            tg[0] <= 3; tg[1] <= 3; tg[2] <= 3; tg[3] <= 3; tg[4] <= 3; tg[5] <= 3; tg[6] <= 3; tg[7] <= 3;
        end else if (busy) begin
            // XCH, ciclo 2: ST(i) <- antigo ST0
            st[xi] <= tmp; tg[xi] <= tmp_t; busy <= 0;
        end else if (go) begin
            case (cmd)
                4'd1: begin top <= 0; cwr <= 16'h037F; exc <= 0; {c3, c2, c1, c0} <= 0;
                            tg[0] <= 3; tg[1] <= 3; tg[2] <= 3; tg[3] <= 3; tg[4] <= 3; tg[5] <= 3; tg[6] <= 3; tg[7] <= 3; end
                4'd2: begin
                    if (tg[ntop] != 2'd3) begin
                        exc[0] <= 1'b1; exc[6] <= 1'b1; c1 <= 1'b1;
                        if (cwr[0]) begin top <= ntop; st[ntop] <= INDEF; tg[ntop] <= 2'd2; end
                    end else begin top <= ntop; st[ntop] <= wdata; tg[ntop] <= ctag(wdata); end
                end
                4'd3: begin
                    if (tg[top] == 2'd3) begin
                        exc[0] <= 1'b1; exc[6] <= 1'b1; c1 <= 1'b0;
                        if (cwr[0]) top <= top + 3'd1;
                    end else begin tg[top] <= 2'd3; top <= top + 3'd1; end
                end
                4'd4: begin
                    // ciclo 1: ST(ra) <- ST(rb); guarda ST(ra) antigo
                    tmp <= ra; tmp_t <= tg[pa]; xi <= pb;
                    st[pa] <= rb; tg[pa] <= tg[pb];
                    busy <= 1'b1;
                end
                4'd5: begin st[pi_] <= wdata; tg[pi_] <= ctag(wdata); end
                4'd6: top <= top + 3'd1;
                4'd7: top <= top - 3'd1;
                4'd8: cwr <= wdata[15:0];
                4'd9: exc <= 7'd0;
                4'd10: exc[5:0] <= exc[5:0] | flags_in;
                4'd11: begin c0 <= wdata[0]; c1 <= wdata[1]; c2 <= wdata[2]; c3 <= wdata[3]; end
                4'd12: begin exc <= wdata[6:0]; c0 <= wdata[8]; c1 <= wdata[9]; c2 <= wdata[10]; top <= wdata[13:11]; c3 <= wdata[14]; end
                4'd13: begin tg[0] <= wdata[1:0]; tg[1] <= wdata[3:2]; tg[2] <= wdata[5:4]; tg[3] <= wdata[7:6]; tg[4] <= wdata[9:8]; tg[5] <= wdata[11:10]; tg[6] <= wdata[13:12]; tg[7] <= wdata[15:14]; end
                4'd14: tg[pi_] <= 2'd3;
                default: ;
            endcase
        end
    end
endmodule
