// fpu_top.v - FPU do R8064: pilha x87 (fpu_stk) + aritmetica (fpu_half/fpu_alu, a clk/2) + sequenciador de comandos + sequenciador de macros (transcendentais) para o nucleo.
// Interface: 'go' (1 pulso, so com busy=0) com cmd, idx (indice STn do byte da instrucao) e din (valor do registrador). 'busy' = 1 enquanto o comando termina.
// 'dout' e combinacional a partir de gsel (comandos GET >= 48) e sempre le registradores estaveis (rdr, sw, cw, tw).
// Registrador de passagem xin (80 bits): SETLO/SETHI o montam; LD32/LD64/FILD/LD80/WRC o consomem. rdr (80 bits) recebe ST(i) (RDI/RD0/RDC) ou o resultado de CVT32/CVT64/FIST.
// Contador cnt (3 bits): CLRCNT zera; RDC e WRC leem/gravam ST(cnt) e incrementam (FSAVE/FRSTR sem precisar de indice constante).
// Comandos: 0 NOP | 1 SETLO | 2 SETHI | 3 LD80 | 4 LD32 | 5 LD64 | 6 FILD | 8 FLD1 | 9 FLDZ | 10 FLDPI | 11 FLDL2T | 12 FLDLG2 | 13 FLDLN2
//  14 FADD | 15 FSUB | 16 FMUL | 17 FDIV (ST0 := ST0 op STn) | 18 FSQRT | 19 FCOM STn | 20 FCOPP | 21 FCHS | 22 FABS | 23 FXCH | 24 FLD STn | 25 FSTP STn | 26 FRINT
//  27 POP | 28 FINIT | 29 SETCW | 30 SETSW | 31 SETTW | 32 RDI | 33 RDC | 34 WRC | 35 CLRCNT | 36 CVT32 | 37 CVT64 | 38 FIST | 39 RD0
//  MACROS (ROM de firmware, ver 08_fpu/macro/fpu_macro.py): 40 FSIN | 41 FCOS | 42 FSINC | 43 FTAN | 44 FLN | 45 FYL2X | 46 FYL2P | 47 FREM | 7 FREM1
//  internos das macros: 48..51 ADDST SUBST MULST DIVST (STn := STn op ST0) | 63 KLD (empilha constante da ROM)
//  GET: 48 lo(rdr) | 49 hi(rdr) | 50 SW | 51 CW | 52 TW | 53 CC no formato de F ({C1,C3,000,C2,0,C0})
// Durante uma macro: arredondamento = nearest, precisao = 64 bits, so a excecao PE e acumulada pelas operacoes internas.
module fpu_top(
    input  wire        clk, rst,
    input  wire        go,
    input  wire [5:0]  cmd,
    input  wire [2:0]  idx,
    input  wire [63:0] din,
    output wire        busy,
    input  wire [5:0]  gsel,
    output reg  [63:0] dout
);
    reg [79:0] xin, rdr; reg [2:0] cnt, idxq;
    reg [2:0] st; reg [2:0] ps; reg [3:0] pk;
    localparam S_IDLE = 0, S_ONE = 1, S_ALU = 2, S_POST = 3, S_FR = 4;
    localparam P_NONE = 0, P_ST0 = 1, P_LD = 2, P_CMP = 3, P_CMP2 = 4, P_OUT = 5, P_POP = 6, P_STN = 7, P_FREM = 8;
    // gerado por 08_fpu/macro/fpu_macro.py - NAO editar a mao
    function [79:0] krom(input [5:0] i);
        case (i)
            6'd0: krom = 80'h00000000000000000000;
            6'd1: krom = 80'h3fff8000000000000000;
            6'd2: krom = 80'h3ffe8000000000000000;
            6'd3: krom = 80'h40008000000000000000;
            6'd4: krom = 80'h403f8000000000000000;
            6'd5: krom = 80'hffffc000000000000000;
            6'd6: krom = 80'hffff8000000000000000;
            6'd7: krom = 80'h3fffb504f333f9de6484;
            6'd8: krom = 80'h3ffeb17217f7d1cf79ac;
            6'd9: krom = 80'h3fffb8aa3b295c17f0bc;
            6'd10: krom = 80'h3ffea2f9836e4e44152a;
            6'd11: krom = 80'h3fffc90fdaa200000000;
            6'd12: krom = 80'h3fdd85a308d000000000;
            6'd13: krom = 80'h3fbfc4c6628b80dc1cd1;
            6'd14: krom = 80'hbffcaaaaaaaaaaaaaaab;
            6'd15: krom = 80'h3ff88888888888888889;
            6'd16: krom = 80'hbff2d00d00d00d00d00d;
            6'd17: krom = 80'h3fecb8ef1d2ab6399c7d;
            6'd18: krom = 80'hbfe5d7322b3faa271c7f;
            6'd19: krom = 80'h3fdeb092309d43684be5;
            6'd20: krom = 80'hbfd6d73f9f399dc0f88f;
            6'd21: krom = 80'h3fceca963b81856a5359;
            6'd22: krom = 80'hbfc697a4da340a0ab926;
            6'd23: krom = 80'hbffe8000000000000000;
            6'd24: krom = 80'h3ffaaaaaaaaaaaaaaaab;
            6'd25: krom = 80'hbff5b60b60b60b60b60b;
            6'd26: krom = 80'h3fefd00d00d00d00d00d;
            6'd27: krom = 80'hbfe993f27dbbc4fae397;
            6'd28: krom = 80'h3fe28f76c77fc6c4bdaa;
            6'd29: krom = 80'hbfdac9cba54603e4e906;
            6'd30: krom = 80'h3fd2d73f9f399dc0f88f;
            6'd31: krom = 80'hbfcab413c31dcbecbbde;
            6'd32: krom = 80'h3ffdaaaaaaaaaaaaaaab;
            6'd33: krom = 80'h3ffccccccccccccccccd;
            6'd34: krom = 80'h3ffc9249249249249249;
            6'd35: krom = 80'h3ffbe38e38e38e38e38e;
            6'd36: krom = 80'h3ffbba2e8ba2e8ba2e8c;
            6'd37: krom = 80'h3ffb9d89d89d89d89d8a;
            6'd38: krom = 80'h3ffb8888888888888889;
            6'd39: krom = 80'h3ffaf0f0f0f0f0f0f0f1;
            6'd40: krom = 80'h3ffad79435e50d79435e;
            6'd41: krom = 80'h3ffac30c30c30c30c30c;
            6'd42: krom = 80'h3ffab21642c8590b2164;
            6'd43: krom = 80'h3ffaa3d70a3d70a3d70a;
            default: krom = 80'd0;
        endcase
    endfunction
    function [15:0] mrom(input [9:0] a);
        case (a)
            10'd0: mrom = 16'h040a;
            10'd1: mrom = 16'h0050;
            10'd2: mrom = 16'h001a;
            10'd3: mrom = 16'h0026;
            10'd4: mrom = 16'h1c00;
            10'd5: mrom = 16'h040b;
            10'd6: mrom = 16'h0050;
            10'd7: mrom = 16'h00b1;
            10'd8: mrom = 16'h001b;
            10'd9: mrom = 16'h040c;
            10'd10: mrom = 16'h0050;
            10'd11: mrom = 16'h00b1;
            10'd12: mrom = 16'h001b;
            10'd13: mrom = 16'h040d;
            10'd14: mrom = 16'h0050;
            10'd15: mrom = 16'h00b1;
            10'd16: mrom = 16'h001b;
            10'd17: mrom = 16'h001b;
            10'd18: mrom = 16'h0018;
            10'd19: mrom = 16'h0050;
            10'd20: mrom = 16'h0416;
            10'd21: mrom = 16'h0050;
            10'd22: mrom = 16'h0415;
            10'd23: mrom = 16'h004e;
            10'd24: mrom = 16'h0059;
            10'd25: mrom = 16'h0050;
            10'd26: mrom = 16'h0414;
            10'd27: mrom = 16'h004e;
            10'd28: mrom = 16'h0059;
            10'd29: mrom = 16'h0050;
            10'd30: mrom = 16'h0413;
            10'd31: mrom = 16'h004e;
            10'd32: mrom = 16'h0059;
            10'd33: mrom = 16'h0050;
            10'd34: mrom = 16'h0412;
            10'd35: mrom = 16'h004e;
            10'd36: mrom = 16'h0059;
            10'd37: mrom = 16'h0050;
            10'd38: mrom = 16'h0411;
            10'd39: mrom = 16'h004e;
            10'd40: mrom = 16'h0059;
            10'd41: mrom = 16'h0050;
            10'd42: mrom = 16'h0410;
            10'd43: mrom = 16'h004e;
            10'd44: mrom = 16'h0059;
            10'd45: mrom = 16'h0050;
            10'd46: mrom = 16'h040f;
            10'd47: mrom = 16'h004e;
            10'd48: mrom = 16'h0059;
            10'd49: mrom = 16'h0050;
            10'd50: mrom = 16'h040e;
            10'd51: mrom = 16'h004e;
            10'd52: mrom = 16'h0059;
            10'd53: mrom = 16'h0050;
            10'd54: mrom = 16'h0090;
            10'd55: mrom = 16'h008e;
            10'd56: mrom = 16'h0097;
            10'd57: mrom = 16'h001b;
            10'd58: mrom = 16'h041f;
            10'd59: mrom = 16'h0050;
            10'd60: mrom = 16'h041e;
            10'd61: mrom = 16'h004e;
            10'd62: mrom = 16'h0059;
            10'd63: mrom = 16'h0050;
            10'd64: mrom = 16'h041d;
            10'd65: mrom = 16'h004e;
            10'd66: mrom = 16'h0059;
            10'd67: mrom = 16'h0050;
            10'd68: mrom = 16'h041c;
            10'd69: mrom = 16'h004e;
            10'd70: mrom = 16'h0059;
            10'd71: mrom = 16'h0050;
            10'd72: mrom = 16'h041b;
            10'd73: mrom = 16'h004e;
            10'd74: mrom = 16'h0059;
            10'd75: mrom = 16'h0050;
            10'd76: mrom = 16'h041a;
            10'd77: mrom = 16'h004e;
            10'd78: mrom = 16'h0059;
            10'd79: mrom = 16'h0050;
            10'd80: mrom = 16'h0419;
            10'd81: mrom = 16'h004e;
            10'd82: mrom = 16'h0059;
            10'd83: mrom = 16'h0050;
            10'd84: mrom = 16'h0418;
            10'd85: mrom = 16'h004e;
            10'd86: mrom = 16'h0059;
            10'd87: mrom = 16'h0050;
            10'd88: mrom = 16'h0417;
            10'd89: mrom = 16'h004e;
            10'd90: mrom = 16'h0059;
            10'd91: mrom = 16'h0050;
            10'd92: mrom = 16'h0401;
            10'd93: mrom = 16'h004e;
            10'd94: mrom = 16'h0059;
            10'd95: mrom = 16'h0057;
            10'd96: mrom = 16'h001b;
            10'd97: mrom = 16'h1400;
            10'd98: mrom = 16'h0803;
            10'd99: mrom = 16'h4c72;
            10'd100: mrom = 16'h0804;
            10'd101: mrom = 16'h4c77;
            10'd102: mrom = 16'h0805;
            10'd103: mrom = 16'h4c7c;
            10'd104: mrom = 16'h0808;
            10'd105: mrom = 16'h4c7e;
            10'd106: mrom = 16'h1000;
            10'd107: mrom = 16'h0800;
            10'd108: mrom = 16'h8057;
            10'd109: mrom = 16'h0059;
            10'd110: mrom = 16'h0801;
            10'd111: mrom = 16'h4015;
            10'd112: mrom = 16'h3400;
            10'd113: mrom = 16'h1800;
            10'd114: mrom = 16'h0400;
            10'd115: mrom = 16'h0070;
            10'd116: mrom = 16'h001b;
            10'd117: mrom = 16'h3400;
            10'd118: mrom = 16'h1800;
            10'd119: mrom = 16'h0405;
            10'd120: mrom = 16'h0059;
            10'd121: mrom = 16'h2401;
            10'd122: mrom = 16'h3400;
            10'd123: mrom = 16'h1800;
            10'd124: mrom = 16'h3400;
            10'd125: mrom = 16'h1800;
            10'd126: mrom = 16'h3404;
            10'd127: mrom = 16'h1800;
            10'd128: mrom = 16'h0803;
            10'd129: mrom = 16'h4c90;
            10'd130: mrom = 16'h0804;
            10'd131: mrom = 16'h4c95;
            10'd132: mrom = 16'h0805;
            10'd133: mrom = 16'h4c9a;
            10'd134: mrom = 16'h0808;
            10'd135: mrom = 16'h4c9e;
            10'd136: mrom = 16'h1000;
            10'd137: mrom = 16'h0800;
            10'd138: mrom = 16'h4057;
            10'd139: mrom = 16'h0059;
            10'd140: mrom = 16'h0802;
            10'd141: mrom = 16'h4015;
            10'd142: mrom = 16'h3400;
            10'd143: mrom = 16'h1800;
            10'd144: mrom = 16'h0400;
            10'd145: mrom = 16'h0070;
            10'd146: mrom = 16'h001b;
            10'd147: mrom = 16'h3400;
            10'd148: mrom = 16'h1800;
            10'd149: mrom = 16'h0405;
            10'd150: mrom = 16'h0059;
            10'd151: mrom = 16'h2401;
            10'd152: mrom = 16'h3400;
            10'd153: mrom = 16'h1800;
            10'd154: mrom = 16'h0401;
            10'd155: mrom = 16'h0059;
            10'd156: mrom = 16'h3400;
            10'd157: mrom = 16'h1800;
            10'd158: mrom = 16'h3404;
            10'd159: mrom = 16'h1800;
            10'd160: mrom = 16'h0803;
            10'd161: mrom = 16'h4cb1;
            10'd162: mrom = 16'h0804;
            10'd163: mrom = 16'h4cb6;
            10'd164: mrom = 16'h0805;
            10'd165: mrom = 16'h4cbb;
            10'd166: mrom = 16'h0808;
            10'd167: mrom = 16'h4cbd;
            10'd168: mrom = 16'h1000;
            10'd169: mrom = 16'h0800;
            10'd170: mrom = 16'h8057;
            10'd171: mrom = 16'h0051;
            10'd172: mrom = 16'h0059;
            10'd173: mrom = 16'h0800;
            10'd174: mrom = 16'h4015;
            10'd175: mrom = 16'h3400;
            10'd176: mrom = 16'h1800;
            10'd177: mrom = 16'h0400;
            10'd178: mrom = 16'h0070;
            10'd179: mrom = 16'h001b;
            10'd180: mrom = 16'h3400;
            10'd181: mrom = 16'h1800;
            10'd182: mrom = 16'h0405;
            10'd183: mrom = 16'h0059;
            10'd184: mrom = 16'h2401;
            10'd185: mrom = 16'h3400;
            10'd186: mrom = 16'h1800;
            10'd187: mrom = 16'h3400;
            10'd188: mrom = 16'h1800;
            10'd189: mrom = 16'h3404;
            10'd190: mrom = 16'h1800;
            10'd191: mrom = 16'h0803;
            10'd192: mrom = 16'h4cd2;
            10'd193: mrom = 16'h0804;
            10'd194: mrom = 16'h4cd8;
            10'd195: mrom = 16'h0805;
            10'd196: mrom = 16'h4cde;
            10'd197: mrom = 16'h0808;
            10'd198: mrom = 16'h4ce2;
            10'd199: mrom = 16'h1000;
            10'd200: mrom = 16'h0800;
            10'd201: mrom = 16'h8057;
            10'd202: mrom = 16'h0801;
            10'd203: mrom = 16'h4015;
            10'd204: mrom = 16'h0057;
            10'd205: mrom = 16'h0802;
            10'd206: mrom = 16'h4015;
            10'd207: mrom = 16'h0057;
            10'd208: mrom = 16'h3400;
            10'd209: mrom = 16'h1800;
            10'd210: mrom = 16'h0400;
            10'd211: mrom = 16'h0070;
            10'd212: mrom = 16'h001b;
            10'd213: mrom = 16'h0018;
            10'd214: mrom = 16'h3400;
            10'd215: mrom = 16'h1800;
            10'd216: mrom = 16'h0405;
            10'd217: mrom = 16'h0059;
            10'd218: mrom = 16'h2401;
            10'd219: mrom = 16'h0018;
            10'd220: mrom = 16'h3400;
            10'd221: mrom = 16'h1800;
            10'd222: mrom = 16'h0401;
            10'd223: mrom = 16'h0057;
            10'd224: mrom = 16'h3400;
            10'd225: mrom = 16'h1800;
            10'd226: mrom = 16'h3404;
            10'd227: mrom = 16'h1800;
            10'd228: mrom = 16'h0807;
            10'd229: mrom = 16'h6c01;
            10'd230: mrom = 16'h4404;
            10'd231: mrom = 16'h4050;
            10'd232: mrom = 16'h4059;
            10'd233: mrom = 16'h2000;
            10'd234: mrom = 16'h0407;
            10'd235: mrom = 16'h0053;
            10'd236: mrom = 16'h001b;
            10'd237: mrom = 16'h0809;
            10'd238: mrom = 16'h4402;
            10'd239: mrom = 16'h4050;
            10'd240: mrom = 16'h4059;
            10'd241: mrom = 16'h7000;
            10'd242: mrom = 16'h0018;
            10'd243: mrom = 16'h0401;
            10'd244: mrom = 16'h00b1;
            10'd245: mrom = 16'h004e;
            10'd246: mrom = 16'h00b3;
            10'd247: mrom = 16'h001b;
            10'd248: mrom = 16'h001b;
            10'd249: mrom = 16'h0018;
            10'd250: mrom = 16'h0050;
            10'd251: mrom = 16'h042b;
            10'd252: mrom = 16'h0050;
            10'd253: mrom = 16'h042a;
            10'd254: mrom = 16'h004e;
            10'd255: mrom = 16'h0059;
            10'd256: mrom = 16'h0050;
            10'd257: mrom = 16'h0429;
            10'd258: mrom = 16'h004e;
            10'd259: mrom = 16'h0059;
            10'd260: mrom = 16'h0050;
            10'd261: mrom = 16'h0428;
            10'd262: mrom = 16'h004e;
            10'd263: mrom = 16'h0059;
            10'd264: mrom = 16'h0050;
            10'd265: mrom = 16'h0427;
            10'd266: mrom = 16'h004e;
            10'd267: mrom = 16'h0059;
            10'd268: mrom = 16'h0050;
            10'd269: mrom = 16'h0426;
            10'd270: mrom = 16'h004e;
            10'd271: mrom = 16'h0059;
            10'd272: mrom = 16'h0050;
            10'd273: mrom = 16'h0425;
            10'd274: mrom = 16'h004e;
            10'd275: mrom = 16'h0059;
            10'd276: mrom = 16'h0050;
            10'd277: mrom = 16'h0424;
            10'd278: mrom = 16'h004e;
            10'd279: mrom = 16'h0059;
            10'd280: mrom = 16'h0050;
            10'd281: mrom = 16'h0423;
            10'd282: mrom = 16'h004e;
            10'd283: mrom = 16'h0059;
            10'd284: mrom = 16'h0050;
            10'd285: mrom = 16'h0422;
            10'd286: mrom = 16'h004e;
            10'd287: mrom = 16'h0059;
            10'd288: mrom = 16'h0050;
            10'd289: mrom = 16'h0421;
            10'd290: mrom = 16'h004e;
            10'd291: mrom = 16'h0059;
            10'd292: mrom = 16'h0050;
            10'd293: mrom = 16'h0420;
            10'd294: mrom = 16'h004e;
            10'd295: mrom = 16'h0059;
            10'd296: mrom = 16'h0050;
            10'd297: mrom = 16'h0401;
            10'd298: mrom = 16'h004e;
            10'd299: mrom = 16'h0059;
            10'd300: mrom = 16'h0090;
            10'd301: mrom = 16'h000e;
            10'd302: mrom = 16'h0099;
            10'd303: mrom = 16'h001b;
            10'd304: mrom = 16'h1400;
            10'd305: mrom = 16'h0803;
            10'd306: mrom = 16'h4d42;
            10'd307: mrom = 16'h0805;
            10'd308: mrom = 16'h4d46;
            10'd309: mrom = 16'h0806;
            10'd310: mrom = 16'h4d4a;
            10'd311: mrom = 16'h0804;
            10'd312: mrom = 16'h4d40;
            10'd313: mrom = 16'h10e4;
            10'd314: mrom = 16'h0006;
            10'd315: mrom = 16'h0408;
            10'd316: mrom = 16'h0072;
            10'd317: mrom = 16'h001b;
            10'd318: mrom = 16'h004e;
            10'd319: mrom = 16'h0059;
            10'd320: mrom = 16'h3400;
            10'd321: mrom = 16'h1800;
            10'd322: mrom = 16'h0400;
            10'd323: mrom = 16'h0070;
            10'd324: mrom = 16'h001b;
            10'd325: mrom = 16'h0d40;
            10'd326: mrom = 16'h0406;
            10'd327: mrom = 16'h0059;
            10'd328: mrom = 16'h2404;
            10'd329: mrom = 16'h0d40;
            10'd330: mrom = 16'h0405;
            10'd331: mrom = 16'h0059;
            10'd332: mrom = 16'h2401;
            10'd333: mrom = 16'h0d40;
            10'd334: mrom = 16'h0803;
            10'd335: mrom = 16'h4d61;
            10'd336: mrom = 16'h0805;
            10'd337: mrom = 16'h4d65;
            10'd338: mrom = 16'h0806;
            10'd339: mrom = 16'h4d69;
            10'd340: mrom = 16'h0804;
            10'd341: mrom = 16'h4d5d;
            10'd342: mrom = 16'h10e4;
            10'd343: mrom = 16'h0409;
            10'd344: mrom = 16'h0072;
            10'd345: mrom = 16'h001b;
            10'd346: mrom = 16'h0006;
            10'd347: mrom = 16'h004e;
            10'd348: mrom = 16'h0059;
            10'd349: mrom = 16'h0072;
            10'd350: mrom = 16'h001b;
            10'd351: mrom = 16'h3400;
            10'd352: mrom = 16'h1800;
            10'd353: mrom = 16'h0400;
            10'd354: mrom = 16'h0070;
            10'd355: mrom = 16'h001b;
            10'd356: mrom = 16'h0d5d;
            10'd357: mrom = 16'h0406;
            10'd358: mrom = 16'h0059;
            10'd359: mrom = 16'h2404;
            10'd360: mrom = 16'h0d5d;
            10'd361: mrom = 16'h0405;
            10'd362: mrom = 16'h0059;
            10'd363: mrom = 16'h2401;
            10'd364: mrom = 16'h0d5d;
            10'd365: mrom = 16'h080a;
            10'd366: mrom = 16'h8db0;
            10'd367: mrom = 16'h0018;
            10'd368: mrom = 16'h0403;
            10'd369: mrom = 16'h004e;
            10'd370: mrom = 16'h00b3;
            10'd371: mrom = 16'h001b;
            10'd372: mrom = 16'h001b;
            10'd373: mrom = 16'h0018;
            10'd374: mrom = 16'h0050;
            10'd375: mrom = 16'h042b;
            10'd376: mrom = 16'h0050;
            10'd377: mrom = 16'h042a;
            10'd378: mrom = 16'h004e;
            10'd379: mrom = 16'h0059;
            10'd380: mrom = 16'h0050;
            10'd381: mrom = 16'h0429;
            10'd382: mrom = 16'h004e;
            10'd383: mrom = 16'h0059;
            10'd384: mrom = 16'h0050;
            10'd385: mrom = 16'h0428;
            10'd386: mrom = 16'h004e;
            10'd387: mrom = 16'h0059;
            10'd388: mrom = 16'h0050;
            10'd389: mrom = 16'h0427;
            10'd390: mrom = 16'h004e;
            10'd391: mrom = 16'h0059;
            10'd392: mrom = 16'h0050;
            10'd393: mrom = 16'h0426;
            10'd394: mrom = 16'h004e;
            10'd395: mrom = 16'h0059;
            10'd396: mrom = 16'h0050;
            10'd397: mrom = 16'h0425;
            10'd398: mrom = 16'h004e;
            10'd399: mrom = 16'h0059;
            10'd400: mrom = 16'h0050;
            10'd401: mrom = 16'h0424;
            10'd402: mrom = 16'h004e;
            10'd403: mrom = 16'h0059;
            10'd404: mrom = 16'h0050;
            10'd405: mrom = 16'h0423;
            10'd406: mrom = 16'h004e;
            10'd407: mrom = 16'h0059;
            10'd408: mrom = 16'h0050;
            10'd409: mrom = 16'h0422;
            10'd410: mrom = 16'h004e;
            10'd411: mrom = 16'h0059;
            10'd412: mrom = 16'h0050;
            10'd413: mrom = 16'h0421;
            10'd414: mrom = 16'h004e;
            10'd415: mrom = 16'h0059;
            10'd416: mrom = 16'h0050;
            10'd417: mrom = 16'h0420;
            10'd418: mrom = 16'h004e;
            10'd419: mrom = 16'h0059;
            10'd420: mrom = 16'h0050;
            10'd421: mrom = 16'h0401;
            10'd422: mrom = 16'h004e;
            10'd423: mrom = 16'h0059;
            10'd424: mrom = 16'h0090;
            10'd425: mrom = 16'h000e;
            10'd426: mrom = 16'h0099;
            10'd427: mrom = 16'h001b;
            10'd428: mrom = 16'h0409;
            10'd429: mrom = 16'h0072;
            10'd430: mrom = 16'h001b;
            10'd431: mrom = 16'h0d5d;
            10'd432: mrom = 16'h0401;
            10'd433: mrom = 16'h004e;
            10'd434: mrom = 16'h0059;
            10'd435: mrom = 16'h0d4e;
            10'd436: mrom = 16'h0803;
            10'd437: mrom = 16'h4dc2;
            10'd438: mrom = 16'h080b;
            10'd439: mrom = 16'h4dc2;
            10'd440: mrom = 16'h0804;
            10'd441: mrom = 16'h4dc5;
            10'd442: mrom = 16'h080d;
            10'd443: mrom = 16'h4dc5;
            10'd444: mrom = 16'h080c;
            10'd445: mrom = 16'h4dc3;
            10'd446: mrom = 16'h0805;
            10'd447: mrom = 16'h4dc3;
            10'd448: mrom = 16'h2800;
            10'd449: mrom = 16'h1800;
            10'd450: mrom = 16'h004e;
            10'd451: mrom = 16'h3400;
            10'd452: mrom = 16'h1800;
            10'd453: mrom = 16'h0405;
            10'd454: mrom = 16'h0059;
            10'd455: mrom = 16'h2401;
            10'd456: mrom = 16'h3400;
            10'd457: mrom = 16'h1800;
            10'd458: mrom = 16'h0803;
            10'd459: mrom = 16'h4dd8;
            10'd460: mrom = 16'h080b;
            10'd461: mrom = 16'h4dd8;
            10'd462: mrom = 16'h0804;
            10'd463: mrom = 16'h4ddb;
            10'd464: mrom = 16'h080d;
            10'd465: mrom = 16'h4ddb;
            10'd466: mrom = 16'h080c;
            10'd467: mrom = 16'h4dd9;
            10'd468: mrom = 16'h0805;
            10'd469: mrom = 16'h4dd9;
            10'd470: mrom = 16'h2801;
            10'd471: mrom = 16'h1800;
            10'd472: mrom = 16'h004e;
            10'd473: mrom = 16'h3400;
            10'd474: mrom = 16'h1800;
            10'd475: mrom = 16'h0405;
            10'd476: mrom = 16'h0059;
            10'd477: mrom = 16'h2401;
            10'd478: mrom = 16'h3400;
            10'd479: mrom = 16'h1800;
            default: mrom = 16'h1800;
        endcase
    endfunction
    function [9:0] mentry(input [5:0] c);
        case (c)
            6'd40: mentry = 10'd98;
            6'd41: mentry = 10'd128;
            6'd42: mentry = 10'd191;
            6'd43: mentry = 10'd160;
            6'd44: mentry = 10'd305;
            6'd45: mentry = 10'd334;
            6'd46: mentry = 10'd365;
            6'd47: mentry = 10'd436;
            6'd7: mentry = 10'd458;
            default: mentry = 10'd0;
        endcase
    endfunction

    // ---- macros
    reg m_run, m_P, m_dn; reg [9:0] m_pc, m_ret; reg [1:0] m_kq;
    wire [15:0] mw = mrom(m_pc);
    wire [1:0] m_cnd = mw[15:14]; wire [3:0] m_kd = mw[13:10]; wire [9:0] m_arg = mw[9:0];
    wire m_ok = (m_cnd == 2'd0) || (m_cnd == 2'd1 && m_P) || (m_cnd == 2'd2 && !m_P);
    wire ext_macro = go && (cmd == 6'd7 || (cmd >= 6'd40 && cmd <= 6'd47));
    // ---- pilha
    reg s_go; reg [3:0] s_cmd; reg [2:0] s_idx, ra_idx, rb_idx; reg [79:0] s_wd; reg [5:0] s_fl;
    wire [79:0] ra, rb; wire [1:0] tag_a, tag_b; wire [15:0] cw, sw, tw; wire [3:0] fxam; wire es, stk_busy;
    fpu_stk u_stk(.clk(clk), .rst(rst), .go(s_go), .cmd(s_cmd), .idx(s_idx), .wdata(s_wd), .flags_in(s_fl), .ra_idx(ra_idx), .rb_idx(rb_idx),
                  .ra(ra), .rb(rb), .tag_a(tag_a), .tag_b(tag_b), .cw(cw), .sw(sw), .tw(tw), .fxam(fxam), .es(es), .busy(stk_busy));
    // ---- aritmetica
    reg a_start; reg [3:0] a_op; reg [79:0] a_a, a_b;
    wire a_busy, a_done, a_up; wire [79:0] a_res; wire [5:0] a_fl; wire [2:0] a_cc;
    fpu_half u_alu(.clk(clk), .rst(rst), .start(a_start), .op(a_op), .rc(m_run ? 2'd0 : cw[11:10]), .pc(m_run ? 2'd3 : cw[9:8]), .a(a_a), .b(a_b), .busy(a_busy), .done(a_done), .res(a_res), .flags(a_fl), .up(a_up), .cc(a_cc));
    wire [5:0] a_flm = m_run ? (a_fl & 6'h20) : a_fl;
    // ---- resto parcial
    reg fr_start; wire fr_busy, fr_done; wire [79:0] fr_res; wire [2:0] fr_q; reg [2:0] frq;
    fpu_frem u_frem(.clk(clk), .rst(rst), .start(fr_start), .near(m_arg[0]), .x(ra), .y(rb), .busy(fr_busy), .done(fr_done), .res(fr_res), .q(fr_q));
    assign busy = (st != S_IDLE) || stk_busy || a_busy || m_run || fr_busy;
    // ---- decisao de macro: palavra executada neste ciclo (macro ativa, tudo parado)
    wire m_idle = m_run && (st == S_IDLE) && !stk_busy && !a_busy && !fr_busy && !ext_macro;
    wire m_exec = m_idle && m_ok;
    wire m_icmd = m_exec && (m_kd == 4'd0 || m_kd == 4'd1);                 // CMD ou KLD: reaproveita o decodificador de comandos
    wire [5:0] cmd_e = m_icmd ? ((m_kd == 4'd1) ? 6'd63 : m_arg[5:0]) : cmd;
    wire [2:0] idx_i = m_icmd ? m_arg[8:6] : idx;
    wire go_e = m_icmd | go;
    wire [2:0] idx_e = (st == S_IDLE) ? idx_i : idxq;
    function [79:0] kconst(input [5:0] c);
        case (c)
            6'd8:  kconst = {16'h3FFF, 64'h8000_0000_0000_0000};
            6'd9:  kconst = 80'd0;
            6'd10: kconst = {16'h4000, 64'hC90F_DAA2_2168_C235};
            6'd11: kconst = {16'h4000, 64'hD49A_784B_CD1B_8AFE};
            6'd12: kconst = {16'h3FFD, 64'h9A20_9A84_FBCF_F799};
            default: kconst = {16'h3FFE, 64'hB172_17F7_D1CF_79AC};
        endcase
    endfunction
    wire sc0 = sw[8], sc1 = sw[9], sc2 = sw[10], sc3 = sw[14];
    // classificacao de um valor de 80 bits
    function [4:0] clsf(input [79:0] v);       // {big, small, neg, den, zero... } ver uso abaixo
        reg ex0, exf, m63, mz;
        begin
            ex0 = (v[78:64] == 15'd0); exf = (v[78:64] == 15'h7FFF); m63 = v[63]; mz = (v[62:0] == 63'd0);
            clsf[0] = exf ? !(m63 && mz) : (ex0 ? m63 : !m63);       // nan / nao suportado
            clsf[1] = exf && m63 && mz;                                // infinito
            clsf[2] = ex0 && !m63 && (v[62:0] == 63'd0);               // zero
            clsf[3] = ex0 && !m63 && !(v[62:0] == 63'd0);              // denormal
            clsf[4] = 1'b0;
        end
    endfunction
    wire [4:0] c0f = clsf(ra), c1f = clsf(rb);
    reg pval;
    always @* case (m_arg[3:0])
        4'd0: pval = m_kq[0];
        4'd1: pval = m_kq[1];
        4'd2: pval = m_kq[0] ^ m_kq[1];
        4'd3: pval = c0f[0];
        4'd4: pval = c0f[1];
        4'd5: pval = c0f[2];
        4'd6: pval = ra[79];
        4'd7: pval = c0f[3];
        4'd8: pval = (ra[78:64] >= 15'h3FFF + 15'd30);
        4'd9: pval = sc0;
        4'd10: pval = (ra[78:64] < 15'h3FFD);
        4'd11: pval = c1f[0];
        4'd12: pval = c1f[1];
        4'd13: pval = c1f[2];
        default: pval = m_dn;
    endcase
    wire signed [16:0] xe = $signed({2'b00, ra[78:64]}) - 17'sd16383 - (m_dn ? 17'sd64 : 17'sd0);
    always @* begin
        s_go = 1'b0; s_cmd = 4'd0; s_idx = idx_e; s_wd = 80'd0; s_fl = 6'd0; ra_idx = 3'd0; rb_idx = idx_e;
        a_start = 1'b0; a_op = 4'd0; a_a = ra; a_b = rb; fr_start = 1'b0;
        if (st == S_POST) begin
            case (pk)
                P_ST0:  case (ps)
                            3'd0: begin s_go = 1'b1; s_cmd = 4'd5; s_idx = 3'd0; s_wd = a_res; end
                            3'd1: begin s_go = 1'b1; s_cmd = 4'd10; s_fl = a_flm; end
                            default: begin s_go = !m_run; s_cmd = 4'd11; s_wd = {76'd0, sc3, sc2, a_up, sc0}; end
                        endcase
                P_STN:  case (ps)
                            3'd0: begin s_go = 1'b1; s_cmd = 4'd5; s_idx = idxq; s_wd = a_res; end
                            default: begin s_go = 1'b1; s_cmd = 4'd10; s_fl = a_flm; end
                        endcase
                P_LD:   case (ps)
                            3'd0: begin s_go = 1'b1; s_cmd = 4'd2; s_wd = a_res; end
                            default: begin s_go = 1'b1; s_cmd = 4'd10; s_fl = a_flm; end
                        endcase
                P_CMP, P_CMP2: case (ps)
                            3'd0: begin s_go = 1'b1; s_cmd = 4'd11; s_wd = {76'd0, a_cc[2], a_cc[1], 1'b0, a_cc[0]}; end
                            3'd1: begin s_go = 1'b1; s_cmd = 4'd10; s_fl = a_flm; end
                            default: begin s_go = (pk == P_CMP2); s_cmd = 4'd3; end
                        endcase
                P_OUT:  begin s_go = 1'b1; s_cmd = 4'd10; s_fl = a_flm; end
                P_POP:  begin s_go = 1'b1; s_cmd = 4'd3; end
                P_FREM: case (ps)
                            3'd0: begin s_go = 1'b1; s_cmd = 4'd5; s_idx = 3'd0; s_wd = fr_res; end
                            default: begin s_go = 1'b1; s_cmd = 4'd11; s_wd = {76'd0, frq[1], 1'b0, frq[0], frq[2]}; end
                        endcase
                default: ;
            endcase
        end else if (go_e && st == S_IDLE) begin
            case (cmd_e)
                6'd3: begin s_go = 1'b1; s_cmd = 4'd2; s_wd = xin; end
                6'd4, 6'd5, 6'd6: begin a_start = 1'b1; a_op = (cmd_e == 6'd4) ? 4'd9 : (cmd_e == 6'd5) ? 4'd10 : 4'd6; a_a = xin; end
                6'd8, 6'd9, 6'd10, 6'd11, 6'd12, 6'd13: begin s_go = 1'b1; s_cmd = 4'd2; s_wd = kconst(cmd_e); end
                6'd14, 6'd15, 6'd16, 6'd17: begin a_start = 1'b1; a_op = cmd_e[3:0] - 4'd14; end   // 14->0 ADD, 15->1 SUB, 16->2 MUL, 17->3 DIV
                6'd48, 6'd49, 6'd50, 6'd51: begin a_start = 1'b1; a_op = cmd_e[3:0] - 4'd0; a_a = rb; a_b = ra; end   // STn := STn op ST0
                6'd18: begin a_start = 1'b1; a_op = 4'd4; end
                6'd19: begin a_start = 1'b1; a_op = 4'd5; end
                6'd20: begin a_start = 1'b1; a_op = 4'd5; rb_idx = 3'd1; end
                6'd21: begin s_go = 1'b1; s_cmd = 4'd5; s_idx = 3'd0; s_wd = {~ra[79], ra[78:0]}; end
                6'd22: begin s_go = 1'b1; s_cmd = 4'd5; s_idx = 3'd0; s_wd = {1'b0, ra[78:0]}; end
                6'd23: begin s_go = 1'b1; s_cmd = 4'd4; ra_idx = 3'd0; rb_idx = idx_e; end
                6'd24: begin s_go = 1'b1; s_cmd = 4'd2; s_wd = rb; end
                6'd25: begin s_go = 1'b1; s_cmd = 4'd5; s_wd = ra; end
                6'd26: begin a_start = 1'b1; a_op = 4'd8; end
                6'd27: begin s_go = 1'b1; s_cmd = 4'd3; end
                6'd28: begin s_go = 1'b1; s_cmd = 4'd1; end
                6'd29: begin s_go = 1'b1; s_cmd = 4'd8; s_wd = {64'd0, din[15:0]}; end
                6'd30: begin s_go = 1'b1; s_cmd = 4'd12; s_wd = {64'd0, din[15:0]}; end
                6'd31: begin s_go = 1'b1; s_cmd = 4'd13; s_wd = {64'd0, din[15:0]}; end
                6'd32: ra_idx = idx_e;
                6'd33: ra_idx = cnt;
                6'd34: begin s_go = 1'b1; s_cmd = 4'd5; s_idx = cnt; s_wd = xin; end
                6'd36: begin a_start = 1'b1; a_op = 4'd11; end
                6'd37: begin a_start = 1'b1; a_op = 4'd12; end
                6'd38: begin a_start = 1'b1; a_op = 4'd7; end
                6'd63: begin s_go = 1'b1; s_cmd = 4'd2; s_wd = krom(m_arg[5:0]); end
                default: ;
            endcase
        end else if (m_exec) begin
            case (m_kd)
                4'd2: rb_idx = 3'd1;                                                     // PRED: ST1 pelo porto B
                4'd8: begin s_go = 1'b1; s_cmd = 4'd5; s_idx = 3'd0; s_wd = {ra[79], 15'h3FFF, ra[63:0]}; end   // XTR
                4'd9: begin s_go = 1'b1; s_cmd = 4'd10; s_fl = m_arg[5:0]; end            // FLG
                4'd13: begin s_go = 1'b1; s_cmd = 4'd11; s_wd = {76'd0, m_arg[3:0]}; end  // CC
                4'd10: begin fr_start = 1'b1; rb_idx = 3'd1; end                          // FREM
                default: ;
            endcase
        end
    end
    always @(posedge clk) begin
        if (rst) begin st <= S_IDLE; ps <= 0; pk <= P_NONE; cnt <= 0; xin <= 0; rdr <= 0; idxq <= 0; m_run <= 1'b0; m_P <= 1'b0; m_dn <= 1'b0; m_pc <= 0; m_ret <= 0; m_kq <= 0; frq <= 0; end
        else begin
            // ---- sequenciador de macros (uma palavra por ciclo quando tudo esta parado)
            if (ext_macro && st == S_IDLE) begin m_run <= 1'b1; m_pc <= mentry(cmd); m_P <= 1'b0; m_dn <= 1'b0; end
            else if (m_exec) begin
                m_pc <= m_pc + 10'd1;
                case (m_kd)
                    4'd2: m_P <= pval;
                    4'd3: m_pc <= m_arg;
                    4'd4: begin m_ret <= m_pc + 10'd1; m_pc <= m_arg; end
                    4'd5: m_pc <= m_ret;
                    4'd6: m_run <= 1'b0;
                    4'd7: m_kq <= rdr[1:0];
                    4'd8: xin <= {16'd0, {47{xe[16]}}, xe};
                    4'd10: begin st <= S_FR; end
                    4'd11: m_dn <= m_arg[0];
                    4'd12: xin <= xin + 80'd1;
                    default: ;
                endcase
            end else if (m_idle && !m_ok) m_pc <= m_pc + 10'd1;
            case (st)
                S_IDLE: if (go_e) begin
                    idxq <= idx_i;
                    case (cmd_e)
                        6'd1: xin[63:0] <= din;
                        6'd2: xin[79:64] <= din[15:0];
                        6'd32: rdr <= ra;
                        6'd39: rdr <= ra;
                        6'd33: begin rdr <= ra; cnt <= cnt + 3'd1; end
                        6'd34: cnt <= cnt + 3'd1;
                        6'd35: cnt <= 3'd0;
                        default: ;
                    endcase
                    case (cmd_e)
                        6'd4, 6'd5, 6'd6: begin st <= S_ALU; pk <= P_LD; end
                        6'd14, 6'd15, 6'd16, 6'd17, 6'd18, 6'd26: begin st <= S_ALU; pk <= P_ST0; end
                        6'd48, 6'd49, 6'd50, 6'd51: begin st <= S_ALU; pk <= P_STN; end
                        6'd19: begin st <= S_ALU; pk <= P_CMP; end
                        6'd20: begin st <= S_ALU; pk <= P_CMP2; end
                        6'd36, 6'd37, 6'd38: begin st <= S_ALU; pk <= P_OUT; end
                        6'd25: begin st <= S_POST; pk <= P_POP; ps <= 0; end
                        6'd7, 6'd40, 6'd41, 6'd42, 6'd43, 6'd44, 6'd45, 6'd46, 6'd47: ;          // macros: so ligam m_run
                        default: st <= S_ONE;
                    endcase
                end
                S_ONE: st <= S_IDLE;
                S_ALU: if (a_done) begin
                    st <= S_POST; ps <= 0;
                    if (pk == P_OUT) rdr <= a_res;
                end
                S_FR: if (fr_done) begin st <= S_POST; pk <= P_FREM; ps <= 0; frq <= fr_q; end
                S_POST: begin
                    case (pk)
                        P_ST0: if (ps == 3'd2) st <= S_IDLE; else ps <= ps + 3'd1;
                        P_STN: if (ps == 3'd1) st <= S_IDLE; else ps <= ps + 3'd1;
                        P_LD:  if (ps == 3'd1) st <= S_IDLE; else ps <= ps + 3'd1;
                        P_CMP: if (ps == 3'd1) st <= S_IDLE; else ps <= ps + 3'd1;
                        P_CMP2: if (ps == 3'd3) st <= S_IDLE; else ps <= ps + 3'd1;
                        P_FREM: if (ps == 3'd1) st <= S_IDLE; else ps <= ps + 3'd1;
                        default: st <= S_IDLE;
                    endcase
                end
                default: st <= S_IDLE;
            endcase
        end
    end
    always @* case (gsel)
        6'd48: dout = rdr[63:0];
        6'd49: dout = {48'd0, rdr[79:64]};
        6'd50: dout = {48'd0, sw};
        6'd51: dout = {48'd0, cw};
        6'd52: dout = {48'd0, tw};
        default: dout = {56'd0, sc1, sc3, 3'b000, sc2, 1'b0, sc0};
    endcase
endmodule
