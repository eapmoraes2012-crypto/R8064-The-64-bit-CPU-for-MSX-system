// z80_core.v - Z80 classico MICROCODIFICADO (R8064 modulo 12, v3). Gerado por gen_rtl.py a partir de z80_core.v.in (nao editar o .v a mao).
// Arquitetura: motor de ciclos de barramento (M1/MR/MW/IOR/IOW/INT, igual ao da v1 verificada) + sequenciador de microcodigo.
//  - banco de registradores 32x8 em RAM distribuida (duas copias p/ duas portas de leitura), ULA de 8 bits unica, F/W/Z/I/R em flip-flops;
//  - microcodigo (z80_urom, 74 bits x 1024) + tabela de despacho por opcode (z80_dtab) em BSRAM;
//  - 1 microinstrucao por clock; um ciclo de barramento so comeca quando a microinstrucao pede (T-states exatos; 'tick' conta os T-states).
`timescale 1ns/1ps
module z80_core(
  input  wire        clk,
  input  wire        ce,        // um pulso = um T-state (separados por >= 3 clocks)
  input  wire        rst_n,
  output wire [15:0] addr,
  output wire [7:0]  dout,
  input  wire [7:0]  din,
  output wire        mreq, rd, wr, iorq, m1, rfsh,
  input  wire        wait_n, int_n, nmi_n, busrq_n,
  input  wire        msx_w,     // 1 = +1 wait em M1 e E/S (MSX)
  output wire        halt, busak, bus_oe,
  output reg         instr_done,
  output wire        tick       // 1 por T-state executado (ce aceito com ciclo ativo e sem WAIT)
);
  localparam CT_M1=3'd0, CT_MR=3'd1, CT_MW=3'd2, CT_IOR=3'd3, CT_IOW=3'd4, CT_INT=3'd5;
  localparam [3:0] K_RF=4'd0, K_F=4'd1, K_ZERO=4'd2, K_DBI=4'd3, K_I=4'd4, K_R=4'd5, K_OPR=4'd6, K_WH=4'd7, K_WL=4'd8;
  localparam [9:0] ENTRY_FETCH=10'd0, ENTRY_RESET=10'd8, ENTRY_NMI=10'd600, ENTRY_IM2=10'd615;
  localparam [4:0] BUS_INT = 5'd6;
  localparam [4:0] BUS_IOR = 5'd4;
  localparam [4:0] BUS_IOW = 5'd5;
  localparam [4:0] BUS_M1 = 5'd1;
  localparam [4:0] BUS_MR = 5'd2;
  localparam [4:0] BUS_MW = 5'd3;
  localparam [4:0] BUS_NONE = 5'd0;
  localparam [4:0] C_ALU = 5'd1;
  localparam [4:0] C_BIOF = 5'd14;
  localparam [4:0] C_BIT = 5'd5;
  localparam [4:0] C_CBX = 5'd17;
  localparam [4:0] C_CPF = 5'd13;
  localparam [4:0] C_DAA = 5'd4;
  localparam [4:0] C_INCDEC = 5'd3;
  localparam [4:0] C_LDAI = 5'd11;
  localparam [4:0] C_LDF = 5'd12;
  localparam [4:0] C_NIBA = 5'd15;
  localparam [4:0] C_NIBT = 5'd16;
  localparam [4:0] C_NONE = 5'd0;
  localparam [4:0] C_PASSB = 5'd9;
  localparam [4:0] C_RES = 5'd6;
  localparam [4:0] C_ROT = 5'd2;
  localparam [4:0] C_ROTA = 5'd8;
  localparam [4:0] C_SET = 5'd7;
  localparam [4:0] C_SZP = 5'd10;
  localparam [4:0] K_ALWAYS = 5'd1;
  localparam [4:0] K_CCJR = 5'd3;
  localparam [4:0] K_CCY = 5'd2;
  localparam [4:0] K_CPY = 5'd18;
  localparam [4:0] K_FZ = 5'd8;
  localparam [4:0] K_HALTED = 5'd13;
  localparam [4:0] K_IACK = 5'd12;
  localparam [4:0] K_IM2 = 5'd17;
  localparam [4:0] K_NEVER = 5'd0;
  localparam [4:0] K_PFXNZ = 5'd6;
  localparam [4:0] K_Q = 5'd14;
  localparam [4:0] K_XEQ0 = 5'd16;
  localparam [4:0] K_XEQ1 = 5'd15;
  localparam [4:0] K_Y0 = 5'd10;
  localparam [4:0] K_Y1 = 5'd11;
  localparam [4:0] K_YEQ6 = 5'd4;
  localparam [4:0] K_Z16 = 5'd7;
  localparam [4:0] K_ZEQ6 = 5'd5;
  localparam [4:0] K_ZLA = 5'd9;
  localparam [5:0] R_A = 6'd7;
  localparam [5:0] R_B = 6'd0;
  localparam [5:0] R_C = 6'd1;
  localparam [5:0] R_D = 6'd2;
  localparam [5:0] R_DBI = 6'd31;
  localparam [5:0] R_E = 6'd3;
  localparam [5:0] R_EAH = 6'd35;
  localparam [5:0] R_EAL = 6'd36;
  localparam [5:0] R_F = 6'd6;
  localparam [5:0] R_H = 6'd4;
  localparam [5:0] R_HXH = 6'd12;
  localparam [5:0] R_HXL = 6'd13;
  localparam [5:0] R_I = 6'd32;
  localparam [5:0] R_IXH = 6'd18;
  localparam [5:0] R_IXL = 6'd19;
  localparam [5:0] R_IYH = 6'd20;
  localparam [5:0] R_IYL = 6'd21;
  localparam [5:0] R_L = 6'd5;
  localparam [5:0] R_OPR = 6'd34;
  localparam [5:0] R_PCH = 6'd24;
  localparam [5:0] R_PCL = 6'd25;
  localparam [5:0] R_QH = 6'd16;
  localparam [5:0] R_QL = 6'd17;
  localparam [5:0] R_R = 6'd33;
  localparam [5:0] R_RPH = 6'd14;
  localparam [5:0] R_RPL = 6'd15;
  localparam [5:0] R_SPH = 6'd22;
  localparam [5:0] R_SPL = 6'd23;
  localparam [5:0] R_TH = 6'd28;
  localparam [5:0] R_TL = 6'd29;
  localparam [5:0] R_WH = 6'd26;
  localparam [5:0] R_WL = 6'd27;
  localparam [5:0] R_Y = 6'd8;
  localparam [5:0] R_YN = 6'd10;
  localparam [5:0] R_Z = 6'd9;
  localparam [5:0] R_ZERO = 6'd30;
  localparam [5:0] R_ZN = 6'd11;
  localparam [4:0] S_DI = 5'd9;
  localparam [4:0] S_DISPATCH = 5'd3;
  localparam [4:0] S_EI = 5'd10;
  localparam [4:0] S_END = 5'd1;
  localparam [4:0] S_ENDEI = 5'd2;
  localparam [4:0] S_EXAF = 5'd8;
  localparam [4:0] S_EXX = 5'd7;
  localparam [4:0] S_HALT = 5'd12;
  localparam [4:0] S_INCR = 5'd15;
  localparam [4:0] S_NMIACK = 5'd16;
  localparam [4:0] S_NONE = 5'd0;
  localparam [4:0] S_RETIFF = 5'd13;
  localparam [4:0] S_SETCB = 5'd6;
  localparam [4:0] S_SETED = 5'd5;
  localparam [4:0] S_SETIM = 5'd11;
  localparam [4:0] S_SETOPR = 5'd14;
  localparam [4:0] S_SETPFX = 5'd4;
  localparam [1:0] SQ_RUN=2'd0, SQ_WAIT=2'd1, SQ_INIT=2'd2;

  // ---------------- estado ----------------
  reg [7:0]  rfa [0:31];
  reg [7:0]  rfb [0:31];
  reg [7:0]  f, f2, wh, wl, ri, rr, opr, dbi;
  reg        bkx, bka;
  reg [1:0]  pfx, im;
  reg        pf_ed, pf_cb;
  reg        iff1, iff2, halted, ei_dly, iack, nmi_pend, nmi_prev, cy, zl, z16;
  reg [9:0]  upc;
  reg [1:0]  seq;
  // motor de ciclos
  reg [2:0]  ctyp;
  reg [4:0]  t, ilen;
  reg [1:0]  cext;
  reg        cack, cmsx, busak_r, act;
  reg [15:0] caddr;
  reg [7:0]  cdata;
  integer    ii;
  initial begin for (ii = 0; ii < 32; ii = ii + 1) begin rfa[ii] = 8'd0; rfb[ii] = 8'd0; end end

  wire [73:0] uw;
  wire [9:0]  tq;
  wire [9:0]  raddr;
  wire [4:0] w_cls = uw[4:0];
  wire [2:0] w_op = uw[7:5];
  wire [1:0] w_opsel = uw[9:8];
  wire [5:0] w_sa = uw[15:10];
  wire [5:0] w_sb = uw[21:16];
  wire [5:0] w_dst = uw[27:22];
  wire [2:0] w_bk = uw[30:28];
  wire [1:0] w_fm = uw[32:31];
  wire w_cin = uw[33];
  wire w_zch = uw[34];
  wire w_xyw = uw[35];
  wire w_lda = uw[36];
  wire [2:0] w_bus = uw[39:37];
  wire [4:0] w_bn = uw[44:40];
  wire [4:0] w_cond = uw[49:45];
  wire w_inv = uw[50];
  wire [9:0] w_tgt = uw[60:51];
  wire [4:0] w_sp = uw[65:61];
  wire [7:0] w_imm = uw[73:66];

  // ---------------- motor de ciclos de barramento ----------------
  wire [4:0] clen_e = (ctyp==CT_M1) ? (cack ? 5'd6 : 5'd4 + {4'd0,cmsx}) :
                      (ctyp==CT_MR) ? 5'd3 + {3'd0,cext} :
                      (ctyp==CT_MW) ? 5'd3 :
                      (ctyp==CT_IOR || ctyp==CT_IOW) ? 5'd4 + {4'd0,cmsx} : ilen;
  wire [4:0] wp_e   = (ctyp==CT_M1) ? (cack ? 5'd4 : 5'd2 + {4'd0,cmsx}) :
                      (ctyp==CT_MR || ctyp==CT_MW) ? 5'd2 :
                      (ctyp==CT_IOR || ctyp==CT_IOW) ? 5'd3 + {4'd0,cmsx} : 5'd0;
  wire       run     = ce & ~busak_r;
  wire       waiting = act && (wp_e != 5'd0) && (t == wp_e) && !wait_n;
  wire       sample  = run && act && (wp_e != 5'd0) && (t == wp_e) && wait_n && (ctyp==CT_M1 || ctyp==CT_MR || ctyp==CT_IOR);
  wire       cyc_end = run && act && (t == clen_e) && !waiting;
  assign     tick    = run && act && !waiting;
  wire m1c   = (ctyp==CT_M1);
  assign addr  = (m1c && !cack && (t > wp_e)) ? {ri, rr} : caddr;
  assign dout  = cdata;
  assign m1    = act && m1c && (t <= wp_e) && bus_oe;
  assign mreq  = act && bus_oe && ( (m1c && !cack && (t >= 5'd1)) || ((ctyp==CT_MR || ctyp==CT_MW) && (t>=5'd1)) );
  assign rd    = act && bus_oe && ( (m1c && (t >= 5'd1) && (t <= wp_e)) || (ctyp==CT_MR && t>=5'd1) || (ctyp==CT_IOR && t>=5'd2) );
  assign wr    = act && bus_oe && ( (ctyp==CT_MW && t>=5'd2) || (ctyp==CT_IOW && t>=5'd2) );
  assign iorq  = act && bus_oe && ( ((ctyp==CT_IOR || ctyp==CT_IOW) && t>=5'd2) || (m1c && cack && t>=5'd3 && t<=wp_e) );
  assign rfsh  = act && bus_oe && m1c && !cack && (t > wp_e);
  assign halt  = halted;
  assign busak = busak_r;
  assign bus_oe = ~busak_r;

  // ---------------- funcoes ----------------
  function par8; input [7:0] v; begin par8 = ~(^v); end endfunction

  function ccond; input [2:0] c; input [7:0] fl;
    begin
      case (c)
        3'd0: ccond = ~fl[6]; 3'd1: ccond = fl[6]; 3'd2: ccond = ~fl[0]; 3'd3: ccond = fl[0];
        3'd4: ccond = ~fl[2]; 3'd5: ccond = fl[2]; 3'd6: ccond = ~fl[7]; default: ccond = fl[7];
      endcase
    end
  endfunction

  // mapeamento de identificador de registrador -> {tipo[3:0], endereco do banco[4:0]}
  function [8:0] rmap; input [5:0] rid; input [7:0] o; input [1:0] pf; input bx; input ba;
    reg [3:0] kd; reg [4:0] ad; reg [2:0] v; reg und, lo; reg [1:0] p;
    begin
      kd = K_RF; ad = 5'd0; v = 3'd0; und = 1'b0; lo = 1'b0; p = o[5:4];
      if (rid <= 6'd5) ad = {1'b0, bx, rid[2:0]};
      else case (rid)
        R_F: kd = K_F;
        R_A: ad = {1'b0, ba, 3'd7};
        R_Y, R_YN, R_Z, R_ZN: begin
          v = (rid==R_Y || rid==R_YN) ? o[5:3] : o[2:0];
          und = (rid==R_Y || rid==R_Z);
          if (v == 3'd6) kd = K_ZERO;
          else if (v == 3'd7) ad = {1'b0, ba, 3'd7};
          else if (und && pf != 2'd0 && v[2:1] == 2'b10) ad = {3'b100, (pf==2'd2), v[0]};
          else ad = {1'b0, bx, v};
        end
        R_HXH, R_HXL: begin
          lo = (rid == R_HXL);
          if (pf == 2'd0) ad = {1'b0, bx, 2'b10, lo}; else ad = {3'b100, (pf==2'd2), lo};
        end
        R_RPH, R_RPL, R_QH, R_QL: begin
          lo = (rid == R_RPL) || (rid == R_QL);
          case (p)
            2'd0: ad = {1'b0, bx, 2'b00, lo};
            2'd1: ad = {1'b0, bx, 2'b01, lo};
            2'd2: begin if (pf == 2'd0) ad = {1'b0, bx, 2'b10, lo}; else ad = {3'b100, (pf==2'd2), lo}; end
            default: begin
              if (rid == R_RPH || rid == R_RPL) ad = {4'b1010, lo};
              else if (!lo) ad = {1'b0, ba, 3'd7};
              else kd = K_F;
            end
          endcase
        end
        R_IXH: ad = 5'd16; R_IXL: ad = 5'd17; R_IYH: ad = 5'd18; R_IYL: ad = 5'd19;
        R_SPH: ad = 5'd20; R_SPL: ad = 5'd21; R_PCH: ad = 5'd22; R_PCL: ad = 5'd23;
        R_WH: kd = K_WH; R_WL: kd = K_WL;
        R_TH: ad = 5'd24; R_TL: ad = 5'd25;
        R_ZERO: kd = K_ZERO;
        R_DBI: kd = K_DBI; R_I: kd = K_I; R_R: kd = K_R; R_OPR: kd = K_OPR;
        R_EAH, R_EAL: begin
          lo = (rid == R_EAL);
          if (pf == 2'd0) ad = {1'b0, bx, 2'b10, lo}; else kd = lo ? K_WL : K_WH;
        end
        default: kd = K_ZERO;
      endcase
      rmap = {kd, ad};
    end
  endfunction

  function [7:0] rdv; input [3:0] kd; input [7:0] rfv; input [7:0] f_, dbi_, ri_, rr_, opr_, wh_, wl_;
    begin
      case (kd)
        K_RF: rdv = rfv; K_F: rdv = f_; K_DBI: rdv = dbi_; K_I: rdv = ri_; K_R: rdv = rr_; K_OPR: rdv = opr_;
        K_WH: rdv = wh_; K_WL: rdv = wl_; default: rdv = 8'd0;
      endcase
    end
  endfunction

  // ULA de 8 bits: {cy_out, res[7:0], flags[7:0]}
  function [16:0] f_alu; input [4:0] cls; input [2:0] op; input [7:0] a_, b_, fo, xy_; input iff2_, z16_; input [7:0] dbi_;
    reg [2:0] aop; reg [7:0] bb, tt, r, fl, res, flr, d_, t_; reg [8:0] s, kk; reg ci, sub, ov, c, h, hb; reg cyo; reg [2:0] k3;
    begin
      aop = op; bb = b_; tt = 8'd0;
      if (cls == C_DAA) begin
        if (fo[4] || a_[3:0] > 4'd9) tt = tt | 8'h06;
        if (fo[0] || a_ > 8'h99) tt = tt | 8'h60;
        aop = fo[1] ? 3'd2 : 3'd0; bb = tt;
      end
      if (cls == C_INCDEC) begin aop = op[0] ? 3'd2 : 3'd0; bb = 8'd1; end
      sub = (aop == 3'd2) || (aop == 3'd3) || (aop == 3'd7);
      ci  = (aop == 3'd1 || aop == 3'd3) ? fo[0] : 1'b0;
      if (!sub) s = {1'b0, a_} + {1'b0, bb} + {8'd0, ci};
      else      s = {1'b0, a_} - {1'b0, bb} - {8'd0, ci};
      r = s[7:0];
      fl[7] = r[7]; fl[6] = (r == 8'd0);
      fl[5] = (aop == 3'd7) ? bb[5] : r[5];
      fl[3] = (aop == 3'd7) ? bb[3] : r[3];
      fl[4] = a_[4] ^ bb[4] ^ r[4];
      fl[2] = sub ? ((a_[7] ^ bb[7]) & (a_[7] ^ r[7])) : (~(a_[7] ^ bb[7]) & (a_[7] ^ r[7]));
      fl[1] = sub; fl[0] = s[8];
      res = r; flr = fl; cyo = s[8];
      case (cls)
        C_ALU: begin
          if (aop == 3'd4 || aop == 3'd5 || aop == 3'd6) begin
            res = (aop == 3'd4) ? (a_ & b_) : (aop == 3'd5) ? (a_ ^ b_) : (a_ | b_);
            flr = {res[7], (res == 8'd0), res[5], 1'b0, res[3], par8(res), 2'b00};
            if (aop == 3'd4) flr[4] = 1'b1;
          end
        end
        C_INCDEC: flr = {fl[7:1], fo[0]};
        C_DAA: begin
          case (op[1:0])
            2'd0: begin
              c = fo[0] || (a_ > 8'h99);
              h = fo[1] ? (fo[4] && (a_[3:0] < 4'd6)) : (a_[3:0] > 4'd9);
              res = r; flr = {r[7], (r == 8'd0), r[5], h, r[3], par8(r), fo[1], c};
            end
            2'd1: begin res = ~a_; flr = {fo[7:6], res[5], 1'b1, res[3], fo[2], 1'b1, fo[0]}; end
            2'd2: begin res = a_;  flr = {fo[7:6], a_[5], 1'b0, a_[3], fo[2], 1'b0, 1'b1}; end
            default: begin res = a_; flr = {fo[7:6], a_[5], fo[0], a_[3], fo[2], 1'b0, ~fo[0]}; end
          endcase
        end
        C_ROT, C_ROTA: begin
          k3 = (cls == C_ROT) ? op : {1'b0, op[1:0]};
          case (k3)
            3'd0: begin c = a_[7]; res = {a_[6:0], a_[7]}; end
            3'd1: begin c = a_[0]; res = {a_[0], a_[7:1]}; end
            3'd2: begin c = a_[7]; res = {a_[6:0], fo[0]}; end
            3'd3: begin c = a_[0]; res = {fo[0], a_[7:1]}; end
            3'd4: begin c = a_[7]; res = {a_[6:0], 1'b0}; end
            3'd5: begin c = a_[0]; res = {a_[7], a_[7:1]}; end
            3'd6: begin c = a_[7]; res = {a_[6:0], 1'b1}; end
            default: begin c = a_[0]; res = {1'b0, a_[7:1]}; end
          endcase
          if (cls == C_ROT) flr = {res[7], (res == 8'd0), res[5], 1'b0, res[3], par8(res), 1'b0, c};
          else flr = {fo[7:6], res[5], 1'b0, res[3], fo[2], 1'b0, c};
        end
        C_BIT: begin res = a_; flr = {(op == 3'd7 && a_[op]), ~a_[op], xy_[5], 1'b1, xy_[3], ~a_[op], 1'b0, fo[0]}; end
        C_RES: begin res = a_ & ~(8'd1 << op); flr = fo; end
        C_SET: begin res = a_ | (8'd1 << op); flr = fo; end
        C_PASSB: begin res = b_; flr = fo; end
        C_SZP: begin res = a_; flr = {a_[7], (a_ == 8'd0), a_[5], 1'b0, a_[3], par8(a_), 1'b0, fo[0]}; end
        C_LDAI: begin res = a_; flr = {a_[7], (a_ == 8'd0), a_[5], 1'b0, a_[3], iff2_, 1'b0, fo[0]}; end
        C_LDF: begin
          d_ = a_ + b_; res = a_;
          flr = {fo[7:6], d_[1], 1'b0, d_[3], ~z16_, 1'b0, fo[0]};
        end
        C_CPF: begin
          d_ = a_ - b_; hb = a_[4] ^ b_[4] ^ d_[4]; t_ = d_ - {7'd0, hb}; res = a_;
          flr = {d_[7], (d_ == 8'd0), t_[1], hb, t_[3], ~z16_, 1'b1, fo[0]};
        end
        C_BIOF: begin
          kk = {1'b0, dbi_} + {1'b0, b_}; res = a_;
          flr = {a_[7], (a_ == 8'd0), a_[5], kk[8], a_[3], par8({5'd0, kk[2:0]} ^ a_), dbi_[7], kk[8]};
        end
        C_NIBA: begin
          res = op[0] ? {a_[7:4], b_[7:4]} : {a_[7:4], b_[3:0]};
          flr = {res[7], (res == 8'd0), res[5], 1'b0, res[3], par8(res), 1'b0, fo[0]};
        end
        C_NIBT: begin
          res = op[0] ? {b_[3:0], a_[3:0]} : {a_[3:0], b_[7:4]};
          flr = fo;
        end
        default: begin res = r; flr = fl; end
      endcase
      f_alu = {cyo, res, flr};
    end
  endfunction

  // ---------------- ROM de microcodigo e tabela de despacho ----------------
  z80_urom u_rom(.clk(clk), .addr(raddr), .q(uw));
  z80_dtab u_dt (.clk(clk), .addr({pf_cb ? 2'd2 : (pf_ed ? 2'd1 : 2'd0), opr}), .q(tq));

  // ---------------- decodificacao da microinstrucao e caminho de dados ----------------
  wire [8:0] ma = rmap(w_sa,  opr, pfx, bkx, bka);
  wire [8:0] mb = rmap(w_sb,  opr, pfx, bkx, bka);
  wire [8:0] md = rmap(w_dst, opr, pfx, bkx, bka);
  wire [7:0] ra = rdv(ma[8:5], rfa[ma[4:0]], f, dbi, ri, rr, opr, wh, wl);
  wire [7:0] rb = rdv(mb[8:5], rfb[mb[4:0]], f, dbi, ri, rr, opr, wh, wl);
  wire [2:0] y3 = opr[5:3];
  wire [2:0] z3 = opr[2:0];
  wire [1:0] x2 = opr[7:6];
  wire [2:0] a_op = (w_opsel == 2'd0) ? w_op : (w_opsel == 2'd1) ? y3 : (w_opsel == 2'd2) ? z3 : {1'b0, y3[0], w_op[0]};
  reg  [7:0] b_val;
  always @* begin
    case (w_bk)
      3'd0: b_val = rb;
      3'd1: b_val = 8'd0;
      3'd2: b_val = 8'd1;
      3'd3: b_val = 8'hFF;
      3'd4: b_val = {8{rb[7]}};
      3'd5: b_val = w_imm;
      default: b_val = {2'b00, y3, 3'b000};
    endcase
  end
  wire [4:0] u_cls = (w_cls == C_CBX) ? ((x2 == 2'd0) ? C_ROT : (x2 == 2'd1) ? C_BIT : (x2 == 2'd2) ? C_RES : C_SET) : w_cls;
  wire [7:0] fo_u  = {f[7:1], w_cin ? cy : f[0]};
  wire [7:0] xy_u  = w_xyw ? wh : ra;
  wire [16:0] au   = f_alu(u_cls, a_op, ra, b_val, fo_u, xy_u, iff2, z16, dbi);
  wire [7:0] u_res = au[15:8];
  wire [7:0] u_fl  = au[7:0];
  wire       u_cy  = au[16];
  wire       is_alu = (w_cls != C_NONE);
  wire       wen    = is_alu && !(u_cls == C_BIT || (u_cls == C_ALU && a_op == 3'd7));

  // condicoes
  reg cnd;
  always @* begin
    case (w_cond)
      K_NEVER:  cnd = 1'b0;
      K_ALWAYS: cnd = 1'b1;
      K_CCY:    cnd = ccond(y3, f);
      K_CCJR:   cnd = ccond({1'b0, y3[1:0]}, f);
      K_YEQ6:   cnd = (y3 == 3'd6);
      K_ZEQ6:   cnd = (z3 == 3'd6);
      K_PFXNZ:  cnd = (pfx != 2'd0);
      K_Z16:    cnd = z16;
      K_FZ:     cnd = f[6];
      K_ZLA:    cnd = zl;
      K_Y0:     cnd = y3[0];
      K_Y1:     cnd = y3[1];
      K_IACK:   cnd = iack;
      K_HALTED: cnd = halted;
      K_Q:      cnd = y3[0];
      K_XEQ1:   cnd = (x2 == 2'd1);
      K_XEQ0:   cnd = (x2 == 2'd0);
      K_IM2:    cnd = (im == 2'd2);
      K_CPY:    cnd = (x2 != 2'd1) && (z3 != 3'd6);
      default:  cnd = 1'b0;
    endcase
  end
  wire        take  = cnd ^ w_inv;
  wire        ex    = (seq == SQ_RUN);
  wire        sp_end = (w_sp == S_END) || (w_sp == S_ENDEI);
  wire        int_go = !int_n && iff1 && (w_sp != S_ENDEI);
  reg  [9:0]  nupc;
  always @* begin
    nupc = take ? w_tgt : (upc + 10'd1);
    if (sp_end) nupc = nmi_pend ? ENTRY_NMI : ENTRY_FETCH;
    else if (w_sp == S_DISPATCH) nupc = (iack && im == 2'd2) ? ENTRY_IM2 : tq;
  end
  assign raddr = ex ? nupc : upc;
  wire        bstart = ex && (w_bus != BUS_NONE);
  wire [2:0]  bct = (w_bus == BUS_M1) ? CT_M1 : (w_bus == BUS_MR) ? CT_MR : (w_bus == BUS_MW) ? CT_MW :
                    (w_bus == BUS_IOR) ? CT_IOR : (w_bus == BUS_IOW) ? CT_IOW : CT_INT;

  // ---------------- sequencial ----------------
  always @(posedge clk) begin
    instr_done <= 1'b0;
    if (!rst_n) begin
      f <= 8'hFF; f2 <= 8'hFF; wh <= 8'd0; wl <= 8'd0; ri <= 8'd0; rr <= 8'd0; opr <= 8'd0; dbi <= 8'd0;
      bkx <= 1'b0; bka <= 1'b0; pfx <= 2'd0; im <= 2'd0; pf_ed <= 1'b0; pf_cb <= 1'b0;
      iff1 <= 1'b0; iff2 <= 1'b0; halted <= 1'b0; ei_dly <= 1'b0; iack <= 1'b0; nmi_pend <= 1'b0; nmi_prev <= 1'b1;
      cy <= 1'b0; zl <= 1'b0; z16 <= 1'b0;
      upc <= ENTRY_RESET; seq <= SQ_INIT;
      ctyp <= CT_M1; t <= 5'd1; ilen <= 5'd1; cext <= 2'd0; cack <= 1'b0; cmsx <= 1'b0; busak_r <= 1'b0; act <= 1'b0;
      caddr <= 16'd0; cdata <= 8'd0;
    end else begin
      nmi_prev <= nmi_n;
      if (nmi_prev && !nmi_n) nmi_pend <= 1'b1;
      if (busak_r && busrq_n) busak_r <= 1'b0;
      // ---- motor de ciclos ----
      if (sample) begin
        dbi <= (ctyp == CT_M1 && cack && im == 2'd1) ? 8'hFF : din;
        if (ctyp == CT_M1) opr <= (cack && im == 2'd1) ? 8'hFF : din;
      end
      if (run && act) begin
        if (waiting) begin end
        else if (t == clen_e) begin
          act <= 1'b0;
          if (ctyp == CT_M1) rr <= {rr[7], rr[6:0] + 7'd1};
        end else t <= t + 5'd1;
      end
      if (!busrq_n && (cyc_end || !act)) busak_r <= 1'b1;
      // ---- sequenciador ----
      case (seq)
        SQ_INIT: begin seq <= SQ_RUN; end
        SQ_WAIT: begin if (cyc_end) seq <= SQ_RUN; end
        default: begin   // SQ_RUN: executa a microinstrucao 'uw'
          upc <= nupc;
          // leitura de endereco (LDA)
          if (w_lda) caddr <= {ra, rb};
          // ULA
          if (is_alu) begin
            if (wen) begin
              case (md[8:5])
                K_RF: begin rfa[md[4:0]] <= u_res; rfb[md[4:0]] <= u_res; end
                K_F:  f <= u_res;
                K_I:  ri <= u_res;
                K_R:  rr <= u_res;
                K_WH: wh <= u_res;
                K_WL: wl <= u_res;
                default: ;
              endcase
            end
            case (w_fm)
              2'd1: f <= u_fl;
              2'd2: f <= {f[7:6], u_fl[5:3], f[2], 1'b0, u_fl[0]};
              2'd3: f <= {u_fl[7], u_fl[6] & zl, u_fl[5:0]};
              default: ;
            endcase
            if (w_cls == C_ALU) begin
              cy <= u_cy;
              z16 <= (u_res == 8'd0) & (w_zch ? zl : 1'b1);
              zl  <= (u_res == 8'd0);
            end
          end
          // inicio de ciclo de barramento
          if (bstart) begin
            seq <= SQ_WAIT;
            ctyp <= bct; t <= 5'd1; act <= 1'b1; ilen <= w_bn; cext <= w_bn[1:0];
            cack <= (w_bus == BUS_M1) ? iack : 1'b0; cmsx <= msx_w;
            if (w_bus == BUS_MW || w_bus == BUS_IOW) cdata <= ra;
          end
          // operacoes especiais
          case (w_sp)
            S_END, S_ENDEI: begin
              instr_done <= 1'b1;
              pfx <= 2'd0; pf_ed <= 1'b0; pf_cb <= 1'b0;
              ei_dly <= (w_sp == S_ENDEI);
              if (nmi_pend) begin
                nmi_pend <= 1'b0; iff1 <= 1'b0; halted <= 1'b0; rr <= {rr[7], rr[6:0] + 7'd1};
              end else if (int_go) begin
                iff1 <= 1'b0; iff2 <= 1'b0; halted <= 1'b0; iack <= 1'b1;
              end
            end
            S_DISPATCH: iack <= 1'b0;
            S_SETPFX: pfx <= opr[5] ? 2'd2 : 2'd1;
            S_SETED: begin pf_ed <= 1'b1; pfx <= 2'd0; end
            S_SETCB: pf_cb <= 1'b1;
            S_EXX: bkx <= ~bkx;
            S_EXAF: begin bka <= ~bka; f <= f2; f2 <= f; end
            S_DI: begin iff1 <= 1'b0; iff2 <= 1'b0; end
            S_EI: begin iff1 <= 1'b1; iff2 <= 1'b1; end
            S_SETIM: im <= (y3[1:0] == 2'd2) ? 2'd1 : (y3[1:0] == 2'd3) ? 2'd2 : 2'd0;
            S_HALT: halted <= 1'b1;
            S_RETIFF: iff1 <= iff2;
            S_SETOPR: opr <= dbi;
            default: ;
          endcase
        end
      endcase
    end
  end

  // ---------------- sinais de depuracao (usados pelo testbench; sem custo na sintese) ----------------
  wire [7:0] dbg_a  = rfa[{1'b0, bka, 3'd7}];
  wire [7:0] dbg_a2 = rfa[{1'b0, ~bka, 3'd7}];
  wire [15:0] dbg_bc  = {rfa[{1'b0, bkx, 3'd0}], rfa[{1'b0, bkx, 3'd1}]};
  wire [15:0] dbg_de  = {rfa[{1'b0, bkx, 3'd2}], rfa[{1'b0, bkx, 3'd3}]};
  wire [15:0] dbg_hl  = {rfa[{1'b0, bkx, 3'd4}], rfa[{1'b0, bkx, 3'd5}]};
  wire [15:0] dbg_bc2 = {rfa[{1'b0, ~bkx, 3'd0}], rfa[{1'b0, ~bkx, 3'd1}]};
  wire [15:0] dbg_de2 = {rfa[{1'b0, ~bkx, 3'd2}], rfa[{1'b0, ~bkx, 3'd3}]};
  wire [15:0] dbg_hl2 = {rfa[{1'b0, ~bkx, 3'd4}], rfa[{1'b0, ~bkx, 3'd5}]};
  wire [15:0] dbg_ix  = {rfa[5'd16], rfa[5'd17]};
  wire [15:0] dbg_iy  = {rfa[5'd18], rfa[5'd19]};
  wire [15:0] dbg_sp  = {rfa[5'd20], rfa[5'd21]};
  wire [15:0] dbg_pc  = {rfa[5'd22], rfa[5'd23]};
  wire [15:0] dbg_wz  = {wh, wl};
endmodule
