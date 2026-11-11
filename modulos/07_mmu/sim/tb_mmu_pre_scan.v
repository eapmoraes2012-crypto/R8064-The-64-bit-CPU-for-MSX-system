`timescale 1ns/1ps
// Testbench da MMU: tabelas de paginas reais em memoria comportamental (latencia aleatoria), modelo de referencia em software (percorre as tabelas), fila de esperados.
module tb_mmu;
    reg clk = 0, rst = 1; always #5 clk = ~clk;
    reg en = 0, user = 0; reg [7:0] asid = 0; reg [19:0] root = 1;
    reg fl_all = 0, fl_va_en = 0, fl_asid_en = 0; reg [63:0] fl_va = 0; reg [7:0] fl_asid = 0;
    reg v_req = 0; reg [63:0] v_addr = 0; reg [1:0] v_acc = 0;
    wire ready, p_valid, p_fault; wire [31:0] p_addr; wire [2:0] p_cause;
    wire m_req; wire [18:0] m_addr; reg m_accept = 0, m_done = 0; reg [63:0] m_rdata = 0;
    wire [31:0] sh, sm, sw, sf;
    parameter NENT = 16;
    mmu #(.NENT(NENT)) dut(.clk(clk), .rst(rst), .en(en), .user(user), .asid(asid), .root_ppn(root), .fl_all(fl_all), .fl_va_en(fl_va_en), .fl_asid_en(fl_asid_en), .fl_va(fl_va), .fl_asid(fl_asid),
        .v_req(v_req), .v_addr(v_addr), .v_acc(v_acc), .ready(ready), .p_valid(p_valid), .p_addr(p_addr), .p_fault(p_fault), .p_cause(p_cause),
        .m_req(m_req), .m_addr(m_addr), .m_accept(m_accept), .m_done(m_done), .m_rdata(m_rdata), .st_hit(sh), .st_miss(sm), .st_walk(sw), .st_fault(sf));
    // ---- memoria com latencia aleatoria
    reg [63:0] pm [0:524287];
    integer lat_min = 4, lat_max = 12, nmemrd = 0;
    reg [63:0] rd_lat; reg mbusy = 0; integer mcnt = 0; reg [18:0] maddr_l;
    always @(posedge clk) begin
        m_accept <= 0; m_done <= 0;
        if (!mbusy) begin if (m_req && !m_accept) begin m_accept <= 1; mbusy <= 1; maddr_l <= m_addr; rd_lat <= pm[m_addr]; mcnt = lat_min + ($urandom % (lat_max - lat_min + 1)); end end
        else begin
            mcnt = mcnt - 1;
            if (mcnt <= 0) begin m_done <= 1; m_rdata <= rd_lat; mbusy <= 0; nmemrd = nmemrd + 1; end
        end
    end
    // ---- construtor de tabelas
    integer nexttbl = 2; reg [19:0] t_, nn_; reg [63:0] pe_; integer ii, lv;
    task clear_tbl(input [19:0] p); integer k; begin for (k = 0; k < 512; k = k + 1) pm[{p[9:0], k[8:0]}] = 64'd0; end endtask
    task newroot(input [19:0] p); begin clear_tbl(p); end endtask
    // map: folha em 'leaf' (0 = 4KB, 1 = 2MB)
    task map(input [19:0] rt, input [38:0] va, input [19:0] ppn, input [7:0] flags, input integer leaf);
        reg [8:0] idx;
        begin
            t_ = rt;
            for (lv = 2; lv > leaf; lv = lv - 1) begin
                idx = va[12 + 9*lv +: 9];
                pe_ = pm[{t_[9:0], idx}];
                if (!pe_[0] || (pe_[3:1] != 0)) begin
                    nn_ = nexttbl; nexttbl = nexttbl + 1; clear_tbl(nn_);
                    pm[{t_[9:0], idx}] = {34'd0, nn_, 10'd1};
                    t_ = nn_;
                end else t_ = pe_[29:10];
            end
            idx = va[12 + 9*leaf +: 9];
            pm[{t_[9:0], idx}] = {34'd0, ppn, 2'b00, flags};
        end
    endtask
    // ---- modelo de referencia (percorre as tabelas)
    function [35:0] refx(input e, input [19:0] rt, input [63:0] va, input [1:0] acc, input usr);
        reg [63:0] pe; reg [19:0] tb; integer l; reg done, flt; reg [2:0] cs; reg [31:0] pa; reg [8:0] ix; reg pf;
        begin
            flt = 0; cs = 0; pa = 0; done = 0;
            if (!e) begin refx = {1'b0, 3'd0, va[31:0]}; end
            else begin
                if (va[63:39] != {25{va[38]}}) begin flt = 1; cs = 1; done = 1; end
                tb = rt; l = 2;
                if (!done && rt[19:10] != 0) begin flt = 1; cs = 4; done = 1; end
                while (!done) begin
                    ix = va[12 + 9*l +: 9];
                    pe = pm[{tb[9:0], ix}];
                    if (!pe[0] || (pe[2] && !pe[1])) begin flt = 1; cs = 1; done = 1; end
                    else if (pe[3:1] != 0) begin
                        if (l == 2 || (l == 1 && pe[18:10] != 0)) begin flt = 1; cs = 1; end
                        else if (pe[29:20] != 0) begin flt = 1; cs = 4; end
                        else begin
                            pf = (acc == 0 && !pe[1]) || (acc == 1 && !pe[2]) || (acc == 2 && !pe[3]) || (usr && !pe[4]) || (!usr && pe[4] && acc == 2);
                            if (pf) begin flt = 1; cs = 2; end
                            else if (!pe[6] || (acc == 1 && !pe[7])) begin flt = 1; cs = 3; end
                            else pa = (l == 1) ? {pe[29:19], va[20:0]} : {pe[29:10], va[11:0]};
                        end
                        done = 1;
                    end else begin
                        if (l == 0) begin flt = 1; cs = 1; done = 1; end
                        else if (pe[29:20] != 0) begin flt = 1; cs = 4; done = 1; end
                        else begin tb = pe[29:10]; l = l - 1; end
                    end
                end
                refx = {flt, cs, flt ? 32'd0 : pa};
            end
        end
    endfunction
    // ---- gerador / verificador
    reg [63:0] qa [0:8191]; reg [1:0] qc [0:8191]; reg qu [0:8191]; reg qs [0:8191]; reg exs [0:8191]; integer qh = 0, qt = 0;
    reg [35:0] ex [0:8191]; integer eh = 0, et = 0; integer errs = 0, nchk = 0, acc_cyc = 0, rv_cyc = 0, cyc = 0;
    task push(input [63:0] a, input [1:0] c, input u); begin qa[qt % 8192] = a; qc[qt % 8192] = c; qu[qt % 8192] = u; qs[qt % 8192] = 0; qt = qt + 1; end endtask
    task push_dc(input [63:0] a, input [1:0] c, input u); begin qa[qt % 8192] = a; qc[qt % 8192] = c; qu[qt % 8192] = u; qs[qt % 8192] = 1; qt = qt + 1; end endtask
    reg cur_s, iss_s;
    wire quiet = (qh == qt) && !v_req && (eh == et);
    integer nflt = 0;
    always @(posedge clk) begin
        cyc = cyc + 1;
        if (!rst) begin
            if (p_valid) begin
                if (eh == et) begin errs = errs + 1; $display("ERRO: p_valid sem pedido"); end
                else begin
                    if ({p_fault, p_fault ? p_cause : 3'd0, p_fault ? 32'd0 : p_addr} !== ex[eh % 8192] && !exs[eh % 8192]) begin errs = errs + 1; if (errs < 12) $display("ERRO t=%0t: dut f=%b c=%0d a=%h  esperado f=%b c=%0d a=%h", $time, p_fault, p_cause, p_addr, ex[eh%8192][35], ex[eh%8192][34:32], ex[eh%8192][31:0]); end
                    if (ex[eh % 8192][35]) nflt = nflt + 1;
                    eh = eh + 1; nchk = nchk + 1; rv_cyc = cyc;
                end
            end
            if (!v_req || ready) begin
                if (v_req && ready) begin acc_cyc = cyc; ex[et % 8192] = refx(en, root, v_addr, v_acc, user); exs[et % 8192] = iss_s; et = et + 1; end
                if (qh != qt) begin iss_s = qs[qh % 8192]; v_req <= 1; v_addr <= qa[qh % 8192]; v_acc <= qc[qh % 8192]; user <= qu[qh % 8192]; qh = qh + 1; end
                else v_req <= 0;
            end
        end
    end
    task waitq; begin @(negedge clk); while (!quiet) @(negedge clk); repeat (3) @(negedge clk); while (!quiet) @(negedge clk); end endtask
    integer eb = 0, tot_f = 0; task rep(input [255:0] nome); begin if (errs != eb) begin $display("FALHA %0s: %0d erros", nome, errs - eb); tot_f = tot_f + 1; end else $display("ok   %0s (%0d traducoes conferidas ate aqui, %0d faltas)", nome, nchk, nflt); eb = errs; end endtask
    task pulse_asid(input [7:0] a); begin @(negedge clk); fl_asid_en = 1; fl_asid = a; @(negedge clk); fl_asid_en = 0; end endtask
    integer wk0;
    task chk_w(input integer esperado, input [255:0] nome); begin if (sw - wk0 != esperado) begin errs = errs + 1; $display("ERRO %0s: %0d caminhadas (esperado %0d)", nome, sw - wk0, esperado); end end endtask
    task pulse_all; begin @(negedge clk); fl_all = 1; @(negedge clk); fl_all = 0; end endtask
    task pulse_va(input [63:0] va); begin @(negedge clk); fl_va_en = 1; fl_va = va; @(negedge clk); fl_va_en = 0; end endtask
    // ---- testes
    integer n, k2, gerr, a_, seed; reg qk; initial qk = $test$plusargs("quick");
    reg [38:0] va_; reg [19:0] pp_; reg [7:0] fl_; integer lf_, T0, T1;
    reg [19:0] rootA, rootB;
    reg [63:0] vv;
    reg [63:0] ml [0:2047]; integer nml = 0;
    function [8:0] r4(input integer dummy); begin r4 = $urandom % 4; end endfunction
    task rand_tables(input [19:0] rt, input integer cnt);
        integer q;
        begin
            for (q = 0; q < cnt; q = q + 1) begin
                lf_ = ($urandom % 8 == 0) ? 1 : 0;
                va_ = {r4(0), 9'd0, 9'd0, 12'd0};   // VPN2 em 0..3
                va_[29:21] = $urandom % 6; va_[20:12] = (lf_ == 1) ? 9'd0 : ($urandom % 24);
                if ($urandom % 10 == 0) va_[38] = 1;   // endereco 'negativo' (canonico se estendido)
                pp_ = 20'd256 + ($urandom % 700); if (lf_ == 1) pp_ = {pp_[19:9], 9'd0} & 20'h003FF; if (lf_ == 1 && pp_ == 0) pp_ = 20'h200;
                fl_ = $urandom; fl_[0] = ($urandom % 12 != 0); fl_[6] = ($urandom % 6 != 0); fl_[7] = ($urandom % 3 != 0);
                if (fl_[2] && !fl_[1]) fl_[2] = 0;     // W sem R seria invalida (testada separadamente)
                if (fl_[3:1] == 0) fl_[1] = 1;
                if (lf_ == 1 && $urandom % 8 == 0) pp_[8:0] = 1 + ($urandom % 100);
                if ($urandom % 40 == 0) pp_ = 20'h40000 + ($urandom % 1000);   // fora da memoria
                map(rt, va_, pp_, fl_, lf_); ml[nml % 2048] = {{25{va_[38]}}, va_}; nml = nml + 1;
            end
        end
    endtask
    task rand_reqs(input integer cnt, input [19:0] rt_unused);
        integer q; reg [63:0] a; reg u;
        begin
            for (q = 0; q < cnt; q = q + 1) begin
                a = {25'd0, r4(0), 9'd0, 9'd0, 12'd0}; a[29:21] = $urandom % 6; a[20:12] = $urandom % 24; a[11:0] = $urandom; a[2:0] = 0;
                if ($urandom % 10 == 0) begin a[63:39] = {25{a[38]}}; a[38] = 1; a[63:39] = {25{1'b1}}; end else a[63:39] = 0;
                if (a[38] && $urandom % 10 != 0) a[63:39] = {25{1'b1}};
                if ($urandom % 50 == 0) a[50] = ~a[50];     // nao canonico
                if (nml > 0 && $urandom % 10 < 8) begin a = ml[$urandom % ((nml < 2048) ? nml : 2048)]; a[11:3] = $urandom; a[2:0] = 0; if (a[12+:9] == 0 && $urandom % 2) a[20:12] = $urandom; end
                push(a, $urandom % 3, $urandom % 2);
            end
        end
    endtask
    initial begin
        for (n = 0; n < 524288; n = n + 1) pm[n] = 64'd0;
        repeat (4) @(posedge clk); rst = 0; repeat (2) @(posedge clk);
        // T1: traducao desligada
        en = 0; push(64'h123456789ABC, 0, 0); push(64'hFFFF_0000_1234, 1, 1); waitq; rep("T1 en=0 identidade");
        // T2: mapeamento simples + latencias
        en = 1; root = 1; newroot(1); map(1, 39'h0000_4000, 20'd300, 8'b1100_1111, 0);   // V R W X, A, D (U=0)
        push(64'h4008, 0, 0); waitq; $display("T2 latencia de falha de TLB (1 pagina, 3 niveis): %0d clocks", rv_cyc - acc_cyc);
        push(64'h4010, 0, 0); waitq; $display("T2 latencia de acerto: %0d clock(s)", rv_cyc - acc_cyc);
        rep("T2");
        // T2b: vazao de acertos
        T0 = cyc; for (n = 0; n < 200; n = n + 1) push(64'h4000 + 8 * (n % 64), n % 2, 0); waitq; T1 = rv_cyc; $display("T2b 200 acertos seguidos: %0d clocks", T1 - T0 - 1); rep("T2b");
        // T3: permissoes
        pulse_all; newroot(1); nexttbl = 2;
        map(1, 39'h1000, 20'd301, 8'b0100_0011, 0);   // V R, A       -> so leitura
        map(1, 39'h2000, 20'd302, 8'b0100_0111, 0);   // V R W A (D=0)-> escrita da causa 3
        map(1, 39'h3000, 20'd303, 8'b1101_0111, 0);   // V R W U A D
        map(1, 39'h4000, 20'd304, 8'b1100_1001, 0);   // V X A D
        map(1, 39'h5000, 20'd305, 8'b1000_0011, 0);   // V R, A=0     -> causa 3
        for (n = 1; n <= 5; n = n + 1) begin for (k2 = 0; k2 < 3; k2 = k2 + 1) begin push(64'h1000 * n + 8, k2, 0); push(64'h1000 * n + 8, k2, 1); end end
        waitq; rep("T3 permissoes (R,W,X x usuario/supervisor)");
        pulse_all; for (n = 1; n <= 5; n = n + 1) for (k2 = 0; k2 < 3; k2 = k2 + 1) push(64'h1000 * n + 16, k2, k2 % 2); waitq; rep("T3b repete apos descarga");
        // T4: nao canonico, invalida, folha no nivel 2, megapagina desalinhada, fora da memoria
        push(64'h0001_0000_0000_1000, 0, 0); push(64'h7F00_0000_0000_1000, 0, 0); push(64'hFFFF_FFFF_FFFF_F000, 0, 0);
        pm[{10'd1, 9'd5}] = 64'h0000_0000_0000_0FCF;                    // folha no nivel 2 (VPN2=5)
        map(1, 39'h40_0000_0000 >> 0 & 39'h3F_FFFF_FFFF, 20'd400, 8'hCF, 1);   // possivel desalinhada
        pm[{10'd1, 9'd6}] = {34'd0, 20'd9, 10'd1};                       // nivel2 aponta p/ tabela 9 vazia
        map(1, 39'h2_0000_0000 + 39'h0020_0000, 20'h40001, 8'hCF, 0);   // PPN fora da memoria (>= 4 MB)
        push({25'd0, 39'h1_4000_0000}, 0, 0); push({25'd0, 39'h1_8000_0000}, 0, 0); push({25'd0, 39'h2_0020_0000}, 0, 0);
        push(64'h4020_0000, 0, 0); push(64'h6000_1000, 0, 0);
        waitq; rep("T4 faltas diversas");
        // T5: megapagina correta
        pulse_all; wk0 = sw; newroot(1); nexttbl = 2; map(1, 39'h0040_0000, 20'd512, 8'hCF, 1); map(1, 39'h0060_0000, 20'd1024 - 20'd512, 8'hCF, 1);
        for (n = 0; n < 40; n = n + 1) push(64'h0040_0000 + n * 64'h2468 , n % 3, 0); for (n = 0; n < 40; n = n + 1) push(64'h0060_0000 + n * 64'h1230, n % 2, 0);
        waitq; chk_w(2, "T5 megapagina reaproveitada"); rep("T5 megapaginas");
        // T6: PGINV e remapeamento
        newroot(1); nexttbl = 2; map(1, 39'h8000, 20'd310, 8'hCF, 0); push(64'h8000, 0, 0); waitq;
        map(1, 39'h8000, 20'd311, 8'hCF, 0); pulse_va(64'h8123); push(64'h8000, 0, 0); waitq; rep("T6 PGINV");
        map(1, 39'h8000, 20'd312, 8'hCF, 0); pulse_all; push(64'h8000, 0, 0); waitq; rep("T6b fl_all");
        // T7: dois espacos de enderecos com ASID e pagina global, sem descarga ao trocar
        rootA = 20'd1; rootB = 20'd20; nexttbl = 30; newroot(rootA); newroot(rootB);
        for (n = 0; n < 7; n = n + 1) begin map(rootA, 39'h1000 * n + 39'h10_0000, 20'd320 + n, 8'hCF, 0); map(rootB, 39'h1000 * n + 39'h10_0000, 20'd340 + n, 8'hCF, 0); end
        map(rootA, 39'h20_0000_0000 >> 8, 20'd360, 8'hEF, 0); map(rootB, 39'h20_0000_0000 >> 8, 20'd360, 8'hEF, 0);   // global (bit5)
        pulse_all; wk0 = sw;
        for (a_ = 0; a_ < 6; a_ = a_ + 1) begin
            asid = (a_ % 2) ? 8'd2 : 8'd1; root = (a_ % 2) ? rootB : rootA;
            for (n = 0; n < 7; n = n + 1) push(64'h10_0000 + 64'h1000 * n + 16, 0, 0);
            push(64'h20_0000_0000 >> 8, 0, 0);
            waitq;
        end
        if (NENT >= 16) chk_w(15, "T7 7+7+1 caminhadas"); rep("T7 ASID/global sem descarga");
        $display("   T7 apos a 1a passagem: TLB deve reaproveitar (walks=%0d)", sw);
        // T8: aleatorio com muita pressao na TLB (mais paginas que entradas), com troca de tabelas+descarga total
        for (seed = 0; seed < (qk ? 3 : 6); seed = seed + 1) begin
            root = 1; asid = 3 + seed; newroot(1); nexttbl = 2; nml = 0; rand_tables(1, 150 + 40 * seed);
            lat_min = (seed % 2) ? 1 : 4; lat_max = (seed % 2) ? 3 : 14;
            pulse_all; rand_reqs(qk ? 800 : 3000, 1); waitq;
        end
        rep("T8 aleatorio");
        // T9: descargas aleatorias no meio do trafego (alteracao de PTE + fl_all)
        begin : t9
            integer q;
            for (q = 0; q < (qk ? 15 : 40); q = q + 1) begin
                rand_reqs(80, 1); waitq;
                va_ = {r4(0), 9'd0, 9'd0, 12'd0}; va_[29:21] = $urandom % 6; va_[20:12] = $urandom % 24;
                map(1, va_, 20'd256 + ($urandom % 700), 8'hCF ^ (($urandom % 4) << 1), 0);
                pulse_all;
            end
            rep("T9 remapeamento + fl_all");
        end
        // T10: descarga concorrente com o caminhador (restart)
        begin : t10
            integer q;
            for (q = 0; q < (qk ? 45 : 90); q = q + 1) begin
                pulse_all; lat_min = 8; lat_max = 8;
                push_dc(64'h8000 + (q % 5) * 64'h1000, 0, 0);
                repeat (3 + (q % 36)) @(negedge clk);
                map(1, 39'h8000 + (q % 5) * 39'h1000, 20'd500 + q, 8'hCF, 0);   // muda durante a caminhada
                pulse_all;
                waitq;
                push(64'h8000 + (q % 5) * 64'h1000, 0, 0); waitq;
            end
            rep("T10 descarga durante a caminhada");
        end
        // T11: descarga em offsets variados em relacao a pedidos consecutivos (corrida estagio1->estagio2)
        begin : t11
            integer q, o, pg;
            lat_min = 4; lat_max = 6;
            for (q = 0; q < (qk ? 60 : 200); q = q + 1) begin
                pg = q % 6;
                pulse_all; waitq;
                map(1, 39'h8000 + pg * 39'h1000, 20'd500 + q, 8'hCF, 0); push(64'h8000 + pg * 64'h1000, 0, 0); waitq;
                map(1, 39'h8000 + pg * 39'h1000, 20'd600 + q, 8'hCF, 0);
                push_dc(64'h8000 + pg * 64'h1000, 0, 0); push_dc(64'h8008 + pg * 64'h1000, 0, 0);
                repeat (q % 7) @(negedge clk);
                pulse_va(64'h8000 + pg * 64'h1000);
                @(negedge clk); push(64'h8010 + pg * 64'h1000, 0, 0); push(64'h8018 + pg * 64'h1000, 1, 0);
                waitq;
            end
            rep("T11 PGINV em offsets variados");
        end
        // T12: PGINV numa megapagina com deslocamento de 4 KB diferente do usado no preenchimento
        asid = 1; root = 1; pulse_all; newroot(1); nexttbl = 2; map(1, 39'h40_0000, 20'd512, 8'hCF, 1); push(64'h40_5000, 0, 0); waitq;
        map(1, 39'h40_0000, 20'd0, 8'hCF, 1); pulse_va(64'h40_9000); push(64'h40_1000, 0, 0); waitq; rep("T12 PGINV em megapagina");
        // T13: descarga por ASID: so as paginas nao globais do ASID somem
        pulse_all; newroot(1); nexttbl = 2; asid = 1; root = 1; map(1, 39'h50_0000, 20'd320, 8'hCF, 0); map(1, 39'h51_0000, 20'd321, 8'hEF, 0);
        push(64'h50_0000, 0, 0); push(64'h51_0000, 0, 0); waitq; wk0 = sw;
        pulse_asid(8'd1); push(64'h50_0008, 0, 0); push(64'h51_0008, 0, 0); waitq; chk_w(1, "T13 fl_asid preserva global"); rep("T13 descarga por ASID");
        wk0 = sw; pulse_asid(8'd9); push(64'h50_0010, 0, 0); push(64'h51_0010, 0, 0); waitq; chk_w(0, "T13b fl_asid de outro ASID nao descarrega"); rep("T13b");
        $display("Estatisticas: acertos=%0d falhas(walks)=%0d faltas=%0d leituras de PTE=%0d", sh, sw, sf, nmemrd);
        if (errs == 0) $display("RESULTADO: TODOS OS TESTES PASSARAM"); else $display("RESULTADO: %0d ERROS", errs);
        $finish;
    end
    initial begin #800000000; $display("TIMEOUT"); $finish; end
endmodule
