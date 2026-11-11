// r8064_pipe.v - pipeline de 7 estagios do R8064 (modelo de TEMPORIZACAO dirigido por traco de execucao).
// Estagios: 0=F1 (endereco/PC), 1=F2 (barramento: busca), 2=D (decodificacao), 3=R (registradores), 4=X (execucao),
//           5=M (acesso a dados/E/S), 6=W (escrita). Ordem estrita, sem adiantamento de resultados e SEM hazards de dados
//           (o traco ja e a trajetoria executada; hazards nao sao modelados - ver README).
// - Barramento unico: F2 e M disputam; M tem prioridade (acesso em curso nao e interrompido).
// - Cada acesso ao barramento custa 1 + W clocks (W_RD / W_WR / W_IO conforme a planilha).
// - Desvio tomado: o buscador continua buscando instrucoes do caminho errado (ocupam o barramento) ate a resolucao no
//   estagio D (pen=1), X (pen=2) ou M (pen=3); a resolucao esvazia os estagios mais novos.
// - O decodificador real (r8064_decode) fica no estagio D; sua saida e conferida contra a leitura combinacional das ROMs.
// Parametros: DEC_D = clocks do estagio D (1 = ideal da planilha; 2 = decodificador real: +1 id, +2 controle).
//             SERIAL = 1: a busca da proxima instrucao so comeca depois que F2 da anterior terminou + LEN_LAT clocks
//             (o comprimento vem da decodificacao); 0: busca sequencial antecipada (suposicao da planilha).
module r8064_pipe #(
    parameter NTRACE = 1,
    parameter TRACE_FILE = "trace.mem",
    parameter WRD = 4, WWR = 2, WIO = 1,
    parameter DEC_D = 1, LEN_LAT = 0, SERIAL = 0
)(
    input  wire clk,
    input  wire rst,
    output reg  done,
    output reg  [31:0] cycles,
    output reg  [31:0] retired,
    output reg  [31:0] chk_n,
    output reg  [31:0] chk_err,
    output reg  [31:0] f2_stall,
    output reg  [31:0] wp_fetch
);
    reg [15:0] trace [0:NTRACE-1];
    reg [11:0] rom_a [0:255];
    reg [7:0]  amb   [0:255];
    reg [9:0]  rom_b [0:33*256-1];
    reg [31:0] ctrl  [0:511];
    initial begin
        $readmemh(TRACE_FILE, trace);
        $readmemh("rom_ed_a.mem", rom_a); $readmemh("amb_idx.mem", amb);
        $readmemh("rom_ed_b.mem", rom_b); $readmemh("ctrl.mem", ctrl);
    end
    function [31:0] ctrl_of(input [7:0] b2, input [7:0] b3);
        reg [11:0] a; reg [7:0] am; reg [9:0] id;
        begin a = rom_a[b2]; am = amb[b2]; id = a[10] ? rom_b[{am[5:0], b3}] : a[9:0]; ctrl_of = ctrl[id[8:0]]; end
    endfunction
    localparam [31:0] C_WP = 32'h0001_0003;      // caminho errado: 3 bytes, 1 busca, EX=1, sem desvio

    // decodificador real no estagio D
    reg  v [0:6]; reg wp [0:6]; integer idx [0:6]; integer rem [0:6]; reg [31:0] c [0:6]; reg chk [0:6]; reg fz [0:6];
    wire [7:0] b2d = (v[2] && !wp[2]) ? trace[idx[2]][15:8] : 8'h00;
    wire [7:0] b3d = (v[2] && !wp[2]) ? trace[idx[2]][7:0]  : 8'h00;
    wire [3:0] d_len; wire [4:0] d_nr, d_nw; wire [1:0] d_nio, d_pen; wire [7:0] d_ex; wire d_cond, d_z80, d_ill; wire [9:0] d_id;
    r8064_decode dec(.clk(clk), .b2(b2d), .b3(b3d), .id(d_id), .illegal(d_ill), .len(d_len), .nr(d_nr), .nw(d_nw),
                     .nio(d_nio), .ex(d_ex), .pen_code(d_pen), .has_cond(d_cond), .is_z80(d_z80));
    wire [31:0] dword = {4'd0, 1'b0, d_z80, d_cond, d_pen, d_ex, d_nio, d_nw, d_nr, d_len};

    function integer work(input integer k, input [31:0] w);
        integer nacc, nr, nw, nio, ex, mb, mi;
        begin
            nacc = (w[3:0] + 7) / 8; nr = w[8:4]; nw = w[13:9]; nio = w[15:14]; ex = w[23:16];
            mb = nr * (1 + WRD) + nw * (1 + WWR); mi = nio * (1 + WIO);
            case (k)
                0: work = 1;
                1: work = nacc * (1 + WRD);
                2: work = DEC_D;
                3: work = 1;
                4: work = (ex < 1) ? 1 : ex;
                5: work = (mb > mi) ? ((mb < 1) ? 1 : mb) : ((mi < 1) ? 1 : mi);
                default: work = 1;
            endcase
        end
    endfunction

    integer k, fp, lenwait, ecount, pen_s;
    reg wp_mode; reg [6:0] dn; reg bus_m; reg [31:0] cw; reg [1:0] pc;
    always @(posedge clk) begin
        if (rst) begin
            for (k = 0; k < 7; k = k + 1) begin v[k] = 0; wp[k] = 0; idx[k] = 0; rem[k] = 0; c[k] = 0; chk[k] = 0; fz[k] = 0; end
            fp = 0; lenwait = 0; ecount = 0; wp_mode = 0;
            done <= 0; cycles <= 0; retired <= 0; chk_n <= 0; chk_err <= 0; f2_stall <= 0; wp_fetch <= 0;
        end else if (!done) begin
            ecount = ecount + 1;
            bus_m = v[5] && (rem[5] > 0) && ((c[5][8:4] + c[5][13:9]) != 0);
            // conferencia do decodificador real: 1o clock em R (saida registrada do estagio D)
            if (v[3] && chk[3] && !wp[3] && DEC_D >= 2) begin
                chk_n <= chk_n + 1;
                if (dword[27:0] !== c[3][27:0]) chk_err <= chk_err + 1;
            end
            chk[3] = 0;
            // progresso do trabalho de cada estagio
            for (k = 0; k < 7; k = k + 1)
                if (v[k] && rem[k] > 0) begin
                    if (k == 1 && bus_m) f2_stall <= f2_stall + 1;
                    else rem[k] = rem[k] - 1;
                end
            for (k = 0; k < 7; k = k + 1) dn[k] = v[k] && (rem[k] == 0);   // pronto para sair neste clock
            if (lenwait > 0) lenwait = lenwait - 1;
            // movimentos, do fim para o inicio
            for (k = 6; k >= 1; k = k - 1) begin
                if (k == 6 && dn[6] && v[6]) begin
                    v[6] = 0;
                    if (!wp[6]) begin
                        retired <= retired + 1;
                        if (retired + 1 == NTRACE) begin done <= 1; cycles <= ecount - 1; end
                    end
                end
                if (dn[k-1] && v[k-1] && !v[k]) begin
                    cw = c[k-1];
                    pc = cw[25:24];
                    v[k] = 1; wp[k] = wp[k-1]; idx[k] = idx[k-1]; c[k] = cw; rem[k] = work(k, cw);
                    chk[k] = (k == 3);
                    v[k-1] = 0;
                    if (k == 2) lenwait = LEN_LAT;
                    // resolucao do desvio ao deixar o estagio de resolucao (D=2, X=4, M=5)
                    if (!wp[k-1] && ((pc == 2'd1 && k-1 == 2) || (pc == 2'd2 && k-1 == 4) || (pc == 2'd3 && k-1 == 5))) begin
                        for (pen_s = 0; pen_s < k-1; pen_s = pen_s + 1) v[pen_s] = 0;
                        wp_mode = 0;
                    end
                end
            end
            // busca
            if (!v[0] && (!SERIAL || (!v[1] && lenwait == 0))) begin
                if (wp_mode) begin
                    v[0] = 1; wp[0] = 1; idx[0] = 0; c[0] = C_WP; rem[0] = 1; wp_fetch <= wp_fetch + 1;
                end else if (fp < NTRACE) begin
                    v[0] = 1; wp[0] = 0; idx[0] = fp; c[0] = ctrl_of(trace[fp][15:8], trace[fp][7:0]); rem[0] = 1;
                    fp = fp + 1;
                    if (c[0][25:24] != 0) wp_mode = 1;
                end
            end
            // no estagio F1->F2 o numero de buscas vem de c[] (leitura antecipada das ROMs)
        end
    end
endmodule
