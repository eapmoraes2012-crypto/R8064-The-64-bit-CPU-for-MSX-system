// msx_mem.v - memoria mapeada MSX (portas FC..FF, paginas de 16 KB) + MegaRAM ASCII8 (paginas de 8 KB) + registrador de slot primario (A8h).
// Uma instancia por nucleo (R8064 em modo compatibilidade Z80 e Z80 classico). Traduz endereco de 16 bits do Z80 em endereco fisico (SDRAM) e diz
// se o bloco responde ("hit"). A memoria fisica e compartilhada por fora (arbitro do modulo 05); aqui so ha registradores e combinacional.
// SUPOSICOES a confirmar: (1) portas FC,FD,FE,FF = paginas 0..3 (o pedido dizia "FC, FC, FE, FF"); (2) MegaRAM: IN 8Eh liga modo de escrita na RAM,
// OUT 8Eh volta ao modo ASCII8 (bancos); em modo de escrita o byte vai a RAM e tambem atualiza o registrador de banco se o endereco for 6000-7FFF.
module msx_mem #(
    parameter MAP_BITS  = 6,            // segmentos do mapper = 2**MAP_BITS (6 -> 1 MB, max 8 -> 4 MB)
    parameter MEGA_BITS = 7,            // bancos de 8 KB = 2**MEGA_BITS (7 -> 1 MB, max 8 -> 2 MB)
    parameter [23:0] MAP_BASE  = 24'h000000,
    parameter [23:0] MEGA_BASE = 24'h100000,
    parameter [1:0]  SLOT_MAP  = 2'd3,  // slot primario do mapper
    parameter [1:0]  SLOT_MEGA = 2'd2   // slot primario da MegaRAM
)(
    input  wire        clk, rst,
    input  wire        en,              // 1 = modo compatibilidade 16 bits (no R8064: MMU desligada)
    // barramento de E/S
    input  wire        io_wr, io_rd,
    input  wire [7:0]  io_addr, io_wdata,
    output reg  [7:0]  io_rdata,
    output reg         io_hit,          // este bloco responde a leitura de E/S
    // barramento de memoria do nucleo
    input  wire        mem_rd, mem_wr,
    input  wire [15:0] mem_addr,
    input  wire [7:0]  mem_wdata,
    output reg         hit,             // endereco cai neste bloco
    output reg  [23:0] phys_addr,
    output wire [7:0]  a8_o,            // slot primario atual (para o classificador de memoria)
    output reg         wr_ok            // escrita permitida (RAM do mapper sempre; MegaRAM so em modo de escrita)
);
    reg [7:0] a8;
    assign a8_o = a8;                        // slots primarios das 4 paginas
    reg [7:0] mreg [0:3];                // mapper: segmento de cada pagina de 16 KB
    reg [7:0] breg [0:3];                // MegaRAM: banco de 8 KB para 4000,6000,8000,A000
    reg       wmode;                     // MegaRAM em modo de escrita
    integer i;
    wire [7:0] mapmask  = (MAP_BITS >= 8) ? 8'hFF : ((8'd1 << MAP_BITS) - 8'd1);
    wire [7:0] megamask = (MEGA_BITS >= 8) ? 8'hFF : ((8'd1 << MEGA_BITS) - 8'd1);

    wire [1:0] page = mem_addr[15:14];
    wire [1:0] slot = a8 >> {page, 1'b0};
    wire map_hit  = en && (slot == SLOT_MAP);
    wire mega_hit = en && (slot == SLOT_MEGA) && (mem_addr[15:14] == 2'b01 || mem_addr[15:14] == 2'b10);
    wire [1:0] mseg = mem_addr[14:13] - 2'd2;          // 4000->0, 6000->1, 8000->2, A000->3 (mod 4)
    wire mega_regwr = mem_wr && mega_hit && (mem_addr[15:13] == 3'b011);  // 6000-7FFF
    wire [1:0] mridx = mem_addr[12:11];                 // 6000,6800,7000,7800

    always @* begin
        hit = 1'b0; phys_addr = 24'd0; wr_ok = 1'b0;
        if (map_hit) begin
            hit = 1'b1; wr_ok = 1'b1;
            phys_addr = MAP_BASE + {(mreg[page] & mapmask), mem_addr[13:0]};
        end else if (mega_hit) begin
            hit = 1'b1; wr_ok = wmode;
            phys_addr = MEGA_BASE + {(breg[mseg] & megamask), mem_addr[12:0]};
        end
    end

    always @* begin
        io_hit = 1'b0; io_rdata = 8'hFF;
        if (en && io_rd) begin
            if (io_addr[7:2] == 6'b111111) begin                 // FC..FF
                io_hit = 1'b1; io_rdata = mreg[io_addr[1:0]] | ~mapmask;
            end else if (io_addr == 8'hA8) begin
                io_hit = 1'b1; io_rdata = a8;
            end
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            a8 <= 8'h00; wmode <= 1'b0;
            mreg[0] <= 8'd3; mreg[1] <= 8'd2; mreg[2] <= 8'd1; mreg[3] <= 8'd0;
            for (i = 0; i < 4; i = i + 1) breg[i] <= 8'd0;
        end else if (en) begin
            if (io_wr) begin
                if (io_addr[7:2] == 6'b111111) mreg[io_addr[1:0]] <= io_wdata;
                else if (io_addr == 8'hA8) a8 <= io_wdata;
                else if (io_addr == 8'h8E) wmode <= 1'b0;
            end
            if (io_rd && io_addr == 8'h8E) wmode <= 1'b1;
            if (mega_regwr) breg[mridx] <= mem_wdata;
        end
    end
endmodule
