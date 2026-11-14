// r8064_core_min.v - NUCLEO MINIMO SINTETIZAVEL do R8064 (esqueleto para medir area/Fmax do orcamento enxuto).
// NAO e o nucleo final: executa um subconjunto de microoperacoes dirigido por ROM de microoperacoes (uop.mem, 96 bits; os arquivos antigos de 80 bits continuam validos: os bits 80-95 ficam em 0).
// O que e REAL (estrutura e largura): fila de prefetch 32 B + alinhador de 13 bytes, decodificador ED real (ROM_A/ROM_B/ctrl), ROM de pagina principal,
//   ROM de uops em BSRAM, banco de 64x64 (BSRAM, 3 leituras), mapeamento de registradores (EXX/EX AF), extracao de imediato, forwarding (X2/M/W) com
//   interlock de carga-uso, ALU de 2 estagios (alu_prep/alu_core do modulo 01), somador de enderecos, somador de alvo de desvio, LSU de 64 bits com
//   alinhamento/extensao, flags, desvio resolvido em X2 (esvazia fila), timer 64 bits + interrupcao.
// O que NAO esta aqui: semantica das ~1.480 instrucoes (uops reais), CALL/RET/PUSH/POP multi-passo, E/S, MMU/FPU, hazards de escrita parcial (WAW), 1 instrucao/clock
//   (este front-end emite 1 instrucao a cada 4 clocks: ROM A/B -> ROM ctrl/uop em serie; ver resultados).
module r8064_core_min #(
    parameter UOP_FILE   = "uop.mem",
    parameter MAINC_FILE = "mainctrl.mem"
)(
    input  wire        clk, rst, irq,
    output wire        i_req,
    output wire [63:0] i_addr,
    input  wire        i_ack,
    input  wire [63:0] i_rdata,
    output wire        d_req,
    output wire        d_we,
    output wire [63:0] d_addr,
    output wire [1:0]  d_size,
    output wire [63:0] d_wdata, output wire [7:0] d_be,
    input  wire        d_ack,
    input  wire [63:0] d_rdata,
    // excecoes de traducao (pulso alinhado ao ack) e controle da MMU/caches (CR46..49)
    input  wire        i_flt, d_flt, input wire [2:0] i_cs, d_cs,
    output wire        cr_mmu_en, cr_mmu_user, output wire [7:0] cr_asid, output wire [19:0] cr_root,
    output wire        cr_fl_all, cr_fl_va_en, cr_fl_asid_en, output wire [63:0] cr_fl_va, output wire [7:0] cr_fl_asid, output wire cr_cinv,
    output wire [63:0] dbg_pc,
    output wire [7:0]  dbg_f,
    output wire        dbg_sig,
    // governador de tempo (modos Z80/R800): gov_go segura a emissao; gov_* descrevem a instrucao candidata
    input  wire        gov_go,
    input  wire        gov_wait,        // 1 = modos governados (Z80/R800): uma fase extra de decodificacao para a tabela de tempo
    input  wire [7:0]  port_c,          // registrador C (porta das formas IN r,(C) / OUT (C),r), fornecido pelo invólucro
    output wire [2:0]  gov_page,
    output wire [7:0]  gov_op,
    output wire [7:0]  gov_port,
    output wire        gov_cv,
    output wire        gov_alt_ev,
    output wire        gov_boundary,
    output wire        io_we, io_re, output wire [7:0] io_a, io_wd, input wire [7:0] io_rdata,   // E/S de 8 bits (IN/OUT)
    output wire [15:0] gov_pc,          // endereco da instrucao candidata
    output wire [3:0]  gov_len,         // comprimento (bytes) da candidata
    output wire        gov_dev,         // acesso de dados concluido
    output wire [15:0] gov_daddr,
    output wire [1:0]  gov_dsize,
    output wire        gov_dwe
);
    // ============ controle global ============
    wire hold;                    // M esperando o barramento de dados
    wire flush_br;                // desvio tomado (X2)
    wire irq_take;                // interrupcao aceita
    reg iff2; reg [1:0] im; reg [7:0] ireg; reg irq_ent;   // im: 0/1 = RST 38h, 2 = vetorizado por I, 3 = legado (salta para 'vec', sem empilhar)
    wire irq_new = (im != 2'd3);
    reg [63:0] npc, epc; reg irq_taken_q;
    // flush REGISTRADO (corta flags -> condicao -> flush -> reset de todo o front-end): desvio tomado custa +1 clock
    reg [63:0] pc_last;   // PC da ultima instrucao emitida: a proxima so e emitida >= 6 clocks depois da ultima uop (decodificacao), entao ao chegar em M a uop e sempre da ultima instrucao
    wire ex_take, ex_take_d; reg ex_act; reg [1:0] exk; reg ex_isd, ex_we; reg [2:0] ex_cs;
    wire flush_raw = flush_br | (irq_take & ~irq_new) | ex_take;
    reg  flush_q; reg [63:0] flush_tgt_q;
    wire flush = flush_q;
    wire [63:0] flush_tgt = flush_tgt_q;
    wire [63:0] flush_tgt_raw;
    always @(posedge clk) begin
        if (rst) flush_q <= 1'b0; else flush_q <= flush_raw;
        flush_tgt_q <= flush_tgt_raw;
    end
    reg  [63:0] dpc_q;
    reg  [7:0]  fl;
    wire [63:0] ldval;
    reg  [63:0] tmr, tcmp, vec; reg ie, irq_pend, irq_q;

    // ============ F: busca + fila de 32 bytes ============
    reg [63:0] qw0, qw1, qw2, qw3;
    reg [1:0]  wp;
    reg [5:0]  qcnt;
    reg [4:0]  qoff;
    reg [2:0]  skip;
    reg        drop, ireq_r;
    reg        ifp; reg [63:0] ifa; reg [2:0] ifc;     // falta de busca pendente: endereco da palavra e causa
    reg [63:0] fa;
    assign i_req  = ireq_r;
    assign i_addr = fa;
    wire consume; wire [3:0] clen;
    wire got = i_ack && ireq_r && !drop;
    wire [5:0] addn = got ? (6'd8 - {3'd0, skip}) : 6'd0;
    wire [5:0] subn = consume ? {2'd0, clen} : 6'd0;
    always @(posedge clk) begin
        if (rst) begin wp <= 0; qcnt <= 0; qoff <= 0; skip <= 0; drop <= 0; ireq_r <= 0; fa <= 64'd0; ifp <= 1'b0; ifa <= 64'd0; ifc <= 3'd0; end
        else if (flush) begin
            wp <= 0; qcnt <= 0; qoff <= {2'b00, flush_tgt[2:0]}; skip <= flush_tgt[2:0]; fa <= {flush_tgt[63:3], 3'b000};
            drop <= 1'b0; ireq_r <= 1'b0; ifp <= 1'b0;   // requisicao pode ser retirada antes do ack (a interface de busca do cache aceita cancelar)
        end else begin
            if (i_ack && ireq_r) begin
                ireq_r <= 1'b0;
                if (drop) drop <= 1'b0;
                else begin
                    case (wp) 2'd0: qw0 <= i_rdata; 2'd1: qw1 <= i_rdata; 2'd2: qw2 <= i_rdata; default: qw3 <= i_rdata; endcase
                    wp <= wp + 2'd1; fa <= fa + 64'd8; skip <= 3'd0;
                    if (i_flt && !ifp) begin ifp <= 1'b1; ifa <= fa; ifc <= i_cs; end
                end
            end else if (!ireq_r && !drop && qcnt <= 6'd24) ireq_r <= 1'b1;
            qcnt <= qcnt + addn - subn;
            if (consume) qoff <= qoff + {1'b0, clen};
        end
    end
    // alinhador: 3 palavras consecutivas a partir de qoff[4:3], depois deslocamento de bytes (qoff[2:0]) -> janela de 13 bytes
    reg [191:0] rot;
    always @* case (qoff[4:3])
        2'd0: rot = {qw2, qw1, qw0};
        2'd1: rot = {qw3, qw2, qw1};
        2'd2: rot = {qw0, qw3, qw2};
        default: rot = {qw1, qw0, qw3};
    endcase
    wire [191:0] shf = rot >> {qoff[2:0], 3'b000};
    wire [103:0] win = shf[103:0];

    // ============ D: sequenciador de decodificacao (4 fases) ============
    reg [2:0]   ds;               // 0 captura, 1 ROM A/B, 2 ROM ctrl/uop, 3 emissao (6 nos modos governados: comprimento -> classificador -> tabela de tempo)
    wire [2:0]  ds_last = gov_wait ? 3'd7 : 3'd5;   // 4 sem governador: os indices de registrador sao registrados antes de enderecar o banco
    reg         dv;               // dwin valido
    reg [103:0] dwin;
    reg [103:0] win_q; reg wq_v;      // snapshot da janela (corta o caminho fila -> alinhador -> ROM do decodificador)
    reg [63:0]  dpc;              // endereco da instrucao em decodificacao
    // prefixo de banco: ED 0B (sombra) / ED 0E (N0-N3) / ED 0D (N4-N7) antes de instrucao da pagina ED
    reg [1:0]   bank;             // 0 nenhum, 1 sombra, 2 N0-N3, 3 N4-N7 (registrado na captura)
    wire pfx_w = (win_q[7:0] == 8'hED) && (win_q[15:8] == 8'h0B || win_q[15:8] == 8'h0E || win_q[15:8] == 8'h0D);
    wire bank_on = (bank != 2'd0);
    wire [7:0] b1 = dwin[7:0], b2 = dwin[15:8], b3 = dwin[23:16];
    reg is_cb;                    // prefixo CB: a uop vem da regiao 768 + segundo byte
    // prefixo DD / FD (IX / IY): removido da janela na captura, como o prefixo de banco. A instrucao usa a MESMA uop da pagina principal:
    // o indice HL (3) vira IX/IY (9/10), menos nos operandos marcados (u[90]: D e B; u[91]: A), e as uops com u[92] somam o deslocamento d ao endereco.
    // DD/FD seguido de DD, FD ou ED nao e tratado como prefixo (executa como NOP de 1 byte e o byte seguinte comeca outra instrucao).
    reg [1:0]   xy;               // 0 nenhum, 1 IX, 2 IY
    wire xy_on = (xy != 2'd0);
    wire pfx_xy = (win_q[7:0] == 8'hDD || win_q[7:0] == 8'hFD) && !(win_q[15:8] == 8'hDD || win_q[15:8] == 8'hFD || win_q[15:8] == 8'hED);
    reg is_ed;                    // registrado na captura (corta o comparador de 8 bits do caminho clen)
    wire [9:0] ed_id; wire ed_ill; wire [3:0] ed_len; wire [4:0] ed_nr, ed_nw; wire [1:0] ed_nio; wire [7:0] ed_ex; wire [1:0] ed_pen; wire ed_hc, ed_z80, ed_bk;
    r8064_decode u_dec(.clk(clk), .b2(b2), .b3(b3), .id(ed_id), .illegal(ed_ill), .len(ed_len), .nr(ed_nr), .nw(ed_nw), .nio(ed_nio), .ex(ed_ex), .pen_code(ed_pen), .has_cond(ed_hc), .is_z80(ed_z80), .bankable(ed_bk));
    reg [31:0] mainc [0:255];
    reg [95:0] uopm  [0:2047];
    initial begin $readmemh(MAINC_FILE, mainc); $readmemh(UOP_FILE, uopm); end
    reg [31:0] mainc_q; reg [95:0] uop_q;
    // sequenciador de microoperacoes: u[49]=mais uops, u[62:52]=endereco da proxima. Espaco: principal 0-255, ED 256+id, CB 768-1023, DDCB/FDCB 1792-2047, cadeias 1024-1791
    reg seq; reg [10:0] nxt_r; reg [2:0] seqc;
    wire [10:0] base_a = irq_ent ? (im == 2'd2 ? 11'd601 : 11'd600) : is_ed ? (11'd256 + {1'b0, ed_id}) : is_cb ? (xy_on ? {3'b111, b3} : {3'b011, b2}) : {3'b000, b1};   // DD CB d op: regiao 1792 + op
    wire [10:0] uaddr = seq ? nxt_r : base_a;
    always @(posedge clk) begin mainc_q <= mainc[b1]; uop_q <= uopm[uaddr]; end
    // comprimento registrado: o valor cru (ROM de controle -> mux ED/principal -> +prefixo) fica estavel desde ds=2 e so e consumido em ds_last (>=4);
    // o registrador tira a saida da BSRAM e o somador de 4 bits do caminho dos somadores de PC (dpc+clen, qoff+clen)
    wire [3:0] clen_raw = irq_ent ? 4'd0 : (is_ed ? ed_len : mainc_q[3:0]) + {3'd0, bank_on} + {3'd0, xy_on} + {3'd0, xy_on && mainc_q[4]};   // mainc[4]: operando (HL) -> +1 byte (d) com DD/FD
    reg [3:0] clen_r; always @(posedge clk) clen_r <= clen_raw;
    assign clen = clen_r;
    reg ifx_q; reg [7:0] ifd_q;
    reg hz_q;   // interlock de escrita parcial (ver abaixo)
    wire issue = dv && (ds == ds_last) && !hold && !flush && (gov_go || seq) && (seqc == 3'd0) && !hz_q && !(ifx_q && !seq);
    wire u_last = !uop_q[49];
    assign consume = issue && u_last;
    always @(posedge clk) begin
        if (rst || flush) begin seq <= 1'b0; seqc <= 3'd0; end
        else begin
            if (seqc != 3'd0 && !hold) seqc <= seqc - 3'd1;   // so conta quando o pipeline avanca (um hold congela os produtores)
            if (issue && !u_last) begin seq <= 1'b1; nxt_r <= uop_q[62:52]; seqc <= (uop_q[10] && (uop_q[8] || uop_q[50])) ? 3'd4 : 3'd3; end   // 4 clocks entre uops (encaminhamento X3/M); 5 apos carga/IN: o dado alinhado so e encaminhado de W
            else if (issue) seq <= 1'b0;
        end
    end
    always @(posedge clk) begin
        if (rst || flush) begin ds <= 0; dv <= 0; wq_v <= 0; irq_ent <= 1'b0; xy <= 2'd0; end
        else if (irq_take && irq_new) begin
            // entrada de interrupcao: pseudo-instrucao (opcode FF para o governador) que empilha o PC e salta (IM0/1: 0038h; IM2: [I:FF])
            irq_ent <= 1'b1; dv <= 1'b1; ds <= 0; wq_v <= 0; dpc <= npc; is_ed <= 1'b0; is_cb <= 1'b0; bank <= 2'd0; xy <= 2'd0;
            dwin <= (im == 2'd2) ? {72'd0, ireg, 8'hFF, 8'hFF} : {80'd0, 16'h0038, 8'hFF};   // IM2: bytes 1..2 = [I:FF]
        end else if (!dv) begin
            if (!wq_v) begin
                if (qcnt >= 6'd13 && !hold) begin win_q <= win; wq_v <= 1; end
            end else begin
                dwin <= pfx_w ? {8'h00, win_q[103:16], 8'hED} : pfx_xy ? {8'h00, win_q[103:8]} : win_q;   // remove o prefixo de banco (ED <pfx> op ... -> ED op ...) ou o DD/FD
                xy <= !pfx_xy ? 2'd0 : (win_q[7:0] == 8'hDD) ? 2'd1 : 2'd2;
                bank <= pfx_w ? ((win_q[15:8] == 8'h0B) ? 2'd1 : (win_q[15:8] == 8'h0E) ? 2'd2 : 2'd3) : 2'd0;
                is_ed <= (win_q[7:0] == 8'hED);
                is_cb <= pfx_xy ? (win_q[15:8] == 8'hCB) : (win_q[7:0] == 8'hCB);
                wq_v <= 0; dv <= 1; ds <= 0; dpc <= dpc_q;
            end
        end else if (ds != ds_last) begin if (!hold) ds <= ds + 3'd1; end   // idem: fases de decodificacao so avancam com o pipeline andando
        else if (consume) begin dv <= 0; ds <= 0; irq_ent <= 1'b0; end
    end
    // contador de PC (endereco da proxima instrucao)
    always @(posedge clk) begin
        if (rst) dpc_q <= 64'd0;
        else if (flush) dpc_q <= flush_tgt;
        else if (consume) dpc_q <= dpc + {60'd0, clen};
    end

    // ============ emissao: campos, registradores, imediato ============
    reg sw_main, sw_af;
    wire [95:0] u = uop_q;
    wire f_pos = u[20];
    wire [7:0] fb = is_ed ? b3 : b1;          // pagina ED: campos de registrador vem do byte modificador (b3)
    wire [2:0] rrD = f_pos ? fb[5:3] : fb[2:0];
    wire [2:0] rrA = f_pos ? fb[2:0] : fb[5:3];
    wire [2:0] rrB = u[64] ? b1[5:3] : is_ed ? b3[2:0] : b2[2:0];
    wire [5:0] mD, mA, mB; wire vD, vA, vB;
    regmap_b u_md(.rr(rrD), .swap_main(sw_main), .swap_af(sw_af), .bank(bank), .idx(mD), .valid(vD));
    regmap_b u_ma(.rr(rrA), .swap_main(sw_main), .swap_af(sw_af), .bank(bank), .idx(mA), .valid(vA));
    regmap_b u_mb(.rr(rrB), .swap_main(sw_main), .swap_af(sw_af), .bank(bank), .idx(mB), .valid(vB));
    // instrucao banqueada ilegal: id ilegal, sem operando bancavel, operando de 8 bits em banco N, IX/IY em banco, ou prefixo + 13 bytes
    wire bank_ill = bank_on && (ed_ill || !ed_bk || (bank[1] && uop_q[6:5] == 2'd0) || ed_len > 4'd12 ||
                                (uop_q[17] && !vD) || (uop_q[18] && !vA) || (uop_q[19] && !vB));
    wire en_ill = is_ed && (ed_ill || bank_ill);   // ilegal (excecao: neste esqueleto vira NOP sem escrita)
    wire [5:0] crn = {1'b1, b3[4:0]};            // MTCR/MFCR: CR n = indice 32+n do banco (ED 0A n = MFCR, ED 0C n = MTCR)
    // indices EXPLICITOS da uop (0 AX, 1 BC, 2 DE, 3 HL) tambem obedecem a EXX / EX AF,AF' (antes so os campos rr obedeciam: LDIR apos EXX usava o grupo errado)
    function [5:0] xsw(input [5:0] i, input sm, input sa, input [1:0] ix);   // sm/sa/ix como argumentos: a funcao e reavaliada quando a troca muda
        xsw = (i == 6'd3 && ix != 2'd0) ? (ix == 2'd1 ? 6'd9 : 6'd10) :
              (i == 6'd0) ? (sa ? 6'd5 : 6'd0) : (i >= 6'd1 && i <= 6'd3 && sm) ? (i + 6'd5) : i;
    endfunction
    wire [1:0] xy_db = u[90] ? 2'd0 : xy, xy_a = u[91] ? 2'd0 : xy;
    wire [5:0] iD = u[77] ? crn : u[17] ? mD : xsw(u[26:21], sw_main, sw_af, xy_db);
    wire [5:0] iA = u[47] ? iD : u[78] ? crn : (u[18] ? mA : xsw(u[32:27], sw_main, sw_af, xy_a));   // u[47]: fonte A = destino (2 operandos)
    wire [5:0] iB = u[19] ? mB : xsw(u[38:33], sw_main, sw_af, xy_db);
    // indices registrados (estaveis >= 1 clock antes da emissao): tira ROM de uop -> regmap -> endereco do banco do mesmo ciclo
    reg [5:0] iA_q, iB_q, iD_q;
    always @(posedge clk) begin iA_q <= iA; iB_q <= iB; iD_q <= iD; end
    wire [103:0] ish = (xy_on && u[93]) ? (dwin >> 16) : (dwin >> {u[41:39], 3'b000});   // u[93]: com DD/FD o imediato vem depois do deslocamento (LD (IX+d),n)
    reg [63:0] immv;
    always @* case (u[43:42])
        2'd0: immv = u[44] ? {{56{ish[7]}},  ish[7:0]}  : {56'd0, ish[7:0]};
        2'd1: immv = u[44] ? {{48{ish[15]}}, ish[15:0]} : {48'd0, ish[15:0]};
        2'd2: immv = u[44] ? {{32{ish[31]}}, ish[31:0]} : {32'd0, ish[31:0]};
        default: immv = ish[63:0];
    endcase
    always @(posedge clk) begin
        if (rst) begin sw_main <= 0; sw_af <= 0; end
        else if (issue) begin
            if (u[45] && u[46]) begin sw_main <= 1'b0; sw_af <= 1'b0; end  // EXINI (exx+exaf juntos): volta ao estado de reset: grupo principal E AF (desfaz EXX e EX AF,AF')
            else begin if (u[45]) sw_main <= ~sw_main; if (u[46]) sw_af <= ~sw_af; end
        end
    end

    // ============ banco de registradores (3 leituras: A, B e valor antigo do destino) ============
    reg         v_xr; reg [95:0] u_xr; reg [63:0] pcn_xr, imm_xr, pc_xr; reg [5:0] a_xr, b_xr, d_xr; reg [2:0] ob3_xr; reg xyd_xr; reg [7:0] dsp_xr;
    // sob hold o estagio XR fica parado: o endereco de leitura passa a ser o dele (a_xr/b_xr/d_xr), senao a saida sincrona do banco seguiria o candidato seguinte
    wire [63:0] rf_a, rf_b, rf_d;
    wire        w_we; wire [5:0] w_addr; wire [63:0] w_data;
    regfile64 u_rf1(.clk(clk), .we(w_we), .waddr(w_addr), .wdata(w_data), .raddr_a(hold ? a_xr : iA_q), .raddr_b(hold ? b_xr : iB_q), .rdata_a(rf_a), .rdata_b(rf_b));
    regfile64 u_rf2(.clk(clk), .we(w_we), .waddr(w_addr), .wdata(w_data), .raddr_a(hold ? d_xr : iD_q), .raddr_b(6'd0), .rdata_a(rf_d), .rdata_b());

    // ============ XR: leitura + forwarding ============
    wire        flush_x = flush;
    always @(posedge clk) begin
        if (rst || flush_x) v_xr <= 0;
        else if (!hold) begin
            if (issue) pc_last <= dpc;
            v_xr <= issue && !en_ill; u_xr <= u; imm_xr <= u[63] ? 64'd0 : immv; pcn_xr <= dpc + {60'd0, clen}; pc_xr <= dpc; a_xr <= iA_q; b_xr <= iB_q; d_xr <= iD_q; ob3_xr <= ish[5:3]; xyd_xr <= xy_on && u[92]; dsp_xr <= dwin[15:8];
        end
    end
    // X2 / M / W produzem os valores a encaminhar
    reg [63:0] st_x1, old_x1;   // dado de escrita / valor antigo do destino acompanham a instrucao em X1 (antes eram sobrescritos a cada clock)
    reg         v_x1; reg [95:0] u_x1; reg [63:0] opa_x1, opb_x1, imm_x1, pcn_x1, pc_x1; reg [5:0] d_x1;
        reg         v_x2; reg [95:0] u_x2; reg [63:0] xa_x2, yb_x2, yy_x2, addr_x2, tgt_x2, st_x2, old_x2; reg ci_x2; reg [21:0] ctl_x2; reg [5:0] d_x2; reg [7:0] f_x2in;
    reg         v_m;  reg [95:0] u_m;  reg [63:0] res_m, addr_m, st_m, old_m; reg [5:0] d_m; reg dn_m;
    reg         v_w;  reg [95:0] u_w;  reg [63:0] res_w, old_w; reg [5:0] d_w;
    // ALU em 2 estagios: A em X2 (soma baixa 32 b), B em X3 (soma alta 32 b + flags). Resultado/flags validos no estagio X3.
    reg         v_x3; reg [95:0] u_x3; reg [63:0] addr_x3, st_x3, old_x3; reg [5:0] d_x3;
    wire [63:0] x3_res; wire [7:0] x3_f; wire x3_hc12; wire [1:0] x3_xa53;
    alu_core_s u_core(.clk(clk), .en(!hold), .xa(xa_x2), .yb(yb_x2), .yy(yy_x2), .ci(ci_x2), .ctl(ctl_x2), .sz(u_x2[6:5]), .fin(fl), .res(x3_res), .fout(x3_f), .xa53(x3_xa53), .hc12(x3_hc12));
    wire [63:0] m_fwd = ldval;                    // valor de carga (ou resultado) do estagio M
    wire x3_wr = v_x3 && u_x3[10] && !u_x3[8] && !u_x3[50];    // resultado de ALU disponivel (estagio X3)
    wire m_wr  = v_m  && u_m[10];
    wire w_wr  = v_w  && u_w[10];
    // encaminhamento: X3 (ALU) > M (resultado de ALU/endereco: res_m) > W (res_w, ja com o dado de carga alinhado).
    // O dado de CARGA/IN nunca e encaminhado de M (o alinhador de 64 bits + extensao de sinal ficava no meio do caminho): o interlock hz espera a carga chegar em W.
    // seletores de forwarding PRE-CALCULADOS no clock anterior (comparadores fora do caminho critico XR -> X1).
    // Como as instrucoes sao emitidas com >=4 clocks de intervalo, o produtor em X3 nunca coincide com o consumidor em XR: o ramo X3 foi removido.
    wire        nx_hold_c = hold;
    wire [5:0]  nx_a = (rst || flush_x || hold) ? a_xr : iA_q;
    wire [5:0]  nx_b = (rst || flush_x || hold) ? b_xr : iB_q;
    wire        nx_vm  = rst ? 1'b0 : ex_take_d ? 1'b0 : hold ? v_m : v_x3;
    wire        nx_m_wr = nx_vm && (hold ? u_m[10] : u_x3[10]);
    wire [5:0]  nx_dm  = hold ? d_m : d_x3;
    wire        nx_vw  = rst ? 1'b0 : ex_act ? 1'b1 : (v_m && !hold && !ex_take_d);
    wire        nx_w_wr = nx_vw && (ex_act ? 1'b1 : u_m[10]);
    wire [5:0]  nx_dw  = ex_act ? ((exk == 2'd0) ? 6'd44 : (exk == 2'd1) ? 6'd43 : 6'd45) : d_m;
    reg sm_a, sw_a, sm_b, sw_b;
    always @(posedge clk) begin
        sm_a <= nx_m_wr && (nx_dm == nx_a);
        sw_a <= nx_w_wr && (nx_dw == nx_a) && !(nx_m_wr && (nx_dm == nx_a));
        sm_b <= nx_m_wr && (nx_dm == nx_b);
        sw_b <= nx_w_wr && (nx_dw == nx_b) && !(nx_m_wr && (nx_dm == nx_b));
    end
    wire [63:0] fa_a = sm_a ? res_m : sw_a ? res_w : rf_a;
    wire [63:0] fa_b = sm_b ? res_m : sw_b ? res_w : rf_b;
    // interlock de carga-uso: instrucao em XR depende de carga em X1/X2/M -> segura em XR
    wire ld_dep = v_xr && ((v_x3 && u_x3[8] && u_x3[10] && (d_x3 == a_xr || d_x3 == b_xr)) ||
                           (v_x1 && u_x1[8] && u_x1[10] && (d_x1 == a_xr || d_x1 == b_xr)) ||
                           (v_x2 && u_x2[8] && u_x2[10] && (d_x2 == a_xr || d_x2 == b_xr)) ||
                           (v_m  && u_m[8]  && u_m[10]  && (d_m  == a_xr || d_m  == b_xr)));
    // (ld_dep nao e usado para travar neste esqueleto de 1 instrucao a cada 4 clocks, mas o comparador e contado na area)
    reg ld_dep_q; always @(posedge clk) ld_dep_q <= ld_dep;

    // ============ X1: seleciona operandos B/imediato; AGU e alvo de desvio ============
    // imediato constante -(1<<isz) (uop[79], PUSH/CALL/INT): escolhido aqui, a partir de u_xr registrado, e nao na saida da ROM de uops (caminho BSRAM -> imm_xr era o critico)
    // u[88:87] = imediato derivado dos bits [5:3] do byte apontado por ioff: 1 = vetor de RST (n*8) | 2 = mascara de bit (1<<n) | 3 = mascara invertida
    wire [7:0]  bitm_xr = 8'd1 << ob3_xr;
    wire [63:0] immk_xr = xyd_xr ? {{56{dsp_xr[7]}}, dsp_xr} :      // (IX+d) / (IY+d)
                          u_xr[79] ? (64'hFFFF_FFFF_FFFF_FFFF << u_xr[43:42]) :
                          (u_xr[88:87] == 2'd1) ? {58'd0, ob3_xr, 3'b000} : (u_xr[88:87] == 2'd2) ? {56'd0, bitm_xr} : (u_xr[88:87] == 2'd3) ? {56'd0, ~bitm_xr} : imm_xr;
    // operando B: u[89] = flags (F) | u[80] = registrador >> 8 (byte alto: B, D, H)
    wire [63:0] fb_b = u_xr[89] ? {56'd0, fl} : u_xr[80] ? (fa_b >> 8) : fa_b;
    always @(posedge clk) begin
        if (rst || flush) v_x1 <= 0;
        else if (!hold) begin
            v_x1 <= v_xr; u_x1 <= u_xr; opa_x1 <= u_xr[72] ? (fa_a >> 8) : fa_a; opb_x1 <= u_xr[7] ? immk_xr : fb_b; imm_x1 <= immk_xr; pcn_x1 <= pcn_xr; pc_x1 <= pc_xr; d_x1 <= d_xr;
            st_x1 <= u_xr[65] ? pcn_xr : fb_b; old_x1 <= rf_d;
        end
    end
    wire [63:0] xa, yb, yy; wire ci; wire [21:0] ctl;
    alu_prep u_prep(.a(opa_x1), .b(opb_x1), .op(u_x1[4:0]), .sz(u_x1[6:5]), .fin(fl), .xa(xa), .yb(yb), .yy(yy), .ci(ci), .ctl(ctl));
    always @(posedge clk) begin
        if (rst || flush) v_x2 <= 0;
        else if (!hold) begin
            v_x2 <= v_x1; u_x2 <= u_x1; xa_x2 <= xa; yb_x2 <= yb; yy_x2 <= yy; ci_x2 <= ci; ctl_x2 <= ctl; d_x2 <= d_x1;
            st_x2 <= st_x1; old_x2 <= old_x1;
            addr_x2 <= opa_x1 + imm_x1;
            tgt_x2 <= u_x1[70] ? pc_x1 : u_x1[66] ? (opa_x1 + imm_x1) : u_x1[15] ? (pcn_x1 + imm_x1) : opa_x1;
        end
    end

    // fusao de flags das instrucoes de bloco: u[69:68] = 0 ALU normal | 1 so PV := (res != 0) | 2 S,Z,H,N da ALU (mantem PV e C) | 3 PV := (res != 0), H = N = 0
    wire [63:0] szm = (u_x3[6:5] == 2'd0) ? 64'hFF : (u_x3[6:5] == 2'd1) ? 64'hFFFF : (u_x3[6:5] == 2'd2) ? 64'hFFFF_FFFF : 64'hFFFF_FFFF_FFFF_FFFF;
    wire nzres = |(x3_res & szm);
    reg [7:0] f_new0; wire [7:0] f_leg = {f_new0[7:3], (u_x3[76:74] == 3'd7) ? iff2 : f_new0[2], f_new0[1], u_x3[73] ? fl[0] : f_new0[0]};   // u[73]: mantem C (IN r,(C))
    // u[85:82] = fop: regras de flags do Z80 que nao saem direto da ALU (0 = comportamento anterior)
    reg [7:0] f_new;
    always @* case (u_x3[85:82])
        4'd1: f_new = {fl[7:6], x3_res[5], 1'b0, x3_res[3], fl[2], 1'b0, x3_f[0]};                 // RLCA/RRCA/RLA/RRA: so C, H=N=0, X/Y do resultado
        4'd2: f_new = {fl[7:6], x3_res[13], x3_hc12, x3_res[11], fl[2], 1'b0, x3_f[0]};            // ADD HL,rr: C, H (bit 11), N=0, X/Y do byte alto
        4'd3: f_new = {x3_f[7:6], x3_res[13], x3_hc12, x3_res[11], x3_f[2:0]};                     // ADC/SBC HL,rr: todas, H e X/Y do byte alto
        4'd4: f_new = {fl[7:6], x3_res[5], 1'b0, x3_res[3], fl[2], 1'b0, 1'b1};                    // SCF (resultado = A)
        4'd5: f_new = {fl[7:6], x3_res[5], fl[0], x3_res[3], fl[2], 1'b0, ~fl[0]};                 // CCF (resultado = A)
        4'd7: f_new = {x3_f[7:6], x3_xa53[1], 1'b1, x3_xa53[0], x3_f[2], 1'b0, fl[0]};               // BIT n,r (AND com a mascara): Z/PV/S do resultado, X/Y do operando
        4'd6: f_new = x3_res[7:0];                                                                 // F := resultado (POP AF)
        default: f_new = f_leg;
    endcase
    always @* case (u_x3[69:68])
        2'd0: f_new0 = x3_f;
        2'd1: f_new0 = {fl[7:3], nzres, fl[1:0]};
        2'd2: f_new0 = {x3_f[7:3], fl[2], x3_f[1], fl[0]};
        default: f_new0 = {fl[7:5], 1'b0, fl[3], nzres, 1'b0, fl[0]};
    endcase
    // ============ X2: ALU (nucleo), flags, desvio ============
    wire [7:0] f = fl;
    reg cond_ok0;
    always @* case (u_x2[14:12])
        3'd0: cond_ok0 = 1'b1;
        3'd1: cond_ok0 = f[6];
        3'd2: cond_ok0 = !f[6];
        3'd3: cond_ok0 = f[0];
        3'd4: cond_ok0 = !f[0];
        3'd5: cond_ok0 = f[2];
        3'd6: cond_ok0 = !f[2];
        default: cond_ok0 = f[7];
    endcase
    // u[81] = condicoes estendidas: 0 = P (S=0) | 1 = tz (resultado zero da uop marcada com u[86]; DJNZ nao altera flags) | 2 = nao-tz
    reg tz;
    wire cond_x = (u_x2[14:12] == 3'd0) ? !f[7] : (u_x2[14:12] == 3'd1) ? tz : !tz;
    wire cond_ok = u_x2[81] ? cond_x : u_x2[71] ? (f[2] && !f[6]) : cond_ok0;     // u[71]: PV e nao-Z (CPIR/CPDR)
    assign flush_br = v_x2 && !flush_q && u_x2[11] && cond_ok && !hold;
    // pipeline vazio e 'issue' do ciclo anterior registrados (tira a conjuncao dos v_* do caminho da interrupcao); o termo issue_q cobre o ciclo em que o vazio registrado ainda esta atrasado
    reg pipe_empty_q, issue_q;
    always @(posedge clk) begin pipe_empty_q <= !v_xr && !v_x1 && !v_x2 && !v_x3 && !v_m && !v_w; issue_q <= issue; end
    // EI so vale depois da instrucao seguinte: ei_cnt = 1 apos o EI sair do decodificador; qualquer outra instrucao concluida zera
    reg ei_cnt;
    always @(posedge clk) begin
        if (rst || flush) ei_cnt <= 1'b0;
        else if (consume) ei_cnt <= (u[76:74] == 3'd1) && !irq_ent;
    end
    // irq_arm_q: parte lenta da condicao (INT pendente, IE, atraso do EI) registrada; o atraso de 1 clock e coberto por flush_q / dv (entrada de INT e excecao) e pelo vazio do pipeline
    reg irq_arm_q; always @(posedge clk) irq_arm_q <= rst ? 1'b0 : (irq_pend && ie && !ei_cnt);
    assign irq_take = irq_arm_q && !flush_q && pipe_empty_q && !issue_q && !dv && !seq;   // hold implica v_m (pipe_empty_q = 0)
    assign flush_tgt_raw = (flush_br && !ex_take) ? tgt_x2 : vec;
    // PC da proxima instrucao (arquitetural) e PC salvo na interrupcao. Num bloco repetido (LDIR...) o desvio para o proprio PC
    // deixa npc = PC da instrucao, entao a interrupcao entre iteracoes retoma exatamente a repeticao (BC/HL/DE ja atualizados).
    always @(posedge clk) begin
        if (rst) begin npc <= 64'd0; epc <= 64'd0; irq_taken_q <= 1'b0; end
        else begin
            irq_taken_q <= irq_take;
            if (flush_q) npc <= flush_tgt; else if (consume) npc <= dpc + {60'd0, clen};
            if (irq_take) epc <= npc;
        end
    end
    // F' (EX AF,AF' troca tambem as flags; EXINI = exx+exaf juntos volta ao F principal). A troca anda no pipeline (X3), em ordem com as escritas de flags.
    reg [7:0] fl2; reg sw_f;
    always @(posedge clk) begin
        if (rst) begin fl <= 8'd0; fl2 <= 8'd0; sw_f <= 1'b0; tz <= 1'b0; end
        else if (v_x3 && !hold) begin
            if (u_x3[46] && (!u_x3[45] || sw_f)) begin fl <= fl2; fl2 <= fl; sw_f <= u_x3[45] ? 1'b0 : ~sw_f; end
            else if (u_x3[16]) fl <= f_new;
            if (u_x3[86]) tz <= !nzres;
        end
    end
    // X3: segunda metade da ALU (os dados abaixo apenas atravessam o estagio)
    always @(posedge clk) begin
        if (rst) v_x3 <= 0;
        else if (!hold) begin
            v_x3 <= v_x2 && !flush_q && !ex_take; u_x3 <= u_x2; d_x3 <= d_x2; addr_x3 <= addr_x2; st_x3 <= st_x2; old_x3 <= old_x2;
        end
    end

    // interlock de escrita parcial: uma uop em voo que escreve PARCIALMENTE um registrador (8/16/32 bits sem zero-extensao, ou byte alto) deixa o valor
    // completo so em W; o consumidor (leitura de A/B, ou mescla do destino antigo) esperaria um valor incompleto/antigo. Bloqueia a emissao enquanto houver
    // produtor parcial para o mesmo registrador, e tambem qualquer produtor em voo quando a nova uop e parcial no mesmo destino (WAW). Registrado: uops
    // consecutivas distam >= 4 clocks, entao o atraso de 1 clock nao deixa passar hazard.
    function pw(input [95:0] uu); pw = uu[10] && (uu[48] || (uu[6:5] != 2'd3 && !uu[67])); endfunction
    function wr_(input [95:0] uu); wr_ = uu[10]; endfunction
    wire new_part = pw(u);
    wire [5:0] ra_ = iA_q, rb_ = iB_q, rd_ = iD_q;
    wire hz = (v_xr && ((pw(u_xr) && (d_xr == ra_ || d_xr == rb_ || d_xr == rd_)) || (new_part && wr_(u_xr) && d_xr == rd_))) ||
              (v_x1 && ((pw(u_x1) && (d_x1 == ra_ || d_x1 == rb_ || d_x1 == rd_)) || (new_part && wr_(u_x1) && d_x1 == rd_))) ||
              (v_x2 && ((pw(u_x2) && (d_x2 == ra_ || d_x2 == rb_ || d_x2 == rd_)) || (new_part && wr_(u_x2) && d_x2 == rd_))) ||
              (v_x3 && ((pw(u_x3) && (d_x3 == ra_ || d_x3 == rb_ || d_x3 == rd_)) || (new_part && wr_(u_x3) && d_x3 == rd_))) ||
              (v_m  && ((pw(u_m)  && (d_m  == ra_ || d_m  == rb_ || d_m  == rd_)) || (new_part && wr_(u_m)  && d_m  == rd_))) ||
              (v_w  && ((pw(u_w)  && (d_w  == ra_ || d_w  == rb_ || d_w  == rd_)) || (new_part && wr_(u_w)  && d_w  == rd_)));
    always @(posedge clk) hz_q <= rst ? 1'b0 : (hz && !issue);

    // ============ M: acesso a dados ============
    reg mm_q;                    // m_mem registrado (mesma prioridade/enable de v_m/u_m): tira 1 nivel de LUT de hold e ex_take_d (caminho c_d_ack -> hold/flush)
    wire m_mem = mm_q;           // = v_m && (u_m[8] || u_m[9])
    reg  dreq_r;
    always @(posedge clk) begin
        if (rst) dreq_r <= 0;
        else if (m_mem && !dreq_r && !d_ack) dreq_r <= 1'b1;
        else if (d_ack) dreq_r <= 1'b0;
    end
    // Interface de dados com habilitacao de bytes: d_addr e sempre alinhado a 8 bytes, d_wdata ja vem posicionado na faixa e d_be marca os bytes validos.
    // Acesso que cruza a palavra de 8 bytes (deslocamento + tamanho > 8) vira DUAS transacoes (beat 0: palavra A, beat 1: palavra A+8).
    wire [3:0] nbytes = (u_m[6:5] == 2'd0) ? 4'd1 : (u_m[6:5] == 2'd1) ? 4'd2 : (u_m[6:5] == 2'd2) ? 4'd4 : 4'd8;
    // cruza a palavra: calculado em X3 e registrado junto com a uop (fora do caminho do hold)
    reg xing;
    wire [2:0] off_x3 = addr_x3[2:0];
    wire xing_x3 = (u_x3[6:5] == 2'd1 && off_x3 == 3'd7) || (u_x3[6:5] == 2'd2 && off_x3 >= 3'd5) || (u_x3[6:5] == 2'd3 && off_x3 != 3'd0);
    reg beat; reg [63:0] rd0;
    wire [7:0] bmask = (u_m[6:5] == 2'd0) ? 8'h01 : (u_m[6:5] == 2'd1) ? 8'h03 : (u_m[6:5] == 2'd2) ? 8'h0F : 8'hFF;
    wire [15:0] bme = {8'h00, bmask} << addr_m[2:0];       // mascara de bytes na janela de 16 bytes {palavra A+8, palavra A}
    // um unico rotacionador de 64 bits serve aos dois beats: a faixa L recebe o byte (L - deslocamento) mod 8; o d_be seleciona as faixas validas
    wire [63:0] strot = (st_m << {addr_m[2:0], 3'b000}) | (st_m >> (7'd64 - {addr_m[2:0], 3'b000}));
    assign d_req   = m_mem && !dn_m;
    assign d_we    = u_m[9];
    reg [63:0] addr8_m;   // endereco da palavra seguinte, somado em X3 e registrado (sem somador no caminho de saida)
    assign d_addr  = beat ? addr8_m : {addr_m[63:3], 3'b000};
    assign d_size  = u_m[6:5];
    assign d_be    = beat ? bme[15:8] : bme[7:0];
    assign d_wdata = strot;
    wire [63:0] ldrot  = (d_rdata >> {addr_m[2:0], 3'b000}) | (d_rdata << (7'd64 - {addr_m[2:0], 3'b000}));   // byte j = palavra[(j + desloc) mod 8]
    wire [63:0] lomask = 64'hFFFF_FFFF_FFFF_FFFF >> {addr_m[2:0], 3'b000};                                    // bytes j < 8 - desloc vem do beat 0
    wire [63:0] ldsh   = xing ? ((ldrot & ~lomask) | (rd0 & lomask)) : ldrot;
    always @(posedge clk) begin
        if (rst) beat <= 1'b0;
        else if (m_mem && d_ack) begin
            if (xing && !beat && !d_flt) begin beat <= 1'b1; rd0 <= ldrot; end else beat <= 1'b0;
        end
    end
    reg [63:0] ldval_r;
    always @* case (u_m[6:5])
        2'd0: ldval_r = u_m[44] ? {{56{ldsh[7]}},  ldsh[7:0]}  : {56'd0, ldsh[7:0]};
        2'd1: ldval_r = u_m[44] ? {{48{ldsh[15]}}, ldsh[15:0]} : {48'd0, ldsh[15:0]};
        2'd2: ldval_r = u_m[44] ? {{32{ldsh[31]}}, ldsh[31:0]} : {32'd0, ldsh[31:0]};
        default: ldval_r = ldsh;
    endcase
    assign io_we = v_m && u_m[51] && !hold;
    assign io_re = v_m && u_m[50] && !hold;
    assign io_a  = addr_m[7:0];
    assign io_wd = st_m[7:0];
    assign ldval = u_m[8] ? ldval_r : u_m[50] ? {56'd0, io_rdata} : res_m;
    assign hold = m_mem && !(d_ack && (!xing || beat));
    always @(posedge clk) begin
        if (rst) begin v_m <= 0; dn_m <= 0; mm_q <= 0; end
        else if (ex_take_d) begin v_m <= 1'b0; mm_q <= 1'b0; end
        else if (!hold) begin
            v_m <= v_x3; mm_q <= v_x3 && (u_x3[8] || u_x3[9]); u_m <= u_x3; d_m <= d_x3; dn_m <= 1'b0;
            res_m <= (u_x3[8] || u_x3[9]) ? addr_x3 : x3_res; addr_m <= addr_x3; st_m <= st_x3; old_m <= old_x3; xing <= xing_x3; addr8_m <= {addr_x3[63:3], 3'b000} + 64'd8;
        end
    end

    // ============ W: escrita parcial + banco ============
    wire [63:0] merged;
    // tamanho de escrita e zeragem do valor antigo calculados em M e registrados (tira o somador e os muxes do caminho W -> banco)
    reg [2:0] wsz_w; reg [63:0] oldz_w;
    wire [2:0] wsz_m = u_m[48] ? 3'd1 : (u_m[6:5] == 2'd0) ? 3'd0 : (u_m[6:5] == 2'd1) ? 3'd2 : (u_m[6:5] == 2'd2) ? 3'd3 : 3'd4;
    regmerge u_mrg(.old(oldz_w), .newv(res_w), .wsz(wsz_w), .out(merged));   // sz 0..3 = 8/16/32/64 bits; u[48] = byte alto; u[67] = zero-estende
    assign w_we   = v_w && u_w[10];
    assign w_addr = d_w;
    assign w_data = merged;
    always @(posedge clk) begin
        if (rst) v_w <= 0;
        else if (ex_act) begin   // injecao dos CR de excecao (43 causa, 44 endereco, 45 EPC) pelo estagio W; o pipeline esta vazio
            v_w <= 1'b1; u_w <= 96'h400; d_w <= (exk == 2'd0) ? 6'd44 : (exk == 2'd1) ? 6'd43 : 6'd45;   // k0: endereco (addr_m ainda vale neste clock), k1: causa, k2: EPC (pc_last/dpc ficam estaveis)
            res_w <= (exk == 2'd0) ? (ex_isd ? addr_m : ifa) : (exk == 2'd1) ? {59'd0, ex_we, ex_isd, ex_cs} : (ex_isd ? pc_last : dpc); wsz_w <= 3'd4; oldz_w <= 64'd0;
        end else begin
            v_w <= v_m && !hold && !ex_take_d; u_w <= u_m; d_w <= d_m; res_w <= ldval; old_w <= old_m; wsz_w <= wsz_m; oldz_w <= u_m[67] ? 64'd0 : old_m;
        end
    end

    // ============ excecoes de traducao ============
    // D: o acesso em M terminou com d_flt (ack com dado 0, escrita descartada pela memoria): mata M/W/X3, esvazia o front-end, salta para 'vec'. EPC = PC da instrucao
    //    (pc_last); o reinicio executa a instrucao inteira de novo. REINICIAVEIS (rev22): a uop que acessa a memoria e a PRIMEIRA com efeito visivel: PUSH/CALL/entrada de INT gravam em [SP-2]
    //    (imediato constante immc) e so depois atualizam SP; POP/RET/LDIR/CPIR/OUTI (e IM2) leem antes de alterar registradores (TMP nao e visivel). NAO reiniciaveis: INI/INIR/IND/INDR (a leitura da porta ja ocorreu).
    //    Falta durante a entrada de INT: IFF2 := 1 e a INT volta a ser pedida (RETN restaura IFF1 e a INT e aceita de novo).
    // I: a palavra buscada deu falta; a excecao e tomada na fronteira de instrucao (pipeline vazio) quando a instrucao candidata fica a <= 12 bytes da palavra (EPC = dpc).
    assign ex_take_d = m_mem && d_ack && d_flt;
    wire ex_take_i = dv && !seq && ifx_q && pipe_empty_q && !issue_q && !m_mem && !ex_take_d;
    assign ex_take = ex_take_d | ex_take_i;
    always @(posedge clk) begin
        ifd_q <= ifa[7:0] - dpc[7:0];   // a fila tem <= 40 bytes: a distancia cabe em 8 bits (negativa = candidata ja dentro da palavra)
        ifx_q <= ifp && (ifd_q <= 8'd12 || ifd_q >= 8'd224);
        if (rst) begin ex_act <= 1'b0; exk <= 2'd0; end
        else if (ex_take) begin
            ex_act <= 1'b1; exk <= 2'd0; ex_isd <= ex_take_d; ex_we <= u_m[9]; ex_cs <= ex_take_d ? d_cs : ifc;
        end else if (ex_act) begin exk <= exk + 2'd1; if (exk == 2'd2) ex_act <= 1'b0; end
    end
    // CR46 = {asid[15:8], user[1], en[0]} | CR47 = raiz (PPN, 20 b) | CR48 = escrita -> descarga da TLB por VA | CR49 = escrita: b0 tudo, b1 por ASID ([15:8]), b2 invalida caches
    reg c_en, c_user; reg [7:0] c_asid; reg [19:0] c_root;
    wire cw = v_w && u_w[10];
    always @(posedge clk) begin
        if (rst) begin c_en <= 1'b0; c_user <= 1'b0; c_asid <= 8'd0; c_root <= 20'd0; end
        else begin
            if (cw && d_w == 6'd46) begin c_en <= res_w[0]; c_user <= res_w[1]; c_asid <= res_w[15:8]; end
            if (cw && d_w == 6'd47) c_root <= res_w[19:0];
        end
    end
    assign cr_mmu_en = c_en; assign cr_mmu_user = c_user; assign cr_asid = c_asid; assign cr_root = c_root;
    // pulsos combinacionais no clock em que a escrita esta em W (res_w valido nesse clock)
    assign cr_fl_va_en = cw && d_w == 6'd48; assign cr_fl_va = res_w;
    assign cr_fl_all = cw && d_w == 6'd49 && res_w[0]; assign cr_fl_asid_en = cw && d_w == 6'd49 && res_w[1]; assign cr_fl_asid = res_w[15:8]; assign cr_cinv = cw && d_w == 6'd49 && res_w[2];

    // ============ timer 64 bits + interrupcao ============
    always @(posedge clk) begin
        if (rst) begin tmr <= 0; tcmp <= 64'hFFFF_FFFF_FFFF_FFFF; vec <= 64'h0000_0000_0000_0040; ie <= 0; iff2 <= 0; im <= 2'd3; ireg <= 8'd0; irq_pend <= 0; irq_q <= 0; end
        else begin
            tmr <= tmr + 64'd1; irq_q <= irq;
            if (v_w && u_w[10] && d_w == 6'd40) tcmp <= res_w;
            if (v_w && u_w[10] && d_w == 6'd41) vec  <= res_w;
            if (v_w && u_w[10] && d_w == 6'd42) begin ie <= res_w[0]; iff2 <= res_w[0]; end
            if (v_w && u_w[10] && d_w == 6'd14) ireg <= res_w[7:0];       // registrador I (indice 14 do banco)
            // u[76:74] = misc: 1 EI | 2 DI | 3 RETN/RETI (IFF1 := IFF2) | 4,5,6 IM 0,1,2 | 7 flags de LD A,I (PV := IFF2)
            if (v_w && u_w[76:74] == 3'd1) begin ie <= 1'b1; iff2 <= 1'b1; end
            if (v_w && u_w[76:74] == 3'd2) begin ie <= 1'b0; iff2 <= 1'b0; end
            if (v_w && u_w[76:74] == 3'd3) ie <= iff2;
            if (v_w && u_w[76:74] == 3'd4) im <= 2'd0;
            if (v_w && u_w[76:74] == 3'd5) im <= 2'd1;
            if (v_w && u_w[76:74] == 3'd6) im <= 2'd2;
            if (irq_take) irq_pend <= 1'b0;
            else if (irq || (tmr == tcmp)) irq_pend <= 1'b1;   // INT e por nivel: se continuar ativa, volta a pedir assim que IFF1 permitir
            if (ex_take_d && irq_ent) irq_pend <= 1'b1;         // a entrada da INT foi abortada por falta: pede de novo (volta a ser aceita apos RETN)
            if (ex_take) begin iff2 <= (ex_take_d && irq_ent) ? 1'b1 : ie; ie <= 1'b0; end   // falta na entrada de INT (empilhar PC/ler vetor): o programa tinha IFF1=1, RETN o restaura      // excecao: IFF1 salvo em IFF2 (RETN restaura), interrupcoes desabilitadas
            if (irq_take) begin ie <= 1'b0; iff2 <= 1'b0; end   // entrada de interrupcao desabilita novas (o tratador reabilita escrevendo CR42)
        end
    end

    // descricao da instrucao candidata para o governador (paginas do Z80: 0 principal, 1 CB, 2 ED, 3 DD, 4 FD, 5 DDCB, 6 FDCB)
    // o prefixo DD/FD ja foi removido da janela (xy): b1 = opcode; com CB, b2 = d e b3 = opcode
    wire pfx_dd = (xy == 2'd1), pfx_fd = (xy == 2'd2);
    wire dfcb = xy_on && is_cb;
    assign gov_page = irq_ent ? 3'd7 : dfcb ? (pfx_dd ? 3'd5 : 3'd6) : is_cb ? 3'd1 : is_ed ? 3'd2 : pfx_dd ? 3'd3 : pfx_fd ? 3'd4 : 3'd0;
    assign gov_op   = irq_ent ? 8'd0 : dfcb ? b3 : (is_cb || is_ed) ? b2 : b1;
    wire io_n = (b1 == 8'hD3) || (b1 == 8'hDB);
    assign gov_port = io_n ? b2 : port_c;
    assign gov_cv   = issue && !seq;
    // desvio condicional NAO tomado: usa o tempo alternativo. u[94]: desvio de 'pulo' (CALL cc / RET cc saltam o resto da cadeia quando a condicao do Z80 e FALSA):
    // ai o tempo alternativo vale quando o pulo E tomado
    assign gov_alt_ev = v_x2 && u_x2[11] && (u_x2[94] ? cond_ok : !cond_ok) && !hold;
    assign gov_boundary = !v_xr && !v_x1 && !v_x2 && !v_x3 && !v_m && !v_w;   // pipeline vazio
    assign gov_pc = dpc[15:0]; assign gov_len = clen;
    assign gov_dev = m_mem && d_ack; assign gov_daddr = addr_m[15:0]; assign gov_dsize = u_m[6:5]; assign gov_dwe = u_m[9];
    assign dbg_pc  = dpc_q;
    assign dbg_f   = fl;
    // sinal de observacao (mantem a logica viva na sintese): arvore de paridade em 2 estagios registrados, para nao virar caminho critico artificial
    reg [15:0] dbg_p; reg dbg_s;
    always @(posedge clk) begin
        dbg_p <= {^w_data[63:48], ^w_data[47:32], ^w_data[31:16], ^w_data[15:0], ^d_wdata[63:48], ^d_wdata[47:32], ^d_wdata[31:16], ^d_wdata[15:0],
                  ^d_addr[63:32], ^d_addr[31:0], ^i_addr[63:32], ^i_addr[31:0], ^{w_addr, w_we, i_req, d_req, d_we, d_size}, ^{tmr[63], ld_dep_q, merged[0]}, 2'b00};
        dbg_s <= ^dbg_p;
    end
    assign dbg_sig = dbg_s;
endmodule
