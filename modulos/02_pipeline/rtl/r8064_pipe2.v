// r8064_pipe2.v - 7-stage pipeline with PREFETCH QUEUE (timing model driven by an execution trace).
// Front-end: fetch unit (aligned 8-byte words, 1+WRD clocks per access, contends for the bus with M) -> queue of QCAP bytes
//            -> F1 (decodes the instruction length at the head of the queue, LEN_LAT clocks) -> F2 (extracts LEN bytes from the queue) -> D -> R -> X -> M -> W.
// Branch: on leaving F2 an instruction with penalty (pen!=0) stalls the front-end (hold) - the queue keeps filling with wrong-path bytes
//         (they occupy the bus) until resolution in D (pen=1), X (pen=2) or M (pen=3); then the queue is flushed, the fetch in progress is lost and
//         fetch restarts at the target (offset within the word: TGT_OFF, or pseudo-random if < 0).
// Does not model data hazards or not-taken branches. Real decoder in stage D (as in r8064_pipe).
module r8064_pipe2 #(
    parameter NTRACE = 1, parameter TRACE_FILE = "trace.mem",
    parameter WRD = 4, WWR = 2, WIO = 1,
    parameter DEC_D = 1, LEN_LAT = 1, QCAP = 32, TGT_OFF = -1
)(
    input  wire clk, input wire rst,
    output reg  done, output reg [31:0] cycles, retired, chk_n, chk_err, f2_stall, wp_fetch, starve, fetches
);
    reg [15:0] trace [0:NTRACE-1];
    reg [11:0] rom_a [0:255]; reg [7:0] amb [0:255]; reg [9:0] rom_b [0:33*256-1]; reg [31:0] ctrl [0:511];
    initial begin
        $readmemh(TRACE_FILE, trace);
        $readmemh("rom_ed_a.mem", rom_a); $readmemh("amb_idx.mem", amb);
        $readmemh("rom_ed_b.mem", rom_b); $readmemh("ctrl.mem", ctrl);
    end
    function [31:0] ctrl_of(input [7:0] b2, input [7:0] b3);
        reg [11:0] a; reg [7:0] am; reg [9:0] id;
        begin a = rom_a[b2]; am = amb[b2]; id = a[10] ? rom_b[{am[5:0], b3}] : a[9:0]; ctrl_of = ctrl[id[8:0]]; end
    endfunction

    reg  v [0:6]; integer idx [0:6]; integer rem [0:6]; reg [31:0] c [0:6]; reg chk [0:6];
    wire [7:0] b2d = v[2] ? trace[idx[2]][15:8] : 8'h00;
    wire [7:0] b3d = v[2] ? trace[idx[2]][7:0]  : 8'h00;
    wire [3:0] d_len; wire [4:0] d_nr, d_nw; wire [1:0] d_nio, d_pen; wire [7:0] d_ex; wire d_cond, d_z80, d_ill; wire [9:0] d_id;
    r8064_decode dec(.clk(clk), .b2(b2d), .b3(b3d), .id(d_id), .illegal(d_ill), .len(d_len), .nr(d_nr), .nw(d_nw),
                     .nio(d_nio), .ex(d_ex), .pen_code(d_pen), .has_cond(d_cond), .is_z80(d_z80));
    wire [31:0] dword = {4'd0, 1'b0, d_z80, d_cond, d_pen, d_ex, d_nio, d_nw, d_nr, d_len};

    function integer work(input integer k, input [31:0] w);
        integer nr, nw, nio, ex, mb, mi;
        begin
            nr = w[8:4]; nw = w[13:9]; nio = w[15:14]; ex = w[23:16];
            mb = nr * (1 + WRD) + nw * (1 + WWR); mi = nio * (1 + WIO);
            case (k)
                0: work = (LEN_LAT < 1) ? 1 : LEN_LAT;
                1: work = 1;
                2: work = DEC_D;
                3: work = 1;
                4: work = (ex < 1) ? 1 : ex;
                5: work = (mb > mi) ? ((mb < 1) ? 1 : mb) : ((mi < 1) ? 1 : mi);
                default: work = 1;
            endcase
        end
    endfunction

    integer k, fp, ecount, j, need, claimed, lfsr, fbytes_n, qbytes, frem, fbytes, pcoff;
    reg hold, fetching; reg [6:0] dn; reg bus_m; reg [31:0] cw; reg [1:0] pc; reg [31:0] w0;
    always @(posedge clk) begin
        if (rst) begin
            for (k = 0; k < 7; k = k + 1) begin v[k] = 0; idx[k] = 0; rem[k] = 0; c[k] = 0; chk[k] = 0; end
            fp = 0; ecount = 0; hold = 0; fetching = 0; qbytes = 0; frem = 0; fbytes = 0; pcoff = 0; lfsr = 32'h1ACE_B00C;
            done <= 0; cycles <= 0; retired <= 0; chk_n <= 0; chk_err <= 0; f2_stall <= 0; wp_fetch <= 0; starve <= 0; fetches <= 0;
        end else if (!done) begin
            ecount = ecount + 1;
            lfsr = {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
            bus_m = v[5] && (rem[5] > 0) && ((c[5][8:4] + c[5][13:9]) != 0);
            if (v[3] && chk[3] && DEC_D >= 2) begin
                chk_n <= chk_n + 1;
                if (dword[27:0] !== c[3][27:0]) chk_err <= chk_err + 1;
            end
            chk[3] = 0;
            // fetch unit: advances the access in progress (if the bus is free)
            if (fetching) begin
                if (bus_m) f2_stall <= f2_stall + 1;
                else begin
                    frem = frem - 1;
                    if (frem == 0) begin
                        qbytes = qbytes + fbytes; fetching = 0; fetches <= fetches + 1;
                        if (hold) wp_fetch <= wp_fetch + 1;
                    end
                end
            end
            for (k = 0; k < 7; k = k + 1)
                if (v[k] && rem[k] > 0) rem[k] = rem[k] - 1;
            for (k = 0; k < 7; k = k + 1) dn[k] = v[k] && (rem[k] == 0);
            // moves, from end to start
            for (k = 6; k >= 1; k = k - 1) begin
                if (k == 6 && dn[6] && v[6]) begin
                    v[6] = 0; retired <= retired + 1;
                    if (retired + 1 == NTRACE) begin done <= 1; cycles <= ecount - 1; end
                end
                if (dn[k-1] && v[k-1] && !v[k] && !(k == 2 && qbytes < c[1][3:0])) begin
                    cw = c[k-1]; pc = cw[25:24];
                    v[k] = 1; idx[k] = idx[k-1]; c[k] = cw; rem[k] = work(k, cw); chk[k] = (k == 3);
                    v[k-1] = 0;
                    if (k == 2) begin
                        qbytes = qbytes - cw[3:0];
                    end
                    if ((pc == 2'd1 && k-1 == 2) || (pc == 2'd2 && k-1 == 4) || (pc == 2'd3 && k-1 == 5)) begin
                        for (j = 0; j < k-1; j = j + 1) v[j] = 0;
                        hold = 0; qbytes = 0; fetching = 0;
                        pcoff = (TGT_OFF < 0) ? (lfsr & 7) : TGT_OFF;
                    end
                end
            end
            if (v[1] && dn[1] && qbytes < c[1][3:0]) starve <= starve + 1;
            // F1: instruction at the head of the queue (bytes already available beyond those claimed by the instruction in F2)
            if (!v[0] && !hold && fp < NTRACE) begin
                w0 = ctrl_of(trace[fp][15:8], trace[fp][7:0]);
                need = (w0[3:0] < 3) ? w0[3:0] : 3;
                claimed = v[1] ? c[1][3:0] : 0;
                if (qbytes - claimed >= need) begin
                    v[0] = 1; idx[0] = fp; c[0] = w0; rem[0] = work(0, w0); fp = fp + 1;
                    if (w0[25:24] != 0) hold = 1;   // branch: what comes after is the wrong path
                end
            end
            // start of a new word fetch (if it fits in the queue)
            if (!fetching) begin
                fbytes_n = 8 - pcoff;
                if (qbytes + fbytes_n <= QCAP && (fp < NTRACE || hold || v[0] || v[1])) begin
                    fetching = 1; frem = 1 + WRD; fbytes = fbytes_n; pcoff = 0;
                end
            end
        end
    end
endmodule
