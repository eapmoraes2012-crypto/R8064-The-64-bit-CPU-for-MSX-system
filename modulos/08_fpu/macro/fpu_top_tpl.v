// fpu_top.v - R8064 FPU: x87 stack (fpu_stk) + arithmetic (fpu_half/fpu_alu, at clk/2) + command sequencer + macro sequencer (transcendentals) for the core.
// Interface: 'go' (1 pulse, only with busy=0) with cmd, idx (STn index from the instruction byte) and din (register value). 'busy' = 1 while the command finishes.
// 'dout' is combinational from gsel (GET commands >= 48) and always reads stable registers (rdr, sw, cw, tw).
// Pass-through register xin (80 bits): SETLO/SETHI assemble it; LD32/LD64/FILD/LD80/WRC consume it. rdr (80 bits) receives ST(i) (RDI/RD0/RDC) or the result of CVT32/CVT64/FIST.
// Counter cnt (3 bits): CLRCNT clears it; RDC and WRC read/write ST(cnt) and increment (FSAVE/FRSTR without needing a constant index).
// Commands: 0 NOP | 1 SETLO | 2 SETHI | 3 LD80 | 4 LD32 | 5 LD64 | 6 FILD | 8 FLD1 | 9 FLDZ | 10 FLDPI | 11 FLDL2T | 12 FLDLG2 | 13 FLDLN2
//  14 FADD | 15 FSUB | 16 FMUL | 17 FDIV (ST0 := ST0 op STn) | 18 FSQRT | 19 FCOM STn | 20 FCOPP | 21 FCHS | 22 FABS | 23 FXCH | 24 FLD STn | 25 FSTP STn | 26 FRINT
//  27 POP | 28 FINIT | 29 SETCW | 30 SETSW | 31 SETTW | 32 RDI | 33 RDC | 34 WRC | 35 CLRCNT | 36 CVT32 | 37 CVT64 | 38 FIST | 39 RD0
//  MACROS (ROM de firmware, ver 08_fpu/macro/fpu_macro.py): 40 FSIN | 41 FCOS | 42 FSINC | 43 FTAN | 44 FLN | 45 FYL2X | 46 FYL2P | 47 FREM | 7 FREM1
//  macro internals: 48..51 ADDST SUBST MULST DIVST (STn := STn op ST0) | 63 KLD (pushes a constant from the ROM)
//  GET: 48 lo(rdr) | 49 hi(rdr) | 50 SW | 51 CW | 52 TW | 53 CC in the F format ({C1,C3,000,C2,0,C0})
// During a macro: rounding = nearest, precision = 64 bits, only the PE exception is accumulated by the internal operations.
module fpu_top(
    input  wire        clk, rst,
    input  wire        go,
    input  wire [5:0]  cmd,
    input  wire [2:0]  idx,
    input  wire [63:0] din,
    output wire        busy,
    input  wire [5:0]  gsel,
    output reg  [63:0] dout
);
    reg [79:0] xin, rdr; reg [2:0] cnt, idxq;
    reg [2:0] st; reg [2:0] ps; reg [3:0] pk;
    localparam S_IDLE = 0, S_ONE = 1, S_ALU = 2, S_POST = 3, S_FR = 4;
    localparam P_NONE = 0, P_ST0 = 1, P_LD = 2, P_CMP = 3, P_CMP2 = 4, P_OUT = 5, P_POP = 6, P_STN = 7, P_FREM = 8;
//@ROM@
    // ---- macros
    reg m_run, m_P, m_dn; reg [9:0] m_pc, m_ret; reg [1:0] m_kq;
    wire [15:0] mw = mrom(m_pc);
    wire [1:0] m_cnd = mw[15:14]; wire [3:0] m_kd = mw[13:10]; wire [9:0] m_arg = mw[9:0];
    wire m_ok = (m_cnd == 2'd0) || (m_cnd == 2'd1 && m_P) || (m_cnd == 2'd2 && !m_P);
    wire ext_macro = go && (cmd == 6'd7 || (cmd >= 6'd40 && cmd <= 6'd47));
    // ---- stack
    reg s_go; reg [3:0] s_cmd; reg [2:0] s_idx, ra_idx, rb_idx; reg [79:0] s_wd; reg [5:0] s_fl;
    wire [79:0] ra, rb; wire [1:0] tag_a, tag_b; wire [15:0] cw, sw, tw; wire [3:0] fxam; wire es, stk_busy;
    fpu_stk u_stk(.clk(clk), .rst(rst), .go(s_go), .cmd(s_cmd), .idx(s_idx), .wdata(s_wd), .flags_in(s_fl), .ra_idx(ra_idx), .rb_idx(rb_idx),
                  .ra(ra), .rb(rb), .tag_a(tag_a), .tag_b(tag_b), .cw(cw), .sw(sw), .tw(tw), .fxam(fxam), .es(es), .busy(stk_busy));
    // ---- arithmetic
    reg a_start; reg [3:0] a_op; reg [79:0] a_a, a_b;
    wire a_busy, a_done, a_up; wire [79:0] a_res; wire [5:0] a_fl; wire [2:0] a_cc;
    fpu_half u_alu(.clk(clk), .rst(rst), .start(a_start), .op(a_op), .rc(m_run ? 2'd0 : cw[11:10]), .pc(m_run ? 2'd3 : cw[9:8]), .a(a_a), .b(a_b), .busy(a_busy), .done(a_done), .res(a_res), .flags(a_fl), .up(a_up), .cc(a_cc));
    wire [5:0] a_flm = m_run ? (a_fl & 6'h20) : a_fl;
    // ---- partial remainder
    reg fr_start; wire fr_busy, fr_done; wire [79:0] fr_res; wire [2:0] fr_q; reg [2:0] frq;
    fpu_frem u_frem(.clk(clk), .rst(rst), .start(fr_start), .near(m_arg[0]), .x(ra), .y(rb), .busy(fr_busy), .done(fr_done), .res(fr_res), .q(fr_q));
    assign busy = (st != S_IDLE) || stk_busy || a_busy || m_run || fr_busy;
    // ---- macro decision: word executed in this cycle (macro active, everything stalled)
    wire m_idle = m_run && (st == S_IDLE) && !stk_busy && !a_busy && !fr_busy && !ext_macro;
    wire m_exec = m_idle && m_ok;
    wire m_icmd = m_exec && (m_kd == 4'd0 || m_kd == 4'd1);                 // CMD or KLD: reuses the command decoder
    wire [5:0] cmd_e = m_icmd ? ((m_kd == 4'd1) ? 6'd63 : m_arg[5:0]) : cmd;
    wire [2:0] idx_i = m_icmd ? m_arg[8:6] : idx;
    wire go_e = m_icmd | go;
    wire [2:0] idx_e = (st == S_IDLE) ? idx_i : idxq;
    function [79:0] kconst(input [5:0] c);
        case (c)
            6'd8:  kconst = {16'h3FFF, 64'h8000_0000_0000_0000};
            6'd9:  kconst = 80'd0;
            6'd10: kconst = {16'h4000, 64'hC90F_DAA2_2168_C235};
            6'd11: kconst = {16'h4000, 64'hD49A_784B_CD1B_8AFE};
            6'd12: kconst = {16'h3FFD, 64'h9A20_9A84_FBCF_F799};
            default: kconst = {16'h3FFE, 64'hB172_17F7_D1CF_79AC};
        endcase
    endfunction
    wire sc0 = sw[8], sc1 = sw[9], sc2 = sw[10], sc3 = sw[14];
    // classification of an 80-bit value
    function [4:0] clsf(input [79:0] v);       // {big, small, neg, den, zero... } see use below
        reg ex0, exf, m63, mz;
        begin
            ex0 = (v[78:64] == 15'd0); exf = (v[78:64] == 15'h7FFF); m63 = v[63]; mz = (v[62:0] == 63'd0);
            clsf[0] = exf ? !(m63 && mz) : (ex0 ? m63 : !m63);       // nan / unsupported
            clsf[1] = exf && m63 && mz;                                // infinity
            clsf[2] = ex0 && !m63 && (v[62:0] == 63'd0);               // zero
            clsf[3] = ex0 && !m63 && !(v[62:0] == 63'd0);              // denormal
            clsf[4] = 1'b0;
        end
    endfunction
    wire [4:0] c0f = clsf(ra), c1f = clsf(rb);
    reg pval;
    always @* case (m_arg[3:0])
        4'd0: pval = m_kq[0];
        4'd1: pval = m_kq[1];
        4'd2: pval = m_kq[0] ^ m_kq[1];
        4'd3: pval = c0f[0];
        4'd4: pval = c0f[1];
        4'd5: pval = c0f[2];
        4'd6: pval = ra[79];
        4'd7: pval = c0f[3];
        4'd8: pval = (ra[78:64] >= 15'h3FFF + 15'd30);
        4'd9: pval = sc0;
        4'd10: pval = (ra[78:64] < 15'h3FFD);
        4'd11: pval = c1f[0];
        4'd12: pval = c1f[1];
        4'd13: pval = c1f[2];
        default: pval = m_dn;
    endcase
    wire signed [16:0] xe = $signed({2'b00, ra[78:64]}) - 17'sd16383 - (m_dn ? 17'sd64 : 17'sd0);
    always @* begin
        s_go = 1'b0; s_cmd = 4'd0; s_idx = idx_e; s_wd = 80'd0; s_fl = 6'd0; ra_idx = 3'd0; rb_idx = idx_e;
        a_start = 1'b0; a_op = 4'd0; a_a = ra; a_b = rb; fr_start = 1'b0;
        if (st == S_POST) begin
            case (pk)
                P_ST0:  case (ps)
                            3'd0: begin s_go = 1'b1; s_cmd = 4'd5; s_idx = 3'd0; s_wd = a_res; end
                            3'd1: begin s_go = 1'b1; s_cmd = 4'd10; s_fl = a_flm; end
                            default: begin s_go = !m_run; s_cmd = 4'd11; s_wd = {76'd0, sc3, sc2, a_up, sc0}; end
                        endcase
                P_STN:  case (ps)
                            3'd0: begin s_go = 1'b1; s_cmd = 4'd5; s_idx = idxq; s_wd = a_res; end
                            default: begin s_go = 1'b1; s_cmd = 4'd10; s_fl = a_flm; end
                        endcase
                P_LD:   case (ps)
                            3'd0: begin s_go = 1'b1; s_cmd = 4'd2; s_wd = a_res; end
                            default: begin s_go = 1'b1; s_cmd = 4'd10; s_fl = a_flm; end
                        endcase
                P_CMP, P_CMP2: case (ps)
                            3'd0: begin s_go = 1'b1; s_cmd = 4'd11; s_wd = {76'd0, a_cc[2], a_cc[1], 1'b0, a_cc[0]}; end
                            3'd1: begin s_go = 1'b1; s_cmd = 4'd10; s_fl = a_flm; end
                            default: begin s_go = (pk == P_CMP2); s_cmd = 4'd3; end
                        endcase
                P_OUT:  begin s_go = 1'b1; s_cmd = 4'd10; s_fl = a_flm; end
                P_POP:  begin s_go = 1'b1; s_cmd = 4'd3; end
                P_FREM: case (ps)
                            3'd0: begin s_go = 1'b1; s_cmd = 4'd5; s_idx = 3'd0; s_wd = fr_res; end
                            default: begin s_go = 1'b1; s_cmd = 4'd11; s_wd = {76'd0, frq[1], 1'b0, frq[0], frq[2]}; end
                        endcase
                default: ;
            endcase
        end else if (go_e && st == S_IDLE) begin
            case (cmd_e)
                6'd3: begin s_go = 1'b1; s_cmd = 4'd2; s_wd = xin; end
                6'd4, 6'd5, 6'd6: begin a_start = 1'b1; a_op = (cmd_e == 6'd4) ? 4'd9 : (cmd_e == 6'd5) ? 4'd10 : 4'd6; a_a = xin; end
                6'd8, 6'd9, 6'd10, 6'd11, 6'd12, 6'd13: begin s_go = 1'b1; s_cmd = 4'd2; s_wd = kconst(cmd_e); end
                6'd14, 6'd15, 6'd16, 6'd17: begin a_start = 1'b1; a_op = cmd_e[3:0] - 4'd14; end   // 14->0 ADD, 15->1 SUB, 16->2 MUL, 17->3 DIV
                6'd48, 6'd49, 6'd50, 6'd51: begin a_start = 1'b1; a_op = cmd_e[3:0] - 4'd0; a_a = rb; a_b = ra; end   // STn := STn op ST0
                6'd18: begin a_start = 1'b1; a_op = 4'd4; end
                6'd19: begin a_start = 1'b1; a_op = 4'd5; end
                6'd20: begin a_start = 1'b1; a_op = 4'd5; rb_idx = 3'd1; end
                6'd21: begin s_go = 1'b1; s_cmd = 4'd5; s_idx = 3'd0; s_wd = {~ra[79], ra[78:0]}; end
                6'd22: begin s_go = 1'b1; s_cmd = 4'd5; s_idx = 3'd0; s_wd = {1'b0, ra[78:0]}; end
                6'd23: begin s_go = 1'b1; s_cmd = 4'd4; ra_idx = 3'd0; rb_idx = idx_e; end
                6'd24: begin s_go = 1'b1; s_cmd = 4'd2; s_wd = rb; end
                6'd25: begin s_go = 1'b1; s_cmd = 4'd5; s_wd = ra; end
                6'd26: begin a_start = 1'b1; a_op = 4'd8; end
                6'd27: begin s_go = 1'b1; s_cmd = 4'd3; end
                6'd28: begin s_go = 1'b1; s_cmd = 4'd1; end
                6'd29: begin s_go = 1'b1; s_cmd = 4'd8; s_wd = {64'd0, din[15:0]}; end
                6'd30: begin s_go = 1'b1; s_cmd = 4'd12; s_wd = {64'd0, din[15:0]}; end
                6'd31: begin s_go = 1'b1; s_cmd = 4'd13; s_wd = {64'd0, din[15:0]}; end
                6'd32: ra_idx = idx_e;
                6'd33: ra_idx = cnt;
                6'd34: begin s_go = 1'b1; s_cmd = 4'd5; s_idx = cnt; s_wd = xin; end
                6'd36: begin a_start = 1'b1; a_op = 4'd11; end
                6'd37: begin a_start = 1'b1; a_op = 4'd12; end
                6'd38: begin a_start = 1'b1; a_op = 4'd7; end
                6'd63: begin s_go = 1'b1; s_cmd = 4'd2; s_wd = krom(m_arg[5:0]); end
                default: ;
            endcase
        end else if (m_exec) begin
            case (m_kd)
                4'd2: rb_idx = 3'd1;                                                     // PRED: ST1 through port B
                4'd8: begin s_go = 1'b1; s_cmd = 4'd5; s_idx = 3'd0; s_wd = {ra[79], 15'h3FFF, ra[63:0]}; end   // XTR
                4'd9: begin s_go = 1'b1; s_cmd = 4'd10; s_fl = m_arg[5:0]; end            // FLG
                4'd13: begin s_go = 1'b1; s_cmd = 4'd11; s_wd = {76'd0, m_arg[3:0]}; end  // CC
                4'd10: begin fr_start = 1'b1; rb_idx = 3'd1; end                          // FREM
                default: ;
            endcase
        end
    end
    always @(posedge clk) begin
        if (rst) begin st <= S_IDLE; ps <= 0; pk <= P_NONE; cnt <= 0; xin <= 0; rdr <= 0; idxq <= 0; m_run <= 1'b0; m_P <= 1'b0; m_dn <= 1'b0; m_pc <= 0; m_ret <= 0; m_kq <= 0; frq <= 0; end
        else begin
            // ---- macro sequencer (one word per cycle when everything is stalled)
            if (ext_macro && st == S_IDLE) begin m_run <= 1'b1; m_pc <= mentry(cmd); m_P <= 1'b0; m_dn <= 1'b0; end
            else if (m_exec) begin
                m_pc <= m_pc + 10'd1;
                case (m_kd)
                    4'd2: m_P <= pval;
                    4'd3: m_pc <= m_arg;
                    4'd4: begin m_ret <= m_pc + 10'd1; m_pc <= m_arg; end
                    4'd5: m_pc <= m_ret;
                    4'd6: m_run <= 1'b0;
                    4'd7: m_kq <= rdr[1:0];
                    4'd8: xin <= {16'd0, {47{xe[16]}}, xe};
                    4'd10: begin st <= S_FR; end
                    4'd11: m_dn <= m_arg[0];
                    4'd12: xin <= xin + 80'd1;
                    default: ;
                endcase
            end else if (m_idle && !m_ok) m_pc <= m_pc + 10'd1;
            case (st)
                S_IDLE: if (go_e) begin
                    idxq <= idx_i;
                    case (cmd_e)
                        6'd1: xin[63:0] <= din;
                        6'd2: xin[79:64] <= din[15:0];
                        6'd32: rdr <= ra;
                        6'd39: rdr <= ra;
                        6'd33: begin rdr <= ra; cnt <= cnt + 3'd1; end
                        6'd34: cnt <= cnt + 3'd1;
                        6'd35: cnt <= 3'd0;
                        default: ;
                    endcase
                    case (cmd_e)
                        6'd4, 6'd5, 6'd6: begin st <= S_ALU; pk <= P_LD; end
                        6'd14, 6'd15, 6'd16, 6'd17, 6'd18, 6'd26: begin st <= S_ALU; pk <= P_ST0; end
                        6'd48, 6'd49, 6'd50, 6'd51: begin st <= S_ALU; pk <= P_STN; end
                        6'd19: begin st <= S_ALU; pk <= P_CMP; end
                        6'd20: begin st <= S_ALU; pk <= P_CMP2; end
                        6'd36, 6'd37, 6'd38: begin st <= S_ALU; pk <= P_OUT; end
                        6'd25: begin st <= S_POST; pk <= P_POP; ps <= 0; end
                        6'd7, 6'd40, 6'd41, 6'd42, 6'd43, 6'd44, 6'd45, 6'd46, 6'd47: ;          // macros: only turn on m_run
                        default: st <= S_ONE;
                    endcase
                end
                S_ONE: st <= S_IDLE;
                S_ALU: if (a_done) begin
                    st <= S_POST; ps <= 0;
                    if (pk == P_OUT) rdr <= a_res;
                end
                S_FR: if (fr_done) begin st <= S_POST; pk <= P_FREM; ps <= 0; frq <= fr_q; end
                S_POST: begin
                    case (pk)
                        P_ST0: if (ps == 3'd2) st <= S_IDLE; else ps <= ps + 3'd1;
                        P_STN: if (ps == 3'd1) st <= S_IDLE; else ps <= ps + 3'd1;
                        P_LD:  if (ps == 3'd1) st <= S_IDLE; else ps <= ps + 3'd1;
                        P_CMP: if (ps == 3'd1) st <= S_IDLE; else ps <= ps + 3'd1;
                        P_CMP2: if (ps == 3'd3) st <= S_IDLE; else ps <= ps + 3'd1;
                        P_FREM: if (ps == 3'd1) st <= S_IDLE; else ps <= ps + 3'd1;
                        default: st <= S_IDLE;
                    endcase
                end
                default: st <= S_IDLE;
            endcase
        end
    end
    always @* case (gsel)
        6'd48: dout = rdr[63:0];
        6'd49: dout = {48'd0, rdr[79:64]};
        6'd50: dout = {48'd0, sw};
        6'd51: dout = {48'd0, cw};
        6'd52: dout = {48'd0, tw};
        default: dout = {56'd0, sc1, sc3, 3'b000, sc2, 1'b0, sc0};
    endcase
endmodule
