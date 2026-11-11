// timing_gov.v - governador de tempo do R8064 nos modos Z80 / R800 (ROM ou DRAM). Segura a EMISSAO da proxima instrucao ate que o
// tempo original da anterior tenha passado. Unidades: clock do pipeline (A = 114,56 MHz, B = 85,92 MHz).
//   Z80  : 1 T-state = 32 clocks (A) / 24 (B)    -> 3,579545 MHz
//   R800 : 1 ciclo   = 16 clocks (A) / 12 (B)    -> 7,15909 MHz
// Tempo de uma instrucao (unidades originais):
//   Z80  : T-states da tabela + (M1 de 2 bytes ? 2 : 1) * M1_WAIT                    (igual em ROM e DRAM)
//   R800 : ciclos totais DRAM da tabela + (modo ROM ? WAIT_ROM : 0) + c_xcyc (extra dinamico: quebra de pagina, memoria externa)
//   caminho alternativo ("alt"): condicao falsa / ultima iteracao -> alt_ev encurta o tempo ja carregado
// Extras do R800: refresh (REF_CYC ciclos a cada REF_PER ciclos) e pausa de 8 us entre acessos as portas 98H-9BH.
// Modo nativo de 64 bits: go = 1 (sem governador).
module timing_gov #(
    parameter ROM_FILE = "gov_rom.mem",
    parameter M1_WAIT  = 1,
    parameter WAIT_ROM = 3,
    parameter REF_CYC  = 25,
    parameter REF_PER  = 210
)(
    input  wire        clk, rst,
    input  wire        native64, is_z80, is_rom, clk_sel,
    // instrucao candidata (estavel antes do commit; a tabela e lida em 1 clock)
    input  wire [2:0]  c_page,        // 0 principal, 1 CB, 2 ED, 3 DD, 4 FD, 5 DDCB, 6 FDCB
    input  wire [7:0]  c_op,
    input  wire [7:0]  c_port,        // porta de E/S da instrucao (IN/OUT)
    input  wire [3:0]  c_xcyc,        // ciclos extras dinamicos da busca (unidades da CPU emulada): memoria externa, quebra de pagina
    input  wire        c_romw,        // a busca e feita em ROM (no modo ROM aplica WAIT_ROM); sem classificador, ligar em 1
    input  wire        add_ev,        // evento tardio: acesso de dados com ciclos extras
    input  wire [4:0]  add_n,         // ciclos extras desse acesso
    output wire        phase,         // paridade do ciclo R800 (alinhamento com o barramento externo de 3,58 MHz)
    input  wire        cv,            // commit: a instrucao candidata foi emitida neste clock
    input  wire        alt_ev,        // condicao falsa / fim de repeticao da instrucao em curso
    output wire        go,            // 1 = pode emitir
    output wire [12:0] dbg_rem
);
    reg [31:0] rom [0:2047];
    initial $readmemh(ROM_FILE, rom);
    reg [31:0] rw;
    always @(posedge clk) rw <= rom[{c_page, c_op}];
    wire [5:0] z_t = rw[5:0], z_a = rw[11:6], r_t = rw[17:12], r_a = rw[23:18];
    wire m1x2 = rw[24], isio = rw[25];
    // tempo em unidades originais
    wire [6:0] zadd = m1x2 ? (M1_WAIT * 2) : M1_WAIT;
    wire [6:0] radd = ((is_rom && c_romw) ? WAIT_ROM : 0) + {3'd0, c_xcyc};
    wire [6:0] n_p  = is_z80 ? ({1'b0, z_t} + zadd) : ({1'b0, r_t} + radd);
    wire [6:0] n_a  = is_z80 ? ((z_a == 0) ? n_p : ({1'b0, z_a} + zadd)) : ((r_a == 0) ? n_p : ({1'b0, r_a} + radd));
    wire [6:0] dlt_u = n_p - n_a;
    function [12:0] scale(input [6:0] n, input z, input s);   // n * (clocks por unidade)
        case ({z, s})
            2'b10: scale = {n, 5'b0};                    // 32
            2'b11: scale = {n, 4'b0} + {n, 3'b0};        // 24
            2'b00: scale = {n, 4'b0};                    // 16
            default: scale = {n, 3'b0} + {n, 2'b0};      // 12
        endcase
    endfunction
    // 2o e 3o estagios de registro (cortam ROM -> somadores -> contador): n_p/dlt_u/flag de VDP, depois tempo em clocks.
    // Latencia candidato -> go/commit: 3 clocks (o nucleo usa uma fase extra de decodificacao nos modos governados).
    reg [6:0] n_pq, dltq; reg zq, sq;
    reg [12:0] n_clk, d_clk; reg vdp_port;
    always @(posedge clk) begin
        n_pq <= n_p; dltq <= dlt_u; zq <= is_z80; sq <= clk_sel;
        vdp_port <= isio && (c_port[7:2] == 6'b100110);   // 98H-9BH
        n_clk <= scale(n_pq, zq, sq);
        d_clk <= scale(dltq, zq, sq);
    end
    // pausa do VDP (so R800)
    localparam VDP_A = 916, VDP_B = 687;     // 8 us em 114,56 / 85,92 MHz
    reg [10:0] vdp_cnt;
    wire vdp_blk  = !is_z80 && vdp_port && (vdp_cnt < (clk_sel ? VDP_B : VDP_A));
    reg [12:0] rem, dlt; reg [12:0] rfs, rfc; reg rf_pend;
    wire [12:0] ref_per_clk = clk_sel ? 13'd2520 : 13'd3360;   // 210 ciclos
    wire [12:0] ref_len_clk = clk_sel ? 13'd300  : 13'd400;    // 25 ciclos
    // go registrado (tira a comparacao de rem/VDP do caminho de emissao do nucleo); a latencia de +1 clock e compensada nos contadores
    reg av1, av2; reg [4:0] an1; reg [12:0] add_clk;   // evento de dados em 2 estagios: ..., depois soma ao tempo restante
    wire go_c = (rem == 0) && (rfs == 0) && !rf_pend && !vdp_blk && !av1 && !av2;
    // fase do ciclo R800: toggle a cada 'unidade' (16 / 12 clocks)
    reg [4:0] ph_cnt; reg ph;
    assign phase = ph;
    always @(posedge clk) begin
        if (rst || ph_cnt == (clk_sel ? 5'd11 : 5'd15)) begin ph_cnt <= 0; if (!rst) ph <= ~ph; else ph <= 0; end
        else ph_cnt <= ph_cnt + 5'd1;
    end
    reg go_r;
    assign go = native64 | go_r;
    assign dbg_rem = rem;
    wire commit = cv && go_r && !native64;
    always @(posedge clk) begin
        if (rst || native64) begin go_r <= 0; av1 <= 0; av2 <= 0; add_clk <= 0; rem <= 0; dlt <= 0; rfs <= 0; rfc <= 0; rf_pend <= 0; vdp_cnt <= 11'd1023; end
        else begin
            go_r <= go_c && !commit;
            if (vdp_cnt != 11'd1023) vdp_cnt <= vdp_cnt + 11'd1;
            // refresh (R800)
            if (!is_z80) begin
                if (rfc >= ref_per_clk) rf_pend <= 1'b1; else rfc <= rfc + 13'd1;
                if (rf_pend && rem == 0 && rfs == 0) begin rfs <= ref_len_clk; rf_pend <= 1'b0; rfc <= 0; end
            end else begin rfc <= 0; rf_pend <= 0; end
            if (rfs != 0) rfs <= rfs - 13'd1;
            // evento de dados (2 estagios) -> add_clk
            av1 <= add_ev && !is_z80; an1 <= add_n; av2 <= av1; add_clk <= av1 ? scale({2'd0, an1}, 1'b0, clk_sel) : 13'd0;
            // tempo da instrucao
            if (commit) begin
                rem <= n_clk - 13'd2; dlt <= d_clk;
                if (!is_z80 && vdp_port) vdp_cnt <= 11'd0;
            end else begin
                rem <= ((alt_ev && rem != 0) ? ((rem > dlt) ? (rem - dlt - 13'd1) : 13'd0) : (rem != 0) ? (rem - 13'd1) : 13'd0)
                       + (av2 ? add_clk : 13'd0);
            end
        end
    end
endmodule
