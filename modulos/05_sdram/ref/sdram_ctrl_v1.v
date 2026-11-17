// sdram_ctrl.v - controller for the embedded SDR SDRAM of the Tang Nano 20K (64 Mbit, 4 banks x 2048 rows x 256 columns x 32 bits) for 64-bit R8064 accesses.
// ASSUMPTIONS (not confirmed on the real chip): geometry above; CL=2; BL=2 (one 64-bit access = 2 32-bit words); generic SDR timings at 100 MHz
//   (tRCD=2, tRP=2, tRAS=5, tRC=7, tRFC=7, tWR=2, tMRD=2 clocks) and refresh every 7.8 us (covers 8192 rows in 64 ms). All parameterized.
// Open-page policy, one request at a time; posted write (wdone when the WRITE command is issued); be[7:0] becomes per-byte DQM.
// Interface: req/ready (accepted when ready=1 and req=1 in the same clock), we, addr (64-bit word index, 19 bits = 4 MB), wdata, be; read: rvalid+rdata; write: wdone.
module sdram_ctrl #(
    parameter INIT_CYC = 20000,            // 200 us a 100 MHz
    parameter tRCD = 2, tRP = 2, tRAS = 5, tRC = 7, tRFC = 7, tWR = 2, tMRD = 2, CL = 2,
    parameter REF_INT = 700                // clocks entre pedidos de refresh
)(
    input  wire        clk, rst,
    input  wire        req, we,
    input  wire [18:0] addr,
    input  wire [63:0] wdata,
    input  wire [7:0]  be,
    output wire        ready,
    output reg         rvalid,
    output reg  [63:0] rdata,
    output reg         wdone,
    output wire        init_done,
    // pinos da SDRAM
    output reg         s_cke, s_cs_n, s_ras_n, s_cas_n, s_we_n,
    output reg  [3:0]  s_dqm,
    output reg  [1:0]  s_ba,
    output reg  [10:0] s_a,
    output reg  [31:0] s_dq_o,
    output reg         s_dq_oe,
    input  wire [31:0] s_dq_i
);
    localparam [2:0] CLV = CL;
    localparam [3:0] ST_INIT = 0, ST_IPRE = 1, ST_IREF = 2, ST_IMRS = 3, ST_IDLE = 4, ST_PRE = 5, ST_ACT = 6, ST_RW = 7, ST_WR2 = 8, ST_RD = 9, ST_RPRE = 10, ST_REF = 11, ST_WAIT = 12, ST_WEND = 13;
    reg [3:0] st, nst;
    reg [15:0] icnt; reg [1:0] iref;
    // comandos {cs_n,ras_n,cas_n,we_n}
    localparam [3:0] C_NOP = 4'b0111, C_ACT = 4'b0011, C_RD = 4'b0101, C_WR = 4'b0100, C_PRE = 4'b0010, C_REF = 4'b0001, C_MRS = 4'b0000;
    task cmd(input [3:0] c); begin {s_cs_n, s_ras_n, s_cas_n, s_we_n} <= c; end endtask
    // row/bank/column: 32-bit word w = {addr, 0}: col = w[7:0], bank = w[9:8], row = w[20:10]
    reg lreq_we; reg [1:0] lb; reg [10:0] lrow; reg [7:0] lcol; reg [63:0] lwd; reg [7:0] lbe;
    wire [20:0] w_in = {addr, 1'b0};
    wire [1:0]  b_in = w_in[9:8]; wire [10:0] row_in = w_in[20:10];
    reg [3:0] open_r; reg [10:0] orow [0:3];
    // timers (loaded with N on issue; the dependent command can be issued when <= 1)
    reg [3:0] c_rcd [0:3], c_ras [0:3], c_rc [0:3], c_rp [0:3], c_wr [0:3]; reg [3:0] c_rfc, c_mrd;
    integer i;
    reg [9:0] refc; reg [3:0] pend;
    reg [7:0] rpipe; reg rd_b0_done;
    reg [31:0] rd_lo;
    wire hit_in  = open_r[b_in] && (orow[b_in] == row_in);
    wire miss_in = open_r[b_in] && (orow[b_in] != row_in);
    assign ready = (st == ST_IDLE) && (pend == 0);
    assign init_done = (st >= ST_IDLE);
    wire all_ok_pre = (c_ras[0] <= 1) && (c_ras[1] <= 1) && (c_ras[2] <= 1) && (c_ras[3] <= 1) && (c_wr[0] <= 1) && (c_wr[1] <= 1) && (c_wr[2] <= 1) && (c_wr[3] <= 1);
    wire [3:0] allrp_ok = {c_rp[3] <= 1, c_rp[2] <= 1, c_rp[1] <= 1, c_rp[0] <= 1};
    always @(posedge clk) begin
        // contadores
        for (i = 0; i < 4; i = i + 1) begin
            if (c_rcd[i] != 0) c_rcd[i] <= c_rcd[i] - 1; if (c_ras[i] != 0) c_ras[i] <= c_ras[i] - 1; if (c_rc[i] != 0) c_rc[i] <= c_rc[i] - 1;
            if (c_rp[i] != 0) c_rp[i] <= c_rp[i] - 1;   if (c_wr[i] != 0) c_wr[i] <= c_wr[i] - 1;
        end
        if (c_rfc != 0) c_rfc <= c_rfc - 1; if (c_mrd != 0) c_mrd <= c_mrd - 1;
        cmd(C_NOP); rvalid <= 0; wdone <= 0; rpipe <= {rpipe[6:0], 1'b0};
        // refresh periodico
        if (st >= ST_IDLE) begin
            if (refc == REF_INT - 1) begin refc <= 0; if (pend != 15) pend <= pend + 1; end else refc <= refc + 1;
        end
        // read capture (BL=2): beat0 in rpipe[CL], beat1 in rpipe[CL+1]
        if (rpipe[CL])     rd_lo <= s_dq_i;
        if (rpipe[CL + 1]) begin rdata <= {s_dq_i, rd_lo}; rvalid <= 1; end
        if (rst) begin
            st <= ST_INIT; icnt <= 0; iref <= 0; open_r <= 0; refc <= 0; pend <= 0; rpipe <= 0; s_cke <= 0; s_dq_oe <= 0; s_dqm <= 4'hF; s_a <= 0; s_ba <= 0; s_dq_o <= 0;
            for (i = 0; i < 4; i = i + 1) begin c_rcd[i] <= 0; c_ras[i] <= 0; c_rc[i] <= 0; c_rp[i] <= 0; c_wr[i] <= 0; end
            c_rfc <= 0; c_mrd <= 0; {s_cs_n, s_ras_n, s_cas_n, s_we_n} <= C_NOP;
        end else case (st)
            ST_INIT: begin
                s_cke <= 1; s_dqm <= 4'hF;
                if (icnt == INIT_CYC) begin st <= ST_IPRE; end else icnt <= icnt + 1;
            end
            ST_IPRE: begin   // PRECHARGE ALL
                cmd(C_PRE); s_a <= 11'h400; s_ba <= 0; c_rfc <= tRP; st <= ST_IREF; iref <= 0;
            end
            ST_IREF: if (c_rfc <= 1) begin
                cmd(C_REF); c_rfc <= tRFC; iref <= iref + 1; if (iref == 1) st <= ST_IMRS;
            end
            ST_IMRS: if (c_rfc <= 1) begin
                cmd(C_MRS); s_ba <= 0; s_a <= {4'b0000, CLV, 1'b0, 3'b001};  // BL=2, sequential, CL, burst write
                c_mrd <= tMRD; st <= ST_WAIT;
            end
            ST_WAIT: if (c_mrd <= 1) begin st <= ST_IDLE; s_dqm <= 4'h0; end
            ST_IDLE: begin
                s_dqm <= 4'h0;
                if (pend != 0 && rpipe == 0) st <= ST_RPRE;
                else if (req) begin
                    lreq_we <= we; lb <= b_in; lrow <= row_in; lcol <= w_in[7:0]; lwd <= wdata; lbe <= be;
                    st <= hit_in ? ST_RW : miss_in ? ST_PRE : ST_ACT;
                end
            end
            ST_PRE: if (c_ras[lb] <= 1 && c_wr[lb] <= 1) begin
                cmd(C_PRE); s_a <= 11'h000; s_ba <= lb; open_r[lb] <= 0; c_rp[lb] <= tRP; st <= ST_ACT;
            end
            ST_ACT: if (c_rp[lb] <= 1 && c_rc[lb] <= 1 && c_rfc <= 1) begin
                cmd(C_ACT); s_a <= lrow; s_ba <= lb; open_r[lb] <= 1; orow[lb] <= lrow;
                c_rcd[lb] <= tRCD; c_ras[lb] <= tRAS; c_rc[lb] <= tRC; st <= ST_RW;
            end
            ST_RW: if (c_rcd[lb] <= 1 && rpipe[CL+1:0] == 0) begin
                s_ba <= lb; s_a <= {3'b000, lcol};
                if (lreq_we) begin
                    cmd(C_WR); s_dq_o <= lwd[31:0]; s_dq_oe <= 1; s_dqm <= ~lbe[3:0]; c_wr[lb] <= tWR + 1; wdone <= 1; st <= ST_WR2;
                end else begin
                    cmd(C_RD); s_dqm <= 4'h0; rpipe <= 8'h01; st <= ST_RD;
                end
            end
            ST_WR2: begin s_dq_o <= lwd[63:32]; s_dqm <= ~lbe[7:4]; st <= ST_WEND; end
            ST_RD: if (rpipe[CL + 1]) begin st <= ST_IDLE; rpipe <= 0; end
            ST_RPRE: if (all_ok_pre) begin    // precharge all
                s_dq_oe <= 0;
                cmd(C_PRE); s_a <= 11'h400; s_ba <= 0; open_r <= 0; for (i = 0; i < 4; i = i + 1) c_rp[i] <= tRP; c_rfc <= tRP; st <= ST_REF;
            end
            ST_REF: if (c_rfc <= 1) begin
                cmd(C_REF); c_rfc <= tRFC; pend <= pend - 1; st <= ST_IDLE;
            end
            ST_WEND: begin s_dq_oe <= 0; s_dqm <= 4'h0; st <= ST_IDLE; end    // end of the second write beat
            default: st <= ST_IDLE;
        endcase
    end
endmodule
