module pnr_soc_top(input wire clk, input wire din, output wire dout);
    reg [255:0] l = 256'h1; reg [3:0] rc = 0; reg rstw = 1'b1;
    always @(posedge clk) begin if (rc != 15) rc <= rc + 1; rstw <= (rc != 15); l <= {l[254:0], l[255]^l[253]^l[250]^l[245]^din}; end
    wire mmu_en, mmu_user, io_oe, iox_we, iox_re, nat, cs, z8, ro, mb, dbg_sig, gcv, fifo_irq, fifo_rst, fbi, fbd, i_fault, d_fault, init_done;
    wire [7:0] io_rd, iox_a, iox_wd, fm_rd, dbg_f; wire [63:0] dbg_pc; wire [2:0] ic, dc;
    wire s_cke, s_cs_n, s_ras_n, s_cas_n, s_we_n, s_dq_oe; wire [3:0] s_dqm; wire [1:0] s_ba; wire [10:0] s_a; wire [31:0] s_dq_o;
    r8064_soc u(.clk(clk), .rst(rstw), .irq(l[9]),
        .io_we(l[130]), .io_re(l[131]), .io_a(l[139:132]), .io_wd(l[147:140]), .io_rd(io_rd), .io_oe(io_oe), .io_x_we(iox_we), .io_x_re(iox_re), .io_x_a(iox_a), .io_x_wd(iox_wd), .io_x_rd(l[7:0]), .port_c(l[155:148]),
        .fm_we(l[160]), .fm_re(l[161]), .fm_a(l[163:162]), .fm_wd(l[171:164]), .fm_rd(fm_rd), .fifo_irq(fifo_irq), .fifo_rst(fifo_rst),
        .native64(nat), .clk_sel(cs), .is_z80(z8), .is_rom(ro), .mode_busy(mb), .dbg_pc(dbg_pc), .dbg_f(dbg_f), .dbg_sig(dbg_sig), .gov_cv(gcv),
        .mmu_en(mmu_en), .mmu_user(mmu_user), .fl_busy_i(fbi), .fl_busy_d(fbd),
        .i_fault(i_fault), .d_fault(d_fault), .i_cause(ic), .d_cause(dc),
        .init_done(init_done), .s_cke(s_cke), .s_cs_n(s_cs_n), .s_ras_n(s_ras_n), .s_cas_n(s_cas_n), .s_we_n(s_we_n), .s_dqm(s_dqm), .s_ba(s_ba), .s_a(s_a), .s_dq_o(s_dq_o), .s_dq_oe(s_dq_oe), .s_dq_i(l[245:214]));
    reg [6:0] pp; reg p;
    reg [24:0] ca; reg [39:0] cb; reg [63:0] cc; reg [9:0] cd; reg [26:0] ce; reg [15:0] cf;
    always @(posedge clk) begin
        ca <= {mmu_en, mmu_user, io_oe, iox_we, iox_re, nat, cs, z8, ro, mb, dbg_sig, gcv, fifo_irq, fifo_rst, fbi, fbd, i_fault, d_fault, ic, dc, init_done};
        cb <= {io_rd, iox_a, iox_wd, fm_rd, dbg_f};
        cc <= dbg_pc;
        cd <= {s_cke, s_cs_n, s_ras_n, s_cas_n, s_we_n, s_dqm, s_ba, s_dq_oe};
        ce <= {s_a, s_dq_o[31:16]};
        cf <= s_dq_o[15:0];
        pp <= {^ca, ^cb, ^cc[63:32], ^cc[31:0], ^cd, ^ce, ^cf};
        p <= ^pp;
    end
    assign dout = p;
endmodule
