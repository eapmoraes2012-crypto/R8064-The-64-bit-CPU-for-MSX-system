// z80_msx_sys.v - Z80 classico independente + memoria mapeada MSX (mapper FC-FF, MegaRAM ASCII8, slot A8h) + ponte para memoria fisica por bytes.
// Memoria que cai no mapper/MegaRAM (hit) vai para a porta fisica mp_* (SDRAM); o resto (ROM da BIOS, outros slots, perifericos) sai pelas portas
// externas xm_* (memoria) e xio_* (E/S), com x_wait_n. WAIT e dados sao REGISTRADOS (1 clock) para nao alongar o caminho critico do nucleo;
// isto exige que os pulsos ce do Z80 fiquem separados por >= 3 clocks (vale para z80_ce nos 4 modos de turbo; com use_ext, ce_ext idem).
module z80_msx_sys #(
    parameter [31:0] STEP_BASE = 32'd268435456,
    parameter MAP_BITS = 6, MEGA_BITS = 7,
    parameter [23:0] MAP_BASE = 24'h000000, MEGA_BASE = 24'h100000,
    parameter [1:0] SLOT_MAP = 2'd3, SLOT_MEGA = 2'd2
)(
    input  wire        clk, rst_n,
    input  wire [1:0]  turbo,
    input  wire        use_ext, ce_ext, msx_w,
    // memoria fisica (bytes)
    output reg         mp_req,
    output reg         mp_we,
    output reg  [23:0] mp_addr,
    output reg  [7:0]  mp_wdata,
    input  wire [7:0]  mp_rdata,
    input  wire        mp_ack,
    // memoria e E/S externas (nao mapeadas)
    output wire        xm_rd, xm_wr,
    output wire [15:0] xm_addr,
    output wire [7:0]  xm_wdata,
    input  wire [7:0]  xm_rdata,
    output wire        xio_rd, xio_wr, xio_ack,       // xio_ack = ciclo de reconhecimento de interrupcao (M1+IORQ): xio_rdata deve trazer o vetor
    output wire [7:0]  xio_addr,
    output wire [7:0]  xio_wdata,
    input  wire [7:0]  xio_rdata,
    input  wire        x_wait_n,
    // CPU
    input  wire        int_n, nmi_n, busrq_n,
    output wire        halt_n, busak_n, m1_n, rfsh_n,
    output wire        ce_o, instr_done
);
    wire [15:0] a; wire [7:0] dout; reg [7:0] din;
    wire mreq_n, iorq_n, rd_n, wr_n; wire wait_n;
    z80_top #(.STEP_BASE(STEP_BASE)) u_z80(.clk(clk), .rst_n(rst_n), .turbo(turbo), .use_ext(use_ext), .ce_ext(ce_ext), .msx_w(msx_w),
        .a(a), .dout(dout), .din(din), .mreq_n(mreq_n), .iorq_n(iorq_n), .rd_n(rd_n), .wr_n(wr_n), .m1_n(m1_n), .rfsh_n(rfsh_n),
        .halt_n(halt_n), .busak_n(busak_n), .wait_n(wait_n), .int_n(int_n), .nmi_n(nmi_n), .busrq_n(busrq_n), .ce_o(ce_o), .instr_done(instr_done));

    wire mrd = ~mreq_n & ~rd_n;
    wire mwr = ~mreq_n & ~wr_n;
    wire iord = ~iorq_n & ~rd_n & m1_n;
    wire iowr = ~iorq_n & ~wr_n;
    wire hit, io_hit, wr_ok; wire [23:0] phys; wire [7:0] io_rdata;
    msx_mem #(.MAP_BITS(MAP_BITS), .MEGA_BITS(MEGA_BITS), .MAP_BASE(MAP_BASE), .MEGA_BASE(MEGA_BASE), .SLOT_MAP(SLOT_MAP), .SLOT_MEGA(SLOT_MEGA)) u_mem(
        .clk(clk), .rst(~rst_n), .en(1'b1), .io_wr(iowr), .io_rd(iord), .io_addr(a[7:0]), .io_wdata(dout), .io_rdata(io_rdata), .io_hit(io_hit),
        .mem_rd(mrd), .mem_wr(mwr), .mem_addr(a), .mem_wdata(dout), .hit(hit), .phys_addr(phys), .wr_ok(wr_ok));

    // acesso fisico: leitura em bloco mapeado, ou escrita permitida
    wire need_phys = hit & (mrd | (mwr & wr_ok));
    reg  pend, done; reg [7:0] rbuf;
    always @(posedge clk) begin
        if (!rst_n) begin pend <= 1'b0; done <= 1'b0; mp_req <= 1'b0; end
        else if (!need_phys) begin pend <= 1'b0; done <= 1'b0; mp_req <= 1'b0; end
        else if (!done && !pend) begin
            pend <= 1'b1; mp_req <= 1'b1; mp_we <= mwr; mp_addr <= phys; mp_wdata <= dout;
        end else if (pend && mp_ack) begin
            pend <= 1'b0; mp_req <= 1'b0; done <= 1'b1; rbuf <= mp_rdata;
        end
    end
    // acessos externos
    wire xm_acc  = (mrd | mwr) & ~hit;
    wire xio_acc = (iord | iowr | (~iorq_n & ~m1_n)) & ~(io_hit);
    assign xm_rd = mrd & ~hit;  assign xm_wr = mwr & ~hit;  assign xm_addr = a;  assign xm_wdata = dout;
    assign xio_rd = iord; assign xio_wr = iowr; assign xio_ack = ~iorq_n & ~m1_n; assign xio_addr = a[7:0]; assign xio_wdata = dout;

    reg wq, wxq;
    always @(posedge clk) begin
        wq  <= need_phys & ~done;
        wxq <= (xm_acc | xio_acc) & ~x_wait_n;
    end
    assign wait_n = ~(wq | wxq);

    // dados para a CPU (registrados)
    reg [7:0] dsel;
    always @* begin
        if (~iorq_n)      dsel = io_hit ? io_rdata : xio_rdata;
        else if (hit)     dsel = rbuf;
        else              dsel = xm_rdata;
    end
    always @(posedge clk) din <= dsel;
endmodule
