#!/usr/bin/env python3
# Roda o pipeline RTL (Icarus) para cada programa e configuracao e compara com o modelo da planilha.
import json, subprocess, sys, os, re
W = sys.argv[1]   # pasta de trabalho com .mem e traços
meta = json.load(open(W + '/programs.json')); tab = json.load(open(W + '/idtab.json'))
def sheet(ids, wrd, wwr, wio, with_pen=True):
    t = 0
    for i in ids:
        r = tab[str(i)]
        clk = max(1, r['b'] + r['nr'] + r['nw'], r['nio'], r['ex'])
        t += clk + (r['b'] + r['nr']) * wrd + r['nw'] * wwr + r['nio'] * wio + (r['pen'] if with_pen else 0)
    return t + 6
cfgs = [
 ('A: sem wait, D=1 (ideal)',             dict(WRD=0, WWR=0, WIO=0, DEC_D=1, LEN_LAT=0, SERIAL=0)),
 ('B: wait da planilha, D=1',             dict(WRD=4, WWR=2, WIO=1, DEC_D=1, LEN_LAT=0, SERIAL=0)),
 ('C: wait, D=2 (decodificador real)',    dict(WRD=4, WWR=2, WIO=1, DEC_D=2, LEN_LAT=0, SERIAL=0)),
 ('D: wait, D=2, busca serial (len em 2)', dict(WRD=4, WWR=2, WIO=1, DEC_D=2, LEN_LAT=2, SERIAL=1)),
]
res = {}
for cn, p in cfgs:
    for pn, m in meta.items():
        exe = f'{W}/sim_{abs(hash((cn,pn)))%10**8}'
        args = ['iverilog', '-g2012', '-o', exe, f'-Ptb_pipe.NTRACE={m["n"]}', f'-Ptb_pipe.TRACE_FILE="{pn}.mem"'] + \
               [f'-Ptb_pipe.{k}={v}' for k, v in p.items()] + ['tb_pipe.v', 'r8064_pipe.v', 'r8064_decode.v']
        subprocess.run(args, cwd=W, check=True, capture_output=True)
        out = subprocess.run(['vvp', exe], cwd=W, capture_output=True, text=True).stdout
        os.remove(exe)
        d = dict(re.findall(r'(\w+)=(\d+)', out.split('RESULT')[-1]))
        d = {k: int(v) for k, v in d.items()}
        exp = sheet(m['ids'], p['WRD'], p['WWR'], p['WIO'])
        res[(cn, pn)] = (d, exp)
with open(W + '/resultado_pipeline.txt', 'w') as f:
    for cn, p in cfgs:
        f.write(f'\n== Configuracao {cn} {p}\n')
        f.write(f'{"programa":24s} {"instr":>5s} {"pipeline":>9s} {"planilha":>9s} {"dif":>7s} {"dif%":>7s} {"CPI pipe":>8s} {"CPI plan":>8s} {"chk_err":>7s} {"wp_fetch":>8s}\n')
        for pn, m in meta.items():
            d, exp = res[(cn, pn)]
            c = d['cycles']
            f.write(f'{pn:24s} {m["n"]:5d} {c:9d} {exp:9d} {c-exp:7d} {100.0*(c-exp)/exp:7.1f} {c/m["n"]:8.2f} {exp/m["n"]:8.2f} {d["chk_err"]:7d} {d["wp_fetch"]:8d}\n')
print(open(W + '/resultado_pipeline.txt').read())
