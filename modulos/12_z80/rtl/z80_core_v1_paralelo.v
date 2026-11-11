// z80_core.v - Z80 classico completo (documentado + nao documentado), ciclo-exato por M-ciclo/T-state.
// Todo T-state = um pulso de "ce". Barramento Z80 (sinais ativos em 1, o top inverte).
// Estrutura: motor de ciclos de barramento (M1/MR/MW/IOR/IOW/INT) + logica combinacional "proximo ciclo" executada no fim de cada ciclo.
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
             S_BIOW=6'd36, S_RETCC=6'd37, S_IV0=6'd38, S_IV1=6'd39;

  // ---------------- estado arquitetural ----------------
  reg [7:0]  a, f, a2, f2, ri, rr;
  reg [15:0] bc, de, hl, bc2, de2, hl2, ix, iy, sp, pc, wz;
  reg        iff1, iff2, halted, ei_dly, nmi_pend, nmi_prev, iack, pj0, pj1;
  reg [1:0]  im, pfx;
  reg        pf_ed, pf_cb;
  reg [7:0]  opr, dbi, lo8, tmp8;
  reg [5:0]  st;
  reg [15:0] ea, tmp16, tgt;
  // ---------------- motor de ciclos ----------------
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

  // sinais de barramento
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

  // {res, flags}
  function [15:0] f_alu; input [2:0] op; input [7:0] a_; input [7:0] v; input cf;
    reg [8:0] s; reg ci; reg sub; reg [7:0] r; reg [7:0] fl;
    begin
      sub = (op==3'd2) || (op==3'd3) || (op==3'd7);
      ci  = (op==3'd1 || op==3'd3) ? cf : 1'b0;
      if (op==3'd0 || op==3'd1 || op==3'd2 || op==3'd3 || op==3'd7) begin
        if (!sub) s = {1'b0,a_} + {1'b0,v} + {8'd0,ci};
        else      s = {1'b0,a_} - {1'b0,v} - {8'd0,ci};
        r = s[7:0];
        fl[7] = r[7]; fl[6] = (r==8'd0);
        fl[5] = (op==3'd7) ? v[5] : r[5];
        fl[3] = (op==3'd7) ? v[3] : r[3];
        fl[4] = a_[4] ^ v[4] ^ r[4];
        fl[2] = sub ? ((a_[7]^v[7]) & (a_[7]^r[7])) : (~(a_[7]^v[7]) & (a_[7]^r[7]));
        fl[1] = sub; fl[0] = s[8];
      end else begin
        if (op==3'd4) r = a_ & v; else if (op==3'd5) r = a_ ^ v; else r = a_ | v;
        fl = szp(r); if (op==3'd4) fl[4] = 1'b1;
      end
      f_alu = {r, fl};
    end
  endfunction

  // 16 bits: {res[15:0], flags}. kind: 0 add, 1 adc, 2 sbc
  function [23:0] f_a16; input [1:0] kind; input [15:0] x; input [15:0] y; input [7:0] fo;
    reg [16:0] s; reg [15:0] r; reg [7:0] fl; reg c;
    begin
      c = (kind==2'd0) ? 1'b0 : fo[0];
      if (kind==2'd2) s = {1'b0,x} - {1'b0,y} - {16'd0,c}; else s = {1'b0,x} + {1'b0,y} + {16'd0,c};
      r = s[15:0];
      if (kind==2'd0) fl = {fo[7], fo[6], r[13], (x[12]^y[12]^r[12]), r[11], fo[2], 1'b0, s[16]};
      else if (kind==2'd1) fl = {r[15], (r==16'd0), r[13], (x[12]^y[12]^r[12]), r[11], (~(x[15]^y[15]) & (x[15]^r[15])), 1'b0, s[16]};
      else fl = {r[15], (r==16'd0), r[13], (x[12]^y[12]^r[12]), r[11], ((x[15]^y[15]) & (x[15]^r[15])), 1'b1, s[16]};
      // reordenar: fl acima esta na ordem {S,Z,Y,H,X,P,N,C}
      f_a16 = {r, fl};
    end
  endfunction

  // rotacoes CB: op 0 RLC,1 RRC,2 RL,3 RR,4 SLA,5 SRA,6 SLL,7 SRL -> {res, flags}
  function [15:0] f_rot; input [2:0] op; input [7:0] v; input cf;
    reg [7:0] r; reg c;
    begin
      case (op)
        3'd0: begin c = v[7]; r = {v[6:0], v[7]}; end
        3'd1: begin c = v[0]; r = {v[0], v[7:1]}; end
        3'd2: begin c = v[7]; r = {v[6:0], cf}; end
        3'd3: begin c = v[0]; r = {cf, v[7:1]}; end
        3'd4: begin c = v[7]; r = {v[6:0], 1'b0}; end
        3'd5: begin c = v[0]; r = {v[7], v[7:1]}; end
        3'd6: begin c = v[7]; r = {v[6:0], 1'b1}; end
        default: begin c = v[0]; r = {1'b0, v[7:1]}; end
      endcase
      f_rot = {r, szp(r) | {7'd0, c}};
    end
  endfunction

  function [15:0] f_daa; input [7:0] a_; input [7:0] fo;
    reg [7:0] tt; reg c; reg [7:0] r; reg h; reg [7:0] fl;
    begin
      tt = 8'd0; c = fo[0];
      if (fo[4] || a_[3:0] > 4'd9) tt = tt | 8'h06;
      if (c || a_ > 8'h99) begin tt = tt | 8'h60; c = 1'b1; end
      r = fo[1] ? (a_ - tt) : (a_ + tt);
      if (fo[1]) h = fo[4] && (a_[3:0] < 4'd6); else h = (a_[3:0] > 4'd9);
      fl = szp(r); fl[0] = c; fl[1] = fo[1]; fl[4] = h;
      f_daa = {r, fl};
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

  // ---------------- logica "proximo ciclo" (combinacional) ----------------
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
  // porta de escrita 8 bits / 16 bits
  reg        w8_en, w8_und; reg [2:0] w8_sel; reg [7:0] w8_val;
  reg        w16_en, w16_af; reg [1:0] w16_sel; reg [15:0] w16_val;

  wire [1:0] x = opr[7:6];
  wire [2:0] y = opr[5:3];
  wire [2:0] z = opr[2:0];
  wire [1:0] p = opr[5:4];
  wire       q = opr[3];
  wire [15:0] hlx = (pfx==2'd1) ? ix : (pfx==2'd2) ? iy : hl;
  wire [15:0] pc1 = pc + 16'd1;
  wire [15:0] pcm = iack ? pc : pc1;           // M1 de reconhecimento nao incrementa PC
  reg  [15:0] rp16;                              // rp[p] (BC,DE,HLx,SP)
  always @* begin case (p) 2'd0: rp16 = bc; 2'd1: rp16 = de; 2'd2: rp16 = hlx; default: rp16 = sp; endcase end
  reg  [15:0] rp2;                               // BC,DE,HLx,AF
  always @* begin case (p) 2'd0: rp2 = bc; 2'd1: rp2 = de; 2'd2: rp2 = hlx; default: rp2 = {a,f}; endcase end
  wire [7:0] r_z_nu = g8(z, bc, de, hl, ix, iy, a, pfx, 1'b0);
  wire [7:0] r_z_u  = g8(z, bc, de, hl, ix, iy, a, pfx, 1'b1);
  wire [7:0] r_y_u  = g8(y, bc, de, hl, ix, iy, a, pfx, 1'b1);
  wire [7:0] r_y_nu = g8(y, bc, de, hl, ix, iy, a, pfx, 1'b0);
  wire       msxn = msx_w;

  wire is_memop_np = !pf_ed && !pf_cb &&
        ( (x==2'd1 && opr!=8'h76 && (y==3'd6 || z==3'd6)) || (x==2'd2 && z==3'd6) ||
          (x==2'd0 && y==3'd6 && (z==3'd4 || z==3'd5)) );

  // variaveis temporarias
  reg [2:0] eff;       // codigos: 0 normal ; 1 = S_OP
  reg [5:0] est;
  reg [15:0] t16, t16b; reg [23:0] t24; reg [15:0] t_alu; reg [7:0] t8, t8b, t8c; reg tb;
  reg [15:0] nn;
  reg        taken;
  reg        isop;

  always @* begin
    // defaults
    n_a=a; n_f=f; n_ri=ri; n_rr=rr; n_bc=bc; n_de=de; n_hl=hl; n_sp=sp; n_ix=ix; n_iy=iy; n_pc=pc; n_wz=wz; n_ea=ea;
    n_tmp16=tmp16; n_tgt=tgt; n_iff1=iff1; n_iff2=iff2; n_halted=halted; n_ei_dly=ei_dly; n_iack=iack; n_pj0=pj0; n_pj1=pj1;
    n_nmi_clr=1'b0; n_pf_ed=pf_ed; n_pf_cb=pf_cb; n_im=im; n_pfx=pfx; n_opr=opr; n_lo8=lo8; n_tmp8=tmp8; n_st=st;
    n_ctyp=ctyp; n_ilen=ilen; n_cext=2'd0; n_cack=1'b0; n_done=1'b0; n_caddr=caddr; n_cdata=cdata;
    do_fin=1'b0; do_m1=1'b0; do_exaf=1'b0; do_exx=1'b0; do_exdh=1'b0;
    w8_en=1'b0; w8_und=1'b0; w8_sel=3'd0; w8_val=8'd0; w16_en=1'b0; w16_af=1'b0; w16_sel=2'd0; w16_val=16'd0;
    est=st; t16=16'd0; t16b=16'd0; t24=24'd0; t_alu=16'd0; t8=8'd0; t8b=8'd0; t8c=8'd0; tb=1'b0; nn=16'd0; taken=1'b0; isop=1'b0;
    // R: incrementa a cada M1
    if (ctyp==CT_M1) n_rr = {rr[7], rr[6:0] + 7'd1};

    if (ctyp==CT_M1 && st==S_DISP) est = S_DISP;
    // virtual S_OP: acesso ao operando de memoria
    if (st==S_EA) isop = 1'b1;
    if (st==S_DISP && ctyp==CT_M1 && is_memop_np && pfx==2'd0 && !halted && !iack) begin isop = 1'b1; n_ea = hl; end

    if (isop) begin
      // x==0,z==4/5 (INC/DEC) ; x==1,y==6 (store) ; x==1,z==6 (load) ; x==2 (alu)
      if (st==S_DISP) n_pc = pcm;
      if (x==2'd1 && y==3'd6) begin
        n_ctyp=CT_MW; n_caddr=(st==S_EA)?ea:hl; n_cdata=r_z_nu; n_st=S_WR1;
      end else begin
        n_ctyp=CT_MR; n_caddr=(st==S_EA)?ea:hl; n_st=S_RD1;
      end
    end else begin
    case (st)
    // ------------------------------------------------------------------ despacho apos M1
    S_DISP: begin
      n_pc = pcm;
      if (halted && !iack) begin n_pc = pc; do_fin=1'b1; end
      else if (iack && im==2'd2) begin
        // IM2: INT1 e empilha PC; vetor = {I, dado}
        n_tmp16=pc; n_pj0=1'b0; n_pj1=1'b1; n_tgt={ri, opr}; n_ctyp=CT_INT; n_ilen=5'd1; n_st=S_PSH0;
      end
      else if (!pf_ed && !pf_cb && (opr==8'hDD || opr==8'hFD)) begin
        n_pfx = (opr==8'hDD) ? 2'd1 : 2'd2; do_m1=1'b1;
      end
      else if (!pf_ed && !pf_cb && opr==8'hED) begin n_pf_ed=1'b1; n_pfx=2'd0; do_m1=1'b1; end
      else if (!pf_ed && !pf_cb && opr==8'hCB) begin
        n_pf_cb=1'b1;
        if (pfx!=2'd0) begin n_ctyp=CT_MR; n_caddr=pc1; n_st=S_DC1; end   // DD CB d op
        else do_m1=1'b1;
      end
      else if (pf_cb) begin
        // CB sem prefixo de indice
        if (z==3'd6) begin n_ea=hl; n_ctyp=CT_MR; n_caddr=hl; n_st=S_RD1; end
        else begin
          t8 = r_z_nu;
          if (x==2'd0) begin t_alu=f_rot(y, t8, f[0]); w8_en=1'b1; w8_sel=z; w8_val=t_alu[15:8]; n_f=t_alu[7:0]; end
          else if (x==2'd1) begin
            n_f = {(y==3'd7 && t8[7]), ~t8[y], t8[5], 1'b1, t8[3], ~t8[y], 1'b0, f[0]};
          end
          else if (x==2'd2) begin w8_en=1'b1; w8_sel=z; w8_val=t8 & ~(8'd1<<y); end
          else begin w8_en=1'b1; w8_sel=z; w8_val=t8 | (8'd1<<y); end
          do_fin=1'b1;
        end
      end
      else if (pf_ed) begin
        // ------------------------------- ED
        if (x==2'd1) begin
          case (z)
            3'd0: begin n_ctyp=CT_IOR; n_caddr=bc; n_st=S_IO; end
            3'd1: begin n_ctyp=CT_IOW; n_caddr=bc; n_cdata=(y==3'd6)?8'd0:g8(y,bc,de,hl,ix,iy,a,2'd0,1'b0); n_st=S_IO; n_wz=bc+16'd1; end
            3'd2: begin
              t24 = q ? f_a16(2'd1, hl, rp16, f) : f_a16(2'd2, hl, rp16, f);
              w16_en=1'b1; w16_sel=2'd2; w16_val=t24[23:8]; n_f=t24[7:0]; n_wz=hl+16'd1;
              n_ctyp=CT_INT; n_ilen=5'd7; n_st=S_FINI;
            end
            3'd3: begin n_ctyp=CT_MR; n_caddr=pcm; n_st=S_NL; end
            3'd4: begin t_alu=f_alu(3'd2, 8'd0, a, 1'b0); n_a=t_alu[15:8]; n_f=t_alu[7:0]; do_fin=1'b1; end
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
        else do_fin=1'b1;   // NOP*
      end
      else begin
        // ------------------------------- sem prefixo ED/CB (com possivel DD/FD)
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
              else begin
                t24 = f_a16(2'd0, hlx, rp16, f);
                w16_en=1'b1; w16_sel=2'd2; w16_val=t24[23:8]; n_f=t24[7:0]; n_wz=hlx+16'd1;
                n_ctyp=CT_INT; n_ilen=5'd7; n_st=S_FINI;
              end
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
              w16_en=1'b1; w16_sel=p; w16_val = q ? rp16 - 16'd1 : rp16 + 16'd1;
              n_ctyp=CT_INT; n_ilen=5'd2; n_st=S_FINI;
            end
            3'd4, 3'd5: begin
              if (y!=3'd6) begin
                t8 = r_y_u;
                if (z==3'd4) begin t8b = t8 + 8'd1; n_f = {t8b[7], (t8b==8'd0), t8b[5], (t8[3:0]==4'hF), t8b[3], (t8==8'h7F), 1'b0, f[0]}; end
                else         begin t8b = t8 - 8'd1; n_f = {t8b[7], (t8b==8'd0), t8b[5], (t8[3:0]==4'h0), t8b[3], (t8==8'h80), 1'b1, f[0]}; end
                w8_en=1'b1; w8_und=1'b1; w8_sel=y; w8_val=t8b; do_fin=1'b1;
              end else begin n_ctyp=CT_MR; n_caddr=pcm; n_st=S_D; end   // (IX+d) (pfx != 0 aqui)
            end
            3'd6: begin
              n_ctyp=CT_MR; n_caddr=pcm;
              if (y==3'd6 && pfx!=2'd0) n_st=S_D; else begin n_st=S_IMM8; if (y==3'd6) n_ea=hl; end
            end
            default: begin
              case (y)
                3'd0: begin n_a={a[6:0],a[7]}; n_f={f[7:6], n_a[5], 1'b0, n_a[3], f[2], 1'b0, a[7]}; do_fin=1'b1; end
                3'd1: begin n_a={a[0],a[7:1]}; n_f={f[7:6], n_a[5], 1'b0, n_a[3], f[2], 1'b0, a[0]}; do_fin=1'b1; end
                3'd2: begin n_a={a[6:0],f[0]}; n_f={f[7:6], n_a[5], 1'b0, n_a[3], f[2], 1'b0, a[7]}; do_fin=1'b1; end
                3'd3: begin n_a={f[0],a[7:1]}; n_f={f[7:6], n_a[5], 1'b0, n_a[3], f[2], 1'b0, a[0]}; do_fin=1'b1; end
                3'd4: begin t_alu=f_daa(a, f); n_a=t_alu[15:8]; n_f=t_alu[7:0]; do_fin=1'b1; end
                3'd5: begin n_a=~a; n_f={f[7:6], n_a[5], 1'b1, n_a[3], f[2], 1'b1, f[0]}; do_fin=1'b1; end
                3'd6: begin n_f={f[7:6], a[5], 1'b0, a[3], f[2], 1'b0, 1'b1}; do_fin=1'b1; end
                default: begin n_f={f[7:6], a[5], f[0], a[3], f[2], 1'b0, ~f[0]}; do_fin=1'b1; end
              endcase
            end
          endcase
        end
        2'd1: begin
          if (opr==8'h76) begin n_halted=1'b1; do_fin=1'b1; end
          else if (y==3'd6 || z==3'd6) begin n_ctyp=CT_MR; n_caddr=pcm; n_st=S_D; end  // so com pfx
          else begin w8_en=1'b1; w8_und=1'b1; w8_sel=y; w8_val=r_z_u; do_fin=1'b1; end
        end
        2'd2: begin
          if (z==3'd6) begin n_ctyp=CT_MR; n_caddr=pcm; n_st=S_D; end                 // so com pfx
          else begin
            t_alu=f_alu(y, a, r_z_u, f[0]); if (y!=3'd7) n_a=t_alu[15:8]; n_f=t_alu[7:0]; do_fin=1'b1;
          end
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
                default: do_fin=1'b1;   // 3'd1 = CB (tratado acima)
              endcase
            end
            3'd5: begin
              if (!q) begin tb=1'b1; end   // PUSH
              else if (p==2'd0) begin n_ctyp=CT_MR; n_caddr=pcm; n_st=S_NL; end  // CALL nn
              else do_fin=1'b1;
            end
            3'd6: begin n_ctyp=CT_MR; n_caddr=pcm; n_st=S_IMM8; end
            default: begin  // RST
              n_tmp16=pc1; n_tgt={10'd0, y, 3'd0}; n_pj0=1'b1; n_pj1=1'b0; n_ctyp=CT_INT; n_ilen=5'd1; n_st=S_PSH0;
              if (iack) n_tmp16=pc;
            end
          endcase
          if (z==3'd5 && !q) begin  // PUSH rr
            n_tmp16=rp2; n_pj0=1'b0; n_pj1=1'b0; n_ctyp=CT_INT; n_ilen=5'd1; n_st=S_PSH0;
          end
        end
        endcase
      end
    end

    // ------------------------------------------------------------------ imediato 8 bits
    S_IMM8: begin
      n_pc = pc1;
      if (x==2'd0) begin   // x==0,z==6
        if (y!=3'd6) begin w8_en=1'b1; w8_und=1'b1; w8_sel=y; w8_val=dbi; do_fin=1'b1; end
        else begin n_ctyp=CT_MW; n_caddr=ea; n_cdata=dbi; n_st=S_WR1; end
      end else if (z==3'd6) begin
        t_alu=f_alu(y, a, dbi, f[0]); if (y!=3'd7) n_a=t_alu[15:8]; n_f=t_alu[7:0]; do_fin=1'b1;
      end else if (y==3'd2) begin   // OUT (n),A
        n_ctyp=CT_IOW; n_caddr={a, dbi}; n_cdata=a; n_st=S_IO; n_wz={a, dbi+8'd1};
      end else begin               // IN A,(n)
        n_ctyp=CT_IOR; n_caddr={a, dbi}; n_st=S_IO; n_wz={a, dbi} + 16'd1;
      end
    end
    S_NL: begin n_pc=pc1; n_lo8=dbi; n_ctyp=CT_MR; n_caddr=pc1; n_st=S_NH; end
    S_NH: begin
      n_pc=pc1; nn={dbi, lo8}; n_tmp16=nn;
      if (pf_ed) begin
        if (!q) begin n_ctyp=CT_MW; n_caddr=nn; n_cdata=rp16[7:0]; n_st=S_NW0; end
        else begin n_ctyp=CT_MR; n_caddr=nn; n_st=S_NR0; end
        n_wz = nn + 16'd1;
      end else if (x==2'd0) begin
        if (z==3'd1) begin w16_en=1'b1; w16_sel=p; w16_val=nn; do_fin=1'b1; end
        else case (y)
          3'd4: begin n_ctyp=CT_MW; n_caddr=nn; n_cdata=hlx[7:0]; n_st=S_NW0; n_wz=nn+16'd1; end
          3'd5: begin n_ctyp=CT_MR; n_caddr=nn; n_st=S_NR0; n_wz=nn+16'd1; end
          3'd6: begin n_ctyp=CT_MW; n_caddr=nn; n_cdata=a; n_st=S_WR1; n_wz={a, nn[7:0]+8'd1}; end
          default: begin n_ctyp=CT_MR; n_caddr=nn; n_st=S_RD1; n_wz=nn+16'd1; end
        endcase
      end else begin
        n_wz = nn;
        if (z==3'd2) begin if (ccond(y, f)) n_pc=nn; do_fin=1'b1; end              // JP cc
        else if (z==3'd3) begin n_pc=nn; do_fin=1'b1; end                            // JP nn
        else begin                                                                    // CALL cc / CALL
          if (z==3'd5 || ccond(y, f)) begin n_tmp16=pc1; n_tgt=nn; n_pj0=1'b1; n_pj1=1'b0; n_ctyp=CT_INT; n_ilen=5'd1; n_st=S_PSH0; end
          else do_fin=1'b1;
        end
      end
    end
    S_NW0: begin
      n_ctyp=CT_MW; n_caddr=tmp16+16'd1; n_st=S_WR1;
      if (pf_ed) n_cdata=rp16[15:8]; else n_cdata=hlx[15:8];
    end
    S_NR0: begin n_lo8=dbi; n_ctyp=CT_MR; n_caddr=tmp16+16'd1; n_st=S_NR1; end
    S_NR1: begin
      w16_en=1'b1; w16_val={dbi, lo8};
      if (pf_ed) w16_sel=p; else w16_sel=2'd2;
      do_fin=1'b1;
    end
    // ------------------------------------------------------------------ indexado
    S_D: begin
      n_pc = pc1;
      t16 = ((pfx==2'd1) ? ix : iy) + {{8{dbi[7]}}, dbi};
      n_ea = t16; n_wz = t16;
      if (x==2'd0 && z==3'd6 && y==3'd6) begin n_ctyp=CT_MR; n_caddr=pc1; n_cext=2'd2; n_st=S_IMM8; end
      else begin n_ctyp=CT_INT; n_ilen=5'd5; n_st=S_EA; end
    end
    // ------------------------------------------------------------------ leitura de operando
    S_RD1: begin
      if (pf_ed) begin
        if (x==2'd1) begin   // RRD / RLD
          if (y==3'd4) begin n_a={a[7:4], dbi[3:0]}; n_tmp8={a[3:0], dbi[7:4]}; end
          else         begin n_a={a[7:4], dbi[7:4]}; n_tmp8={dbi[3:0], a[3:0]}; end
          t8 = n_a; n_f = {t8[7], (t8==8'd0), t8[5], 1'b0, t8[3], par8(t8), 1'b0, f[0]};
          n_wz = hl + 16'd1; n_ctyp=CT_INT; n_ilen=5'd4; n_st=S_INC1;
        end else if (z==3'd0) begin    // LDI/LDD..
          n_tmp8=dbi; n_ctyp=CT_MW; n_caddr=de; n_cdata=dbi; n_st=S_BLD;
        end else if (z==3'd1) begin    // CPI/CPD..
          t8 = a - dbi; t8b = {7'd0,1'b0} ; tb = a[4]^dbi[4]^t8[4];
          n_hl = y[0] ? hl - 16'd1 : hl + 16'd1; n_bc = bc - 16'd1;
          t8c = t8 - {7'd0, tb};
          n_f = {t8[7], (t8==8'd0), t8c[1], tb, t8c[3], ((bc-16'd1)!=16'd0), 1'b1, f[0]};
          n_wz = y[0] ? wz - 16'd1 : wz + 16'd1; n_tmp8=t8;
          n_ctyp=CT_INT; n_ilen=5'd5; n_st=S_BCPI;
        end else begin                 // OUTI/OUTD: z==3
          t8 = bc[15:8] - 8'd1;
          n_bc = {t8, bc[7:0]}; n_tmp8 = dbi;
          n_ctyp=CT_IOW; n_caddr={t8, bc[7:0]}; n_cdata=dbi; n_st=S_BIOW;
        end
      end else if (pf_cb) begin
        // (HL) / (IX+d): rot/bit/res/set
        t8 = dbi;
        if (x==2'd0) begin t_alu=f_rot(y, t8, f[0]); n_tmp8=t_alu[15:8]; n_f=t_alu[7:0]; end
        else if (x==2'd1) begin
          n_f = {(y==3'd7 && t8[7]), ~t8[y], (pfx!=2'd0)?ea[13]:wz[13], 1'b1, (pfx!=2'd0)?ea[11]:wz[11], ~t8[y], 1'b0, f[0]};
        end
        else if (x==2'd2) n_tmp8 = t8 & ~(8'd1<<y);
        else n_tmp8 = t8 | (8'd1<<y);
        n_ctyp=CT_INT; n_ilen=5'd1; n_st=S_INC1;
      end else if (x==2'd0 && z==3'd2) begin   // LD A,(BC/DE/nn)
        n_a=dbi;
        if (y==3'd1) n_wz=bc+16'd1; else if (y==3'd3) n_wz=de+16'd1;
        do_fin=1'b1;
      end else if (x==2'd0) begin              // INC/DEC (HL)/(IX+d)
        t8=dbi;
        if (z==3'd4) begin t8b=t8+8'd1; n_f={t8b[7], (t8b==8'd0), t8b[5], (t8[3:0]==4'hF), t8b[3], (t8==8'h7F), 1'b0, f[0]}; end
        else         begin t8b=t8-8'd1; n_f={t8b[7], (t8b==8'd0), t8b[5], (t8[3:0]==4'h0), t8b[3], (t8==8'h80), 1'b1, f[0]}; end
        n_tmp8=t8b; n_ctyp=CT_INT; n_ilen=5'd1; n_st=S_INC1;
      end else if (x==2'd1) begin              // LD r,(HL)
        w8_en=1'b1; w8_und=1'b0; w8_sel=y; w8_val=dbi; do_fin=1'b1;
      end else begin                           // ALU A,(HL)
        t_alu=f_alu(y, a, dbi, f[0]); if (y!=3'd7) n_a=t_alu[15:8]; n_f=t_alu[7:0]; do_fin=1'b1;
      end
    end
    S_INC1: begin
      if (pf_cb && x==2'd1) do_fin=1'b1;
      else begin n_ctyp=CT_MW; n_caddr=(pf_ed)?hl:ea; n_cdata=tmp8; n_st=S_WR1; end
    end
    S_WR1: do_fin=1'b1;
    S_FINI: do_fin=1'b1;
    // ------------------------------------------------------------------ DDCB
    S_DC1: begin
      n_pc=pc1; t16=((pfx==2'd1)?ix:iy) + {{8{dbi[7]}}, dbi}; n_ea=t16; n_wz=t16;
      n_ctyp=CT_MR; n_caddr=pc1; n_cext=2'd2; n_st=S_DC2;
    end
    S_DC2: begin
      n_pc=pc1; n_opr=dbi; n_ctyp=CT_MR; n_caddr=ea; n_st=S_DC3;
    end
    S_DC3: begin
      t8=dbi;
      if (x==2'd0) begin t_alu=f_rot(y, t8, f[0]); n_tmp8=t_alu[15:8]; n_f=t_alu[7:0]; end
      else if (x==2'd1) n_f = {(y==3'd7 && t8[7]), ~t8[y], ea[13], 1'b1, ea[11], ~t8[y], 1'b0, f[0]};
      else if (x==2'd2) n_tmp8 = t8 & ~(8'd1<<y);
      else n_tmp8 = t8 | (8'd1<<y);
      if (x!=2'd1 && z!=3'd6) begin
        w8_en=1'b1; w8_und=1'b0; w8_sel=z;
        if (x==2'd0) w8_val=t_alu[15:8]; else if (x==2'd2) w8_val=t8 & ~(8'd1<<y); else w8_val=t8 | (8'd1<<y);
      end
      n_ctyp=CT_INT; n_ilen=5'd1; n_st=S_INC1;
    end
    // ------------------------------------------------------------------ pilha / saltos
    S_PL: begin n_lo8=dbi; n_ctyp=CT_MR; n_caddr=sp+16'd1; n_st=S_PH; n_sp=sp+16'd1; end
    S_PH: begin
      n_sp=sp+16'd1; nn={dbi, lo8};
      if (pf_ed) begin n_pc=nn; n_wz=nn; n_iff1=iff2; do_fin=1'b1; end         // RETN/RETI
      else if (x==2'd3 && z==3'd1 && q==1'b0) begin   // POP
        w16_en=1'b1; w16_sel=p; w16_val=nn; w16_af=(p==2'd3); do_fin=1'b1;
        n_sp=sp+16'd1;
      end else begin n_pc=nn; n_wz=nn; do_fin=1'b1; end                          // RET / RET cc
    end
    S_RETCC: begin
      if (z==3'd0 && ccond(y, f)) begin n_ctyp=CT_MR; n_caddr=sp; n_st=S_PL; end else do_fin=1'b1;
    end
    S_PSH0: begin
      n_sp=sp-16'd1; n_ctyp=CT_MW; n_caddr=sp-16'd1; n_cdata=tmp16[15:8]; n_st=S_PSHH;
    end
    S_PSHH: begin
      n_sp=sp-16'd1; n_ctyp=CT_MW; n_caddr=sp-16'd1; n_cdata=tmp16[7:0]; n_st=S_PSHL;
    end
    S_PSHL: begin
      if (pj1) begin n_ctyp=CT_MR; n_caddr=tgt; n_st=S_IV0; end
      else begin if (pj0) begin n_pc=tgt; n_wz=tgt; end do_fin=1'b1; end
    end
    S_IV0: begin n_lo8=dbi; n_ctyp=CT_MR; n_caddr=tgt+16'd1; n_st=S_IV1; end
    S_IV1: begin n_pc={dbi, lo8}; n_wz={dbi, lo8}; do_fin=1'b1; end
    S_JR: begin
      n_pc=pc1;
      if (y==3'd2) taken = (bc[15:8]!=8'd0); else if (y==3'd3) taken=1'b1; else taken=ccond({1'b0,y[1:0]}, f);
      if (taken) begin n_pc=pc1 + {{8{dbi[7]}}, dbi}; n_wz=n_pc; n_ctyp=CT_INT; n_ilen=5'd5; n_st=S_FINI; end
      else do_fin=1'b1;
    end
    S_DJNZ: begin n_ctyp=CT_MR; n_caddr=pc; n_st=S_JR; end
    S_IO: begin
      if (pf_ed) begin
        if (z==3'd0) begin
          n_f = {dbi[7], (dbi==8'd0), dbi[5], 1'b0, dbi[3], par8(dbi), 1'b0, f[0]};
          if (y!=3'd6) begin w8_en=1'b1; w8_und=1'b0; w8_sel=y; w8_val=dbi; end
          n_wz=bc+16'd1;
        end else if (z==3'd1) n_wz=bc+16'd1;
        else begin
          // INI/IND: dado lido -> escreve em (HL)
          n_tmp8=dbi; n_ctyp=CT_MW; n_caddr=hl; n_cdata=dbi; n_st=S_BIOW;
        end
        if (!(x==2'd2)) do_fin=1'b1;
      end else begin
        if (y==3'd3) n_a=dbi;   // IN A,(n)
        do_fin=1'b1;
      end
    end
    S_B1: begin n_ctyp=CT_IOR; n_caddr=bc; n_st=S_IO; end              // INI/IND: porta (BC) antes de decrementar B
    S_B2: begin n_ctyp=CT_MR; n_caddr=hl; n_st=S_RD1; end
    S_BIOW: begin
      // fim do INI/IND (apos MW) ou OUTI/OUTD (apos IOW): atualiza HL, B, flags
      t8 = (z==3'd2) ? bc[15:8] - 8'd1 : bc[15:8];          // B novo (OUTI: ja decrementado em n_bc)
      t16 = y[0] ? hl - 16'd1 : hl + 16'd1;
      n_hl = t16;
      if (z==3'd2) begin n_bc={t8, bc[7:0]}; t8c = y[0] ? bc[7:0] - 8'd1 : bc[7:0] + 8'd1; n_wz = y[0] ? bc - 16'd1 : bc + 16'd1; end
      else begin t8c = t16[7:0]; n_wz = y[0] ? bc - 16'd1 : bc + 16'd1; end
      t_alu = {7'd0, 1'b0, tmp8} + {8'd0, t8c};                // k = v + (...)
      n_f = {t8[7], (t8==8'd0), t8[5], t_alu[8], t8[3], par8({5'd0, t_alu[2:0]} ^ t8), tmp8[7], t_alu[8]};
      if (y[1] && t8!=8'd0) begin n_pc=pc-16'd2; n_ctyp=CT_INT; n_ilen=5'd5; n_st=S_FINI; end
      else do_fin=1'b1;
    end
    // ------------------------------------------------------------------ EX (SP),HL
    S_X0: begin n_lo8=dbi; n_ctyp=CT_MR; n_caddr=sp+16'd1; n_st=S_X1; end
    S_X1: begin n_tmp16={dbi, lo8}; n_ctyp=CT_INT; n_ilen=5'd1; n_st=S_X2; end
    S_X2: begin n_ctyp=CT_MW; n_caddr=sp+16'd1; n_cdata=hlx[15:8]; n_st=S_X3; end
    S_X3: begin n_ctyp=CT_MW; n_caddr=sp; n_cdata=hlx[7:0]; n_st=S_X4; end
    S_X4: begin w16_en=1'b1; w16_sel=2'd2; w16_val=tmp16; n_wz=tmp16; n_ctyp=CT_INT; n_ilen=5'd2; n_st=S_FINI; end
    // ------------------------------------------------------------------ blocos
    S_BLD: begin
      // apos MW (DE): atualiza HL/DE/BC, flags
      n_hl = y[0] ? hl - 16'd1 : hl + 16'd1;
      n_de = y[0] ? de - 16'd1 : de + 16'd1;
      n_bc = bc - 16'd1;
      t8 = tmp8 + a;
      n_f = {f[7:6], t8[1], 1'b0, t8[3], ((bc-16'd1)!=16'd0), 1'b0, f[0]};
      n_ctyp=CT_INT; n_ilen=5'd2; n_st=S_BLD2;
    end
    S_BLD2: begin
      if (y[1] && bc!=16'd0) begin n_pc=pc-16'd2; n_wz=pc-16'd1; n_ctyp=CT_INT; n_ilen=5'd5; n_st=S_FINI; end
      else do_fin=1'b1;
    end
    S_BCPI: begin
      if (y[1] && bc!=16'd0 && tmp8!=8'd0) begin n_pc=pc-16'd2; n_wz=pc-16'd1; n_ctyp=CT_INT; n_ilen=5'd5; n_st=S_FINI; end
      else do_fin=1'b1;
    end
    default: do_fin=1'b1;
    endcase
    end

    // ----- DD/FD + CB: ja tratado (DISP). Escritas e trocas
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
      // ei_dly: EI define 1; qualquer outra instrucao limpa
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
          // fim de ciclo: commit
          t <= 5'd1;
          a<=n_a; f<=n_f; ri<=n_ri; rr<=n_rr; sp<=n_sp; pc<=n_pc; wz<=n_wz; ea<=n_ea; tmp16<=n_tmp16; tgt<=n_tgt;
          iff1<=n_iff1; iff2<=n_iff2; halted<=n_halted; ei_dly<=n_ei_dly; iack<=n_iack; pj0<=n_pj0; pj1<=n_pj1;
          pf_ed<=n_pf_ed; pf_cb<=n_pf_cb; im<=n_im; pfx<=n_pfx; lo8<=n_lo8; tmp8<=n_tmp8; st<=n_st;
          // opr: so muda por n_opr (S_DC2); opr de M1 ja foi amostrado
          if (n_opr != opr) opr <= n_opr;
          // pares (com troca de bancos)
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
