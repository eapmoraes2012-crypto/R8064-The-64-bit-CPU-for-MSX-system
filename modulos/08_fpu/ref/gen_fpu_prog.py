# gen_fpu_prog.py - UMA fonte para os "programas" internos da FPU (transcendentais e restos): gera, DENTRO de ../rtl/fpu_unit.v (entre as marcas GERADO), a ROM (512 x 36 bits) com os passos e as
# constantes, e e importado pelo modelo de teste (09_core_min/sim_r64/gen_r64_prog.py), que executa os MESMOS passos com o fpref.py.
# Cada passo e uma operacao do nucleo aritmetico entre registradores (ST relativos, temporarios T0-T7) e constantes de 80 bits.
# Algoritmos (definidos aqui; os resultados NAO sao arredondados corretamente como num x87, erro tipico de poucas unidades na ultima casa):
#   seno/cosseno: k = arredonda(x*2/pi); r = x - k*pi/2 (pi/2 em 3 pedacos: exato para |k| < 2^31); polinomios de Taylor em r (|r| <= pi/4) e troca por quadrante.
#   logaritmo: x = m*2^e (1 <= m < 2); f = (m-1)/(m+1); ln m = f * soma 2/(2i+1) f^2i (20 termos). FYL2P usa f = x/(2+x), sem separar o expoente.
#   resto: ST0 - ST1*int(ST0/ST1), com a divisao arredondada (truncada em FREM, ao mais proximo em FREM1): literal da formula pedida, nao e o resto exato IEEE.
from fractions import Fraction as F
import math, os
def ext(fr):                                    # Fraction -> 80 bits, arredondando o significando de 64 bits ao mais proximo
    if fr == 0: return 0
    s = 1 if fr < 0 else 0; fr = abs(fr); e = fr.numerator.bit_length() - fr.denominator.bit_length()
    if F(2) ** e > fr: e -= 1
    m = fr / F(2) ** (e - 63); mi = m.numerator // m.denominator; rem = m - mi
    if rem > F(1, 2) or (rem == F(1, 2) and mi & 1): mi += 1
    if mi >> 64: mi >>= 1; e += 1
    return s << 79 | (e + 16383) << 64 | mi
def atan_inv(n, bits=320): return sum(F((-1) ** k, (2 * k + 1) * n ** (2 * k + 1)) for k in range(bits // 4))
PI = 16 * atan_inv(5) - 4 * atan_inv(239)       # Machin, com sobra de precisao
LN2 = 2 * sum(F(1, (2 * k + 1) * 3 ** (2 * k + 1)) for k in range(110))
hp = PI / 2
def chop(fr, bits):                             # os 'bits' bits de cima de fr (truncado)
    e = fr.numerator.bit_length() - fr.denominator.bit_length()
    if F(2) ** e > fr: e -= 1
    sc = F(2) ** (e - bits + 1); return (fr / sc).numerator // (fr / sc).denominator * sc
P1 = chop(hp, 33); P2 = chop(hp - P1, 33); P3 = hp - P1 - P2
NS, NC, NL = 11, 12, 20
S = [F((-1) ** (i + 1), math.factorial(2 * i + 3)) for i in range(NS)]
C = [F((-1) ** (i + 1), math.factorial(2 * i + 2)) for i in range(NC)]
L = [F(2, 2 * i + 1) for i in range(NL)]
CONST = [ext(v) for v in [F(1), F(2), 2 / PI, P1, P2, P3, 1 / LN2, LN2] + S + C + L]
K_ONE, K_TWO, K_2OPI, K_P1, K_P2, K_P3, K_L2E, K_LN2, K_S, K_C, K_L = 0, 1, 2, 3, 4, 5, 6, 7, 8, 8 + NS, 8 + NS + NC
ADD, SUB, MUL, DIV, FILD, FIST, RND = 0, 1, 2, 3, 6, 7, 8
T = lambda i: 8 + i                             # temporarios: posicoes 8..15 da memoria da pilha
ST = lambda i: 16 + i                           # relativo ao topo
# passo = dict(k, aop, rc, dst, a, bsel, b, q): k 0 ALU, 1 carrega constante, 2 separa (mantissa -> dst, expoente -> inteiro), 3 escolhe por quadrante
# (b = 0 seno, 1 cosseno), 4 empilha a, 5 laco (b = destino), 6 prepara laco (a = voltas, b = constante inicial), 7 fim (a = desempilha), 8 desvia pela variante
PROG = []
def st(k, **kw): PROG.append(dict(dict(k=k, aop=0, rc=0, dst=0, a=0, bsel=0, b=0, q=0), **kw))
def alu(dst, a, aop, b=0, rc=0, c=None, cdec=False, q=0): st(0, aop=aop, rc=rc, dst=dst, a=a, bsel=2 if cdec else (1 if c is not None else 0), b=c if c is not None else b, q=q)
def horner(dst, z, base, n):                    # dst = soma base[i] * z^i
    st(6, a=n - 2, b=base + n - 1); st(1, dst=dst, bsel=2); top = len(PROG)        # n-1 voltas: (dst*z + C[i]) para i = n-2 .. 0
    alu(dst, dst, MUL, b=z); alu(dst, dst, ADD, cdec=True); st(5, b=top)
ENTRY = {}
ENTRY['trig'] = len(PROG)
alu(T(0), ST(0), MUL, c=K_2OPI); alu(T(0), T(0), RND); alu(0, T(0), FIST, q=1)
alu(T(1), T(0), MUL, c=K_P1); alu(T(2), ST(0), SUB, b=T(1)); alu(T(1), T(0), MUL, c=K_P2); alu(T(2), T(2), SUB, b=T(1)); alu(T(1), T(0), MUL, c=K_P3); alu(T(2), T(2), SUB, b=T(1))
alu(T(3), T(2), MUL, b=T(2))
horner(T(4), T(3), K_S, NS); alu(T(4), T(4), MUL, b=T(3)); alu(T(4), T(4), MUL, b=T(2)); alu(T(4), T(4), ADD, b=T(2))      # T4 = sen r
horner(T(5), T(3), K_C, NC); alu(T(5), T(5), MUL, b=T(3)); alu(T(5), T(5), ADD, c=K_ONE)                                  # T5 = cos r
st(8)                                                                                                                     # variante: 0 FSIN, 1 FCOS, 2 FSINC, 3 FTAN (4 passos cada)
st(3, dst=ST(0), b=0); st(7); st(7); st(7)
st(3, dst=ST(0), b=1); st(7); st(7); st(7)
st(3, dst=T(6), b=0); st(3, dst=ST(0), b=1); st(4, a=T(6)); st(7)                                                         # FSINC: ST0 = seno, ST1 = cosseno
st(3, dst=T(6), b=0); st(3, dst=T(7), b=1); alu(ST(0), T(6), DIV, b=T(7)); st(7)
def lnpoly(): alu(T(4), T(3), MUL, b=T(3)); horner(T(5), T(4), K_L, NL); alu(T(5), T(5), MUL, b=T(3))                      # f em T3 -> ln em T5
def split(): st(2, dst=T(2), a=ST(0)); alu(T(0), 0, FILD); alu(T(3), T(2), SUB, c=K_ONE); alu(T(4), T(2), ADD, c=K_ONE); alu(T(3), T(3), DIV, b=T(4))
ENTRY['fln'] = len(PROG); split(); lnpoly(); alu(T(0), T(0), MUL, c=K_LN2); alu(ST(0), T(0), ADD, b=T(5)); st(7)
ENTRY['fyl2x'] = len(PROG); split(); lnpoly(); alu(T(5), T(5), MUL, c=K_L2E); alu(T(5), T(5), ADD, b=T(0)); alu(ST(1), ST(1), MUL, b=T(5)); st(7, a=1)
ENTRY['fyl2p'] = len(PROG); alu(T(4), ST(0), ADD, c=K_TWO); alu(T(3), ST(0), DIV, b=T(4)); lnpoly(); alu(T(5), T(5), MUL, c=K_L2E); alu(ST(1), ST(1), MUL, b=T(5)); st(7, a=1)
for nm, rc in (('frem', 3), ('frem1', 0)):
    ENTRY[nm] = len(PROG); alu(T(0), ST(0), DIV, b=ST(1)); alu(T(0), T(0), RND, rc=rc); alu(T(0), ST(1), MUL, b=T(0)); alu(ST(0), ST(0), SUB, b=T(0)); st(7)
assert len(PROG) <= 128 and len(CONST) <= 64
def word(p): return p['k'] | p['aop'] << 4 | p['rc'] << 8 | p['dst'] << 10 | p['a'] << 15 | p['bsel'] << 20 | p['b'] << 22 | p['q'] << 29
if __name__ == '__main__':
    # uma ROM de 512 x 36 bits (um bloco de RAM do FPGA): 0-127 passos; 256 + 4*i + parte = constante i em 3 pedacos (36 + 36 + 8 bits)
    o = ['', '// passo: [3:0] tipo, [7:4] operacao, [9:8] arredondamento, [14:10] destino, [19:15] A, [21:20] tipo de B, [28:22] B, [29] guarda o quadrante',
         'initial begin', "    for (ii = 0; ii < 512; ii = ii + 1) rom[ii] = 36'd7;"]
    o += ["    rom[%d] = 36'h%09x;" % (i, word(p)) for i, p in enumerate(PROG)]
    for i, v in enumerate(CONST): o += ["    rom[%d] = 36'h%09x; rom[%d] = 36'h%09x; rom[%d] = 36'h%09x;" % (256 + 4 * i, v & (2 ** 36 - 1), 257 + 4 * i, (v >> 36) & (2 ** 36 - 1), 258 + 4 * i, v >> 72)]
    o += ['end']
    o += ["localparam [6:0] UE_TRIG = 7'd%d, UE_FLN = 7'd%d, UE_FYL2X = 7'd%d, UE_FYL2P = 7'd%d, UE_FREM = 7'd%d, UE_FREM1 = 7'd%d;" % tuple(ENTRY[k] for k in ('trig', 'fln', 'fyl2x', 'fyl2p', 'frem', 'frem1'))]
    fn = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'rtl', 'fpu_unit.v'); t = open(fn).read()
    i = t.index('// >>> GERADO'); i = t.index('\n', i) + 1; j = t.index('    // <<< GERADO')
    open(fn, 'w').write(t[:i] + ''.join('    ' + l + '\n' for l in o[1:]) + t[j:])
    print(len(PROG), 'passos,', len(CONST), 'constantes')
