// mem_class.v - classificador de memoria do R8064 nos modos R800 (ciclos extras por regiao do mapa MSX).
// Regioes (por pagina de 16 KB x slot primario, tabela de 16 entradas programavel): 0 RAM interna, 1 ROM, 2 memoria externa.
//   - Memoria externa: +4 ciclos R800, ou +5 conforme a fase do barramento (phase) - R_WAIT_EXT / premissa da planilha.
//   - ROM (somente modo ROM): +WAIT_ROM, aplicado no governador para a busca (c_romw) e aqui para leituras de dados.
//   - Quebra de pagina de 256 B (R800): +1 se a busca da instrucao ou um acesso de dados atravessa a fronteira.
//   - Modo Z80 e modo nativo: sem extras (o tempo do Z80 e fixo; o nativo nao tem governador).
// Busca: combinacional sobre (pc, comprimento) do candidato -> c_xcyc / c_romw do governador.
// Dados: evento por acesso concluido (d_ev) -> add_ev/add_n (tardio) para o governador.
module mem_class #(parameter WAIT_ROM = 3)(
    input  wire        clk, rst,
    input  wire        active,        // modo R800 (nao Z80, nao nativo)
    input  wire        is_rom,        // modo ROM (R800 ROM)
    input  wire        phase,         // fase do ciclo R800 (governador)
    input  wire [7:0]  a8,            // registrador de slot primario (porta A8H)
    input  wire        map_we,        // programacao da tabela
    input  wire [3:0]  map_idx,       // {pagina[1:0], slot[1:0]}
    input  wire [1:0]  map_val,       // 0 RAM, 1 ROM, 2 externa
    input  wire [15:0] f_pc,
    input  wire [3:0]  f_len,
    output reg  [3:0]  f_xcyc,         // registrado: valido 1 clock depois de (f_pc, f_len)
    output reg         f_romw,
    input  wire        d_ev,
    input  wire [15:0] d_addr,
    input  wire [1:0]  d_size,        // 0 = 1 B, 1 = 2 B, 2 = 4 B, 3 = 8 B
    input  wire        d_we,
    output reg         add_ev,
    output reg  [4:0]  add_n
);
    reg [1:0] map [0:15];
    integer i;
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 16; i = i + 1) map[i] <= (i[1:0] == 2'd3) ? 2'd0 : (i[1:0] == 2'd0 && i[3] == 1'b0) ? 2'd1 : 2'd2;
        end else if (map_we) map[map_idx] <= map_val;
    end
    function [1:0] slot_of(input [1:0] pg); slot_of = a8 >> {pg, 1'b0}; endfunction
    // ---- busca ----
    wire [1:0] f_pg = f_pc[15:14];
    wire [1:0] f_at = map[{f_pg, slot_of(f_pg)}];
    wire [8:0] f_sum = {1'b0, f_pc[7:0]} + {5'd0, f_len};
    wire f_pgb = f_sum > 9'd256;                      // ultimo byte cai na pagina seguinte
    wire [3:0] f_xcyc_c = active ? ((f_at == 2'd2 ? (4'd4 + {3'd0, phase}) : 4'd0) + {3'd0, f_pgb}) : 4'd0;
    wire f_romw_c = (f_at == 2'd1);
    always @(posedge clk) begin f_xcyc <= f_xcyc_c; f_romw <= f_romw_c; end
    // ---- dados ----
    wire [1:0] d_pg = d_addr[15:14];
    wire [1:0] d_at = map[{d_pg, slot_of(d_pg)}];
    wire [3:0] nb = 4'd1 << d_size;
    wire [8:0] d_sum = {1'b0, d_addr[7:0]} + {5'd0, nb};
    wire d_pgb = d_sum > 9'd256;
    wire [4:0] d_x = (d_at == 2'd2 ? (5'd4 + {4'd0, phase}) : 5'd0) + ((d_at == 2'd1 && is_rom && !d_we) ? WAIT_ROM : 5'd0) + {4'd0, d_pgb};
    always @(posedge clk) begin
        add_ev <= rst ? 1'b0 : (d_ev && active && d_x != 5'd0);
        add_n  <= d_x;
    end
endmodule
