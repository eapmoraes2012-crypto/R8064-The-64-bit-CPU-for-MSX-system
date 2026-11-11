// r8064_mode.v - registradores de modo do R8064.
//   Porta 3DH: leitura = 64H (ID); escrita 0A5H arma UMA escrita em 3EH (qualquer outro valor desarma).
//   Porta 3EH: R8064_MODE  bit0 NATIVE64 | bits2:1 CLK (00 = 114,56 MHz, 01 e 1x = 85,92 MHz) | bit3 BUSY (somente leitura).
//   Portas E4H/E5H: S1990 emulada so no registrador 6 (bit5 0 = R800 / 1 = Z80; bit6 0 = DRAM / 1 = ROM). Reset = 60H (Z80 ROM).
//   Outros registradores da S1990 NAO sao tratados aqui (so passam: s1990_idx / s1990_other_we).
// A troca de modo e aplicada na fronteira de instrucao (boundary = 1 quando o pipeline esta vazio / instrucao emitida).
module r8064_mode(
    input  wire       clk, rst,
    input  wire       io_we, io_re,
    input  wire [7:0] io_a, io_wd,
    output reg  [7:0] io_rd,
    output reg        io_oe,
    input  wire       boundary,
    output reg        native64, clk_sel, is_z80, is_rom,
    output wire       busy,
    output wire [7:0] s1990_idx,
    output wire       s1990_other_we
);
    reg armed; reg [7:0] idx; reg [6:5] r6; reg req_nat, req_clk;
    assign s1990_idx = idx;
    assign s1990_other_we = io_we && io_a == 8'hE5 && idx != 8'd6;
    assign busy = (req_nat != native64) || (req_clk != clk_sel) || (r6[5] != is_z80) || (r6[6] != is_rom);
    always @(posedge clk) begin
        if (rst) begin armed <= 0; idx <= 0; r6 <= 2'b11; req_nat <= 0; req_clk <= 0; native64 <= 0; clk_sel <= 0; is_z80 <= 1; is_rom <= 1; end
        else begin
            if (io_we) case (io_a)
                8'h3D: armed <= (io_wd == 8'hA5);
                8'h3E: if (armed) begin req_nat <= io_wd[0]; req_clk <= io_wd[2] | io_wd[1]; armed <= 0; end
                8'hE4: idx <= io_wd;
                8'hE5: if (idx == 8'd6) r6 <= io_wd[6:5];
                default: ;
            endcase
            if (boundary) begin native64 <= req_nat; clk_sel <= req_clk; is_z80 <= r6[5]; is_rom <= r6[6]; end
        end
    end
    always @* begin
        io_oe = 1'b0; io_rd = 8'hFF;
        if (io_re) case (io_a)
            8'h3D: begin io_oe = 1; io_rd = 8'h64; end
            8'h3E: begin io_oe = 1; io_rd = {4'b0, busy, clk_sel ? 2'b01 : 2'b00, native64}; end
            8'hE4: begin io_oe = 1; io_rd = idx; end
            8'hE5: begin io_oe = (idx == 8'd6); io_rd = {1'b0, is_rom, is_z80, 5'b0}; end
            default: ;
        endcase
    end
endmodule
