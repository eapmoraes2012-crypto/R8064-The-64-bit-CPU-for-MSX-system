// z80_ce.v - gerador de clock-enable do Z80 (acumulador de fase) com modo turbo.
// F_cpu = STEP_BASE * 2^turbo * clk / 2^32.   turbo: 0 = 3,58 MHz (Z80 do MSX)  1 = 7,16 MHz (clock do R800)
//                                                     2 = 14,3 MHz             3 = 28,6 MHz
// Padrao: clk = 57,2727 MHz (3,579545 x 16) -> STEP_BASE = 2^28 = 268435456 (exato).
// Limite: pulsos de ce separados por >= 3 clocks => step <= 2^32/3; se STEP_BASE<<turbo passar disso, o turbo e reduzido em 1 degrau
// (a 57,27 MHz: turbo 3 = 28,6 MHz vira 14,3 MHz).
// Outros valores de STEP_BASE para 3.579545 MHz:  clk=100 MHz -> 153740287 ; 85,92 MHz -> 178934226 ; 114,545 MHz -> 134217711
module z80_ce #(parameter [31:0] STEP_BASE = 32'd268435456)(
  input  wire       clk,
  input  wire       rst_n,
  input  wire [1:0] turbo,
  input  wire       use_ext,    // 1 = usa ce_ext (pulso por T-state vindo do clock do slot, para sincronismo exato com o barramento MSX)
  input  wire       ce_ext,
  output reg        ce
);
  reg [31:0] acc;
  wire [31:0] step_raw = STEP_BASE << turbo;
  wire [31:0] step = (step_raw > 32'd1431655765) ? (STEP_BASE << (turbo - 2'd1)) : step_raw;
  wire [32:0] sum  = {1'b0, acc} + {1'b0, step};
  always @(posedge clk) begin
    if (!rst_n) begin acc <= 32'd0; ce <= 1'b0; end
    else begin
      acc <= sum[31:0];
      ce  <= use_ext ? ce_ext : sum[32];
    end
  end
endmodule
