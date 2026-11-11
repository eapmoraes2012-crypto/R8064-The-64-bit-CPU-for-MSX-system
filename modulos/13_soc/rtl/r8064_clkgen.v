// r8064_clkgen.v - gerador do clock do sistema (alvo 57,2727 MHz = 3,579545 MHz x 16) para a Tang Nano 20K (GW2AR-18).
// Fontes (parametro SRC, escolhido na sintese):
//   SRC=0  clk_in = cristal da placa, 27 MHz        -> rPLL 27 x 17 / 8       = 57,375 MHz   (erro +0,18 %; razao exata 70/33 inviavel: PFD < 3 MHz)
//   SRC=1  clk_in = 3,579545 MHz (cristal/oscilador externo ou CLOCK do slot MSX) -> rPLL x 16 = 57,2727 MHz (exato, sincrono com o MSX)
//   SRC=2  clk_in = oscilador ativo de 57,2727 MHz direto (sem PLL; locked = 1; clk_sdram = clk)
//   SRC=3  clk_in = 14,31818 MHz (4 x 3,579545; ex.: pino clk14m da placa de cartucho) -> rPLL x4 = 57,2727 MHz (exato)
// Cristal "nu" de 3,579545 MHz precisa de um oscilador externo (ex.: Pierce com 74HC04, ou modulo oscilador); o FPGA recebe a onda ja quadrada em clk_in.
// VCO (SRC=0): 27/8*17*16 = 918 MHz ; (SRC=1): 3,579545*16*16 = 916,4 MHz - ambos dentro de 500-1250 MHz do GW2A.
// rst: ativo alto; fica em 1 ate o PLL travar + 16 ciclos do clock gerado (liberacao sincrona).
// Simulacao (-DSIM): modelo comportamental que mede o periodo de clk_in e gera clk = clk_in * MUL / DIV.
module r8064_clkgen #(parameter SRC = 1, parameter [3:0] SDR_PSDA = 4'd4)(   // SDR_PSDA: fase do clk_sdram em passos de 22,5 graus (4 = 90 graus); ajustar no hardware
    input  wire clk_in,
    input  wire rst_in,      // reset assincrono externo (ativo alto), opcional (0 se nao usado)
    output wire clk,
    output wire clk_sdram,   // clock enviado a SDRAM (O_sdram_clk): CLKOUTP do PLL com defasagem SDR_PSDA
    output wire locked,
    output wire rst
);
    wire pll_lock, pll_clk, pll_clkp;
    generate
    if (SRC == 2) begin : g_direct
        assign pll_clk  = clk_in;
        assign pll_clkp = clk_in;
        assign pll_lock = 1'b1;
    end else begin : g_pll
`ifdef SIM
        localparam MUL = (SRC == 0) ? 17 : (SRC == 3) ? 4 : 16;
        localparam DIV = (SRC == 0) ? 8  : 1;
        real per, half, t_last; integer n; reg ck, lk;
        initial begin ck = 0; lk = 0; n = 0; t_last = 0; per = 0; half = 1; end
        always @(posedge clk_in) begin
            if (n >= 1) per = $realtime - t_last;
            t_last = $realtime;
            if (n < 20) n = n + 1;
            if (n == 20) begin lk <= 1'b1; half = per * DIV / (2.0 * MUL); end
        end
        always begin #(half) if (n == 20) ck = ~ck; end
        assign pll_clk = ck; assign pll_lock = lk;
        reg ckp = 1'b0;
        always @(ck) ckp <= #(half * SDR_PSDA / 8.0) ck;   // defasagem = SDR_PSDA/16 do periodo
        assign pll_clkp = ckp;
`else
        // IDIV_SEL = IDIV-1 ; FBDIV_SEL = FBDIV-1 ; fout = fin*FBDIV/IDIV ; VCO = fout*ODIV
        localparam [4*8-1:0] SDR_PSDA_S = {"0"+SDR_PSDA[3], "0"+SDR_PSDA[2], "0"+SDR_PSDA[1], "0"+SDR_PSDA[0]};   // "0100" etc.
        rPLL #(
            .FCLKIN       ((SRC == 0) ? "27" : (SRC == 3) ? "14.31818" : "3.579545"),
            .DEVICE       ("GW2A-18"),
            .IDIV_SEL     ((SRC == 0) ? 7  : 0),
            .FBDIV_SEL    ((SRC == 0) ? 16 : (SRC == 3) ? 3 : 15),
            .ODIV_SEL     (16),
            .DYN_IDIV_SEL ("false"), .DYN_FBDIV_SEL ("false"), .DYN_ODIV_SEL ("false"),
            .PSDA_SEL     (SDR_PSDA_S), .DYN_DA_EN ("false"), .DUTYDA_SEL ("1000"),
            .CLKOUT_FT_DIR(1'b1), .CLKOUTP_FT_DIR(1'b1), .CLKOUT_DLY_STEP(0), .CLKOUTP_DLY_STEP(0),
            .CLKFB_SEL    ("internal"), .CLKOUT_BYPASS("false"), .CLKOUTP_BYPASS("false"), .CLKOUTD_BYPASS("false"),
            .DYN_SDIV_SEL (2), .CLKOUTD_SRC("CLKOUT"), .CLKOUTD3_SRC("CLKOUT")
        ) u_pll (
            .CLKOUT(pll_clk), .LOCK(pll_lock), .CLKOUTP(pll_clkp), .CLKOUTD(), .CLKOUTD3(),
            .RESET(rst_in), .RESET_P(1'b0), .CLKIN(clk_in), .CLKFB(1'b0),
            .FBDSEL(6'b0), .IDSEL(6'b0), .ODSEL(6'b0), .PSDA(4'b0), .DUTYDA(4'b0), .FDLY(4'b0));
`endif
    end
    endgenerate

    assign clk    = pll_clk;
    assign clk_sdram = pll_clkp;
    assign locked = pll_lock;
    // liberacao sincrona do reset: so sai de reset 16 ciclos depois do lock
    reg [4:0] cnt = 5'd0; reg rst_r = 1'b1;
    always @(posedge pll_clk or negedge pll_lock) begin
        if (!pll_lock) begin cnt <= 5'd0; rst_r <= 1'b1; end
        else begin
            if (!cnt[4]) cnt <= cnt + 5'd1;
            rst_r <= !cnt[4];
        end
    end
    assign rst = rst_r;
endmodule
