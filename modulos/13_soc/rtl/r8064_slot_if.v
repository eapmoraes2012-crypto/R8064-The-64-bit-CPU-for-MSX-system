// r8064_slot_if.v - interface de cartucho do slot MSX por PORTAS DE E/S (sem acesso a memoria): sincroniza /IORQ, /RD, /WR e A0-A7 ao clock do SoC,
// reconhece os ciclos de E/S nas portas 0Bh (estado/comando), 0Ch (dados) e 0Dh (comprimento) e os converte no barramento de FIFOs (fm_*) do r8064_fifo_if,
// por meio do r8064_slot_dec. Escrito para a placa V9968_Cartridge (Tang Nano 20K + 3 x SN74LVC8T245 + 3 MOSFET), que so liga ao FPGA:
//   A0-A7, D0-D7, /IORQ, /RD, /WR, /RESET (entradas), e WAIT, INT, DIR do barramento de dados (saidas; WAIT/INT/BUSDIR passam por MOSFET: 1 = ativa a linha do slot).
// Polaridade na placa: data_dir = 1 -> o FPGA dirige o barramento (leitura pelo MSX) e o mesmo sinal puxa /BUSDIR para baixo; data_dir = 0 -> MSX -> cartucho.
//
// Leitura (MSX le a porta): ao ver /IORQ e /RD ativos com endereco 0Bh..0Dh o bloco gera UM pulso fm_re (efeito colateral: o DADO retira um byte da FIFO),
//   captura fm_rd (combinacional na mesma fase do pulso) e dirige o barramento (d_oe = 1, data_dir = 1) ate /IORQ ou /RD voltarem a 1.
//   Latencia: 2 clocks de sincronismo + 1 = cerca de 52 ns a 57 MHz, bem dentro do ciclo de E/S do Z80 (>= 2 T-states + 1 espera do MSX ~ 840 ns).
// Escrita: o dado e amostrado 8 clocks (cerca de 140 ns) depois de /WR sincronizado cair, porque alguns bits ainda estao subindo logo apos a borda de /WR
//   (efeito observado em MSX reais na placa de referencia); gera UM pulso fm_we por ciclo. O ciclo de escrita do Z80 dura >= 400 ns.
// WAIT: nao e usado (o estado e consultado por polling); a saida existe e fica em 0 (reservada, ex.: FIFO cheia).
// INT : irq (fifo_irq, nivel) -> slot_int (1 = INT ativo no slot).
// Fora das portas 0Bh..0Dh o bloco nao dirige o barramento nem a linha DIR (o ciclo pertence a outro dispositivo).
module r8064_slot_if #(parameter P_ST = 8'h0B, parameter P_DT = 8'h0C, parameter P_LN = 8'h0D, parameter WR_DLY = 8)(
    input  wire       clk, rst,
    // slot (assincronos, ja no nivel de 3,3 V pelos conversores)
    input  wire       slot_iorq_n, slot_rd_n, slot_wr_n,
    input  wire [7:0] slot_a,
    input  wire [7:0] slot_d_i,
    output wire [7:0] slot_d_o,
    output wire       slot_d_oe,
    output wire       slot_data_dir,
    output wire       slot_wait,
    output wire       slot_int,
    // lado FIFO (m_*) do r8064_fifo_if
    output wire       fm_we, fm_re, output wire [1:0] fm_a, output wire [7:0] fm_wd, input wire [7:0] fm_rd,
    input  wire       irq
);
    // sincronizadores de 2 FF (valor em repouso: inativo)
    reg [1:0] sio = 2'b11, srd = 2'b11, swr = 2'b11;
    reg [7:0] a_s1 = 8'd0, a_s = 8'd0;
    always @(posedge clk) begin
        sio <= {sio[0], slot_iorq_n}; srd <= {srd[0], slot_rd_n}; swr <= {swr[0], slot_wr_n};
        a_s1 <= slot_a; a_s <= a_s1;
    end
    wire iorq = ~sio[1], rd = ~srd[1], wr = ~swr[1];

    // decodificacao de porta (combinacional sobre o endereco sincronizado)
    reg [3:0] wc = 4'd0; reg we_p = 1'b0; reg [7:0] d_l = 8'd0; reg drv = 1'b0; reg [7:0] rd_lat = 8'd0;
    wire d_re, d_we; wire [1:0] d_a; wire [7:0] d_wd; wire hit; wire [7:0] d_rdv;
    wire act_rd = iorq & rd & ~wr & hit;
    wire act_wr = iorq & wr & ~rd & hit;
    wire re_p = act_rd & ~drv;                    // um pulso por ciclo de leitura
    r8064_slot_dec #(.P_ST(P_ST), .P_DT(P_DT), .P_LN(P_LN)) u_dec(.clk(clk), .rst(rst),
        .io_we(we_p), .io_re(re_p), .io_a(a_s), .io_wd(d_l), .io_rd(d_rdv), .io_hit(hit),
        .fm_we(fm_we), .fm_re(fm_re), .fm_a(fm_a), .fm_wd(fm_wd), .fm_rd(fm_rd));
    always @(posedge clk) begin
        if (rst) begin wc <= 4'd0; we_p <= 1'b0; drv <= 1'b0; end
        else begin
            drv <= act_rd;
            if (re_p) rd_lat <= d_rdv;
            we_p <= 1'b0;
            if (!act_wr) wc <= 4'd0;
            else if (wc < WR_DLY) begin
                wc <= wc + 4'd1;
                if (wc == WR_DLY - 1) begin d_l <= slot_d_i; we_p <= 1'b1; end
            end
        end
    end
    assign slot_d_o      = rd_lat;
    assign slot_d_oe     = drv & act_rd & ~slot_iorq_n & ~slot_rd_n;   // solta o barramento no mesmo instante em que /RD ou /IORQ sobem (sem esperar o sincronizador)
    assign slot_data_dir = slot_d_oe;
    assign slot_wait     = 1'b0;
    assign slot_int      = irq;
endmodule
