`timescale 1ns/1ps
// tb_r64core.v - instrucoes inteiras do R8064 (16/32/64 bits) no nucleo contra o modelo em Python (gen_r64_prog.py), instrucao a instrucao.
// Libera UMA instrucao por vez (gov_go), espera o pipeline esvaziar e compara PC, AX, BC, DE, HL, IX, IY, SP (64 bits) e F; no fim compara os 64 KB de memoria.
// Plusargs: +hex=<prefixo>_mem.hex +trace=<prefixo>_trace.txt +fim=<prefixo>_fim.hex [+v]
module tb_r64core;
    reg clk = 0, rst = 1, go = 0; always #5 clk = ~clk;
    wire i_req, d_req, d_we; wire [63:0] i_addr, d_addr, d_wdata, dbg_pc; wire [1:0] d_size; wire [7:0] dbg_f, d_be; wire dbg_sig;
    reg i_ack = 0, d_ack = 0; reg [63:0] i_rdata = 0, d_rdata = 0; reg [7:0] mem [0:65535]; reg [7:0] fim [0:65535];
    wire io_we, io_re; wire [7:0] io_a, io_wd;
    r8064_core_min dut(.i_flt(1'b0), .d_flt(1'b0), .i_cs(3'd0), .d_cs(3'd0), .clk(clk), .rst(rst), .irq(1'b0),
        .i_req(i_req), .i_addr(i_addr), .i_ack(i_ack), .i_rdata(i_rdata),
        .d_req(d_req), .d_we(d_we), .d_addr(d_addr), .d_size(d_size), .d_wdata(d_wdata), .d_be(d_be), .d_ack(d_ack), .d_rdata(d_rdata),
        .dbg_pc(dbg_pc), .dbg_f(dbg_f), .dbg_sig(dbg_sig), .gov_go(go), .gov_wait(1'b0), .port_c(8'd0), .gov_page(), .gov_op(), .gov_port(), .gov_cv(), .gov_alt_ev(), .gov_boundary(),
        .gov_pc(), .gov_len(), .gov_dev(), .gov_daddr(), .gov_dsize(), .gov_dwe(), .io_we(io_we), .io_re(io_re), .io_a(io_a), .io_wd(io_wd), .io_rdata(8'hFF));
    integer ic = 0, k;
    wire [15:0] ia = {i_addr[15:3], 3'b000}, da = {d_addr[15:3], 3'b000};
    always @(posedge clk) begin
        i_ack <= 0; d_ack <= 0;
        if (i_req && !i_ack) begin ic <= ic + 1; if (ic == 1) begin ic <= 0; i_ack <= 1; for (k = 0; k < 8; k = k + 1) i_rdata[8*k +: 8] <= mem[ia + k[15:0]]; end end else ic <= 0;
        if (d_req && !d_ack) begin d_ack <= 1;
            if (d_we) begin for (k = 0; k < 8; k = k + 1) if (d_be[k]) mem[da + k[15:0]] <= d_wdata[8*k +: 8]; end
            else for (k = 0; k < 8; k = k + 1) d_rdata[8*k +: 8] <= mem[da + k[15:0]];
        end
    end
    wire busy = dut.v_xr | dut.v_x1 | dut.v_x2 | dut.v_x3 | dut.v_m | dut.v_w | dut.flush_q | dut.flush_raw | dut.seq;
    reg [1023:0] fhex, ftrace, ffim; integer fd, rc, n = 0, errs = 0, idle, tmo, merr = 0, q; reg verb;
    reg [63:0] e [0:7], g [0:7], pc0; reg [7:0] e_f;
    initial begin
        if (!$value$plusargs("hex=%s", fhex) || !$value$plusargs("trace=%s", ftrace)) begin $display("faltam +hex= e +trace="); $finish; end
        verb = $test$plusargs("v");
        $readmemh(fhex, mem); fd = $fopen(ftrace, "r");
        repeat (4) @(posedge clk); rst = 0;
        begin : laco
            forever begin
                rc = $fscanf(fd, "%h %h %h %h %h %h %h %h %h", e[0], e[1], e[2], e[3], e[4], e[5], e[6], e[7], e_f);
                if (rc != 9) disable laco;
                pc0 = dut.npc;
                go = 1; tmo = 0; @(posedge clk);
                while (!dut.consume && !dut.flush_br) begin @(posedge clk); tmo = tmo + 1; if (tmo > 5000) begin $display("ERRO: instrucao %0d (pc=%h) nao foi emitida", n, pc0); errs = errs + 1; disable laco; end end
                #1 go = 0; idle = 0; tmo = 0;
                while (idle < 3) begin @(posedge clk); #1; idle = busy ? 0 : idle + 1; tmo = tmo + 1; if (tmo > 5000) begin $display("ERRO: instrucao %0d (pc=%h) nao terminou", n, pc0); errs = errs + 1; disable laco; end end
                n = n + 1;
                g[0] = dut.npc; g[1] = dut.u_rf1.mem_a[0]; g[2] = dut.u_rf1.mem_a[1]; g[3] = dut.u_rf1.mem_a[2]; g[4] = dut.u_rf1.mem_a[3];
                g[5] = dut.u_rf1.mem_a[9]; g[6] = dut.u_rf1.mem_a[10]; g[7] = dut.u_rf1.mem_a[11];
                if (verb) $display("#%0d pc=%h op=%h %h %h %h -> pc=%h ax=%h bc=%h f=%h", n, pc0[15:0], mem[pc0[15:0]], mem[pc0[15:0]+16'd1], mem[pc0[15:0]+16'd2], mem[pc0[15:0]+16'd3], g[0], g[1], g[2], dut.fl);
                q = 0; for (k = 0; k < 8; k = k + 1) if (g[k] !== e[k]) q = 1;
                if (q || dut.fl !== e_f) begin
                    errs = errs + 1;
                    $display("DIVERGENCIA na instrucao %0d: pc=%h opcode %h %h %h %h %h", n, pc0, mem[pc0[15:0]], mem[pc0[15:0]+16'd1], mem[pc0[15:0]+16'd2], mem[pc0[15:0]+16'd3], mem[pc0[15:0]+16'd4]);
                    $display("  nucleo: pc=%h ax=%h bc=%h de=%h hl=%h ix=%h iy=%h sp=%h f=%h", g[0], g[1], g[2], g[3], g[4], g[5], g[6], g[7], dut.fl);
                    $display("  modelo: pc=%h ax=%h bc=%h de=%h hl=%h ix=%h iy=%h sp=%h f=%h", e[0], e[1], e[2], e[3], e[4], e[5], e[6], e[7], e_f);
                    disable laco;
                end
            end
        end
        if (errs == 0 && $value$plusargs("fim=%s", ffim)) begin
            $readmemh(ffim, fim);
            for (k = 0; k < 65536; k = k + 1) if (mem[k] !== fim[k]) begin merr = merr + 1; if (merr <= 5) $display("MEMORIA difere em %h: nucleo %h modelo %h", k[15:0], mem[k], fim[k]); end
            errs = errs + merr;
        end
        $display("%0d instrucoes comparadas, %0d bytes de memoria diferentes", n, merr);
        if (errs == 0) $display("RESULTADO: R8064 16/32/64 NO NUCLEO OK"); else $display("RESULTADO: %0d ERROS", errs);
        $finish;
    end
endmodule
