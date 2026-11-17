`timescale 1ns/1ps
module tb_muldiv;
    parameter NM = 1, ND = 1;
    reg clk = 0, rst = 1; always #5 clk = ~clk;
    reg [63:0] ma [0:NM-1], mb [0:NM-1]; reg [7:0] mc [0:NM-1]; reg [127:0] me [0:NM-1];
    reg [63:0] dh [0:ND-1], dl [0:ND-1], dd [0:ND-1], dq [0:ND-1], dr [0:ND-1]; reg [7:0] dc [0:ND-1]; reg de [0:ND-1];
    initial begin
        $readmemh("mul_a.mem", ma); $readmemh("mul_b.mem", mb); $readmemh("mul_c.mem", mc); $readmemh("mul_e.mem", me);
        $readmemh("div_h.mem", dh); $readmemh("div_l.mem", dl); $readmemh("div_d.mem", dd); $readmemh("div_c.mem", dc);
        $readmemh("div_q.mem", dq); $readmemh("div_r.mem", dr); $readmemh("div_e.mem", de);
    end
    // ---- DUTs
    reg m_in = 0; reg [1:0] m_sz = 0; reg m_sgn = 0; reg [63:0] m_a = 0, m_b = 0; wire m_rdy, m_ov; wire [127:0] m_p;
    mul_unit mu(.clk(clk), .rst(rst), .in_valid(m_in), .sz(m_sz), .sgn(m_sgn), .a(m_a), .b(m_b), .ready(m_rdy), .out_valid(m_ov), .prod(m_p));
    reg m_rdy_s; always @(posedge clk) m_rdy_s <= m_rdy;
    reg d_st = 0; reg [1:0] d_sz = 0; reg d_sgn = 0; reg [63:0] d_h = 0, d_l = 0, d_d = 0; wire d_busy, d_done, d_err; wire [63:0] d_q, d_r;
    div_unit du(.clk(clk), .rst(rst), .start(d_st), .sz(d_sz), .sgn(d_sgn), .hi(d_h), .lo(d_l), .d(d_d), .busy(d_busy), .done(d_done), .q(d_q), .r(d_r), .err(d_err));
    function [127:0] mk(input [1:0] z);
        mk = (z == 0) ? 128'hFFFF : (z == 1) ? 128'hFFFF_FFFF : (z == 2) ? 128'hFFFF_FFFF_FFFF_FFFF : {128{1'b1}};
    endfunction
    integer i, t, errs_m, errs_s, errs_d, errs_c, lat, nsm, k, nb, lmin [0:3], lmax [0:3], expn;
    integer cmin [0:7], cmax [0:7], sel;
    reg [63:0] eq, er;
    integer sidx [0:NM-1]; integer ns, issued, got, errs_b;
    reg [127:0] exq [0:NM-1];
    initial begin
        errs_m = 0; errs_s = 0; errs_d = 0; errs_c = 0; errs_b = 0;
        for (k = 0; k < 4; k = k + 1) begin lmin[k] = 999; lmax[k] = 0; end
        for (k = 0; k < 8; k = k + 1) begin cmin[k] = 999; cmax[k] = 0; end
        repeat (4) @(posedge clk); #1 rst = 0; repeat (2) @(posedge clk);
        // ================= multiplier: sequential (measures latency)
        for (i = 0; i < NM; i = i + 1) begin
            #1 m_a = ma[i]; m_b = mb[i]; m_sz = mc[i][1:0]; m_sgn = mc[i][2]; m_in = 1;
            @(posedge clk); #1 m_in = 0; lat = 1;
            while (!m_ov && lat < 40) begin @(posedge clk); #1 lat = lat + 1; end
            if ((m_p & mk(mc[i][1:0])) !== (me[i] & mk(mc[i][1:0]))) begin
                errs_m = errs_m + 1;
                if (errs_m <= 5) $display("ERROR mul i=%0d sz=%0d sgn=%0d a=%h b=%h got=%h expected=%h", i, mc[i][1:0], mc[i][2], ma[i], mb[i], m_p & mk(mc[i][1:0]), me[i] & mk(mc[i][1:0]));
            end
            if (lat < lmin[mc[i][1:0]]) lmin[mc[i][1:0]] = lat; if (lat > lmax[mc[i][1:0]]) lmax[mc[i][1:0]] = lat;
            repeat (2) @(posedge clk);
        end
        // ================= multiplier: stream of small operations every clock
        ns = 0; for (i = 0; i < NM; i = i + 1) if (mc[i][1:0] != 3) begin sidx[ns] = i; ns = ns + 1; end
        issued = 0; got = 0;
        fork
            begin : issue
                while (issued < ns) begin
                    #1 m_a = ma[sidx[issued]]; m_b = mb[sidx[issued]]; m_sz = mc[sidx[issued]][1:0]; m_sgn = mc[sidx[issued]][2]; m_in = 1;
                    @(posedge clk); issued = issued + 1;
                end
                #1 m_in = 0;
            end
            begin : capture
                while (got < ns) begin
                    @(posedge clk); #0.5;
                    if (m_ov) begin
                        if ((m_p & mk(mc[sidx[got]][1:0])) !== (me[sidx[got]] & mk(mc[sidx[got]][1:0]))) errs_s = errs_s + 1;
                        got = got + 1;
                    end
                end
            end
        join
        $display("MUL stream: %0d small operations issued 1 per clock, %0d received, errors %0d", ns, got, errs_s);
        repeat (4) @(posedge clk);
        // ================= 64-bit multiplier in sequence (ready)
        nb = 0; issued = 0; got = 0;
        for (i = 0; i < NM; i = i + 1) if (mc[i][1:0] == 3) begin sidx[nb] = i; nb = nb + 1; end
        t = 0;
        fork
            begin : issue_b
                while (issued < nb) begin
                    #1 m_a = ma[sidx[issued]]; m_b = mb[sidx[issued]]; m_sz = 3; m_sgn = mc[sidx[issued]][2]; m_in = 1;
                    @(posedge clk); #0.2; if (m_rdy_s) begin issued = issued + 1; end
                end
                #1 m_in = 0;
            end
            begin : cap_b
                while (got < nb) begin
                    @(posedge clk); #0.5;
                    if (m_ov) begin
                        if (m_p !== me[sidx[got]]) errs_b = errs_b + 1;
                        got = got + 1;
                    end
                end
            end
            begin : cnt_b
                while (got < nb) begin @(posedge clk); t = t + 1; end
            end
        join
        $display("MUL 64 bits in sequence: %0d operations in %0d clocks (%0.2f clocks/op), errors %0d", nb, t, t * 1.0 / nb, errs_b);
        // ================= divisor
        for (i = 0; i < ND; i = i + 1) begin
            #1 d_h = dh[i]; d_l = dl[i]; d_d = dd[i]; d_sz = dc[i][1:0]; d_sgn = dc[i][2]; d_st = 1;
            @(posedge clk); #1 d_st = 0; lat = 0;
            while (!d_done && lat < 200) begin @(posedge clk); #1 lat = lat + 1; end
            // lat = clocks busy until DONE inclusive
            lat = lat + 1;
            if (d_err !== de[i] || (!de[i] && (d_q !== dq[i] || d_r !== dr[i]))) begin
                errs_d = errs_d + 1;
                if (errs_d <= 5) $display("ERROR div i=%0d sz=%0d sgn=%0d h=%h l=%h d=%h q=%h/%h r=%h/%h e=%b/%b", i, dc[i][1:0], dc[i][2], dh[i], dl[i], dd[i], d_q, dq[i], d_r, dr[i], d_err, de[i]);
            end
            if (!de[i]) begin
                expn = (dc[i][1:0] == 0 ? 8 : dc[i][1:0] == 1 ? 16 : dc[i][1:0] == 2 ? 32 : 64) + (dc[i][2] ? 7 : 2);   // REV44: signed = sz+7 (single negator)
                if (lat !== expn) errs_c = errs_c + 1;
                sel = dc[i][2] * 4 + dc[i][1:0];
                if (lat < cmin[sel]) cmin[sel] = lat; if (lat > cmax[sel]) cmax[sel] = lat;
            end
            @(posedge clk);
        end
        $display("MUL: %0d sequential vectors, errors %0d | latency (cycle of acceptance until out_valid): 8b %0d..%0d, 16b %0d..%0d, 32b %0d..%0d, 64b %0d..%0d", NM, errs_m, lmin[0], lmax[0], lmin[1], lmax[1], lmin[2], lmax[2], lmin[3], lmax[3]);
        $display("DIV: %0d vectors, result errors %0d, cycle errors (no overflow) %0d", ND, errs_d, errs_c);
        $display("DIV busy cycles (unsigned) 8b %0d 16b %0d 32b %0d 64b %0d | (signed) 8b %0d 16b %0d 32b %0d 64b %0d", cmax[0], cmax[1], cmax[2], cmax[3], cmax[4], cmax[5], cmax[6], cmax[7]);
        if (errs_m + errs_s + errs_b + errs_d + errs_c == 0) $display("PASS"); else $display("FAIL");
        $finish;
    end
endmodule
