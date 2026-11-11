# R8064 - CPU de 64 bits derivada do Z80, em FPGA (Tang Nano 20K, GW2AR-18)

CPU de 64 bits compativel com o Z80 (e com modos R800 e nativo), construida modulo a modulo para um slot de MSX.
Alvo de clock: 57,28 MHz (3,58 MHz x 16).

## Modulos (`modulos/`)
| Pasta | Conteudo |
|---|---|
| `01_alu_regfile` ... `07_mmu` | ALU, pipeline, mul/div, interface MSX, SDRAM, caches, MMU |
| `08_fpu`, `11_fpu_stk` | FPU em hardware (substituida por firmware) e pilha de FPU |
| `09_core_min` | nucleo minimo (decodificador por ROM de uops) |
| `10_mode_gov` | governador de tempo + modos (Z80 ROM, R800 DRAM, nativo) + sistema MSX |
| `12_z80` | Z80 para MSX (referencia) |
| `13_soc` | SoC completo: core + MMU + caches + SDRAM; top de placa e fluxo de PnR |
| `14_vec3d` | unidade 3D (arquivada; fora do core) |

## Como rodar
No terminal do OSS CAD Suite:
- Regressao do core/governador/sistema: `modulos\10_mode_gov\rodar_tudo.bat`
- Excecoes do SoC: `modulos\13_soc\rodar_exc.bat`
- Place-and-route do top da placa (4 sementes): `modulos\13_soc\pnr\rodar_pnr_board.bat`
- Bitstream: `modulos\13_soc\pnr\gerar_bitstream_board.bat 0 <semente>`

Os resultados e o historico de revisoes estao em `modulos/13_soc/resultado_soc.txt`.
Os `.mem` (uop, ctrl, rom_ed_b, gov_rom) sao FONTE do projeto: regenere-os com `gen_roms.py` e mantenha as copias de `sim/` e `pnr/` iguais.

---

# Pacote RTL do R8064: ROM de decodificação, testbench e ciclos esperados

Gerado a partir de `Planilha_instrucoes_R8064_rev5.xlsx`. Cobre SOMENTE a página do prefixo ED:
as 210 instruções do R8064 (todas começam em ED) e as 80 instruções ED do Z80 (modo Z80 do R8064).
As páginas do Z80 sem ED (principal, CB, DD, FD, DDCB, FDCB) não têm ROM aqui; seus T-states estão em `ref/z80_classico_tstates.csv`.

## O que foi e o que NÃO foi verificado
- VERIFICADO (Python, `ref/verify_roms.py`): as ROMs reproduzem as 65.536 combinações (b2, b3) esperadas, e as palavras de controle reproduzem Ciclos/Clock, Ciclos/Wait e Penalidade da planilha para as 290 instruções (0 divergências).
- VERIFICADO (simulação RTL): o testbench passa (PASS) no Icarus Verilog e no Verilator: 65.536 vetores, 0 erros de id, 0 erros de ciclos. Detalhes em `ref/resultados_simulacao.txt`.
- VERIFICADO (síntese Yosys, `synth_gowin`): o módulo sintetiza; 6 blocos de BSRAM (SPX9) e ~164 LUT4 mais 71 MUX2.
- VERIFICADO (netlist): simulação em nível de portas da síntese sem BSRAM: PASS. Com BSRAM não dá para simular com os modelos do Yosys (BSRAM sem modelo de comportamento).
- VERIFICADO (place-and-route): GW2AR-LV18QN88C8/I7, 111 MHz de Fmax (meta 100 MHz) para o decodificador isolado, em um invólucro de teste (`pnr/`). 36 avisos de hold do nextpnr não analisados.
- NÃO CONCLUÍDO: timing do projeto completo (ALU, FPU, MMU, SDRAM) e os pinos reais do slot MSX.
- NÃO VERIFICADO: o formato dos `.mi` (Gowin) segue o que eu lembro do IP Core Generator; importe um e confira.

## Arquivos
| Arquivo | Conteúdo |
|---|---|
| `rom/rom_ed_a.mem` | 256 × 12 bits, indexada por b2. Bit 10 = "página ambígua" (consulta ROM_B); bits 9:0 = id da instrução (acesso direto) |
| `rom/amb_idx.mem` | 256 × 8 bits: número da página de ROM_B para cada b2 (só vale se o bit 10 de ROM_A = 1). Vira lógica combinacional (LUT) |
| `rom/rom_ed_b.mem` | 33 páginas × 256 × 10 bits, indexada por {página, b3}: id da instrução (0 = ilegal) |
| `rom/ctrl.mem` | 512 × 32 bits, indexada pelo id (palavra de controle abaixo) |
| `gowin_mi/*.mi` | As mesmas ROMs no formato de inicialização do IP de memória da Gowin (a conferir) |
| `rtl/r8064_decode.v` | Decodificador: ROM_A e ROM_B em paralelo (+1 clock), ROM de controle em série (+2 clocks) |
| `rtl/tb_r8064_decode.v` | Testbench exaustivo (65.536 vetores) + conferência de ciclos |
| `ref/expected_id.mem` | id esperado para cada (b2, b3), gerado direto dos padrões de bits (independente das ROMs) |
| `ref/expected_clock.mem`, `expected_wait.mem`, `expected_pen.mem` | Ciclos/Clock, Ciclos/Wait (típico) e penalidade de desvio por id |
| `ref/expected_cycles.csv` | Tudo da planilha por instrução (ponto e vírgula, UTF-8) |
| `ref/instr_ids.csv` | id ↔ mnemônico ↔ hex |
| `ref/z80_classico_tstates.csv` | T-states do Z80 clássico, 1.270 opcodes |
| `ref/verify_roms.py` | Conferência em Python, sem simulador |

## Palavra de controle (32 bits)
`[3:0]` bytes da instrução · `[8:4]` leituras (NR) · `[13:9]` escritas (NW) · `[15:14]` acessos de E/S (NIO) · `[23:16]` ocupação do estágio X (EX) · `[25:24]` penalidade: 0 nenhuma, 1 BR_D, 2 BR_X, 3 BR_M · `[26]` existe variante "condição falsa" · `[27]` instrução ED do Z80 · `[31:28]` reservado.
Fórmulas (iguais às da planilha, com HIT_I = HIT_D = 0): acessos de busca = ⌈bytes/8⌉; Ciclos/Clock = MAX(1, busca+NR+NW, NIO, EX); Ciclos/Wait = (busca+NR)·W_RD_HIT + NW·W_WR_HIT + NIO·W_IO; total = clock + wait + penalidade.

## Como rodar
- Icarus Verilog (a partir de uma pasta de trabalho): `cp rom/*.mem ref/*.mem rtl/*.v . && iverilog -g2012 -o sim tb_r8064_decode.v r8064_decode.v && vvp sim` → deve imprimir `PASS`.
- Sem simulador: `python3 ref/verify_roms.py`.
- Tudo de uma vez (simulação, síntese, place-and-route): `bash scripts/simular_e_sintetizar.sh`.
- Gowin EDA: adicione `r8064_decode.v` e os `.mem` ao projeto. Confirme que a síntese infere BSRAM a partir de `$readmemh`; se não, gere as ROMs pelo IP Core Generator com os `.mi`.

## Pontos de atenção
1. As duas leituras em série (decodificação + controle) podem não caber no estágio D de 1 clock do pipeline. Decisões possíveis: dividir D em 2 clocks (o modelo de ciclos precisa de +1 de latência e de penalidade de desvio) ou ler a ROM de controle no estágio R.
2. Tamanho medido: ROM_A 3 Kbit, ROM_B ≈ 84 Kbit, controle 16 Kbit. A síntese do Yosys mapeou o módulo em 6 blocos de BSRAM (SPX9) e cerca de 164 LUT4; a planilha previa 3 blocos. A aba Ocupação foi corrigida com esses números.
3. Bytes ED ilegais: `id = 0`. No Z80 clássico independente executam como NOP de 8 T-states; no R8064, devem gerar exceção (decisão sua).
4. A coluna "cond. falsa" da planilha NÃO está na ROM (só o bit `has_cond`).
