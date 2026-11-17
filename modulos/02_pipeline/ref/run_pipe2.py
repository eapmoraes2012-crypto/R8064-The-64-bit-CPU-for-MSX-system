#!/usr/bin/env python3
# Runs r8064_pipe2 (prefetch queue) and compares with the spreadsheet model. Usage: run_pipe2.py <working folder>
import json, subprocess, sys, os, re
W = sys.argv[1]
meta = json.load(open(W + '/programs.json')); tab = json.load(open(W + '/idtab.json'))
def sheet(ids, wrd, wwr, wio):
    t = 0
    for i in ids:
        r = tab[str(i)]
        t += max(1, r['b'] + r['nr'] + r['nw'], r['nio'], r['ex']) + (r['b'] + r['nr']) * wrd + r['nw'] * wwr + r['nio'] * wio + r['pen']
    return t + 6
base = dict(WRD=4, WWR=2, WIO=1, DEC_D=1, LEN_LAT=1, QCAP=32, TGT_OFF=-1)
cfgs = [
 ('E: queue 32 B, D=1, len 1 clock, spreadsheet wait', dict(base)),
 ('F: 32 B queue, D=2 (real decoder), len 2',    dict(base, DEC_D=2, LEN_LAT=2)),
 ('G: 16 B queue, D=2, len 2',                          dict(base, DEC_D=2, LEN_LAT=2, QCAP=16)),
 ('H: 64 B queue, D=2, len 2',                          dict(base, DEC_D=2, LEN_LAT=2, QCAP=64)),
 ('I: NO wait (W=0), queue 32 B, D=1, len 1',          dict(base, WRD=0, WWR=0, WIO=0)),
 ('K: 24 B queue (practical minimum), D=2, len 2',                dict(base, DEC_D=2, LEN_LAT=2, QCAP=24)),
 ('J: NO wait (W=0), queue 32 B, D=2, len 2',          dict(base, WRD=0, WWR=0, WIO=0, DEC_D=2, LEN_LAT=2)),
]
sel = [int(a) for a in sys.argv[2:]] or range(len(cfgs))
out = []
for ci in sel:
    cn, p = cfgs[ci]
    out.append(f'\n== Configuration {cn} {p}')
    out.append(f'{"program":24s} {"instr":>5s} {"pipeline":>9s} {"sheet":>9s} {"diff%":>7s} {"CPI pipe":>8s} {"CPI sheet":>8s} {"chk_err":>7s} {"fetch":>6s} {"wp":>5s} {"queue empty":>10s}')
    for pn, m in meta.items():
        exe = f'{W}/s2_{os.getpid()}'
        args = ['iverilog', '-g2012', '-o', exe, f'-Ptb_pipe2.NTRACE={m["n"]}', f'-Ptb_pipe2.TRACE_FILE="{pn}.mem"'] + \
               [f'-Ptb_pipe2.{k}={v}' for k, v in p.items()] + ['tb_pipe2.v', 'r8064_pipe2.v', 'r8064_decode.v']
        subprocess.run(args, cwd=W, check=True, capture_output=True)
        o = subprocess.run(['vvp', exe], cwd=W, capture_output=True, text=True, timeout=60).stdout
        os.remove(exe)
        d = {k: int(v) for k, v in re.findall(r'(\w+)=(-?\d+)', o.split('RESULT')[-1])}
        exp = sheet(m['ids'], p['WRD'], p['WWR'], p['WIO']); c = d['cycles']
        out.append(f'{pn:24s} {m["n"]:5d} {c:9d} {exp:9d} {100.0*(c-exp)/exp:7.1f} {c/m["n"]:8.2f} {exp/m["n"]:8.2f} {d["chk_err"]:7d} {d["fetches"]:6d} {d["wp_fetch"]:5d} {d["starve"]:10d}')
open(W + '/resultado_prefetch_%s.txt' % ('_'.join(map(str, sel))), 'w').write('\n'.join(out) + '\n')
print('\n'.join(out))
