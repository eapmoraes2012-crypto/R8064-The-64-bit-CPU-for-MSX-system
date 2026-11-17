#!/usr/bin/env python3
# build_monitor.py - monta monitor.asm (zasm_mon.py) e gera monitor_l0..7.hex (8 raias, 2048 linhas) + monitor.bin + monitor.lst (mapa de rotulos)
import os, sys
os.environ['ZASM_ORG0'] = '1'
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import zasm_mon
def crc_tab():
    t = []
    for i in range(256):
        c = i << 8
        for _ in range(8): c = ((c << 1) ^ 0x1021) & 0xFFFF if c & 0x8000 else (c << 1) & 0xFFFF
        t.append(c)
    return t
T = crc_tab()
src = open('monitor.asm', encoding='latin-1').read()
lo = '\n'.join('        db ' + ','.join('0%02Xh' % (T[i + j] & 255) for j in range(16)) for i in range(0, 256, 16))
hi = '\n'.join('        db ' + ','.join('0%02Xh' % (T[i + j] >> 8) for j in range(16)) for i in range(0, 256, 16))
src = src.replace(';@CRCTAB@', lo + '\n        org THI\n' + hi)
a = zasm_mon.Asm(src); b = a.assemble()
code_end = a.sym['codeend']
assert code_end < 0x800, 'codigo invade a tabela do CRC'
img = bytearray(16384); img[:len(b)] = b
open('monitor.bin', 'wb').write(img)
for g in range(8):
    with open('monitor_l%d.hex' % g, 'w') as f:
        for k in range(2048): f.write('%02X\n' % img[8 * k + g])
with open('monitor.lst', 'w') as f:
    for k, v in sorted(a.sym.items(), key=lambda x: x[1]): f.write('%04X %s\n' % (v, k))
print('monitor: codigo ate %04X (%d bytes), tabelas CRC em 0800h/0900h, imagem 16384 bytes' % (code_end, code_end))
