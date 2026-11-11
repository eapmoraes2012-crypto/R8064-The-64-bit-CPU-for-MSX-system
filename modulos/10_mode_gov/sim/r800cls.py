import re
R='[ABCDEHL]'
# (regex, R800 base, R800 total com RAM interna [Grauw 'R800+wait'], observacao)
RULES=[
 (r'^NOP$','1','1'),
 (rf'^LD {R},{R}$','1','1'),
 (rf'^LD {R},\(HL\)$','2','4'),(rf'^LD \(HL\),{R}$','2','4'),
 (rf'^LD {R},n$','2','2'),(r'^LD \(HL\),n$','3','5'),
 (r'^LD A,\((BC|DE)\)$','2','4'),(r'^LD \((BC|DE)\),A$','2','4'),
 (r'^LD A,\(nn\)$','4','6'),(r'^LD \(nn\),A$','4','6'),
 (r'^LD HL,\(nn\)$','5','7'),(r'^LD \(nn\),HL$','5','7'),
 (r'^LD (BC|DE|HL|SP),nn$','3','3'),(r'^LD SP,HL$','1','1'),
 (r'^LD (BC|DE|SP|HL),\(nn\)$','6','8'),(r'^LD \(nn\),(BC|DE|SP|HL)$','6','8'),
 (r'^LD (IX|IY),nn$','4','4'),(r'^LD (IX|IY),\(nn\)$','6','8'),(r'^LD \(nn\),(IX|IY)$','6','8'),
 (r'^LD SP,(IX|IY)$','2','2'),
 (r'^LD A,(I|R)$','2','2'),(r'^LD (I|R),A$','2','2'),
 (rf'^LD {R},\((IX|IY)\+d\)$','5','7'),(rf'^LD \((IX|IY)\+d\),{R}$','5','7'),(r'^LD \((IX|IY)\+d\),n$','5','7'),
 (r'^LD (IXH|IXL|IYH|IYL),n$','3','3'),
 (rf'^LD ({R}|IXH|IXL|IYH|IYL),({R}|IXH|IXL|IYH|IYL)$','2','2'),
 (r'^(ADD|ADC|SBC) A,(' + R + r')$','1','1'),(r'^(SUB|AND|XOR|OR|CP) ' + R + '$','1','1'),
 (r'^(ADD|ADC|SBC) A,\(HL\)$','2','4'),(r'^(SUB|AND|XOR|OR|CP) \(HL\)$','2','4'),
 (r'^(ADD|ADC|SBC) A,n$','2','2'),(r'^(SUB|AND|XOR|OR|CP) n$','2','2'),
 (r'^(ADD|ADC|SBC) A,\((IX|IY)\+d\)$','5','7'),(r'^(SUB|AND|XOR|OR|CP) \((IX|IY)\+d\)$','5','7'),
 (r'^(ADD|ADC|SBC) A,(IXH|IXL|IYH|IYL)$','2','2'),(r'^(SUB|AND|XOR|OR|CP) (IXH|IXL|IYH|IYL)$','2','2'),
 (rf'^(INC|DEC) {R}$','1','1'),(r'^(INC|DEC) \(HL\)$','4','7'),(r'^(INC|DEC) \((IX|IY)\+d\)$','7','10'),
 (r'^(INC|DEC) (BC|DE|HL|SP)$','1','1'),(r'^(INC|DEC) (IX|IY)$','2','2'),(r'^(INC|DEC) (IXH|IXL|IYH|IYL)$','2','2'),
 (r'^ADD HL,(BC|DE|HL|SP)$','1','1'),(r'^ADD (IX|IY),(BC|DE|SP|IX|IY)$','2','2'),(r'^(ADC|SBC) HL,(BC|DE|HL|SP)$','2','2'),
 (r'^(RLCA|RRCA|RLA|RRA|DAA|CPL|SCF|CCF)$','1','1'),
 (r'^NEG$','2','2'),(r'^HALT$','2','2'),(r'^DI$','2','2'),(r'^EI$','1','1'),(r'^IM [012]$','3','3'),
 (r"^EX AF,AF'$",'1','1'),(r'^EXX$','1','1'),(r'^EX DE,HL$','1','1'),(r'^EX \(SP\),HL$','5','7'),(r'^EX \(SP\),(IX|IY)$','6','8'),
 (r'^JP nn$','3','5'),(r'^JP (NZ|Z|NC|C|PO|PE|P|M),nn$','3','5/3'),(r'^JP \(HL\)$','1','3'),(r'^JP \((IX|IY)\)$','2','4'),
 (r'^JR e$','3','3'),(r'^JR (NZ|Z|NC|C),e$','3/2','3/2'),(r'^DJNZ e$','3/2','3/2'),
 (r'^CALL nn$','5','8/7'),(r'^CALL (NZ|Z|NC|C|PO|PE|P|M),nn$','5/3','8/7/3'),
 (r'^RET$','3','5'),(r'^RET (NZ|Z|NC|C|PO|PE|P|M)$','3/1','5/1'),(r'^(RETI|RETN)$','5','7'),(r'^RST [0-9A-F]+H$','4','6/7'),
 (r'^PUSH (BC|DE|HL|AF)$','4','6'),(r'^PUSH (IX|IY)$','5','7'),(r'^POP (BC|DE|HL|AF)$','3','5'),(r'^POP (IX|IY)$','4','6'),
 (r'^IN (A,\(n\)|' + R + r',\(C\)|F,\(C\))$','3','10/9'),(r'^OUT (\(n\),A|\(C\),(' + R + r'|0))$','3','10/9'),
 (r'^(INI|IND|OUTI|OUTD)$','4','12/11'),(r'^(INIR|INDR|OTIR|OTDR)$','4/3','?/12/11'),
 (r'^(LDI|LDD)$','4','7'),(r'^(LDIR|LDDR)$','4','?/7'),(r'^(CPI|CPD)$','4','6'),(r'^(CPIR|CPDR)$','5','?/8'),(r'^(RLD|RRD)$','5','8'),
 # CB
 (rf'^(RLC|RRC|RL|RR|SLA|SRA|SLL|SRL) {R}$','2','2'),(r'^(RLC|RRC|RL|RR|SLA|SRA|SLL|SRL) \(HL\)$','5','8'),
 (rf'^BIT [0-7],{R}$','2','2'),(r'^BIT [0-7],\(HL\)$','3','5'),(rf'^(RES|SET) [0-7],{R}$','2','2'),(r'^(RES|SET) [0-7],\(HL\)$','5','8'),
 # DDCB / FDCB
 (r'^(RLC|RRC|RL|RR|SLA|SRA|SLL|SRL)( [0-7],)? ?\((IX|IY)\+d\)(,' + R + ')?$','7','10'),
 (r'^BIT [0-7],\((IX|IY)\+d\)(,' + R + ')?$','5','7'),(r'^(RES|SET) [0-7],\((IX|IY)\+d\)(,' + R + ')?$','7','10'),
]
RULES=[(re.compile(a),b,c) for a,b,c in RULES]
def classify(m):
    for rx,b,c in RULES:
        if rx.match(m): return b,c
    return None
def num(s):
    return [None if x=='?' else int(x) for x in s.split('/')]
