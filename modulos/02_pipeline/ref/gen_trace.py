#!/usr/bin/env python3
# Gera tracos de programa (b2,b3 por instrucao executada) e o total esperado pelo modelo da planilha.
import csv, random, sys, json
P = sys.argv[1]            # pasta do pacote R8064_rtl_pack
OUT = sys.argv[2]
ids = [int(l.strip(), 16) for l in open(P + '/ref/expected_id.mem') if l.strip()]
enc = {}
for i, v in enumerate(ids):
    if v and v not in enc: enc[v] = (i >> 8, i & 255)
rows = {}
for r in csv.DictReader(open(P + '/ref/expected_cycles.csv', encoding='utf-8-sig'), delimiter=';'):
    rows[int(r['id'])] = r
def mn(i): return rows[i]['mnemonico']
byname = {}
for i, r in rows.items(): byname.setdefault(r['mnemonico'], []).append(i)
r8064 = [i for i, r in rows.items() if r['origem'] == 'R8064']
ex_big = [i for i in r8064 if int(rows[i]['ocupacao_X']) >= 8]
io = [i for i in rows if int(rows[i]['es']) > 0]
loads = [i for i in r8064 if int(rows[i]['leituras']) > 0 and int(rows[i]['penalidade_desvio']) == 0 and int(rows[i]['ocupacao_X']) == 1]
stores = [i for i in r8064 if int(rows[i]['escritas']) > 0 and int(rows[i]['penalidade_desvio']) == 0 and int(rows[i]['ocupacao_X']) == 1]
alu = [i for i in r8064 if rows[i]['classe'].startswith('ALU 64')]
def pick(name): return byname[name][0]
ADDQ, INCQ, LDQ_L, LDQ_S = pick('ADDQ rr, rr’'), pick('INCQ rr'), pick('LDQ rr, (rr’)'), pick('LDQ (rr), rr’')
JPQ, DJNZ, RETQ, CALLQ = pick('JPQ nnnnnnnnn'[:-1]) if 'JPQ nnnnnnnnn' in byname else pick('JPQ nnnnnnnn'), pick('DJNZW nn'), pick('RETQ'), pick('CALLQ nnnnnnnn')
rnd = random.Random(8064)
progs = {
 'p00_um_ADDQ': [ADDQ],
 'p01_100_ADDQ': [ADDQ]*100,
 'p02_100_LDQ_ler': [LDQ_L]*100,
 'p03_100_LDQ_gravar': [LDQ_S]*100,
 'p04_JPQ_BR_D': [ADDQ, JPQ]*40,
 'p05_DJNZ_BR_X': [LDQ_L, ADDQ, LDQ_S, DJNZ]*30,
 'p06_CALL_RET': [CALLQ, ADDQ, INCQ, RETQ]*30,
 'p07_EX_longo': [ADDQ] + [rnd.choice(ex_big) for _ in range(60)],
 'p08_ES': [rnd.choice(io) for _ in range(60)],
 'p09_mistura_alu_mem': [rnd.choice(alu + loads + stores) for _ in range(300)],
 'p10_aleatorio_210': [rnd.choice(r8064) for _ in range(500)],
}
meta = {}
for n, lst in progs.items():
    with open(f'{OUT}/{n}.mem', 'w') as f:
        for i in lst: f.write('%02x%02x\n' % enc[i])
    meta[n] = {'n': len(lst), 'ids': lst}
json.dump(meta, open(f'{OUT}/programs.json', 'w'))
# tabela por id para o modelo da planilha
tab = {i: dict(b=int(r['acessos_busca']), nr=int(r['leituras']), nw=int(r['escritas']), nio=int(r['es']), ex=int(r['ocupacao_X']), pen=int(r['penalidade_desvio'])) for i, r in rows.items()}
json.dump(tab, open(f'{OUT}/idtab.json', 'w'))
print({n: (m['n']) for n, m in meta.items()}, 'ex_big', len(ex_big), 'io', len(io))
