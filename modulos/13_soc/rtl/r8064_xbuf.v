// r8064_xbuf.v - buffer de 16 KB da janela de troca MSX <-> R8064 (REV46). 8 raias de 2048 x 8 bits (8 BSRAM), porta unica por raia.
// Dono do buffer (win): win = 1 -> MSX (acesso byte a byte, A[13:0] da pagina 2) | win = 0 -> DMA do R8064 (palavras de 64 bits, 1 por clock).
// A posse e exclusiva (half-duplex), por isso uma unica porta por raia basta: o endereco e os dados sao multiplexados por win.
// Lado MSX: o endereco s_a deve ficar estavel >= 1 clock ANTES do pulso s_re (a leitura da BSRAM tem 1 clock de latencia); com win = 0 a leitura devolve FFh e a escrita e ignorada.
// Lado DMA: d_a/d_wd/d_we valem so com win = 0; d_q e valido 1 clock depois de d_a (r8064_dma faz isso na espera E_RWB).
// INIT_IMG=1: conteudo inicial = imagem do monitor, 8 arquivos <INIT_PFX><lane>.hex (1 byte por linha, 2048 linhas), copiada para a SDRAM no boot (r8064_soc, BOOT_WORDS).
// Conteudo inicial (configuracao do FPGA): assinatura "R8064", versao do protocolo (1), 0, 0 nos 8 primeiros bytes. O monitor deve refaze-la ao iniciar.
module r8064_xbuf #(parameter INIT_IMG = 0, parameter INIT_PFX = "monitor_l")(
    input  wire        clk,
    input  wire        win,
    input  wire        s_we, s_re, input wire [13:0] s_a, input wire [7:0] s_wd, output wire [7:0] s_rd,
    input  wire        d_re, d_we, input wire [10:0] d_a, input wire [63:0] d_wd, output wire [63:0] d_q
);
    reg [2:0] lane_q; always @(posedge clk) lane_q <= s_a[2:0];
    wire [7:0] q [0:7];
    genvar g;
    generate for (g = 0; g < 8; g = g + 1) begin : lane
        reg [7:0] mem [0:2047];
        reg [7:0] qr;
        if (INIT_IMG) begin : img
            initial $readmemh({INIT_PFX, 8'h30 + g[7:0], ".hex"}, mem);
        end else begin : sig
        initial begin
            mem[0] = (g == 0) ? 8'h52 : (g == 1) ? 8'h38 : (g == 2) ? 8'h30 : (g == 3) ? 8'h36 : (g == 4) ? 8'h34 : (g == 5) ? 8'h01 : 8'h00;   // 'R','8','0','6','4',1,0,0
        end
        end
        wire [10:0] a  = win ? s_a[13:3] : d_a;
        wire        we = win ? (s_we && s_a[2:0] == g) : d_we;
        wire [7:0]  wd = win ? s_wd : d_wd[8*g +: 8];
        always @(posedge clk) begin
            if (we) mem[a] <= wd;
            qr <= mem[a];
        end
        assign q[g] = qr;
    end endgenerate
    assign s_rd = win ? q[lane_q] : 8'hFF;
    assign d_q  = {q[7], q[6], q[5], q[4], q[3], q[2], q[1], q[0]};
endmodule
