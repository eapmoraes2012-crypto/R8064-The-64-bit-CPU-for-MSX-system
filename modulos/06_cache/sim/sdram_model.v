// sdram_model.v - behavioral model of SDR SDRAM (4 banks x 2048 x 256 x 32) with protocol and timing CHECKING (independent of the controller).
// Counts violations: command illegal for the bank state, tRCD, tRP, tRAS, tRC, tRFC, tWR, tMRD, ACT before MRS, DQ contention, interval between refreshes, read of a non-active row, etc.
module sdram_model #(
    parameter tRCD = 2, tRP = 2, tRAS = 5, tRC = 7, tRFC = 7, tWR = 2, tMRD = 2, MAX_REF_GAP = 800, MIN_INIT_REF = 2
)(
    input  wire        clk, cke, cs_n, ras_n, cas_n, we_n,
    input  wire [3:0]  dqm, input wire [1:0] ba, input wire [10:0] a,
    input  wire [31:0] dq_i, input wire dq_oe,
    output reg  [31:0] dq_o
);
    reg [31:0] mem [0:(1<<21)-1];
    integer viol = 0, nact = 0, nrd = 0, nwr = 0, nref = 0, npre = 0, max_gap = 0, last_ref = 0, refs_init = 0, cyc = 0;
    reg mode_set = 0; integer cl = 2, bl = 2;
    reg active [0:3]; reg [10:0] arow [0:3]; integer t_act [0:3], t_pre [0:3], t_wr_last [0:3]; integer t_ref = -1000, t_mrs = -1000, t_last_cmd = 0;
    reg gap_flag = 0; integer k; reg [3:0] cmd; integer rd_sched [0:15]; integer rb [0:15]; integer rcol [0:15]; reg [10:0] rrow [0:15]; integer nq = 0, q;
    reg [31:0] wr_pending; integer wcol, wbank; reg [10:0] wrow; integer wbeat = 0; reg wr_act = 0; integer dq_driven_at = -1;
    initial begin
        for (k = 0; k < (1<<21); k = k + 1) mem[k] = 32'd0;
        for (k = 0; k < 4; k = k + 1) begin active[k] = 0; arow[k] = 0; t_act[k] = -1000; t_pre[k] = -1000; t_wr_last[k] = -1000; end
        for (k = 0; k < 16; k = k + 1) rd_sched[k] = -1;
        dq_o = 32'hzzzzzzzz;
    end
    task err(input [255:0] msg); begin viol = viol + 1; if (viol <= 8) $display("[SDRAM %0t] VIOLATION: %0s (cycle %0d)", $time, msg, cyc); end endtask
    function integer widx(input integer b, input [10:0] r, input integer c); widx = (r << 10) | (b << 8) | c; endfunction
    reg [31:0] dv;
    always @(posedge clk) begin
        cyc = cyc + 1;
        cmd = {cs_n, ras_n, cas_n, we_n};
        // scheduled read data: puts it on the bus at (capture instant - 1)
        dq_o <= 32'hzzzzzzzz;
        for (q = 0; q < 16; q = q + 1) if (rd_sched[q] == cyc + 1) begin
            dv = mem[widx(rb[q], rrow[q], rcol[q])];
            dq_o <= dv; dq_driven_at = cyc + 1; rd_sched[q] = -1;
        end
        if (dq_oe && dq_driven_at == cyc) err("DQ contention: controller driving during read");
        // second write beat
        if (wr_act) begin
            if (!dq_oe) err("write: DQ not driven on the 2nd beat");
            if (!dqm[0]) mem[widx(wbank, wrow, wcol + 1)][7:0]   = dq_i[7:0];
            if (!dqm[1]) mem[widx(wbank, wrow, wcol + 1)][15:8]  = dq_i[15:8];
            if (!dqm[2]) mem[widx(wbank, wrow, wcol + 1)][23:16] = dq_i[23:16];
            if (!dqm[3]) mem[widx(wbank, wrow, wcol + 1)][31:24] = dq_i[31:24];
            t_wr_last[wbank] = cyc; wr_act = 0;
        end
        if (cke && cmd != 4'b0111 && cmd[3] == 0) begin
            case (cmd)
                4'b0011: begin   // ACTIVE
                    nact = nact + 1;
                    if (!mode_set) err("ACTIVE before MRS");
                    if (active[ba]) err("ACTIVE on an already active bank");
                    if (cyc - t_pre[ba] < tRP) err("tRP (PRECHARGE->ACTIVE)");
                    if (cyc - t_act[ba] < tRC) err("tRC (ACTIVE->ACTIVE)");
                    if (cyc - t_ref < tRFC) err("tRFC (REFRESH->ACTIVE)");
                    active[ba] = 1; arow[ba] = a; t_act[ba] = cyc;
                end
                4'b0101, 4'b0100: begin   // READ / WRITE
                    if (!active[ba]) err("READ/WRITE on a bank without an active row");
                    if (cyc - t_act[ba] < tRCD) err("tRCD (ACTIVE->READ/WRITE)");
                    if (cmd == 4'b0101) begin
                        nrd = nrd + 1;
                        for (q = 0; q < 16; q = q + 1) if (rd_sched[q] == -1 && nq >= 0) begin
                            // agenda 2 beats
                            rd_sched[q] = cyc + cl; rb[q] = ba; rrow[q] = arow[ba]; rcol[q] = a[7:0]; q = 99;
                        end
                        for (q = 0; q < 16; q = q + 1) if (rd_sched[q] == -1) begin
                            rd_sched[q] = cyc + cl + 1; rb[q] = ba; rrow[q] = arow[ba]; rcol[q] = a[7:0] + 1; q = 99;
                        end
                    end else begin
                        nwr = nwr + 1;
                        if (!dq_oe) err("WRITE without DQ driven on the 1st beat");
                        if (!dqm[0]) mem[widx(ba, arow[ba], a[7:0])][7:0]   = dq_i[7:0];
                        if (!dqm[1]) mem[widx(ba, arow[ba], a[7:0])][15:8]  = dq_i[15:8];
                        if (!dqm[2]) mem[widx(ba, arow[ba], a[7:0])][23:16] = dq_i[23:16];
                        if (!dqm[3]) mem[widx(ba, arow[ba], a[7:0])][31:24] = dq_i[31:24];
                        wr_act = 1; wbank = ba; wrow = arow[ba]; wcol = a[7:0]; t_wr_last[ba] = cyc;
                    end
                end
                4'b0010: begin   // PRECHARGE
                    npre = npre + 1;
                    for (k = 0; k < 4; k = k + 1) if (a[10] || k == ba) begin
                        if (active[k]) begin
                            if (cyc - t_act[k] < tRAS) err("tRAS (ACTIVE->PRECHARGE)");
                            if (cyc - t_wr_last[k] < tWR) err("tWR (write->PRECHARGE)");
                        end
                        active[k] = 0; t_pre[k] = cyc;
                    end
                end
                4'b0001: begin   // AUTO REFRESH
                    nref = nref + 1;
                    for (k = 0; k < 4; k = k + 1) begin
                        if (active[k]) err("REFRESH with an active bank");
                        if (cyc - t_pre[k] < tRP) err("tRP (PRECHARGE->REFRESH)");
                    end
                    if (cyc - t_ref < tRFC) err("tRFC (REFRESH->REFRESH)");
                    if (!mode_set) refs_init = refs_init + 1;
                    else begin if (cyc - last_ref > max_gap) max_gap = cyc - last_ref; end
                    last_ref = cyc; t_ref = cyc; gap_flag = 0;
                end
                4'b0000: begin   // LOAD MODE REGISTER
                    for (k = 0; k < 4; k = k + 1) if (active[k]) err("MRS with an active bank");
                    if (refs_init < MIN_INIT_REF) err("MRS before the 2 initialization AUTO REFRESHes");
                    if (a[2:0] != 3'b001) err("mode: BL different from 2");
                    if (a[6:4] != 3'd2) err("mode: CL different from 2");
                    mode_set = 1; t_mrs = cyc; last_ref = cyc;
                end
                default: ;
            endcase
            if (cmd != 4'b0000 && cyc - t_mrs < tMRD && t_mrs > 0) err("tMRD");
        end
        if (mode_set && !gap_flag && cyc - last_ref > MAX_REF_GAP) begin err("late refresh (interval larger than MAX_REF_GAP)"); gap_flag = 1; end
    end
endmodule
