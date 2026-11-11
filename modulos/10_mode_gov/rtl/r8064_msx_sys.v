// r8064_msx_sys.v - sistema MSX do R8064: CPU (nucleo + modo + governador + classificador) + msx_mem (mapper/MegaRAM/A8h) + decodificador de E/S.
//  E/S:  3D,3E,E4,E5 -> registradores de modo   | A8,FC-FF,8E -> msx_mem   | demais portas saem por io_x_* (msx_if, VDP, PSG...).
//  Memoria: i_addr/d_addr de 64 bits; nos modos Z80/R800 usa-se so [15:0], traduzidos pelo msx_mem (2 instancias: busca e dados, mesmos
//  registradores escritos pelo mesmo barramento de E/S). Endereco sem hit (ROM/outros slots) passa sem traducao. Modo nativo: sem traducao (MMU do modulo 07).
//  O NUCLEO ESQUELETO AINDA NAO EXECUTA IN/OUT: io_we/io_re/io_a/io_wd vem de fora (futuro nucleo) ou do testbench.
module r8064_msx_sys #(parameter ROM_FILE = "gov_rom.mem", parameter FIFO_BASE = 8'hE8)(
    input  wire        clk, rst, irq,
    // memoria fisica (para o cache/SDRAM)
    output wire        i_req, input wire i_ack, output wire [63:0] i_paddr, input wire [63:0] i_rdata,
    output wire        d_req, d_we, output wire [63:0] d_paddr, output wire [1:0] d_size, output wire [63:0] d_wdata, output wire [7:0] d_be,
    input  wire        d_ack, input wire [63:0] d_rdata,
    output wire        i_hit, d_hit, d_wr_ok,
    // barramento de E/S
    input  wire        io_we, io_re, input wire [7:0] io_a, io_wd, output wire [7:0] io_rd, output wire io_oe,
    output wire        io_x_we, io_x_re, output wire [7:0] io_x_a, io_x_wd, input wire [7:0] io_x_rd,
    input  wire [7:0]  port_c,
    input  wire        i_flt, d_flt, input wire [2:0] i_cs, d_cs,
    output wire        cr_mmu_en, cr_mmu_user, output wire [7:0] cr_asid, output wire [19:0] cr_root,
    output wire        cr_fl_all, cr_fl_va_en, cr_fl_asid_en, output wire [63:0] cr_fl_va, output wire [7:0] cr_fl_asid, output wire cr_cinv,
    // lado MSX das FIFOs (E/S do slot, ja sincronizado ao clk)
    input  wire        fm_we, fm_re, input wire [1:0] fm_a, input wire [7:0] fm_wd, output wire [7:0] fm_rd,
    output wire        fifo_irq, fifo_rst,
    output wire        native64, clk_sel, is_z80, is_rom, mode_busy,
    output wire [63:0] dbg_pc, output wire [7:0] dbg_f, output wire dbg_sig, output wire gov_cv
);
    wire i_ack_c = i_ack;
    wire [63:0] i_addr, d_addr; wire [7:0] a8, md_rd, mi_rd; wire md_oe, mi_hit_io, md_hit_io;
    // barramento de E/S unico: o nucleo (IN/OUT) tem prioridade sobre as portas externas io_* (usadas por testes / outro mestre)
    wire cio_we, cio_re; wire [7:0] cio_a, cio_wd;
    wire c_act = cio_we | cio_re;
    wire        b_we = io_we | cio_we, b_re = io_re | cio_re;
    wire [7:0]  b_a  = c_act ? cio_a : io_a;
    wire [7:0]  b_wd = cio_we ? cio_wd : io_wd;
    wire mode_port = (b_a == 8'h3D) || (b_a == 8'h3E) || (b_a == 8'hE4) || (b_a == 8'hE5);
    wire mem_port  = (b_a == 8'hA8) || (b_a[7:2] == 6'b111111) || (b_a == 8'h8E);
    wire fifo_hit;
    wire m_we = b_we && !mode_port, m_re = b_re && !mode_port;   // msx_mem ve apenas portas que nao sao de modo
    // classificador / mapa: os registros de regioes ficam com defaults; map_* nao usados aqui (programaveis por firmware futuro)
    wire [2:0] lane_d = d_be[0] ? 3'd0 : d_be[1] ? 3'd1 : d_be[2] ? 3'd2 : d_be[3] ? 3'd3 : d_be[4] ? 3'd4 : d_be[5] ? 3'd5 : d_be[6] ? 3'd6 : 3'd7;
    wire [7:0] lane_wd = d_wdata >> {lane_d, 3'b000};
    r8064_cpu_gov #(.ROM_FILE(ROM_FILE)) u_cpu(.clk(clk), .rst(rst), .irq(irq), .i_req(i_req), .i_ack(i_ack_c), .i_addr(i_addr), .i_rdata(i_rdata),
        .d_req(d_req), .d_we(d_we), .d_addr(d_addr), .d_size(d_size), .d_wdata(d_wdata), .d_be(d_be), .d_ack(d_ack), .d_rdata(d_rdata),
        .i_flt(i_flt), .d_flt(d_flt), .i_cs(i_cs), .d_cs(d_cs), .cr_mmu_en(cr_mmu_en), .cr_mmu_user(cr_mmu_user), .cr_asid(cr_asid), .cr_root(cr_root),
        .cr_fl_all(cr_fl_all), .cr_fl_va_en(cr_fl_va_en), .cr_fl_asid_en(cr_fl_asid_en), .cr_fl_va(cr_fl_va), .cr_fl_asid(cr_fl_asid), .cr_cinv(cr_cinv),
        .io_we(b_we && mode_port), .io_re(b_re && mode_port), .io_a(b_a), .io_wd(b_wd), .io_rd(md_rd), .io_oe(md_oe), .port_c(port_c),
        .cio_we(cio_we), .cio_re(cio_re), .cio_a(cio_a), .cio_wd(cio_wd), .cio_rd(io_rd),
        .a8(a8), .map_we(1'b0), .map_idx(4'd0), .map_val(2'd0),
        .native64(native64), .clk_sel(clk_sel), .is_z80(is_z80), .is_rom(is_rom), .mode_busy(mode_busy),
        .dbg_pc(dbg_pc), .dbg_f(dbg_f), .dbg_sig(dbg_sig), .gov_cv(gov_cv));
    wire en_mm = !native64;
    wire [23:0] i_ph, d_ph; wire i_wr_ok_unused;
    msx_mem u_mmi(.clk(clk), .rst(rst), .en(en_mm), .io_wr(m_we), .io_rd(m_re), .io_addr(b_a), .io_wdata(b_wd), .io_rdata(mi_rd), .io_hit(mi_hit_io),
        .mem_rd(i_req), .mem_wr(1'b0), .mem_addr(i_addr[15:0]), .mem_wdata(8'd0), .hit(i_hit), .phys_addr(i_ph), .a8_o(a8), .wr_ok(i_wr_ok_unused));
    wire [7:0] dummy_rd; wire dummy_io_hit; wire [7:0] a8_d;
    msx_mem u_mmd(.clk(clk), .rst(rst), .en(en_mm), .io_wr(m_we), .io_rd(m_re), .io_addr(b_a), .io_wdata(b_wd), .io_rdata(dummy_rd), .io_hit(dummy_io_hit),
        .mem_rd(d_req && !d_we), .mem_wr(d_req && d_we), .mem_addr({d_addr[15:3], lane_d}), .mem_wdata(lane_wd), .hit(d_hit), .phys_addr(d_ph), .a8_o(a8_d), .wr_ok(d_wr_ok));
    // endereco fisico: nativo = sem traducao; classico com hit = traduzido; sem hit = endereco original de 16 bits
    assign i_paddr = native64 ? i_addr : (i_hit ? {40'd0, i_ph} : {48'd0, i_addr[15:0]});
    assign d_paddr = native64 ? d_addr : (d_hit ? {40'd0, d_ph} : {48'd0, d_addr[15:0]});
    // E/S
    assign io_x_a = b_a; assign io_x_wd = b_wd;
    assign io_x_we = b_we && !mode_port && !mem_port && !fifo_hit;
    assign io_x_re = b_re && !mode_port && !mem_port && !fifo_hit;
    assign io_oe = io_re;                             // o sistema sempre responde a leitura (portas externas por io_x_rd)
    wire [7:0] ff_rd;
    r8064_fifo_if #(.BASE(FIFO_BASE)) u_fifo(.clk(clk), .rst(rst),
        .r_we(b_we && !mode_port && !mem_port), .r_re(b_re && !mode_port && !mem_port), .r_a(b_a), .r_wd(b_wd), .r_rd(ff_rd), .r_hit(fifo_hit),
        .m_we(fm_we), .m_re(fm_re), .m_a(fm_a), .m_wd(fm_wd), .m_rd(fm_rd), .m_irq(fifo_irq), .r8064_rst(fifo_rst));
    assign io_rd = md_oe ? md_rd : mi_hit_io ? mi_rd : fifo_hit ? ff_rd : io_x_rd;
endmodule
