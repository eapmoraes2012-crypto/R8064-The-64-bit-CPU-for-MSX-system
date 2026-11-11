import os,sys
s=open('mmu.v').read()
H=sys.argv[1]
M={
1:("(e_g[i] || e_asid[i] == s1_asid) &&","(e_asid[i] == s1_asid) &&"),
2:("(e_g[i] || e_asid[i] == s1_asid) &&","1 &&"),
3:("(e_big[i] || e_vpn[i][8:0] == s1_vpn[8:0]);","(e_vpn[i][8:0] == s1_vpn[8:0]);"),
4:("h_big ? {h_ppn[19:9], s2_addr[20:0]}","h_big ? {h_ppn[19:9], 9'd0, s2_addr[11:0]}"),
5:("(s2_acc == 2'd1 && !h_w) ||",""),
6:("(s2_user && !h_u) ||",""),
7:(" || (!s2_user && h_u && s2_acc == 2'd2)",""),
8:(" || (s2_acc == 2'd1 && !h_d)",""),
9:("wire canon1 = (s1_addr[63:39] == {25{s1_addr[38]}});","wire canon1 = 1;"),
10:("if (lvl == 2'd2 || (lvl == 2'd1 && pppn[8:0] != 0))","if (lvl == 2'd1 && pppn[8:0] != 0)"),
11:(" || (lvl == 2'd1 && pppn[8:0] != 0)) begin wf_valid"," ) begin wf_valid"),
12:("else if (pppn[19:10] != 0) begin wf_valid <= 1; wf_cause <= 3'd4; ws <= W_IDLE; end\n                        else begin   // instala","else begin   // instala"),
13:("(e_big[i] || e_vpn[i][8:0] == fl_va[20:12])","(e_vpn[i][8:0] == fl_va[20:12])"),
14:("if (restart || flush_any) begin","if (0) begin"),
15:("if (fl_asid_en && !e_g[i] && ","if (fl_asid_en && "),
16:(" || (pw && !pr)) begin wf_valid",") begin wf_valid"),
17:("if (fl_va_en && e_vpn[i][26:9] == fl_va[38:21] &&","if (fl_va_en && 1'b0 &&"),
18:("if (flush_any && (s2_valid || adv)) s2_stale <= 1;","if (flush_any && s2_valid) s2_stale <= 1;"),
19:("else if (p_valid) begin s2_valid <= 0; wf_valid <= 0; end","else if (p_valid) begin s2_valid <= 0; end"),
20:("mt2 <= ({{(NENT-1){1'b0}}, 1'b1} << vic); s2_stale <= 0;","s2_stale <= 0;"),
}
for n,(a,b) in M.items():
    if s.count(a)!=1: print("m",n,"padrao",s.count(a)); continue
    with open(os.path.join(H,f'm_{n}.v'),'w') as f: f.write(s.replace(a,b))
