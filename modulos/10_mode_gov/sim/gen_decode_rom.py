# gera r8064_decode_rom.v: ROM A (256x12) e ROM de ambiguidade (256x8) como logica combinacional (case), a partir de rom_ed_a.mem / amb_idx.mem.
# Motivo: como "reg []" + $readmemh o yosys absorve o registrador de endereco (b2) na porta de leitura e leva o caminho D->b2 para dentro da ROM.
import sys
def mk(name,fn,w):
    v=[int(l,16) for l in open(fn) if l.strip()]
    s=f"(* keep_hierarchy *) module {name}(input wire [7:0] a, output reg [{w-1}:0] d);\n    always @* case (a)\n"
    for i,x in enumerate(v): s+=f"        8'd{i}: d = {w}'h{x:0{(w+3)//4}x};\n"
    return s+f"        default: d = {w}'h0;\n    endcase\nendmodule\n"
open('../rtl/r8064_decode_rom.v','w').write("// GERADO por sim/gen_decode_rom.py - nao editar\n"+mk('r8064_rom_a','rom_ed_a.mem',12)+mk('r8064_rom_amb','amb_idx.mem',8))
