// fpu_unit.v - FPU do R8064 vista pelo nucleo: pilha ST0-ST7 (80 bits), marcas de vazio, palavra de estado, o nucleo aritmetico (fpu_seq.v) e um pequeno
// executor de "programas" (passos de fpu_prog.vh, gerado por ../ref/gen_fpu_prog.py) para as transcendentais e os restos.
// O nucleo manda um comando por vez ('go' com fop/n/din/dhi) e espera 'done'. Especificacao: 09_core_min/MODELO_FPU.txt.
// fop[5:4] = tipo:
//   0  aritmetica, codigo = operacao do fpu_seq: 0 FADD n, 1 FSUB n, 2 FMUL n, 3 FDIV n (ST0 := ST0 op STn), 4 FSQRT, 8 FRINT (ST0 := f(ST0)),
//      5 FCOM n (so C3 C2 C0), 6 FILD, 9 FLD32, 10 FLD64 (empilha a conversao de din), 7 FIST, 11 FST32, 12 FST64 (r0 := conversao de ST0; a pilha fica)
//   1  FCOPP: compara ST0 com ST1 e desempilha os dois (codigo 5)
//   2  sem aritmetica: 0 FLD STn, 1 FXCH n, 2 FSTP STn, 3 FCHS, 4 FABS, 5 FINIT, 6 FLD80 ({dhi, din}), 7 FST80 ({r1, r0} := ST0), 8 desempilha, 9 FSTSW (r0 := byte para F),
//      10 FLD1, 11 FLDZ, 12 FLDPI, 13 FLDL2 (log2 10), 14 FLDLG (log10 2), 15 FLDLN (ln 2)
//   3  0 le o estado (r0 := {vazios, palavra de estado}; zera o indice), 1 le o proximo registrador fisico ({r1, r0}), 2 grava o estado (din), 3 grava o proximo
//      registrador fisico ({dhi, din})  [FSAVE / FRSTR]; 4 FSIN, 5 FCOS, 6 FSINC, 7 FTAN, 8 FLN, 9 FYL2X, 10 FYL2P, 11 FREM, 12 FREM1 (programas)
// Palavra de controle FIXA: arredondamento para o mais proximo, precisao de 64 bits, todas as excecoes mascaradas (resposta padrao do x87; so as marcas ficam).
// Pilha: ler registrador vazio ou empilhar sobre ST7 ocupado = IE + SF e o valor vira o INDEFINIDO (C1 = 1 no estouro, 0 na falta).
// Para sintetizar sem a FPU (economiza a unidade inteira): defina R8064_SEM_FPU (ver o fim de 09_core_min/MODELO_FPU.txt).
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
    reg [79:0] stk [0:15];            // 0-7 pilha (posicoes fisicas), 8-15 temporarios dos programas
    reg [2:0] top; reg [7:0] emp;
    integer ii; initial for (ii = 0; ii < 16; ii = ii + 1) stk[ii] = 80'd0;
`ifdef R8064_SEM_FPU
    // Sintese SEM a FPU (read_verilog -DR8064_SEM_FPU): a unidade some; toda instrucao de FPU termina na hora, devolve zero e nao guarda nada.
    assign sw = 16'd0; assign empty = 8'hFF;
    always @(posedge clk) begin done <= !rst && go; r0 <= 64'd0; r1 <= 16'd0; end
`else
    reg [35:0] rom [0:511]; reg [35:0] rq; reg [29:0] mir; reg [79:0] cb; wire [8:0] raddr;      // ROM de passos e constantes (bloco de RAM)
    always @(posedge clk) rq <= rom[raddr];
    // >>> GERADO por ../ref/gen_fpu_prog.py (nao editar entre as marcas)
    // passo: [3:0] tipo, [7:4] operacao, [9:8] arredondamento, [14:10] destino, [19:15] A, [21:20] tipo de B, [28:22] B, [29] guarda o quadrante
    initial begin
        for (ii = 0; ii < 512; ii = ii + 1) rom[ii] = 36'd7;
        rom[0] = 36'h000982020;
        rom[1] = 36'h000042080;
        rom[2] = 36'h020040070;
        rom[3] = 36'h000d42420;
        rom[4] = 36'h002482810;
        rom[5] = 36'h001142420;
        rom[6] = 36'h002452810;
        rom[7] = 36'h001542420;
        rom[8] = 36'h002452810;
        rom[9] = 36'h002852c20;
        rom[10] = 36'h004848006;
        rom[11] = 36'h000203001;
        rom[12] = 36'h002c63020;
        rom[13] = 36'h000263000;
        rom[14] = 36'h003000005;
        rom[15] = 36'h002c63020;
        rom[16] = 36'h002863020;
        rom[17] = 36'h002863000;
        rom[18] = 36'h007850006;
        rom[19] = 36'h000203401;
        rom[20] = 36'h002c6b420;
        rom[21] = 36'h00026b400;
        rom[22] = 36'h005000005;
        rom[23] = 36'h002c6b420;
        rom[24] = 36'h00016b400;
        rom[25] = 36'h000000008;
        rom[26] = 36'h000004003;
        rom[27] = 36'h000000007;
        rom[28] = 36'h000000007;
        rom[29] = 36'h000000007;
        rom[30] = 36'h000404003;
        rom[31] = 36'h000000007;
        rom[32] = 36'h000000007;
        rom[33] = 36'h000000007;
        rom[34] = 36'h000003803;
        rom[35] = 36'h000404003;
        rom[36] = 36'h000070004;
        rom[37] = 36'h000000007;
        rom[38] = 36'h000003803;
        rom[39] = 36'h000403c03;
        rom[40] = 36'h003c74030;
        rom[41] = 36'h000000007;
        rom[42] = 36'h000082802;
        rom[43] = 36'h000002060;
        rom[44] = 36'h000152c10;
        rom[45] = 36'h000153000;
        rom[46] = 36'h00305ac30;
        rom[47] = 36'h002c5b020;
        rom[48] = 36'h00c890006;
        rom[49] = 36'h000203401;
        rom[50] = 36'h00306b420;
        rom[51] = 36'h00026b400;
        rom[52] = 36'h00c800005;
        rom[53] = 36'h002c6b420;
        rom[54] = 36'h001d42020;
        rom[55] = 36'h003444000;
        rom[56] = 36'h000000007;
        rom[57] = 36'h000082802;
        rom[58] = 36'h000002060;
        rom[59] = 36'h000152c10;
        rom[60] = 36'h000153000;
        rom[61] = 36'h00305ac30;
        rom[62] = 36'h002c5b020;
        rom[63] = 36'h00c890006;
        rom[64] = 36'h000203401;
        rom[65] = 36'h00306b420;
        rom[66] = 36'h00026b400;
        rom[67] = 36'h010400005;
        rom[68] = 36'h002c6b420;
        rom[69] = 36'h00196b420;
        rom[70] = 36'h00206b400;
        rom[71] = 36'h00348c420;
        rom[72] = 36'h000008007;
        rom[73] = 36'h000583000;
        rom[74] = 36'h003082c30;
        rom[75] = 36'h002c5b020;
        rom[76] = 36'h00c890006;
        rom[77] = 36'h000203401;
        rom[78] = 36'h00306b420;
        rom[79] = 36'h00026b400;
        rom[80] = 36'h013800005;
        rom[81] = 36'h002c6b420;
        rom[82] = 36'h00196b420;
        rom[83] = 36'h00348c420;
        rom[84] = 36'h000008007;
        rom[85] = 36'h004482030;
        rom[86] = 36'h000042380;
        rom[87] = 36'h00208a020;
        rom[88] = 36'h002084010;
        rom[89] = 36'h000000007;
        rom[90] = 36'h004482030;
        rom[91] = 36'h000042080;
        rom[92] = 36'h00208a020;
        rom[93] = 36'h002084010;
        rom[94] = 36'h000000007;
        rom[256] = 36'h000000000; rom[257] = 36'hff8000000; rom[258] = 36'h00000003f;
        rom[260] = 36'h000000000; rom[261] = 36'h008000000; rom[262] = 36'h000000040;
        rom[264] = 36'he4e44152a; rom[265] = 36'hfea2f9836; rom[266] = 36'h00000003f;
        rom[268] = 36'h200000000; rom[269] = 36'hffc90fdaa; rom[270] = 36'h00000003f;
        rom[272] = 36'h300000000; rom[273] = 36'hdd85a308d; rom[274] = 36'h00000003f;
        rom[276] = 36'h01b839a25; rom[277] = 36'hba98cc517; rom[278] = 36'h00000003f;
        rom[280] = 36'h95c17f0bc; rom[281] = 36'hffb8aa3b2; rom[282] = 36'h00000003f;
        rom[284] = 36'h7d1cf79ac; rom[285] = 36'hfeb17217f; rom[286] = 36'h00000003f;
        rom[288] = 36'haaaaaaaab; rom[289] = 36'hfcaaaaaaa; rom[290] = 36'h0000000bf;
        rom[292] = 36'h888888889; rom[293] = 36'hf88888888; rom[294] = 36'h00000003f;
        rom[296] = 36'h00d00d00d; rom[297] = 36'hf2d00d00d; rom[298] = 36'h0000000bf;
        rom[300] = 36'hab6399c7d; rom[301] = 36'hecb8ef1d2; rom[302] = 36'h00000003f;
        rom[304] = 36'hfaa271c7f; rom[305] = 36'he5d7322b3; rom[306] = 36'h0000000bf;
        rom[308] = 36'hd43684be5; rom[309] = 36'hdeb092309; rom[310] = 36'h00000003f;
        rom[312] = 36'h99dc0f88f; rom[313] = 36'hd6d73f9f3; rom[314] = 36'h0000000bf;
        rom[316] = 36'h1856a5359; rom[317] = 36'hceca963b8; rom[318] = 36'h00000003f;
        rom[320] = 36'h40a0ab926; rom[321] = 36'hc697a4da3; rom[322] = 36'h0000000bf;
        rom[324] = 36'h6e7ab8c5f; rom[325] = 36'hbdb8dc77b; rom[326] = 36'h00000003f;
        rom[328] = 36'h8b1c0cecc; rom[329] = 36'hb4bb0da09; rom[330] = 36'h0000000bf;
        rom[332] = 36'h000000000; rom[333] = 36'hfe8000000; rom[334] = 36'h0000000bf;
        rom[336] = 36'haaaaaaaab; rom[337] = 36'hfaaaaaaaa; rom[338] = 36'h00000003f;
        rom[340] = 36'h60b60b60b; rom[341] = 36'hf5b60b60b; rom[342] = 36'h0000000bf;
        rom[344] = 36'h00d00d00d; rom[345] = 36'hefd00d00d; rom[346] = 36'h00000003f;
        rom[348] = 36'hbc4fae397; rom[349] = 36'he993f27db; rom[350] = 36'h0000000bf;
        rom[352] = 36'hfc6c4bdaa; rom[353] = 36'he28f76c77; rom[354] = 36'h00000003f;
        rom[356] = 36'h603e4e906; rom[357] = 36'hdac9cba54; rom[358] = 36'h0000000bf;
        rom[360] = 36'h99dc0f88f; rom[361] = 36'hd2d73f9f3; rom[362] = 36'h00000003f;
        rom[364] = 36'hdcbecbbde; rom[365] = 36'hcab413c31; rom[366] = 36'h0000000bf;
        rom[368] = 36'h01011283d; rom[369] = 36'hc1f2a15d2; rom[370] = 36'h00000003f;
        rom[372] = 36'hdbfc294a3; rom[373] = 36'hb98671cb6; rom[374] = 36'h0000000bf;
        rom[376] = 36'hb97abbe65; rom[377] = 36'haff96780c; rom[378] = 36'h00000003f;
        rom[380] = 36'h000000000; rom[381] = 36'h008000000; rom[382] = 36'h000000040;
        rom[384] = 36'haaaaaaaab; rom[385] = 36'hfeaaaaaaa; rom[386] = 36'h00000003f;
        rom[388] = 36'hccccccccd; rom[389] = 36'hfdccccccc; rom[390] = 36'h00000003f;
        rom[392] = 36'h249249249; rom[393] = 36'hfd9249249; rom[394] = 36'h00000003f;
        rom[396] = 36'h38e38e38e; rom[397] = 36'hfce38e38e; rom[398] = 36'h00000003f;
        rom[400] = 36'h2e8ba2e8c; rom[401] = 36'hfcba2e8ba; rom[402] = 36'h00000003f;
        rom[404] = 36'hd89d89d8a; rom[405] = 36'hfc9d89d89; rom[406] = 36'h00000003f;
        rom[408] = 36'h888888889; rom[409] = 36'hfc8888888; rom[410] = 36'h00000003f;
        rom[412] = 36'h0f0f0f0f1; rom[413] = 36'hfbf0f0f0f; rom[414] = 36'h00000003f;
        rom[416] = 36'h50d79435e; rom[417] = 36'hfbd79435e; rom[418] = 36'h00000003f;
        rom[420] = 36'h30c30c30c; rom[421] = 36'hfbc30c30c; rom[422] = 36'h00000003f;
        rom[424] = 36'h8590b2164; rom[425] = 36'hfbb21642c; rom[426] = 36'h00000003f;
        rom[428] = 36'hd70a3d70a; rom[429] = 36'hfba3d70a3; rom[430] = 36'h00000003f;
        rom[432] = 36'hd097b425f; rom[433] = 36'hfb97b425e; rom[434] = 36'h00000003f;
        rom[436] = 36'h8d3dcb08d; rom[437] = 36'hfb8d3dcb0; rom[438] = 36'h00000003f;
        rom[440] = 36'h210842108; rom[441] = 36'hfb8421084; rom[442] = 36'h00000003f;
        rom[444] = 36'h3e0f83e10; rom[445] = 36'hfaf83e0f8; rom[446] = 36'h00000003f;
        rom[448] = 36'ha0ea0ea0f; rom[449] = 36'hfaea0ea0e; rom[450] = 36'h00000003f;
        rom[452] = 36'h60dd67c8a; rom[453] = 36'hfadd67c8a; rom[454] = 36'h00000003f;
        rom[456] = 36'h20d20d20d; rom[457] = 36'hfad20d20d; rom[458] = 36'h00000003f;
    end
    localparam [6:0] UE_TRIG = 7'd0, UE_FLN = 7'd42, UE_FYL2X = 7'd57, UE_FYL2P = 7'd73, UE_FREM = 7'd85, UE_FREM1 = 7'd90;
    // <<< GERADO
    reg [5:0] exc; reg sf, c3, c2, c1, c0;
    reg [5:0] fr; reg [2:0] nn, pidx; reg [63:0] dq;
    reg [3:0] us; localparam U_IDLE = 0, U_EX = 1, U_W = 2, U_X2 = 3, U_P = 4, U_PW = 5, U_PD = 6, U_F = 7, U_C0 = 8, U_C1 = 9, U_C2 = 10;
    reg [6:0] upc; reg [4:0] lc; reg [5:0] cidx; reg [1:0] q, vnt; reg eng;
    // passo corrente do programa
    wire [29:0] mi = mir;
    wire f_con = (rq[3:0] == 4'd1) || (rq[3:0] == 4'd0 && rq[21:20] != 2'd0);              // (em U_F) o passo usa uma constante
    wire [5:0] f_ci = (rq[21:20] == 2'd2) ? cidx : rq[27:22];
    assign raddr = (us == U_F) ? {1'b1, f_ci, 2'd0} : (us == U_C0) ? {1'b1, ((mir[21:20] == 2'd2) ? cidx : mir[27:22]), 2'd1} :
                   (us == U_C1) ? {1'b1, ((mir[21:20] == 2'd2) ? cidx : mir[27:22]), 2'd2} : {2'b00, upc};
    wire [3:0] mk = mi[3:0], m_aop = mi[7:4]; wire [1:0] m_rc = mi[9:8], m_bsel = mi[21:20]; wire [4:0] m_dst = mi[14:10], m_a = mi[19:15]; wire [6:0] m_b = mi[28:22]; wire m_q = mi[29];
    wire sel_cos = m_b[0];
    wire [3:0] selsrc = (sel_cos ^ q[0]) ? 4'd13 : 4'd12;                       // T5 (cos r) ou T4 (sen r)
    wire selneg = sel_cos ? (q[1] ^ q[0]) : q[1];
    function [3:0] ridx(input [4:0] r, input [2:0] t); ridx = r[4] ? {1'b0, t + r[2:0]} : r[3:0]; endfunction   // t = topo (argumento: funcao nao deve ler sinal de fora)
    wire [2:0] ib = top + nn, im1 = top - 3'd1, ip1 = top + 3'd1;
    wire rdp = !eng && (fr == 6'h31);                                          // FSAVE: le o registrador fisico 'pidx'
    wire [3:0] ia_i = rdp ? {1'b0, pidx} : !eng ? {1'b0, top} : (mk == 4'd3) ? selsrc : ridx(m_a, top);
    wire [3:0] ib_i = !eng ? {1'b0, ib} : ridx(m_b[4:0], top);
    wire [79:0] ra = stk[ia_i], rb = stk[ib_i];
    wire ea = emp[top], eb = emp[ib], full = !emp[im1];
    wire [1:0] kind = fr[5:4]; wire [3:0] code = fr[3:0];
    wire [3:0] aop = eng ? m_aop : code;
    wire memsrc = (aop == 4'd6) || (aop == 4'd9) || (aop == 4'd10);
    wire needb = (code <= 4'd3) || (code == 4'd5);
    wire wr0 = (code <= 4'd4) || (code == 4'd8);
    wire [79:0] cval = cb;
    reg astart; wire adone; wire [79:0] ares; wire [5:0] afl; wire aup; wire [2:0] acc;
    fpu_seq u_seq(.clk(clk), .rst(rst), .start(astart), .op(aop), .rc(eng ? m_rc : 2'd0), .pc(2'd3), .a(memsrc ? {16'd0, dq} : ra),
                  .b((eng && m_bsel != 2'd0) ? cval : rb), .busy(), .done(adone), .res(ares), .flags(afl), .up(aup), .cc(acc));
    reg we; reg [3:0] wi; reg [79:0] wd;
    always @(posedge clk) if (we) stk[wi] <= wd;
    assign sw = {1'b0, c3, top, c2, c1, c0, 1'b0, sf, exc[5], exc[4], exc[3], exc[2], exc[1], exc[0]};
    assign empty = emp;
    wire [79:0] kval = (code == 4'd10) ? {16'h3FFF, 64'h8000_0000_0000_0000} : (code == 4'd11) ? 80'd0 : (code == 4'd12) ? {16'h4000, 64'hC90F_DAA2_2168_C235} :
                       (code == 4'd13) ? {16'h4000, 64'hD49A_784B_CD1B_8AFE} : (code == 4'd14) ? {16'h3FFD, 64'h9A20_9A84_FBCF_F799} : {16'h3FFE, 64'hB172_17F7_D1CF_79AC};
    // programas: 2 operandos (ST0 e ST1) em FYL2X, FYL2P, FREM, FREM1; o resultado vai para ST1 (e desempilha) em FYL2X / FYL2P
    wire p2 = (code >= 4'd9), pst1 = (code == 4'd9) || (code == 4'd10), plog = (code == 4'd8) || (code == 4'd9);
    wire badlog = plog && (ra[79] || ra[78:64] == 15'd0 || ra[78:64] == 15'h7FFF || !ra[63]);   // logaritmo so de normal positivo
    wire [16:0] eint = {2'b00, ra[78:64]} - 17'd16383;
    // empilha v (ou o INDEFINIDO, com IE + SF + C1, se ST7 esta ocupado)
    task push(input [79:0] v); begin
        we <= 1'b1; wi <= {1'b0, im1}; wd <= full ? INDEF : v; top <= im1; emp[im1] <= 1'b0;
        if (full) begin exc[0] <= 1'b1; sf <= 1'b1; c1 <= 1'b1; end
    end endtask
    task under; begin exc[0] <= 1'b1; sf <= 1'b1; c1 <= 1'b0; end endtask
    always @(posedge clk) begin
        we <= 1'b0; done <= 1'b0; astart <= 1'b0;
        if (rst) begin us <= U_IDLE; top <= 3'd0; emp <= 8'hFF; exc <= 6'd0; sf <= 1'b0; c3 <= 1'b0; c2 <= 1'b0; c1 <= 1'b0; c0 <= 1'b0; eng <= 1'b0; pidx <= 3'd0; end
        else case (us)
            U_IDLE: if (go) begin fr <= fop; nn <= (fop[5:4] == 2'd1 || fop[5:4] == 2'd3) ? 3'd1 : n; dq <= din; eng <= 1'b0; us <= U_EX; end
            U_EX: begin
                us <= U_IDLE; done <= 1'b1;
                if (kind == 2'd3) case (code)
                    4'd0: begin r0 <= {40'd0, emp, sw}; pidx <= 3'd0; end
                    4'd1: begin {r1, r0} <= ra; pidx <= pidx + 3'd1; end
                    4'd2: begin {c3, top, c2, c1, c0} <= dq[14:8]; sf <= dq[6]; exc <= dq[5:0]; emp <= dq[23:16]; pidx <= 3'd0; end
                    4'd3: begin we <= 1'b1; wi <= {1'b0, pidx}; wd <= {dhi, dq}; pidx <= pidx + 3'd1; end
                    default: begin                                                 // programas
                        if (ea || (p2 && eb) || badlog) begin
                            exc[0] <= 1'b1; c1 <= 1'b0; if (ea || (p2 && eb)) sf <= 1'b1;
                            we <= 1'b1; wi <= {1'b0, pst1 ? ib : top}; wd <= INDEF; emp[pst1 ? ib : top] <= 1'b0;
                            if (pst1) begin emp[top] <= 1'b1; top <= ip1; end
                        end else begin
                            done <= 1'b0; eng <= 1'b1; us <= U_PD; vnt <= code[1:0];
                            upc <= (code <= 4'd7) ? UE_TRIG : (code == 4'd8) ? UE_FLN : (code == 4'd9) ? UE_FYL2X : (code == 4'd10) ? UE_FYL2P : (code == 4'd11) ? UE_FREM : UE_FREM1;
                        end
                    end
                endcase
                else if (kind == 2'd2) case (code)
                    4'd0: begin c1 <= 1'b0; if (eb) under; push(eb ? INDEF : rb); end
                    4'd1: begin c1 <= 1'b0; if (ea || eb) under; {r1, r0} <= ea ? INDEF : ra; we <= 1'b1; wi <= {1'b0, top}; wd <= eb ? INDEF : rb; emp[top] <= 1'b0; done <= 1'b0; us <= U_X2; end
                    4'd2: begin c1 <= 1'b0; if (ea) under; we <= 1'b1; wi <= {1'b0, ib}; wd <= ea ? INDEF : ra; emp[ib] <= 1'b0; emp[top] <= 1'b1; top <= ip1; end
                    4'd3, 4'd4: begin c1 <= 1'b0; if (ea) under; we <= 1'b1; wi <= {1'b0, top}; wd <= ea ? INDEF : {(code == 4'd3) ? ~ra[79] : 1'b0, ra[78:0]}; emp[top] <= 1'b0; end
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
                    if (wr0) begin we <= 1'b1; wi <= {1'b0, top}; wd <= INDEF; emp[top] <= 1'b0; end
                    if (code == 4'd5) begin c3 <= 1'b1; c2 <= 1'b1; c0 <= 1'b1; end
                    r0 <= (code == 4'd7) ? 64'h8000_0000_0000_0000 : (code == 4'd11) ? 64'h0000_0000_FFC0_0000 : 64'hFFF8_0000_0000_0000;
                    if (kind == 2'd1) begin emp[top] <= 1'b1; emp[ip1] <= 1'b1; top <= top + 3'd2; end
                end else begin astart <= 1'b1; done <= 1'b0; us <= U_W; end
            end
            U_W: if (adone) begin
                us <= U_IDLE; done <= 1'b1; exc <= exc | afl; c1 <= aup;
                if (wr0) begin we <= 1'b1; wi <= {1'b0, top}; wd <= ares; end
                if (code == 4'd5) begin c3 <= acc[2]; c2 <= acc[1]; c0 <= acc[0]; end
                if (memsrc) push(ares);
                r0 <= ares[63:0];
                if (kind == 2'd1) begin emp[top] <= 1'b1; emp[ip1] <= 1'b1; top <= top + 3'd2; end
            end
            U_X2: begin we <= 1'b1; wi <= {1'b0, ib}; wd <= {r1, r0}; emp[ib] <= 1'b0; us <= U_IDLE; done <= 1'b1; end
            // ---- executor de programas: um passo por vez; U_PD da um clock para a escrita anterior chegar a memoria; U_F / U_C* buscam o passo e a constante ----
            U_PD: us <= U_F;                                                       // a ROM esta lendo o passo 'upc'
            U_F: begin mir <= rq[29:0]; us <= f_con ? U_C0 : U_P; end
            U_C0: begin cb[35:0] <= rq; us <= U_C1; end
            U_C1: begin cb[71:36] <= rq; us <= U_C2; end
            U_C2: begin cb[79:72] <= rq[7:0]; us <= U_P; end
            U_P: begin
                us <= U_PD; upc <= upc + 7'd1;
                case (mk)
                    4'd0: begin astart <= 1'b1; upc <= upc; us <= U_PW; end
                    4'd1: begin we <= 1'b1; wi <= ridx(m_dst, top); wd <= cval; if (m_bsel == 2'd2) cidx <= cidx - 6'd1; end
                    4'd2: begin we <= 1'b1; wi <= ridx(m_dst, top); wd <= {16'h3FFF, ra[63:0]}; dq <= {{47{eint[16]}}, eint}; end
                    4'd3: begin we <= 1'b1; wi <= ridx(m_dst, top); wd <= {ra[79] ^ selneg, ra[78:0]}; end
                    4'd4: push(ra);
                    4'd5: if (lc != 5'd0) begin lc <= lc - 5'd1; upc <= m_b; end
                    4'd6: begin lc <= m_a; cidx <= m_b[5:0]; end
                    4'd8: upc <= upc + 7'd1 + {3'd0, vnt, 2'b00};
                    default: begin                                                 // fim: desempilha (m_a[0]) e termina
                        if (m_a[0]) begin emp[top] <= 1'b1; top <= ip1; end
                        eng <= 1'b0; done <= 1'b1; us <= U_IDLE;
                    end
                endcase
            end
            U_PW: if (adone) begin
                exc <= exc | afl; c1 <= aup; upc <= upc + 7'd1; us <= U_PD;
                if (m_q) q <= ares[1:0]; else begin we <= 1'b1; wi <= ridx(m_dst, top); wd <= ares; end
                if (m_bsel == 2'd2) cidx <= cidx - 6'd1;
            end
            default: us <= U_IDLE;
        endcase
    end
`endif
endmodule
