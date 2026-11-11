// regfile64.v - banco de registradores de 64 bits: 64 entradas, 2 leituras sincronas, 1 escrita.
// A memoria le "read-first" (le e escreve o mesmo endereco no mesmo clock -> valor ANTIGO). O repasse e feito DEPOIS da leitura:
// a ultima escrita fica registrada (wq_*) e, se coincide com o endereco lido, substitui a saida da memoria. Cobre o consumidor que le
// exatamente quando o produtor esta no estagio W; os demais casos sao encaminhados pelo pipeline. (Nao entra no caminho w_data -> leitura.)
// Duas copias para inferir BSRAM (2 portas de leitura).
// Indices: 0 QAX,1 QBC,2 QDE,3 QHL,4 QWX,5 QAX',6 QBC',7 QDE',8 QHL',9 QIX,10 QIY,11 QSP,12 QPC,13 temporario; 16..23 = N0..N7; 32..51 = CR0..CR19.
module regfile64(
    input  wire        clk,
    input  wire        we,
    input  wire [5:0]  waddr,
    input  wire [63:0] wdata,
    input  wire [5:0]  raddr_a,
    input  wire [5:0]  raddr_b,
    output wire [63:0] rdata_a,
    output wire [63:0] rdata_b
);
    reg [63:0] mem_a [0:63];
    reg [63:0] mem_b [0:63];
    integer i;
    initial for (i = 0; i < 64; i = i + 1) begin mem_a[i] = 64'd0; mem_b[i] = 64'd0; end
    reg [63:0] ra_raw, rb_raw, wq_d; reg byp_a, byp_b;
    always @(posedge clk) begin
        if (we) begin mem_a[waddr] <= wdata; mem_b[waddr] <= wdata; end
        ra_raw <= mem_a[raddr_a];
        rb_raw <= mem_b[raddr_b];
        byp_a <= we && (waddr == raddr_a); byp_b <= we && (waddr == raddr_b);
        wq_d <= wdata;
    end
    assign rdata_a = byp_a ? wq_d : ra_raw;
    assign rdata_b = byp_b ? wq_d : rb_raw;
endmodule
