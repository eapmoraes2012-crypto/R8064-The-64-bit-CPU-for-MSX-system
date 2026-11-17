// z80_ce.v - Z80 clock-enable generator (phase accumulator) with turbo mode.
// F_cpu = STEP_BASE * 2^turbo * clk / 2^32.   turbo: 0 = 3,58 MHz (Z80 do MSX)  1 = 7,16 MHz (clock do R800)
//                                                     2 = 14,3 MHz             3 = 28,6 MHz
// Padrao: clk = 57,2727 MHz (3,579545 x 16) -> STEP_BASE = 2^28 = 268435456 (exato).
// Limit: ce pulses separated by >= 3 clocks => step <= 2^32/3; if STEP_BASE<<turbo exceeds that, the turbo is reduced by 1 step
// (a 57,27 MHz: turbo 3 = 28,6 MHz vira 14,3 MHz).
// Other STEP_BASE values for 3.579545 MHz:  clk=100 MHz -> 153740287 ; 85.92 MHz -> 178934226 ; 114.545 MHz -> 134217711
module z80_ce #(parameter [31:0] STEP_BASE = 32'd268435456)(
  input  wire       clk,
  input  wire       rst_n,
  input  wire [1:0] turbo,
  input  wire       use_ext,    // 1 = uses ce_ext (one pulse per T-state coming from the slot clock, for exact synchronism with the MSX bus)
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
