# R8064 - CPU de 64 bits derivada do Z80, em FPGA (Tang Nano 20K, GW2AR-18)

CPU de 64 bits derivada do Z80 (com modos de tempo Z80/R800 e modo nativo), construida modulo a modulo para um slot de MSX.
Alvo de clock: 57,28 MHz (3,58 MHz x 16).

## Estado atual (leia antes de usar)
- O nucleo do SoC e o **nucleo minimo** (`09_core_min`), um esqueleto para medir area e tempo. A pagina principal ainda usa uma **codificacao de teste**
  (LDI, ADD de 3 operandos, LD, ST, ADDI, JR, JRNZ; ver o inicio de `gen_roms.py`), que NAO e a do Z80: o opcode 00, por exemplo, e um LDI de 2 bytes.
  Por cima dela ha 16 opcodes reais do Z80 (JR, LD SP,nn, PUSH/POP BC/DE/HL, CALL, RET, OUT (n),A, IN A,(n), EI, DI, EXX, EX AF,AF').
  Da pagina ED: 50 das 80 instrucoes do Z80 e 13 instrucoes R8064. As paginas CB, DD e FD nao sao executadas. Nao e, ainda, um Z80.
- O SoC (`13_soc`) reune nucleo + governador + memoria MSX + MMU + caches + SDRAM. Nao instancia mul/div (03), `msx_if` (04), FPU (08/11) nem o Z80 classico (12).
- O Z80 classico (`12_z80`) passa no ZEXDOC, mas a ultima Fmax medida (44-52 MHz) esta abaixo do clock de 57,28 MHz.
- Nada foi verificado em hardware. O topo de placa ainda nao liga o barramento do MSX.
- Pendencias e historico: `modulos/13_soc/resultado_soc.txt` (a REV33 lista o que esta aberto).

## Modulos (`modulos/`)
| Pasta | Conteudo | Usado no SoC |
|---|---|---|
| `01_alu_regfile` | ALU de 64 bits e banco de registradores | sim (via 09) |
| `02_pipeline` | modelo de temporizacao do pipeline (estudo, nao sintetizavel) | nao |
| `03_muldiv` | multiplicador e divisor | nao |
| `04_msx_if` | interface MSX + FIFO (primeira versao) | nao |
| `05_sdram` | controlador de SDRAM e modelo de simulacao | sim |
| `05b_cache` | estudo de dimensionamento das caches (Python) | - |
| `06_cache` | `cache8k` (2 vias, estudo) e `cache_dm` (mapeamento direto, a usada) | `cache_dm` |
| `07_mmu` | MMU Sv39 | sim |
| `08_fpu`, `11_fpu_stk` | FPU em hardware (substituida por firmware) e pilha de FPU | nao |
| `09_core_min` | nucleo minimo (decodificador por ROM de uops) e geradores de ROM | sim |
| `10_mode_gov` | governador de tempo + modos (Z80 ROM, R800 DRAM, nativo) + sistema MSX | sim |
| `10_msx_mem` | mapper de memoria MSX + MegaRAM | sim |
| `12_z80` | Z80 classico independente (referencia) | nao |
| `13_soc` | SoC: core + MMU + caches + SDRAM; top de placa e fluxo de PnR | - |
| `14_vec3d` | unidade 3D (arquivada; fora do core) | nao |

## Como rodar
No terminal do OSS CAD Suite:
- Regressao do core/governador/sistema: `modulos\10_mode_gov\rodar_tudo.bat`
- SoC (excecoes, SoC basico, gerador de clock): `modulos\13_soc\rodar_exc.bat`
- Place-and-route do top da placa (4 sementes): `modulos\13_soc\pnr\rodar_pnr_board.bat`
- Bitstream: `modulos\13_soc\pnr\gerar_bitstream_board.bat 0 <semente>`

## Arquivos `.mem` (sao FONTE do projeto)
Mantenha iguais as copias de `sim/` e `pnr/` dos modulos 09, 10 e 13.
| Arquivo | De onde vem |
|---|---|
| `uop.mem`, `mainctrl.mem`, `prog*.mem` | `09_core_min/sim/gen_roms.py` |
| `ctrl_b.mem` | `09_core_min/sim/gen_bank.py instr_ids.csv ctrl.mem` |
| `r8064_decode_rom.v` | `09_core_min/sim/gen_decode_rom.py` (a partir de `rom_ed_a.mem` e `amb_idx.mem`) |
| `gov_rom.mem` | `10_mode_gov/sim/gen_gov_rom.py ref/z80_classico_tstates.csv` |
| `ctrl.mem`, `rom_ed_a.mem`, `rom_ed_b.mem`, `amb_idx.mem` | **sem gerador no repositorio**: vieram da planilha de instrucoes e foram editados a mao depois (ids 291-295) |

O RTL do nucleo existe em duas copias (`09_core_min/rtl` para simulacao, `10_mode_gov/rtl` para sintese): mantenha-as iguais (`rodar_tudo.bat` avisa se divergirem).

Nao versionados (`.gitignore`): pastas `bak/` e logs de PnR (`*.log`) citados nos textos de resultado, e as planilhas de instrucoes.

---

# Pacote historico (pastas `rom/`, `rtl/`, `sim/`, `ref/`, `pnr/`, `gowin_mi/` da raiz): ROM de decodificação, testbench e ciclos esperados

> Este e o primeiro pacote do projeto (decodificador ED isolado, planilha rev5, 290 instrucoes, meta de 100 MHz na epoca).
> As ROMs e o `r8064_decode.v` daqui sao **anteriores** aos dos modulos 09/10/13 (que tem os ids 291-295 e a familia ED 26 recodificada): nao misture.
> O texto abaixo descreve o estado daquela epoca; o testbench daqui continua passando com as ROMs daqui.

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
