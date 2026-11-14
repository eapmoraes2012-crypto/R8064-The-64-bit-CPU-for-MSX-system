// alu_core_s.v - nucleo da ALU em 2 ESTAGIOS (somador de 64 bits dividido em 2 x 32). Mesma semantica de flags de alu_core.v.
// Estagio A (entradas = registradores X2): soma baixa de 32 bits (+ci), logica/deslocamento, Z da soma em paralelo, bits de hc/sinais -> registradores B.
// Estagio B (saidas validas 1 clock depois): soma alta de 32 bits com o vai-um do estagio A, mascara de tamanho, flags.
// 'en' = 0 congela os registradores B (hold do pipeline).
module alu_core_s(
    input  wire        clk, en,
    input  wire [63:0] xa, yb, yy,
    input  wire        ci,
    input  wire [21:0] ctl,
    input  wire [1:0]  sz,
    input  wire [7:0]  fin,
    output wire [63:0] res,
    output wire [7:0]  fout,
    output wire [1:0]  xa53,     // bits 5 e 3 do operando A (flags X/Y de BIT n,r)
    output wire        hc12      // meio-vai-um do bit 11 -> 12 (flag H das somas de 16 bits do Z80: ADD/ADC/SBC HL,rr)
);
    // ---------------- estagio A
    wire c_and=ctl[6], c_or=ctl[7], c_xor=ctl[8], c_cpl=ctl[9], c_shl=ctl[10], c_shr=ctl[11], c_sar=ctl[12], c_rol=ctl[13], c_ror=ctl[14];
    wire [63:0] m   = (sz == 2'd0) ? 64'h0000_0000_0000_00FF : (sz == 2'd1) ? 64'h0000_0000_0000_FFFF :
                      (sz == 2'd2) ? 64'h0000_0000_FFFF_FFFF : 64'hFFFF_FFFF_FFFF_FFFF;
    wire [5:0]  msb = (sz == 2'd0) ? 6'd7 : (sz == 2'd1) ? 6'd15 : (sz == 2'd2) ? 6'd31 : 6'd63;
    wire [63:0] x = xa, bm = yb, y = yy;
    wire [32:0] lo = {1'b0, x[31:0]} + {1'b0, y[31:0]} + {32'd0, ci};
    wire top = x[msb], low = x[0];
    wire c_insc = ctl[17], c_ins1 = ctl[18], c_daa = ctl[19];
    wire ins = (c_insc & fin[0]) | c_ins1;            // bit que entra por baixo em RL / SLL
    // DAA (8 bits, regras do Z80): ajuste 06h se H ou nibble baixo > 9; 60h se C ou A > 99h; soma ou subtrai conforme N
    wire       daa_lo = fin[4] || (x[3:0] > 4'd9);
    wire       daa_c  = fin[0] || (x[7:0] > 8'h99);
    wire [7:0] daa_t  = {1'b0, daa_c, daa_c, 1'b0, 1'b0, daa_lo, daa_lo, 1'b0};
    wire [7:0] daa_r  = fin[1] ? (x[7:0] - daa_t) : (x[7:0] + daa_t);
    wire       daa_h  = fin[1] ? (fin[4] && (x[3:0] < 4'd6)) : (x[3:0] > 4'd9);
    reg [63:0] lr; reg sh_out;
    always @* begin
        lr = 64'd0; sh_out = 1'b0;
        if (c_and) lr = x & bm;
        else if (c_or) lr = x | bm;
        else if (c_xor) lr = x ^ bm;
        else if (c_cpl) lr = ~x & m;
        else if (c_daa) begin sh_out = daa_c; lr = {56'd0, daa_r}; end
        else if (ctl[20]) lr = (x << 4) & m;
        else if (ctl[21]) lr = x >> 4;
        else if (c_shl) begin sh_out = top; lr = ((x << 1) & m) | {63'd0, ins}; end
        else if (c_shr) begin sh_out = low; lr = (x >> 1) | ({63'd0, c_insc & fin[0]} << msb); end
        else if (c_sar) begin sh_out = low; lr = (x >> 1) | ({63'd0, top} << msb); end
        else if (c_rol) begin sh_out = top; lr = ((x << 1) & m) | {63'd0, top}; end
        else if (c_ror) begin sh_out = low; lr = (x >> 1) | ({63'd0, low} << msb); end
    end
    wire par_a = ~^lr[7:0];
    wire [63:0] zk = {(x[62:0] | y[62:0]), ci};
    wire za_a  = ((((x ^ y) ^ zk) & m) == 64'd0);      // x+y+ci==0 sem esperar a cadeia de vai-um
    wire hc_a  = c_daa ? daa_h : (x[4] ^ bm[4] ^ lo[4]);
    wire hc12_a = x[12] ^ bm[12] ^ lo[12];
    // registradores do estagio B
    reg [32:0] lo_b; reg [31:0] xh_b, yh_b; reg [63:0] lr_b;
    reg sh_b, par_b, za_b, hc_b, xs_b, ys_b, yb5_b, yb3_b, hc12_b;
    reg [21:0] ctl_b; reg [1:0] xa53_b; assign xa53 = xa53_b; reg [1:0] sz_b; reg [7:0] fin_b;
    always @(posedge clk) if (en) begin
        lo_b <= lo; xh_b <= x[63:32]; yh_b <= y[63:32]; lr_b <= lr; sh_b <= sh_out;
        par_b <= par_a; za_b <= za_a; hc_b <= hc_a; hc12_b <= hc12_a; xa53_b <= {x[5], x[3]}; xs_b <= x[msb]; ys_b <= y[msb];
        yb5_b <= bm[5]; yb3_b <= bm[3]; ctl_b <= ctl; sz_b <= sz; fin_b <= fin;
    end
    // ---------------- estagio B
    wire keep_c=ctl_b[4], arith=ctl_b[5], is_sub=ctl_b[3], is_cp=ctl_b[15], undef=ctl_b[16];
    wire b_and=ctl_b[6], b_or=ctl_b[7], b_xor=ctl_b[8], b_cpl=ctl_b[9];
    wire is_logic = b_and | b_or | b_xor;
    wire is_shift = ctl_b[10] | ctl_b[11] | ctl_b[12] | ctl_b[13] | ctl_b[14];
    wire b_daa = ctl_b[19];
    assign hc12 = hc12_b;
    wire [63:0] mb  = (sz_b == 2'd0) ? 64'h0000_0000_0000_00FF : (sz_b == 2'd1) ? 64'h0000_0000_0000_FFFF :
                      (sz_b == 2'd2) ? 64'h0000_0000_FFFF_FFFF : 64'hFFFF_FFFF_FFFF_FFFF;
    wire [5:0]  msbb = (sz_b == 2'd0) ? 6'd7 : (sz_b == 2'd1) ? 6'd15 : (sz_b == 2'd2) ? 6'd31 : 6'd63;
    wire [32:0] hs   = {1'b0, xh_b} + {1'b0, yh_b} + {32'd0, lo_b[32]};
    wire [64:0] sum  = {hs, lo_b[31:0]};
    wire [63:0] sres = sum[63:0] & mb;
    // vai-um e bit de sinal: so o caso de 64 bits depende da soma alta (hs); os demais saem de lo_b (registrado), tirando o mux 64:1 do caminho do somador alto
    wire cout = (sz_b == 2'd3) ? hs[32] : (sz_b == 2'd2) ? lo_b[32] : (sz_b == 2'd1) ? lo_b[16] : lo_b[8];
    wire rs   = (sz_b == 2'd3) ? hs[31] : (sz_b == 2'd2) ? lo_b[31] : (sz_b == 2'd1) ? lo_b[15] : lo_b[7];
    wire ovf  = (xs_b == ys_b) && (rs != xs_b);
    wire [63:0] r = arith ? sres : lr_b;
    assign res = (undef ? 64'd0 : r) & mb;
    wire c_o = arith ? (keep_c ? fin_b[0] : (is_sub ? ~cout : cout)) : ((is_shift | b_daa) ? sh_b : 1'b0);
    wire s_o = arith ? rs : lr_b[msbb];
    wire zl_b = ((lr_b & mb) == 64'd0);                 // Z do caminho logico: calculado no estagio B (corta o caminho do estagio A)
    wire z_o = arith ? za_b : zl_b;
    wire [7:0] f_nor;
    assign f_nor[7] = s_o;
    assign f_nor[6] = z_o;
    assign f_nor[5] = is_cp ? yb5_b : r[5];
    assign f_nor[4] = (arith | b_daa) ? hc_b : (b_and | b_cpl);
    assign f_nor[3] = is_cp ? yb3_b : r[3];
    assign f_nor[2] = arith ? ovf : (is_logic | is_shift | b_daa) ? par_b : (b_cpl ? fin_b[2] : 1'b0);
    assign f_nor[1] = arith ? is_sub : b_daa ? fin_b[1] : b_cpl;
    assign f_nor[0] = b_cpl ? fin_b[0] : c_o;
    assign fout = undef ? fin_b : b_cpl ? {fin_b[7], fin_b[6], f_nor[5:0]} : f_nor;
endmodule
