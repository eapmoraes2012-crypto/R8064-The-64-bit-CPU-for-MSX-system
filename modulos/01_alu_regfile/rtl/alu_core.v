// alu_core.v - nucleo da ALU (estagio X). Semantica de flags: ver alu64.v/ref (premissas). Entradas ja preparadas por alu_prep.
module alu_core(
    input  wire [63:0] xa,
    input  wire [63:0] yb,
    input  wire [63:0] yy,
    input  wire        ci,
    input  wire [16:0] ctl,
    input  wire [1:0]  sz,      // 0=8, 1=16, 2=32, 3=64 bits
    input  wire [7:0]  fin,
    output wire [63:0] res,
    output wire [7:0]  fout
);
    wire inv=ctl[0], cin1=ctl[1], cin0=ctl[2], is_sub=ctl[3], keep_c=ctl[4], arith=ctl[5];
    wire c_and=ctl[6], c_or=ctl[7], c_xor=ctl[8], c_cpl=ctl[9], c_shl=ctl[10], c_shr=ctl[11], c_sar=ctl[12], c_rol=ctl[13], c_ror=ctl[14], is_cp=ctl[15], undef=ctl[16];
    wire is_logic = c_and | c_or | c_xor;
    wire is_shift = c_shl | c_shr | c_sar | c_rol | c_ror;

    wire [63:0] m   = (sz == 2'd0) ? 64'h0000_0000_0000_00FF :
                      (sz == 2'd1) ? 64'h0000_0000_0000_FFFF :
                      (sz == 2'd2) ? 64'h0000_0000_FFFF_FFFF : 64'hFFFF_FFFF_FFFF_FFFF;
    wire [5:0]  msb = (sz == 2'd0) ? 6'd7 : (sz == 2'd1) ? 6'd15 : (sz == 2'd2) ? 6'd31 : 6'd63;
    wire [63:0] x   = xa;
    wire [63:0] bm  = yb;
    wire [63:0] y   = yy;

    // ---- caminho aritmetico (cadeia de vai-um)
    wire [64:0] sum  = {1'b0, x} + {1'b0, y} + {64'd0, ci};
    wire [63:0] sres = sum[63:0] & m;
    wire        cout = (sz == 2'd0) ? sum[8] : (sz == 2'd1) ? sum[16] : (sz == 2'd2) ? sum[32] : sum[64];
    wire        xs = x[msb], ys = y[msb], rs = sres[msb];
    wire        ovf = (xs == ys) && (rs != xs);
    wire        hc  = x[4] ^ bm[4] ^ sres[4];

    // ---- caminho logico / deslocamento (em paralelo, fora da cadeia de vai-um)
    wire        top = x[msb];
    wire        low = x[0];
    reg  [63:0] lr;
    reg         sh_out;
    always @* begin
        lr = 64'd0; sh_out = 1'b0;
        if (c_and) lr = x & bm;
        else if (c_or) lr = x | bm;
        else if (c_xor) lr = x ^ bm;
        else if (c_cpl) lr = ~x & m;
        else if (c_shl) begin sh_out = top; lr = (x << 1) & m; end
        else if (c_shr) begin sh_out = low; lr = x >> 1; end
        else if (c_sar) begin sh_out = low; lr = (x >> 1) | ({63'd0, top} << msb); end
        else if (c_rol) begin sh_out = top; lr = ((x << 1) & m) | {63'd0, top}; end
        else if (c_ror) begin sh_out = low; lr = (x >> 1) | ({63'd0, low} << msb); end
    end
    wire [63:0] r   = arith ? sres : lr;
    assign res = (undef ? 64'd0 : r) & m;
    wire par = ~^lr[7:0];
    wire zl  = ((lr & m) == 64'd0);        // Z do caminho nao aritmetico
    wire za  = (sres == 64'd0);            // Z do caminho aritmetico
    wire c_o = arith ? (keep_c ? fin[0] : (is_sub ? ~cout : cout)) : (is_shift ? sh_out : 1'b0);
    wire s_o = arith ? rs : lr[msb];
    wire z_o = arith ? za : zl;
    wire [7:0] f_nor;
    assign f_nor[7] = s_o;
    assign f_nor[6] = z_o;
    assign f_nor[5] = is_cp ? yb[5] : r[5];
    assign f_nor[4] = arith ? hc : (c_and | c_cpl);
    assign f_nor[3] = is_cp ? yb[3] : r[3];
    assign f_nor[2] = arith ? ovf : (is_logic | is_shift) ? par : (c_cpl ? fin[2] : 1'b0);
    assign f_nor[1] = arith ? is_sub : c_cpl;
    assign f_nor[0] = c_cpl ? fin[0] : c_o;
    assign fout = undef ? fin : c_cpl ? {fin[7], fin[6], f_nor[5:0]} : f_nor;
endmodule
