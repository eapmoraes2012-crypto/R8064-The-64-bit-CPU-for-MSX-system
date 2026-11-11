import json,re,sys
r=json.load(open(sys.argv[1]))
p=r['critical_paths'][0]['path']
t=0;out=[]
for s in p:
    t+=s['delay']
    if s['type']=='logic' and s['delay']>0.2 or s['type'] in('clk-to-q','setup'):
        n=re.sub(r'(_ALU_COUT|_CIN|_COUT|_ALU_SUM)+','~',s['to']['cell'])
        out.append((round(t,2),s['type'],n[:50]))
print('start',p[0]['from']['cell'][:40],'end',p[-1]['to']['cell'][:40],'total',round(t,2))
for o in out[:6]+out[-6:]: print(o)
