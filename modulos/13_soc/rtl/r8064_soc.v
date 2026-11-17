// r8064_soc.v - integracao: sistema MSX (nucleo+modo+governador+msx_mem+FIFOs) + MMU (TLB I e D) + cache I 4 KB + cache D 8 KB + arbitros + controlador de SDRAM.
// Caminho de instrucoes : core i_req/i_paddr -> MMU-I (v_req) -> cache I -> arbitro I (cache I > caminhador I) -+
//                                                                                                          +-> arbitro topo (D > I) -> sdram_ctrl -> pinos
// Caminho de dados      : core d_req/d_paddr -> MMU-D (v_req) -> cache D -> arbitro D (cache D > caminhador D) -+
// Cada lado tem uma FSM de adaptacao do protocolo ack do nucleo para o protocolo req/ready/rvalid da cache (ver comentarios). Faltas de traducao: sao sinalizadas em
// i_fault/d_fault (+causa); o nucleo as recebe como excecao (CR43 causa, CR44 endereco, CR45 EPC; salta para CR41); controle da MMU nos CR46-49 do nucleo. Com mmu_en=0 o endereco passa direto (32 bits baixos).
// Memoria fisica = 8 MB (indice de palavra de 64 bits de 20 bits = p_addr[22:3]).
// DMA de 4 canais (r8064_dma): registradores CR19..CR30 (MTCR), status/IE nas portas EDh/EEh/EFh, 5o mestre do arbitro da SDRAM; buffer de troca de 16 KB (r8064_xbuf, janela MSX).
// BOOT (BOOT_WORDS > 0): apos a inicializacao da SDRAM o canal 0 do DMA copia BOOT_WORDS palavras do buffer da janela (offset 0; conteudo inicial = INIT_IMG=1: 8 arquivos
//   <INIT_PFX><lane>.hex) para a SDRAM 0; o nucleo fica em reset (boot_busy=1) ate o fim e a janela pertence ao DMA durante a copia. BOOT_WORDS=0: sem boot (nucleo parte direto).
module r8064_soc #(parameter FIFO_BASE = 8'hE8, parameter INIT_CYC = 20000, parameter REF_INT = 400, parameter BOOT_WORDS = 0, parameter INIT_IMG = 0)(
    input  wire        clk, rst, irq,
    // E/S
    input  wire        io_we, io_re, input wire [7:0] io_a, io_wd, output wire [7:0] io_rd, output wire io_oe,
    output wire        io_x_we, io_x_re, output wire [7:0] io_x_a, io_x_wd, input wire [7:0] io_x_rd,
    input  wire [7:0]  port_c,
    input  wire        fm_we, fm_re, input wire [1:0] fm_a, input wire [7:0] fm_wd, output wire [7:0] fm_rd,
    // janela de troca MSX (page 2, 16 KB): acesso do slot ao buffer (endereco A[13:0], sincronizado; s_a estavel >= 1 clock antes de sb_re)
    input  wire        sb_we, sb_re, input wire [13:0] sb_a, input wire [7:0] sb_wd, output wire [7:0] sb_rd,
    output wire        fifo_irq, fifo_rst,
    output wire        native64, clk_sel, is_z80, is_rom, mode_busy,
    output wire [63:0] dbg_pc, output wire [7:0] dbg_f, output wire dbg_sig, output wire gov_cv,
    output wire        fl_busy_i, fl_busy_d,     // TLB flush sweep in progress (informational)
    output wire        mmu_en, mmu_user, output wire i_fault, d_fault, output wire [2:0] i_cause, d_cause,   // MMU state / fault pulses (observation)
    // SDRAM
    output wire        init_done,
    output wire        s_cke, s_cs_n, s_ras_n, s_cas_n, s_we_n, output wire [3:0] s_dqm, output wire [1:0] s_ba, output wire [10:0] s_a,
    output wire [31:0] s_dq_o, output wire s_dq_oe, input wire [31:0] s_dq_i
);
    // ---------------- DMA de 4 canais (r8064_dma): registradores em CR19..CR30, status/IE nas portas EDh/EEh/EFh, 5o mestre da SDRAM ----------------
    wire dma_cr_we; wire [3:0] dma_cr_idx; wire [63:0] dma_cr_wd;
    wire dma_pop, dma_push; wire [7:0] dma_wd; wire dma_a_avail, dma_b_space; wire [7:0] dma_a_q;
    wire dma_irq, dma_inv, dma_io_sel; wire [7:0] dma_io_rd;
    wire fifo_win, xb_re, xb_we; wire [10:0] xb_a; wire [63:0] xb_wd, xb_q;
    wire sx_we, sx_re; wire [7:0] sx_a, sx_wd;
    assign io_x_we = sx_we && !dma_io_sel; assign io_x_re = sx_re && !dma_io_sel; assign io_x_a = sx_a; assign io_x_wd = sx_wd;   // as portas do DMA nao saem do SoC
    wire x_req, x_we, x_acc, x_done; wire [19:0] x_addr; wire [63:0] x_wd, x_rd; wire [7:0] x_be;
    // sequenciador de boot: 0 espera init_done | 1 pulso boot_go | 2 espera 1 clock | 3 espera o canal 0 concluir | 4 pulso boot_clr e libera o nucleo
    reg boot_busy; reg [2:0] bst; wire boot_go = (bst == 3'd1), boot_clr = (bst == 3'd4), boot_done;
    always @(posedge clk) begin
        if (rst) begin boot_busy <= (BOOT_WORDS != 0); bst <= (BOOT_WORDS != 0) ? 3'd0 : 3'd5; end
        else case (bst)
            3'd0: if (init_done) bst <= 3'd1;
            3'd1: bst <= 3'd2;
            3'd2: bst <= 3'd3;
            3'd3: if (boot_done) bst <= 3'd4;
            3'd4: begin boot_busy <= 1'b0; bst <= 3'd5; end
            default: ;
        endcase
    end
    r8064_dma u_dma(.clk(clk), .rst(rst), .cr_we(dma_cr_we), .cr_idx(dma_cr_idx), .cr_wd(dma_cr_wd),
        .io_we(sx_we), .io_re(sx_re), .io_a(sx_a), .io_wd(sx_wd), .io_rd(dma_io_rd), .io_sel(dma_io_sel),
        .m_req(x_req), .m_we(x_we), .m_addr(x_addr), .m_wd(x_wd), .m_be(x_be), .m_acc(x_acc), .m_done(x_done), .m_rd(x_rd),
        .a_avail(dma_a_avail), .a_q(dma_a_q), .b_space(dma_b_space), .d_pop(dma_pop), .d_push(dma_push), .d_wd(dma_wd),
        .b_ok(!fifo_win || boot_busy), .b_re(xb_re), .b_we(xb_we), .b_a(xb_a), .b_wd(xb_wd), .b_q(xb_q),
        .irq(dma_irq), .inv(dma_inv), .boot_go(boot_go), .boot_cnt(BOOT_WORDS[18:0]), .boot_done(boot_done), .boot_clr(boot_clr));
    r8064_xbuf #(.INIT_IMG(INIT_IMG)) u_xbuf(.clk(clk), .win(fifo_win && !boot_busy), .s_we(sb_we), .s_re(sb_re), .s_a(sb_a), .s_wd(sb_wd), .s_rd(sb_rd),
        .d_re(xb_re), .d_we(xb_we), .d_a(xb_a), .d_wd(xb_wd), .d_q(xb_q));
    // ---------------- sistema MSX + nucleo ----------------
    wire [7:0] mmu_asid, fl_asid; wire [19:0] mmu_root; wire fl_all, fl_va_en, fl_asid_en, cache_inv; wire [63:0] fl_va;
    wire c_i_req, c_i_ack, c_d_req, c_d_we, c_d_ack; wire [63:0] c_i_pa, c_i_rd, c_d_pa, c_d_wd, c_d_rd; wire [1:0] c_d_sz; wire [7:0] c_d_be; wire hit_i, hit_d, wr_ok;
    r8064_msx_sys #(.FIFO_BASE(FIFO_BASE)) u_sys(.clk(clk), .rst(rst | boot_busy), .irq(irq & ~dma_irq),
        .i_req(c_i_req), .i_ack(c_i_ack), .i_paddr(c_i_pa), .i_rdata(c_i_rd),
        .d_req(c_d_req), .d_we(c_d_we), .d_paddr(c_d_pa), .d_size(c_d_sz), .d_wdata(c_d_wd), .d_be(c_d_be), .d_ack(c_d_ack), .d_rdata(c_d_rd),
        .i_hit(hit_i), .d_hit(hit_d), .d_wr_ok(wr_ok),
        .i_flt(i_fault), .d_flt(d_fault), .i_cs(i_cause), .d_cs(d_cause), .cr_mmu_en(mmu_en), .cr_mmu_user(mmu_user), .cr_asid(mmu_asid), .cr_root(mmu_root),
        .cr_fl_all(fl_all), .cr_fl_va_en(fl_va_en), .cr_fl_asid_en(fl_asid_en), .cr_fl_va(fl_va), .cr_fl_asid(fl_asid), .cr_cinv(cache_inv),
        .io_we(io_we), .io_re(io_re), .io_a(io_a), .io_wd(io_wd), .io_rd(io_rd), .io_oe(io_oe),
        .io_x_we(sx_we), .io_x_re(sx_re), .io_x_a(sx_a), .io_x_wd(sx_wd), .io_x_rd(dma_io_sel ? dma_io_rd : io_x_rd), .port_c(port_c),
        .dma_cr_we(dma_cr_we), .dma_cr_idx(dma_cr_idx), .dma_cr_wd(dma_cr_wd), .dma_pop(dma_pop), .dma_push(dma_push), .dma_wd(dma_wd),
        .dma_a_avail(dma_a_avail), .dma_a_q(dma_a_q), .dma_b_space(dma_b_space),
        .fm_we(fm_we), .fm_re(fm_re), .fm_a(fm_a), .fm_wd(fm_wd), .fm_rd(fm_rd), .fifo_irq(fifo_irq), .fifo_rst(fifo_rst), .fifo_win(fifo_win),
        .native64(native64), .clk_sel(clk_sel), .is_z80(is_z80), .is_rom(is_rom), .mode_busy(mode_busy),
        .dbg_pc(dbg_pc), .dbg_f(dbg_f), .dbg_sig(dbg_sig), .gov_cv(gov_cv));

    // ---------------- subsistema de memoria ----------------
    r8064_memsys #(.INIT_CYC(INIT_CYC), .REF_INT(REF_INT)) u_mem(.clk(clk), .rst(rst),
        .c_i_req(c_i_req), .c_i_ack(c_i_ack), .c_i_pa(c_i_pa), .c_i_rd(c_i_rd),
        .c_d_req(c_d_req), .c_d_we(c_d_we), .c_d_ack(c_d_ack), .c_d_pa(c_d_pa), .c_d_wd(c_d_wd), .c_d_be(c_d_be), .c_d_rd(c_d_rd),
        .mmu_en(mmu_en), .mmu_user(mmu_user), .mmu_asid(mmu_asid), .mmu_root(mmu_root),
        .fl_all(fl_all), .fl_va_en(fl_va_en), .fl_asid_en(fl_asid_en), .fl_va(fl_va), .fl_asid(fl_asid), .fl_busy_i(fl_busy_i), .fl_busy_d(fl_busy_d),
        .cache_inv(cache_inv | dma_inv),
        .x_req(x_req), .x_we(x_we), .x_addr(x_addr), .x_wd(x_wd), .x_be(x_be), .x_acc(x_acc), .x_done(x_done), .x_rd(x_rd), .i_fault(i_fault), .d_fault(d_fault), .i_cause(i_cause), .d_cause(d_cause),
        .init_done(init_done), .s_cke(s_cke), .s_cs_n(s_cs_n), .s_ras_n(s_ras_n), .s_cas_n(s_cas_n), .s_we_n(s_we_n), .s_dqm(s_dqm), .s_ba(s_ba), .s_a(s_a),
        .s_dq_o(s_dq_o), .s_dq_oe(s_dq_oe), .s_dq_i(s_dq_i));
endmodule
