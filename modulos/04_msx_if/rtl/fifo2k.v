// fifo2k.v - FIFO sincrono 2048 x 8 (BSRAM), palavra da frente (FWFT). Itens ficam visiveis 2 clocks apos a escrita; apos pop a nova cabeca vale no clock seguinte.
module fifo2k #(parameter AW = 11)(
    input  wire       clk, rst, clr,
    input  wire       push, input wire [7:0] din,
    input  wire       pop,
    output wire [7:0] dout,
    output wire       empty,      // nada visivel para leitura
    output wire       full,       // sem espaco para escrever
    output wire [AW:0] level
);
    reg [7:0] mem [0:(1<<AW)-1];
    reg [AW:0] wp, rp, cnt, cnt_v; reg p1, p2; reg [7:0] q;
    assign full  = (cnt == (1 << AW));
    assign empty = (cnt_v == 0);
    assign dout  = q;
    assign level = cnt;
    wire do_push = push && !full;
    wire do_pop  = pop && !empty;
    wire [AW:0] rp_n = rp + (do_pop ? 1'b1 : 1'b0);
    always @(posedge clk) begin
        if (do_push) mem[wp[AW-1:0]] <= din;
        q <= mem[rp_n[AW-1:0]];
    end
    always @(posedge clk) begin
        if (rst || clr) begin wp <= 0; rp <= 0; cnt <= 0; cnt_v <= 0; p1 <= 0; p2 <= 0; end
        else begin
            p1 <= do_push; p2 <= p1;
            if (do_push) wp <= wp + 1'b1;
            rp <= rp_n;
            cnt   <= cnt   + (do_push ? 1 : 0) - (do_pop ? 1 : 0);
            cnt_v <= cnt_v + (p2 ? 1 : 0)      - (do_pop ? 1 : 0);
        end
    end
endmodule
