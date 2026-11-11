// r8064_decode.v - decodificador da pagina ED do R8064 (GERADO a partir da planilha rev. 5).
// NAO FOI COMPILADO NEM SIMULADO no ambiente em que foi gerado (sem Icarus/Verilator/Yosys).
//
// Latencias (a partir do ciclo em que b2/b3 estao estaveis antes da borda do clock):
//   +1 clock : id e illegal validos      (ROM_A e ROM_B lidas em paralelo; amb_idx e logica combinacional)
//   +2 clocks: campos de controle validos (ROM de controle lida com o id)
// ATENCAO: essas duas leituras em serie podem nao caber no estagio D do pipeline de 7 estagios
// (o modelo de ciclos da planilha supoe D em 1 clock). Decida entre dividir D, ou ler a ROM de
// controle no estagio R. Veja o README.
module r8064_decode #(
    parameter ROM_A_FILE = "rom_ed_a.mem",
    parameter ROM_B_FILE = "rom_ed_b.mem",
    parameter AMB_FILE   = "amb_idx.mem",
    parameter CTRL_FILE  = "ctrl.mem"
)(
    input  wire       clk,
    input  wire [7:0] b2,        // segundo byte (apos o prefixo ED)
    input  wire [7:0] b3,        // terceiro byte (so conta nas paginas ambiguas)
    output wire [9:0] id,        // numero da instrucao (0 = ilegal)
    output wire       illegal,
    output wire [3:0] len,       // bytes da instrucao
    output wire [4:0] nr,        // leituras de dados (acessos de 64 bits)
    output wire [4:0] nw,        // escritas de dados
    output wire [1:0] nio,       // acessos de E/S
    output wire [7:0] ex,        // ocupacao do estagio X (clocks)
    output wire [1:0] pen_code,  // 0 nenhuma, 1 BR_D, 2 BR_X, 3 BR_M
    output wire       has_cond,  // existe variante "condicao falsa"
    output wire       is_z80     // instrucao ED do Z80 (modo Z80)
);
    localparam NPAGES = 33;
    localparam PW     = 6;

    reg [11:0] rom_a [0:255];
    reg [7:0]  amb   [0:255];
    reg [9:0]  rom_b [0:NPAGES*256-1];
    reg [31:0] ctrl  [0:511];
    initial begin
        $readmemh(ROM_A_FILE, rom_a);
        $readmemh(AMB_FILE,   amb);
        $readmemh(ROM_B_FILE, rom_b);
        $readmemh(CTRL_FILE,  ctrl);
    end

    // pagina da ROM_B: logica combinacional a partir de b2 (256 x PW bits)
    wire [7:0]    amb_w = amb[b2];
    wire [PW-1:0] page  = amb_w[PW-1:0];

    reg [11:0] a_q;
    reg [9:0]  b_q;
    always @(posedge clk) begin
        a_q <= rom_a[b2];
        b_q <= rom_b[{page, b3}];
    end

    assign id      = a_q[10] ? b_q : a_q[9:0];
    assign illegal = (id == 10'd0);

    reg [31:0] c_q;
    always @(posedge clk) c_q <= ctrl[id[8:0]];

    assign len      = c_q[3:0];
    assign nr       = c_q[8:4];
    assign nw       = c_q[13:9];
    assign nio      = c_q[15:14];
    assign ex       = c_q[23:16];
    assign pen_code = c_q[25:24];
    assign has_cond = c_q[26];
    assign is_z80   = c_q[27];
endmodule
