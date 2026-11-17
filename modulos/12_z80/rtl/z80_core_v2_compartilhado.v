// z80_core.v - complete classic Z80 (documented + undocumented), cycle-exact per M-cycle/T-state.
// Every T-state = one "ce" pulse. Z80 bus (signals active at 1, the top inverts).
// Structure: bus cycle engine (M1/MR/MW/IOR/IOW/INT) + combinational "next cycle" logic executed at the end of each cycle.
`timescale 1ns/1ps
module z80_core(
  input  wire        clk,
  input  wire        ce,        // um pulso = um T-state
  input  wire        rst_n,
  output wire [15:0] addr,
  output wire [7:0]  dout,
  input  wire [7:0]  din,
  output wire        mreq, rd, wr, iorq, m1, rfsh,
  input  wire        wait_n, int_n, nmi_n, busrq_n,
  input  wire        msx_w,     // 1 = +1 wait em M1 e E/S (MSX)
  output wire        halt, busak, bus_oe,
  output reg         instr_done
);
  localparam CT_M1=3'd0, CT_MR=3'd1, CT_MW=3'd2, CT_IOR=3'd3, CT_IOW=3'd4, CT_INT=3'd5;
  localparam S_DISP=6'd0, S_IMM8=6'd1, S_NL=6'd2, S_NH=6'd3, S_D=6'd4, S_EA=6'd5, S_RD1=6'd7, S_INC1=6'd8, S_WR1=6'd9,
             S_FINI=6'd10, S_PL=6'd11, S_PH=6'd12, S_NR0=6'd13, S_NR1=6'd14, S_NW0=6'd15, S_PSH0=6'd16, S_PSHH=6'd17,
             S_PSHL=6'd18, S_JR=6'd19, S_DJNZ=6'd20, S_IO=6'd21, S_X0=6'd22, S_X1=6'd23, S_X2=6'd24, S_X3=6'd25, S_X4=6'd26,
             S_DC1=6'd27, S_DC2=6'd28, S_DC3=6'd29, S_BLD=6'd31, S_BLD2=6'd32, S_BCPI=6'd33, S_B1=6'd34, S_B2=6'd35,
             S_BIOW=6'd36, S_RETCC=6'd37, S_IV0=6'd38, S_IV1=6'd39,
             S_ADD=6'd40, S_BLD1=6'd41, S_C1=6'd42, S_C2=6'd43, S_PCM2=6'd44, S_PCM2B=6'd45;

  // ---------------- architectural state ----------------
  reg [7:0]  a, f, a2, f2, ri, rr;
  reg [15:0] bc, de, hl, bc2, de2, hl2, ix, iy, sp, pc, wz;
  reg        iff1, iff2, halted, ei_dly, nmi_pend, nmi_prev, iack, pj0, pj1;
  reg [1:0]  im, pfx;
  reg        pf_ed, pf_cb;
  reg [7:0]  opr, dbi, lo8, tmp8;
  reg [5:0]  st;
  reg [15:0] ea, tmp16, tgt;
  // ---------------- cycle engine ----------------
  reg [2:0]  ctyp;
  reg [4:0]  t, ilen;
  reg [1:0]  cext;
  reg        cack, cmsx, busak_r;
  reg [15:0] caddr;
  reg [7:0]  cdata;

  wire [4:0] clen_e = (ctyp==CT_M1) ? (cack ? 5'd6 : 5'd4 + {4'd0,cmsx}) :
                      (ctyp==CT_MR) ? 5'd3 + {3'd0,cext} :
                      (ctyp==CT_MW) ? 5'd3 :
                      (ctyp==CT_IOR || ctyp==CT_IOW) ? 5'd4 + {4'd0,cmsx} : ilen;
  wire [4:0] wp_e   = (ctyp==CT_M1) ? (cack ? 5'd4 : 5'd2 + {4'd0,cmsx}) :
                      (ctyp==CT_MR || ctyp==CT_MW) ? 5'd2 :
                      (ctyp==CT_IOR || ctyp==CT_IOW) ? 5'd3 + {4'd0,cmsx} : 5'd0;
  wire       run     = ce & ~busak_r;
  wire       waiting = (wp_e != 5'd0) && (t == wp_e) && !wait_n;
  wire       sample  = run && (wp_e != 5'd0) && (t == wp_e) && wait_n && (ctyp==CT_M1 || ctyp==CT_MR || ctyp==CT_IOR);
  wire       cyc_end = run && (t == clen_e) && !waiting;

  // bus signals
  wire m1c   = (ctyp==CT_M1);
  wire is_rd = (ctyp==CT_MR) || (ctyp==CT_IOR);
  assign addr  = (m1c && !cack && (t > wp_e)) ? {ri, rr} : caddr;
  assign dout  = cdata;
  assign m1    = m1c && (t <= wp_e) && bus_oe;
  assign mreq  = bus_oe && ( (m1c && !cack && (t >= 5'd1)) || ((ctyp==CT_MR || ctyp==CT_MW) && (t>=5'd1)) );
  assign rd    = bus_oe && ( (m1c && (t >= 5'd1) && (t <= wp_e)) || (ctyp==CT_MR && t>=5'd1) || (ctyp==CT_IOR && t>=5'd2) );
  assign wr    = bus_oe && ( (ctyp==CT_MW && t>=5'd2) || (ctyp==CT_IOW && t>=5'd2) );
  assign iorq  = bus_oe && ( ((ctyp==CT_IOR || ctyp==CT_IOW) && t>=5'd2) || (m1c && cack && t>=5'd3 && t<=wp_e) );
  assign rfsh  = bus_oe && m1c && !cack && (t > wp_e);
  assign halt  = halted;
  assign busak = busak_r;
  assign bus_oe = ~busak_r;

  // ---------------- funcoes ----------------
  function par8; input [7:0] v; begin par8 = ~(^v); end endfunction
  function [7:0] szp; input [7:0] v; begin szp = {v[7], (v==8'd0), v[5], 1'b0, v[3], par8(v), 1'b0, 1'b0}; end endfunction

  // Unidade de 8 bits unica (somador compartilhado). cls: 0 ALU(op) 1 ROT(op) 2 INC/DEC(op[0]) 3 DAA/CPL/SCF/CCF(op 0..3)
  //                                                      4 BIT 5 RES 6 SET 7 rotacoes de A (RLCA,RRCA,RLA,RRA)
  function [15:0] f_u; input [2:0] cls; input [2:0] op; input [7:0] a_; input [7:0] b_; input [7:0] fo; input [7:0] xy;
    reg [2:0] aop; reg [7:0] bb; reg [8:0] s; reg ci; reg sub; reg [7:0] r; reg [7:0] fl; reg [7:0] res; reg [7:0] flr;
    reg [7:0] tt; reg c; reg h;
    begin
      aop = op; bb = b_; tt = 8'd0;
      if (cls==3'd3) begin
        if (fo[4] || a_[3:0] > 4'd9) tt = tt | 8'h06;
        if (fo[0] || a_ > 8'h99)     tt = tt | 8'h60;
        aop = fo[1] ? 3'd2 : 3'd0; bb = tt;
      end
      if (cls==3'd2) begin aop = op[0] ? 3'd2 : 3'd0; bb = 8'd1; end
      sub = (aop==3'd2) || (aop==3'd3) || (aop==3'd7);
      ci  = (aop==3'd1 || aop==3'd3) ? fo[0] : 1'b0;
      if (!sub) s = {1'b0,a_} + {1'b0,bb} + {8'd0,ci};
      else      s = {1'b0,a_} - {1'b0,bb} - {8'd0,ci};
      r = s[7:0];
      fl[7] = r[7]; fl[6] = (r==8'd0);
      fl[5] = (aop==3'd7) ? bb[5] : r[5];
      fl[3] = (aop==3'd7) ? bb[3] : r[3];
      fl[4] = a_[4] ^ bb[4] ^ r[4];
      fl[2] = sub ? ((a_[7]^bb[7]) & (a_[7]^r[7])) : (~(a_[7]^bb[7]) & (a_[7]^r[7]));
      fl[1] = sub; fl[0] = s[8];
      res = r; flr = fl;
      case (cls)
        3'd0: begin
          if (aop==3'd4 || aop==3'd5 || aop==3'd6) begin
            res = (aop==3'd4) ? (a_ & b_) : (aop==3'd5) ? (a_ ^ b_) : (a_ | b_);
            flr = szp(res); if (aop==3'd4) flr[4] = 1'b1;
          end
        end
        3'd1: begin
          case (op)
            3'd0: begin c = a_[7]; res = {a_[6:0], a_[7]}; end
            3'd1: begin c = a_[0]; res = {a_[0], a_[7:1]}; end
            3'd2: begin c = a_[7]; res = {a_[6:0], fo[0]}; end
            3'd3: begin c = a_[0]; res = {fo[0], a_[7:1]}; end
            3'd4: begin c = a_[7]; res = {a_[6:0], 1'b0}; end
            3'd5: begin c = a_[0]; res = {a_[7], a_[7:1]}; end
            3'd6: begin c = a_[7]; res = {a_[6:0], 1'b1}; end
            default: begin c = a_[0]; res = {1'b0, a_[7:1]}; end
          endcase
          flr = szp(res); flr[0] = c;
        end
        3'd2: begin flr = {fl[7:1], fo[0]}; end
        3'd3: begin
          case (op[1:0])
            2'd0: begin
              c = fo[0] || (a_ > 8'h99);
              h = fo[1] ? (fo[4] && (a_[3:0] < 4'd6)) : (a_[3:0] > 4'd9);
              res = r; flr = szp(r); flr[0] = c; flr[1] = fo[1]; flr[4] = h;
            end
            2'd1: begin res = ~a_; flr = {fo[7:6], res[5], 1'b1, res[3], fo[2], 1'b1, fo[0]}; end
            2'd2: begin res = a_;  flr = {fo[7:6], a_[5], 1'b0, a_[3], fo[2], 1'b0, 1'b1}; end
            default: begin res = a_; flr = {fo[7:6], a_[5], fo[0], a_[3], fo[2], 1'b0, ~fo[0]}; end
          endcase
        end
        3'd4: begin res = a_; flr = {(op==3'd7 && a_[op]), ~a_[op], xy[5], 1'b1, xy[3], ~a_[op], 1'b0, fo[0]}; end
        3'd5: begin res = a_ & ~(8'd1 << op); flr = fo; end
        3'd6: begin res = a_ | (8'd1 << op);  flr = fo; end
        default: begin
          case (op[1:0])
            2'd0: begin c = a_[7]; res = {a_[6:0], a_[7]}; end
            2'd1: begin c = a_[0]; res = {a_[0], a_[7:1]}; end
            2'd2: begin c = a_[7]; res = {a_[6:0], fo[0]}; end
            default: begin c = a_[0]; res = {fo[0], a_[7:1]}; end
          endcase
          flr = {fo[7:6], res[5], 1'b0, res[3], fo[2], 1'b0, c};
        end
      endcase
      f_u = {res, flr};
    end
  endfunction

  // 16 bits: {res[15:0], flags}. k: 0 add, 1 adc, 2 sbc
  function [23:0] f_add16; input [1:0] k; input [15:0] x_; input [15:0] y_; input [7:0] fo;
    reg [16:0] s; reg [15:0] r; reg [7:0] fl; reg c;
    begin
      c = (k==2'd0) ? 1'b0 : fo[0];
      if (k==2'd2) s = {1'b0,x_} - {1'b0,y_} - {16'd0,c}; else s = {1'b0,x_} + {1'b0,y_} + {16'd0,c};
      r = s[15:0];
      if (k==2'd0)      fl = {fo[7], fo[6], r[13], (x_[12]^y_[12]^r[12]), r[11], fo[2], 1'b0, s[16]};
      else if (k==2'd1) fl = {r[15], (r==16'd0), r[13], (x_[12]^y_[12]^r[12]), r[11], (~(x_[15]^y_[15]) & (x_[15]^r[15])), 1'b0, s[16]};
      else              fl = {r[15], (r==16'd0), r[13], (x_[12]^y_[12]^r[12]), r[11], ((x_[15]^y_[15]) & (x_[15]^r[15])), 1'b1, s[16]};
      f_add16 = {r, fl};
    end
  endfunction

  function ccond; input [2:0] c; input [7:0] fl;
    begin
      case (c)
        3'd0: ccond = ~fl[6]; 3'd1: ccond = fl[6]; 3'd2: ccond = ~fl[0]; 3'd3: ccond = fl[0];
        3'd4: ccond = ~fl[2]; 3'd5: ccond = fl[2]; 3'd6: ccond = ~fl[7]; default: ccond = fl[7];
      endcase
    end
  endfunction

  function [7:0] g8; input [2:0] s; input [15:0] bc_, de_, hl_, ix_, iy_; input [7:0] a_; input [1:0] pf; input und;
    begin
      case (s)
        3'd0: g8 = bc_[15:8]; 3'd1: g8 = bc_[7:0]; 3'd2: g8 = de_[15:8]; 3'd3: g8 = de_[7:0];
        3'd4: g8 = (und && pf==2'd1) ? ix_[15:8] : (und && pf==2'd2) ? iy_[15:8] : hl_[15:8];
        3'd5: g8 = (und && pf==2'd1) ? ix_[7:0]  : (und && pf==2'd2) ? iy_[7:0]  : hl_[7:0];
        default: g8 = a_;
      endcase
    end
  endfunction

  // ---------------- decoding ----------------
  wire [1:0] x = opr[7:6];
  wire [2:0] y = opr[5:3];
  wire [2:0] z = opr[2:0];
  wire [1:0] p = opr[5:4];
  wire       q = opr[3];
  wire [15:0] hlx = (pfx==2'd1) ? ix : (pfx==2'd2) ? iy : hl;
  wire [15:0] pc1 = pc + 16'd1;
  wire [15:0] pcm = iack ? pc : pc1;
  reg  [15:0] rp16;
  always @* begin case (p) 2'd0: rp16 = bc; 2'd1: rp16 = de; 2'd2: rp16 = hlx; default: rp16 = sp; endcase end
  reg  [15:0] rp2;
  always @* begin case (p) 2'd0: rp2 = bc; 2'd1: rp2 = de; 2'd2: rp2 = hlx; default: rp2 = {a,f}; endcase end
  wire [7:0] r_z_nu = g8(z, bc, de, hl, ix, iy, a, pfx, 1'b0);
  wire [7:0] r_z_u  = g8(z, bc, de, hl, ix, iy, a, pfx, 1'b1);
  wire [7:0] r_y_u  = g8(y, bc, de, hl, ix, iy, a, pfx, 1'b1);

  wire is_memop_np = !pf_ed && !pf_cb &&
        ( (x==2'd1 && opr!=8'h76 && (y==3'd6 || z==3'd6)) || (x==2'd2 && z==3'd6) ||
          (x==2'd0 && y==3'd6 && (z==3'd4 || z==3'd5)) );
  wire is_pfxbyte = !pf_ed && !pf_cb && (opr==8'hDD || opr==8'hFD || opr==8'hED || opr==8'hCB);
  wire dsp = (st==S_DISP) && !(halted && !iack) && !(iack && im==2'd2) && !is_pfxbyte;
  wire [15:0] dirv = y[0] ? 16'hFFFF : 16'h0001;     // +1 / -1 according to the "dec" bit of the block opcode

  // ---------------- request to the 16-bit adder (shared) ----------------
  reg [15:0] a16_x, a16_y; reg [1:0] a16_k;
  always @* begin
    a16_x = pc; a16_y = 16'd0; a16_k = 2'd0;
    case (st)
      S_DISP: if (dsp) begin
        if (pf_ed) begin
          if (x==2'd1 && (z==3'd0 || z==3'd1)) begin a16_x = bc; a16_y = 16'd1; end
          else if (x==2'd1 && z==3'd2)         begin a16_x = hl; a16_y = 16'd1; end
        end else if (!pf_cb) begin
          if (x==2'd0 && z==3'd1 && q)  begin a16_x = hlx; a16_y = 16'd1; end
          else if (x==2'd0 && z==3'd3)  begin a16_x = rp16; a16_y = q ? 16'hFFFF : 16'h0001; end
        end
      end
      S_ADD:  begin a16_x = hlx; a16_y = rp16; a16_k = pf_ed ? (q ? 2'd1 : 2'd2) : 2'd0; end
      S_D, S_DC1: begin a16_x = (pfx==2'd1) ? ix : iy; a16_y = {{8{dbi[7]}}, dbi}; end
      S_JR:   begin a16_x = pc1; a16_y = {{8{dbi[7]}}, dbi}; end
      S_NH:   begin a16_x = {dbi, lo8}; a16_y = 16'd1; end
      S_NW0, S_NR0: begin a16_x = tmp16; a16_y = 16'd1; end
      S_IMM8: begin a16_x = {a, dbi}; a16_y = 16'd1; end
      S_RD1: begin
        if (pf_ed) begin
          if (x==2'd1)                     begin a16_x = hl; a16_y = 16'd1; end
          else if (x==2'd2 && z==3'd1)     begin a16_x = hl; a16_y = dirv; end
          else if (x==2'd2 && z==3'd3)     begin a16_x = bc; a16_y = y[0] ? 16'hFEFF : 16'hFF01; end
        end else if (!pf_cb && x==2'd0 && z==3'd2) begin a16_x = (y==3'd1) ? bc : de; a16_y = 16'd1; end
      end
      S_PL, S_PH, S_X0, S_X2: begin a16_x = sp; a16_y = 16'd1; end
      S_PSH0, S_PSHH:         begin a16_x = sp; a16_y = 16'hFFFF; end
      S_IV0:  begin a16_x = tgt; a16_y = 16'd1; end
      S_B1:   begin a16_x = bc; a16_y = dirv; end
      S_BIOW: begin a16_x = hl; a16_y = dirv; end
      S_BLD:  begin a16_x = de; a16_y = dirv; end
      S_BLD1: begin a16_x = hl; a16_y = dirv; end
      S_BLD2, S_C1: begin a16_x = bc; a16_y = 16'hFFFF; end
      S_C2:   begin a16_x = wz; a16_y = dirv; end
      S_PCM2: begin a16_x = pc; a16_y = 16'hFFFE; end
      S_PCM2B: begin a16_x = pc; a16_y = 16'd1; end
      default: ;
    endcase
  end
  wire [23:0] a16_o = f_add16(a16_k, a16_x, a16_y, f);
  wire [15:0] a16_res = a16_o[23:8];
  wire [7:0]  a16_f   = a16_o[7:0];

  // ---------------- requisicao a unidade de 8 bits (compartilhada) ----------------
  reg [2:0] u_cls, u_op, u_rsel; reg [7:0] u_a, u_b, u_xy; reg u_to_a, u_to_reg, u_to_tmp, u_fen, u_rund;
  always @* begin
    u_cls=3'd0; u_op=y; u_a=a; u_b=8'd0; u_xy=8'd0; u_to_a=1'b0; u_to_reg=1'b0; u_to_tmp=1'b0; u_fen=1'b0; u_rsel=y; u_rund=1'b0;
    case (st)
      S_DISP: if (dsp) begin
        if (pf_cb) begin
          if (z!=3'd6) begin
            u_a=r_z_nu; u_xy=r_z_nu; u_rsel=z; u_rund=1'b0;
            case (x)
              2'd0: begin u_cls=3'd1; u_to_reg=1'b1; u_fen=1'b1; end
              2'd1: begin u_cls=3'd4; u_fen=1'b1; end
              2'd2: begin u_cls=3'd5; u_to_reg=1'b1; end
              default: begin u_cls=3'd6; u_to_reg=1'b1; end
            endcase
          end
        end else if (pf_ed) begin
          if (x==2'd1 && z==3'd4) begin u_cls=3'd0; u_op=3'd2; u_a=8'd0; u_b=a; u_to_a=1'b1; u_fen=1'b1; end
        end else begin
          if (x==2'd0 && (z==3'd4 || z==3'd5) && y!=3'd6) begin
            u_cls=3'd2; u_op={2'b00, z[0]}; u_a=r_y_u; u_rsel=y; u_rund=1'b1; u_to_reg=1'b1; u_fen=1'b1;
          end else if (x==2'd0 && z==3'd7) begin
            if (y<3'd4) begin u_cls=3'd7; u_op=y; end else begin u_cls=3'd3; u_op={1'b0, y[1:0]}; end
            u_to_a=1'b1; u_fen=1'b1;
          end else if (x==2'd2 && z!=3'd6) begin
            u_cls=3'd0; u_op=y; u_a=a; u_b=r_z_u; u_to_a=(y!=3'd7); u_fen=1'b1;
          end
        end
      end
      S_IMM8: if (x==2'd3 && z==3'd6) begin u_cls=3'd0; u_op=y; u_a=a; u_b=dbi; u_to_a=(y!=3'd7); u_fen=1'b1; end
      S_RD1: begin
        if (pf_cb) begin
          u_a=dbi; u_xy=wz[15:8];
          case (x)
            2'd0: begin u_cls=3'd1; u_to_tmp=1'b1; u_fen=1'b1; end
            2'd1: begin u_cls=3'd4; u_fen=1'b1; end
            2'd2: begin u_cls=3'd5; u_to_tmp=1'b1; end
            default: begin u_cls=3'd6; u_to_tmp=1'b1; end
          endcase
        end else if (!pf_ed && x==2'd2) begin u_cls=3'd0; u_op=y; u_a=a; u_b=dbi; u_to_a=(y!=3'd7); u_fen=1'b1; end
        else if (!pf_ed && x==2'd0 && (z==3'd4 || z==3'd5)) begin u_cls=3'd2; u_op={2'b00, z[0]}; u_a=dbi; u_to_tmp=1'b1; u_fen=1'b1; end
      end
      S_DC3: begin
        u_a=dbi; u_xy=ea[15:8]; u_rsel=z; u_rund=1'b0;
        case (x)
          2'd0: begin u_cls=3'd1; u_to_tmp=1'b1; u_fen=1'b1; u_to_reg=(z!=3'd6); end
          2'd1: begin u_cls=3'd4; u_fen=1'b1; end
          2'd2: begin u_cls=3'd5; u_to_tmp=1'b1; u_to_reg=(z!=3'd6); end
          default: begin u_cls=3'd6; u_to_tmp=1'b1; u_to_reg=(z!=3'd6); end
        endcase
      end
      default: ;
    endcase
  end
  wire [15:0] u_o = f_u(u_cls, u_op, u_a, u_b, f, u_xy);
  wire [7:0]  u_res = u_o[15:8];
  wire [7:0]  u_f   = u_o[7:0];

  // ---------------- "next cycle" logic (combinational) ----------------
  reg [7:0]  n_a, n_f, n_ri, n_rr;
  reg [15:0] n_bc, n_de, n_hl, n_sp, n_ix, n_iy, n_pc, n_wz, n_ea, n_tmp16, n_tgt;
  reg        n_iff1, n_iff2, n_halted, n_ei_dly, n_iack, n_pj0, n_pj1, n_nmi_clr, n_pf_ed, n_pf_cb;
  reg [1:0]  n_im, n_pfx;
  reg [7:0]  n_opr, n_lo8, n_tmp8;
  reg [5:0]  n_st;
  reg [2:0]  n_ctyp;
  reg [4:0]  n_ilen;
  reg [1:0]  n_cext;
  reg        n_cack, n_done;
  reg [15:0] n_caddr;
  reg [7:0]  n_cdata;
  reg        do_fin, do_m1, do_exaf, do_exx, do_exdh;
  reg        w8_en, w8_und; reg [2:0] w8_sel; reg [7:0] w8_val;
  reg        w16_en, w16_af; reg [1:0] w16_sel; reg [15:0] w16_val;
  reg        isop;
  reg [7:0]  t8, t8b, t8c; reg [8:0] tsum; reg tb; reg [15:0] nn; reg taken;

  always @* begin
    n_a=a; n_f=f; n_ri=ri; n_rr=rr; n_bc=bc; n_de=de; n_hl=hl; n_sp=sp; n_ix=ix; n_iy=iy; n_pc=pc; n_wz=wz; n_ea=ea;
    n_tmp16=tmp16; n_tgt=tgt; n_iff1=iff1; n_iff2=iff2; n_halted=halted; n_ei_dly=ei_dly; n_iack=iack; n_pj0=pj0; n_pj1=pj1;
    n_nmi_clr=1'b0; n_pf_ed=pf_ed; n_pf_cb=pf_cb; n_im=im; n_pfx=pfx; n_opr=opr; n_lo8=lo8; n_tmp8=tmp8; n_st=st;
    n_ctyp=ctyp; n_ilen=ilen; n_cext=2'd0; n_cack=1'b0; n_done=1'b0; n_caddr=caddr; n_cdata=cdata;
    do_fin=1'b0; do_m1=1'b0; do_exaf=1'b0; do_exx=1'b0; do_exdh=1'b0;
    w8_en=1'b0; w8_und=1'b0; w8_sel=3'd0; w8_val=8'd0; w16_en=1'b0; w16_af=1'b0; w16_sel=2'd0; w16_val=16'd0;
    t8=8'd0; t8b=8'd0; t8c=8'd0; tsum=9'd0; tb=1'b0; nn=16'd0; taken=1'b0; isop=1'b0;
    if (ctyp==CT_M1) n_rr = {rr[7], rr[6:0] + 7'd1};

    if (st==S_EA) isop = 1'b1;
    if (st==S_DISP && ctyp==CT_M1 && is_memop_np && pfx==2'd0 && !halted && !iack) begin isop = 1'b1; n_ea = hl; end

    if (isop) begin
      if (st==S_DISP) n_pc = pcm;
      if (x==2'd1 && y==3'd6) begin
        n_ctyp=CT_MW; n_caddr=(st==S_EA)?ea:hl; n_cdata=r_z_nu; n_st=S_WR1;
      end else begin
        n_ctyp=CT_MR; n_caddr=(st==S_EA)?ea:hl; n_st=S_RD1;
      end
    end else begin
    case (st)
    // ------------------------------------------------------------------ dispatch after M1
    S_DISP: begin
      n_pc = pcm;
      if (halted && !iack) begin n_pc = pc; do_fin=1'b1; end
      else if (iack && im==2'd2) begin
        n_tmp16=pc; n_pj0=1'b0; n_pj1=1'b1; n_tgt={ri, opr}; n_ctyp=CT_INT; n_ilen=5'd1; n_st=S_PSH0;
      end
      else if (!pf_ed && !pf_cb && (opr==8'hDD || opr==8'hFD)) begin
        n_pfx = (opr==8'hDD) ? 2'd1 : 2'd2; do_m1=1'b1;
      end
      else if (!pf_ed && !pf_cb && opr==8'hED) begin n_pf_ed=1'b1; n_pfx=2'd0; do_m1=1'b1; end
      else if (!pf_ed && !pf_cb && opr==8'hCB) begin
        n_pf_cb=1'b1;
        if (pfx!=2'd0) begin n_ctyp=CT_MR; n_caddr=pcm; n_st=S_DC1; end
        else do_m1=1'b1;
      end
      else if (pf_cb) begin
        if (z==3'd6) begin n_ea=hl; n_ctyp=CT_MR; n_caddr=hl; n_st=S_RD1; end
        else do_fin=1'b1;                                                      // unidade U faz o resto
      end
      else if (pf_ed) begin
        if (x==2'd1) begin
          case (z)
            3'd0: begin n_ctyp=CT_IOR; n_caddr=bc; n_st=S_IO; n_wz=a16_res; end
            3'd1: begin n_ctyp=CT_IOW; n_caddr=bc; n_cdata=(y==3'd6)?8'd0:g8(y,bc,de,hl,ix,iy,a,2'd0,1'b0); n_st=S_IO; n_wz=a16_res; end
            3'd2: begin n_wz=a16_res; n_ctyp=CT_INT; n_ilen=5'd4; n_st=S_ADD; end
            3'd3: begin n_ctyp=CT_MR; n_caddr=pcm; n_st=S_NL; end
            3'd4: do_fin=1'b1;
            3'd5: begin n_ctyp=CT_MR; n_caddr=sp; n_st=S_PL; end
            3'd6: begin n_im = (y[1:0]==2'd2) ? 2'd1 : (y[1:0]==2'd3) ? 2'd2 : 2'd0; do_fin=1'b1; end
            default: begin
              case (y)
                3'd0: begin n_ri=a; n_ctyp=CT_INT; n_ilen=5'd1; n_st=S_FINI; end
                3'd1: begin n_rr=a; n_ctyp=CT_INT; n_ilen=5'd1; n_st=S_FINI; end
                3'd2: begin n_a=ri; n_f={ri[7], (ri==8'd0), ri[5], 1'b0, ri[3], iff2, 1'b0, f[0]}; n_ctyp=CT_INT; n_ilen=5'd1; n_st=S_FINI; end
                3'd3: begin n_a=n_rr; n_f={n_rr[7], (n_rr==8'd0), n_rr[5], 1'b0, n_rr[3], iff2, 1'b0, f[0]}; n_ctyp=CT_INT; n_ilen=5'd1; n_st=S_FINI; end
                3'd4, 3'd5: begin n_ea=hl; n_ctyp=CT_MR; n_caddr=hl; n_st=S_RD1; end
                default: do_fin=1'b1;
              endcase
            end
          endcase
        end
        else if (x==2'd2 && z<3'd4 && y>=3'd4) begin
          case (z)
            3'd0, 3'd1: begin n_ctyp=CT_MR; n_caddr=hl; n_st=S_RD1; end
            3'd2: begin n_ctyp=CT_INT; n_ilen=5'd1; n_st=S_B1; end
            default: begin n_ctyp=CT_INT; n_ilen=5'd1; n_st=S_B2; end
          endcase
        end
        else do_fin=1'b1;
      end
      else begin
        case (x)
        2'd0: begin
          case (z)
            3'd0: begin
              case (y)
                3'd0: do_fin=1'b1;
                3'd1: begin do_exaf=1'b1; do_fin=1'b1; end
                3'd2: begin n_bc = {bc[15:8]-8'd1, bc[7:0]}; n_ctyp=CT_INT; n_ilen=5'd1; n_st=S_DJNZ; end
                default: begin n_ctyp=CT_MR; n_caddr=pcm; n_st=S_JR; end
              endcase
            end
            3'd1: begin
              if (!q) begin n_ctyp=CT_MR; n_caddr=pcm; n_st=S_NL; end
              else begin n_wz=a16_res; n_ctyp=CT_INT; n_ilen=5'd4; n_st=S_ADD; end
            end
            3'd2: begin
              case (y)
                3'd0: begin n_ctyp=CT_MW; n_caddr=bc; n_cdata=a; n_st=S_WR1; n_wz={a, bc[7:0]+8'd1}; end
                3'd1: begin n_ctyp=CT_MR; n_caddr=bc; n_st=S_RD1; end
                3'd2: begin n_ctyp=CT_MW; n_caddr=de; n_cdata=a; n_st=S_WR1; n_wz={a, de[7:0]+8'd1}; end
                3'd3: begin n_ctyp=CT_MR; n_caddr=de; n_st=S_RD1; end
                default: begin n_ctyp=CT_MR; n_caddr=pcm; n_st=S_NL; end
              endcase
            end
            3'd3: begin
              w16_en=1'b1; w16_sel=p; w16_val=a16_res;
              n_ctyp=CT_INT; n_ilen=5'd2; n_st=S_FINI;
            end
            3'd4, 3'd5: begin
              if (y!=3'd6) do_fin=1'b1;
              else begin n_ctyp=CT_MR; n_caddr=pcm; n_st=S_D; end
            end
            3'd6: begin
              n_ctyp=CT_MR; n_caddr=pcm;
              if (y==3'd6 && pfx!=2'd0) n_st=S_D; else begin n_st=S_IMM8; if (y==3'd6) n_ea=hl; end
            end
            default: do_fin=1'b1;     // x==0,z==7: unidade U
          endcase
        end
        2'd1: begin
          if (opr==8'h76) begin n_halted=1'b1; do_fin=1'b1; end
          else if (y==3'd6 || z==3'd6) begin n_ctyp=CT_MR; n_caddr=pcm; n_st=S_D; end
          else begin w8_en=1'b1; w8_und=1'b1; w8_sel=y; w8_val=r_z_u; do_fin=1'b1; end
        end
        2'd2: begin
          if (z==3'd6) begin n_ctyp=CT_MR; n_caddr=pcm; n_st=S_D; end
          else do_fin=1'b1;           // unidade U
        end
        default: begin
          case (z)
            3'd0: begin n_ctyp=CT_INT; n_ilen=5'd1; n_st=S_RETCC; end
            3'd1: begin
              if (!q) begin n_ctyp=CT_MR; n_caddr=sp; n_st=S_PL; end
              else case (p)
                2'd0: begin n_ctyp=CT_MR; n_caddr=sp; n_st=S_PL; end
                2'd1: begin do_exx=1'b1; do_fin=1'b1; end
                2'd2: begin n_pc=hlx; do_fin=1'b1; end
                default: begin n_sp=hlx; n_ctyp=CT_INT; n_ilen=5'd2; n_st=S_FINI; end
              endcase
            end
            3'd2, 3'd4: begin n_ctyp=CT_MR; n_caddr=pcm; n_st=S_NL; end
            3'd3: begin
              case (y)
                3'd0: begin n_ctyp=CT_MR; n_caddr=pcm; n_st=S_NL; end
                3'd2, 3'd3: begin n_ctyp=CT_MR; n_caddr=pcm; n_st=S_IMM8; end
                3'd4: begin n_ctyp=CT_MR; n_caddr=sp; n_st=S_X0; end
                3'd5: begin do_exdh=1'b1; do_fin=1'b1; end
                3'd6: begin n_iff1=1'b0; n_iff2=1'b0; do_fin=1'b1; end
                3'd7: begin n_iff1=1'b1; n_iff2=1'b1; n_ei_dly=1'b1; do_fin=1'b1; end
                default: do_fin=1'b1;
              endcase
            end
            3'd5: begin
              if (!q) begin n_tmp16=rp2; n_pj0=1'b0; n_pj1=1'b0; n_ctyp=CT_INT; n_ilen=5'd1; n_st=S_PSH0; end
              else if (p==2'd0) begin n_ctyp=CT_MR; n_caddr=pcm; n_st=S_NL; end
              else do_fin=1'b1;
            end
            3'd6: begin n_ctyp=CT_MR; n_caddr=pcm; n_st=S_IMM8; end
            default: begin
              n_tmp16=pcm; n_tgt={10'd0, y, 3'd0}; n_pj0=1'b1; n_pj1=1'b0; n_ctyp=CT_INT; n_ilen=5'd1; n_st=S_PSH0;
            end
          endcase
        end
        endcase
      end
    end

    // ------------------------------------------------------------------ imediato 8 bits
    S_IMM8: begin
      n_pc = pc1;
      if (x==2'd0) begin
        if (y!=3'd6) begin w8_en=1'b1; w8_und=1'b1; w8_sel=y; w8_val=dbi; do_fin=1'b1; end
        else begin n_ctyp=CT_MW; n_caddr=ea; n_cdata=dbi; n_st=S_WR1; end
      end else if (z==3'd6) begin
        do_fin=1'b1;                                                            // ALU n (unidade U)
      end else if (y==3'd2) begin
        n_ctyp=CT_IOW; n_caddr={a, dbi}; n_cdata=a; n_st=S_IO; n_wz={a, dbi+8'd1};
      end else begin
        n_ctyp=CT_IOR; n_caddr={a, dbi}; n_st=S_IO; n_wz=a16_res;
      end
    end
    S_NL: begin n_pc=pc1; n_lo8=dbi; n_ctyp=CT_MR; n_caddr=pc1; n_st=S_NH; end
    S_NH: begin
      n_pc=pc1; nn={dbi, lo8}; n_tmp16=nn;
      if (pf_ed) begin
        if (!q) begin n_ctyp=CT_MW; n_caddr=nn; n_cdata=rp16[7:0]; n_st=S_NW0; end
        else begin n_ctyp=CT_MR; n_caddr=nn; n_st=S_NR0; end
        n_wz = a16_res;
      end else if (x==2'd0) begin
        if (z==3'd1) begin w16_en=1'b1; w16_sel=p; w16_val=nn; do_fin=1'b1; end
        else case (y)
          3'd4: begin n_ctyp=CT_MW; n_caddr=nn; n_cdata=hlx[7:0]; n_st=S_NW0; n_wz=a16_res; end
          3'd5: begin n_ctyp=CT_MR; n_caddr=nn; n_st=S_NR0; n_wz=a16_res; end
          3'd6: begin n_ctyp=CT_MW; n_caddr=nn; n_cdata=a; n_st=S_WR1; n_wz={a, nn[7:0]+8'd1}; end
          default: begin n_ctyp=CT_MR; n_caddr=nn; n_st=S_RD1; n_wz=a16_res; end
        endcase
      end else begin
        n_wz = nn;
        if (z==3'd2) begin if (ccond(y, f)) n_pc=nn; do_fin=1'b1; end
        else if (z==3'd3) begin n_pc=nn; do_fin=1'b1; end
        else begin
          if (z==3'd5 || ccond(y, f)) begin n_tmp16=pc1; n_tgt=nn; n_pj0=1'b1; n_pj1=1'b0; n_ctyp=CT_INT; n_ilen=5'd1; n_st=S_PSH0; end
          else do_fin=1'b1;
        end
      end
    end
    S_NW0: begin
      n_ctyp=CT_MW; n_caddr=a16_res; n_st=S_WR1;
      if (pf_ed) n_cdata=rp16[15:8]; else n_cdata=hlx[15:8];
    end
    S_NR0: begin n_lo8=dbi; n_ctyp=CT_MR; n_caddr=a16_res; n_st=S_NR1; end
    S_NR1: begin
      w16_en=1'b1; w16_val={dbi, lo8};
      if (pf_ed) w16_sel=p; else w16_sel=2'd2;
      do_fin=1'b1;
    end
    // ------------------------------------------------------------------ indexado
    S_D: begin
      n_pc = pc1;
      n_ea = a16_res; n_wz = a16_res;
      if (x==2'd0 && z==3'd6 && y==3'd6) begin n_ctyp=CT_MR; n_caddr=pc1; n_cext=2'd2; n_st=S_IMM8; end
      else begin n_ctyp=CT_INT; n_ilen=5'd5; n_st=S_EA; end
    end
    S_ADD: begin
      w16_en=1'b1; w16_sel=2'd2; w16_val=a16_res; n_f=a16_f;
      n_ctyp=CT_INT; n_ilen=5'd3; n_st=S_FINI;
    end
    // ------------------------------------------------------------------ operand read
    S_RD1: begin
      if (pf_ed) begin
        if (x==2'd1) begin   // RRD / RLD
          if (y==3'd4) begin n_a={a[7:4], dbi[3:0]}; n_tmp8={a[3:0], dbi[7:4]}; end
          else         begin n_a={a[7:4], dbi[7:4]}; n_tmp8={dbi[3:0], a[3:0]}; end
          t8 = (y==3'd4) ? {a[7:4], dbi[3:0]} : {a[7:4], dbi[7:4]};
          n_f = {t8[7], (t8==8'd0), t8[5], 1'b0, t8[3], par8(t8), 1'b0, f[0]};
          n_wz = a16_res; n_ctyp=CT_INT; n_ilen=5'd4; n_st=S_INC1;
        end else if (z==3'd0) begin
          n_tmp8=dbi; n_ctyp=CT_MW; n_caddr=de; n_cdata=dbi; n_st=S_BLD;
        end else if (z==3'd1) begin    // CPI/CPD..: HL e flags (P e BC no S_C1)
          t8 = a - dbi; tb = a[4]^dbi[4]^t8[4];
          n_hl = a16_res;
          t8c = t8 - {7'd0, tb};
          n_f = {t8[7], (t8==8'd0), t8c[1], tb, t8c[3], 1'b0, 1'b1, f[0]};
          n_tmp8=t8; n_ctyp=CT_INT; n_ilen=5'd1; n_st=S_C1;
        end else begin                 // OUTI/OUTD
          t8 = bc[15:8] - 8'd1;
          n_bc = {t8, bc[7:0]}; n_tmp8 = dbi; n_wz = a16_res;
          n_ctyp=CT_IOW; n_caddr={t8, bc[7:0]}; n_cdata=dbi; n_st=S_BIOW;
        end
      end else if (pf_cb) begin
        n_ctyp=CT_INT; n_ilen=5'd1; n_st=S_INC1;                                  // U: rot/bit/res/set
      end else if (x==2'd0 && z==3'd2) begin
        n_a=dbi;
        if (y==3'd1 || y==3'd3) n_wz=a16_res;
        do_fin=1'b1;
      end else if (x==2'd0) begin
        n_ctyp=CT_INT; n_ilen=5'd1; n_st=S_INC1;                                  // INC/DEC (HL): U
      end else if (x==2'd1) begin
        w8_en=1'b1; w8_und=1'b0; w8_sel=y; w8_val=dbi; do_fin=1'b1;
      end else do_fin=1'b1;                                                       // ALU A,(HL): U
    end
    S_INC1: begin
      if (pf_cb && x==2'd1) do_fin=1'b1;
      else begin n_ctyp=CT_MW; n_caddr=(pf_ed)?hl:ea; n_cdata=tmp8; n_st=S_WR1; end
    end
    S_WR1: do_fin=1'b1;
    S_FINI: do_fin=1'b1;
    // ------------------------------------------------------------------ DDCB
    S_DC1: begin
      n_pc=pc1; n_ea=a16_res; n_wz=a16_res;
      n_ctyp=CT_MR; n_caddr=pc1; n_cext=2'd2; n_st=S_DC2;
    end
    S_DC2: begin n_pc=pc1; n_opr=dbi; n_ctyp=CT_MR; n_caddr=ea; n_st=S_DC3; end
    S_DC3: begin n_ctyp=CT_INT; n_ilen=5'd1; n_st=S_INC1; end                     // U faz o calculo
    // ------------------------------------------------------------------ stack / jumps
    S_PL: begin n_lo8=dbi; n_ctyp=CT_MR; n_caddr=a16_res; n_st=S_PH; n_sp=a16_res; end
    S_PH: begin
      n_sp=a16_res; nn={dbi, lo8};
      if (pf_ed) begin n_pc=nn; n_wz=nn; n_iff1=iff2; do_fin=1'b1; end
      else if (x==2'd3 && z==3'd1 && q==1'b0) begin
        w16_en=1'b1; w16_sel=p; w16_val=nn; w16_af=(p==2'd3); do_fin=1'b1;
      end else begin n_pc=nn; n_wz=nn; do_fin=1'b1; end
    end
    S_RETCC: begin
      if (z==3'd0 && ccond(y, f)) begin n_ctyp=CT_MR; n_caddr=sp; n_st=S_PL; end else do_fin=1'b1;
    end
    S_PSH0: begin n_sp=a16_res; n_ctyp=CT_MW; n_caddr=a16_res; n_cdata=tmp16[15:8]; n_st=S_PSHH; end
    S_PSHH: begin n_sp=a16_res; n_ctyp=CT_MW; n_caddr=a16_res; n_cdata=tmp16[7:0]; n_st=S_PSHL; end
    S_PSHL: begin
      if (pj1) begin n_ctyp=CT_MR; n_caddr=tgt; n_st=S_IV0; end
      else begin if (pj0) begin n_pc=tgt; n_wz=tgt; end do_fin=1'b1; end
    end
    S_IV0: begin n_lo8=dbi; n_ctyp=CT_MR; n_caddr=a16_res; n_st=S_IV1; end
    S_IV1: begin n_pc={dbi, lo8}; n_wz={dbi, lo8}; do_fin=1'b1; end
    S_JR: begin
      n_pc=pc1;
      if (y==3'd2) taken = (bc[15:8]!=8'd0); else if (y==3'd3) taken=1'b1; else taken=ccond({1'b0,y[1:0]}, f);
      if (taken) begin n_pc=a16_res; n_wz=a16_res; n_ctyp=CT_INT; n_ilen=5'd5; n_st=S_FINI; end
      else do_fin=1'b1;
    end
    S_DJNZ: begin n_ctyp=CT_MR; n_caddr=pc; n_st=S_JR; end
    S_IO: begin
      if (pf_ed) begin
        if (z==3'd0) begin
          n_f = {dbi[7], (dbi==8'd0), dbi[5], 1'b0, dbi[3], par8(dbi), 1'b0, f[0]};
          if (y!=3'd6) begin w8_en=1'b1; w8_und=1'b0; w8_sel=y; w8_val=dbi; end
          do_fin=1'b1;
        end else if (z==3'd1) do_fin=1'b1;
        else begin n_tmp8=dbi; n_ctyp=CT_MW; n_caddr=hl; n_cdata=dbi; n_st=S_BIOW; end
      end else begin
        if (y==3'd3) n_a=dbi;
        do_fin=1'b1;
      end
    end
    S_B1: begin n_wz=a16_res; n_ctyp=CT_IOR; n_caddr=bc; n_st=S_IO; end
    S_B2: begin n_ctyp=CT_MR; n_caddr=hl; n_st=S_RD1; end
    S_BIOW: begin
      t8 = (z==3'd2) ? bc[15:8] - 8'd1 : bc[15:8];
      n_hl = a16_res;
      if (z==3'd2) begin n_bc={t8, bc[7:0]}; t8c = y[0] ? bc[7:0] - 8'd1 : bc[7:0] + 8'd1; end
      else t8c = a16_res[7:0];
      tsum = {1'b0,tmp8} + {1'b0,t8c};
      n_f = {t8[7], (t8==8'd0), t8[5], ({1'b0,tmp8} + {1'b0,t8c} > 9'd255), t8[3],
             par8({5'd0, tsum[2:0]} ^ t8), tmp8[7], ({1'b0,tmp8} + {1'b0,t8c} > 9'd255)};
      if (y[1] && t8!=8'd0) begin n_ctyp=CT_INT; n_ilen=5'd3; n_st=S_PCM2; end
      else do_fin=1'b1;
    end
    // ------------------------------------------------------------------ EX (SP),HL
    S_X0: begin n_lo8=dbi; n_ctyp=CT_MR; n_caddr=a16_res; n_st=S_X1; end
    S_X1: begin n_tmp16={dbi, lo8}; n_ctyp=CT_INT; n_ilen=5'd1; n_st=S_X2; end
    S_X2: begin n_ctyp=CT_MW; n_caddr=a16_res; n_cdata=hlx[15:8]; n_st=S_X3; end
    S_X3: begin n_ctyp=CT_MW; n_caddr=sp; n_cdata=hlx[7:0]; n_st=S_X4; end
    S_X4: begin w16_en=1'b1; w16_sel=2'd2; w16_val=tmp16; n_wz=tmp16; n_ctyp=CT_INT; n_ilen=5'd2; n_st=S_FINI; end
    // ------------------------------------------------------------------ blocos
    S_BLD:  begin n_de=a16_res; n_ctyp=CT_INT; n_ilen=5'd1; n_st=S_BLD1; end
    S_BLD1: begin n_hl=a16_res; n_ctyp=CT_INT; n_ilen=5'd1; n_st=S_BLD2; end
    S_BLD2: begin
      n_bc=a16_res;
      t8 = tmp8 + a;
      n_f = {f[7:6], t8[1], 1'b0, t8[3], (a16_res!=16'd0), 1'b0, f[0]};
      if (y[1] && a16_res!=16'd0) begin n_ctyp=CT_INT; n_ilen=5'd3; n_st=S_PCM2; end
      else do_fin=1'b1;
    end
    S_C1: begin
      n_bc=a16_res; n_f={f[7:3], (a16_res!=16'd0), f[1:0]};
      n_ctyp=CT_INT; n_ilen=5'd1; n_st=S_C2;
    end
    S_C2: begin n_wz=a16_res; n_ctyp=CT_INT; n_ilen=5'd3; n_st=S_BCPI; end
    S_BCPI: begin
      if (y[1] && bc!=16'd0 && tmp8!=8'd0) begin n_ctyp=CT_INT; n_ilen=5'd3; n_st=S_PCM2; end
      else do_fin=1'b1;
    end
    S_PCM2: begin n_pc=a16_res; n_ctyp=CT_INT; n_ilen=5'd2; n_st=S_PCM2B; end
    S_PCM2B: begin if (z==3'd0 || z==3'd1) n_wz=a16_res; do_fin=1'b1; end
    default: do_fin=1'b1;
    endcase
    end

    // ----- unit U: writes
    if (u_to_a)   n_a = u_res;
    if (u_to_tmp) n_tmp8 = u_res;
    if (u_fen)    n_f = u_f;
    if (u_to_reg) begin w8_en=1'b1; w8_und=u_rund; w8_sel=u_rsel; w8_val=u_res; end

    if (w8_en) begin
      case (w8_sel)
        3'd0: n_bc[15:8]=w8_val; 3'd1: n_bc[7:0]=w8_val; 3'd2: n_de[15:8]=w8_val; 3'd3: n_de[7:0]=w8_val;
        3'd4: begin if (w8_und && pfx==2'd1) n_ix[15:8]=w8_val; else if (w8_und && pfx==2'd2) n_iy[15:8]=w8_val; else n_hl[15:8]=w8_val; end
        3'd5: begin if (w8_und && pfx==2'd1) n_ix[7:0]=w8_val;  else if (w8_und && pfx==2'd2) n_iy[7:0]=w8_val;  else n_hl[7:0]=w8_val;  end
        3'd7: n_a=w8_val;
        default: ;
      endcase
    end
    if (w16_en) begin
      case (w16_sel)
        2'd0: n_bc=w16_val; 2'd1: n_de=w16_val;
        2'd2: begin if (pfx==2'd1) n_ix=w16_val; else if (pfx==2'd2) n_iy=w16_val; else n_hl=w16_val; end
        default: begin if (w16_af) begin n_a=w16_val[15:8]; n_f=w16_val[7:0]; end else n_sp=w16_val; end
      endcase
    end

    // ----- finalizacao
    if (do_fin || do_m1) begin
      n_st = S_DISP; n_iack=1'b0; n_pj0=1'b0; n_pj1=1'b0;
      if (do_fin) begin n_pfx=2'd0; n_done=1'b1; n_pf_ed=1'b0; n_pf_cb=1'b0; end
      if (do_fin && !(st==S_DISP && !pf_ed && !pf_cb && x==2'd3 && z==3'd3 && y==3'd7)) n_ei_dly=1'b0;
      n_ctyp=CT_M1; n_cack=1'b0; n_caddr=n_pc;
      if (do_fin) begin
        if (nmi_pend) begin
          n_nmi_clr=1'b1; n_iff1=1'b0; n_halted=1'b0; n_tmp16=n_pc; n_tgt=16'h0066; n_pj0=1'b1; n_pj1=1'b0;
          n_ctyp=CT_INT; n_ilen=5'd5; n_st=S_PSH0; n_rr={n_rr[7], n_rr[6:0] + 7'd1};
        end else if (!int_n && n_iff1 && !n_ei_dly) begin
          n_iff1=1'b0; n_iff2=1'b0; n_halted=1'b0; n_iack=1'b1; n_cack=1'b1;
        end
      end
    end
  end

  // ---------------- commit sequencial ----------------
  always @(posedge clk) begin
    instr_done <= 1'b0;
    if (!rst_n) begin
      a<=8'hFF; f<=8'hFF; a2<=8'hFF; f2<=8'hFF; ri<=8'd0; rr<=8'd0;
      bc<=16'hFFFF; de<=16'hFFFF; hl<=16'hFFFF; bc2<=16'hFFFF; de2<=16'hFFFF; hl2<=16'hFFFF;
      ix<=16'hFFFF; iy<=16'hFFFF; sp<=16'hFFFF; pc<=16'd0; wz<=16'd0;
      iff1<=1'b0; iff2<=1'b0; halted<=1'b0; ei_dly<=1'b0; nmi_pend<=1'b0; nmi_prev<=1'b1; iack<=1'b0; pj0<=1'b0; pj1<=1'b0;
      im<=2'd0; pfx<=2'd0; pf_ed<=1'b0; pf_cb<=1'b0; opr<=8'd0; dbi<=8'd0; lo8<=8'd0; tmp8<=8'd0; st<=S_DISP;
      ea<=16'd0; tmp16<=16'd0; tgt<=16'd0;
      ctyp<=CT_M1; t<=5'd1; ilen<=5'd1; cext<=2'd0; cack<=1'b0; cmsx<=1'b0; busak_r<=1'b0; caddr<=16'd0; cdata<=8'd0;
    end else begin
      nmi_prev <= nmi_n;
      if (nmi_prev && !nmi_n) nmi_pend <= 1'b1;
      if (busak_r && busrq_n) busak_r <= 1'b0;
      if (sample) begin
        dbi <= (ctyp==CT_M1 && cack && im==2'd1) ? 8'hFF : din;
        if (ctyp==CT_M1) opr <= (cack && im==2'd1) ? 8'hFF : din;
      end
      if (run) begin
        if (waiting) begin end
        else if (t == clen_e) begin
          // end of cycle: commit
          t <= 5'd1;
          a<=n_a; f<=n_f; ri<=n_ri; rr<=n_rr; sp<=n_sp; pc<=n_pc; wz<=n_wz; ea<=n_ea; tmp16<=n_tmp16; tgt<=n_tgt;
          iff1<=n_iff1; iff2<=n_iff2; halted<=n_halted; ei_dly<=n_ei_dly; iack<=n_iack; pj0<=n_pj0; pj1<=n_pj1;
          pf_ed<=n_pf_ed; pf_cb<=n_pf_cb; im<=n_im; pfx<=n_pfx; lo8<=n_lo8; tmp8<=n_tmp8; st<=n_st;
          // opr: only changes by n_opr (S_DC2); the M1 opr has already been sampled
          if (n_opr != opr) opr <= n_opr;
          // pairs (with bank switching)
          if (do_exaf) begin a<=a2; f<=f2; a2<=n_a; f2<=n_f; end
          if (do_exx) begin bc<=bc2; de<=de2; hl<=hl2; bc2<=n_bc; de2<=n_de; hl2<=n_hl; ix<=n_ix; iy<=n_iy; end
          else if (do_exdh) begin de<=n_hl; hl<=n_de; ix<=n_ix; iy<=n_iy; end
          else begin bc<=n_bc; de<=n_de; hl<=n_hl; ix<=n_ix; iy<=n_iy; end
          if (n_nmi_clr) nmi_pend <= 1'b0;
          ctyp<=n_ctyp; caddr<=n_caddr; cdata<=n_cdata; ilen<=n_ilen; cext<=n_cext; cack<=n_cack; cmsx<=msx_w;
          instr_done <= n_done;
          if (!busrq_n) busak_r <= 1'b1;
        end else t <= t + 5'd1;
      end
    end
  end
endmodule
