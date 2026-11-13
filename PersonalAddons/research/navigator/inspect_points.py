import re, pathlib, json, ast, statistics
base=pathlib.Path(__file__).parent
raw=(base/'pfquest_db_units.lua').read_text()
entries={int(m[1]):m[2] for m in re.finditer(r'^  \[(\d+)\] = \{\n(.*?)^  \},',raw,re.M|re.S)}
points={n:[(float(x),float(y),int(z)) for x,y,z in re.findall(r'\{ ([\d.]+), ([\d.]+), (\d+), \d+ \}',s)] for n,s in entries.items()}
# Only inspect a narrow fact from the comparison source: first spawn table and friendly faction.
class Parser:
 def __init__(self,s):self.s=s;self.i=0
 def ws(self):
  while self.i<len(self.s) and self.s[self.i].isspace():self.i+=1
 def parse(self):
  self.ws();c=self.s[self.i]
  if c in "'\"":
   q=c;self.i+=1;out=''
   while self.i<len(self.s):
    c=self.s[self.i];self.i+=1
    if c==q:return out
    if c=='\\':c=self.s[self.i];self.i+=1
    out+=c
  if c=='{':
   self.i+=1;d={};n=1
   while True:
    self.ws()
    if self.s[self.i]=='}':self.i+=1;return d
    if self.s[self.i]=='[':
     self.i+=1;k=self.parse();self.ws();assert self.s[self.i]==']';self.i+=1;self.ws();assert self.s[self.i]=='=';self.i+=1;v=self.parse();d[k]=v
    else:d[n]=self.parse();n+=1
    self.ws()
    if self.s[self.i]==',':self.i+=1
  if self.s[self.i:].startswith('nil'):self.i+=3;return None
  m=re.match(r'-?\d+(?:\.\d+)?',self.s[self.i:]);assert m,self.s[self.i:self.i+40];self.i+=len(m[0]);return float(m[0]) if '.' in m[0] else int(m[0])
q={}
for m in re.finditer(r'^\[(\d+)\] = (\{.*\}),$',(base/'data_Forever_foreverNpcDB.lua').read_text(),re.M):
 q[int(m[1])]=Parser(m[2]).parse()
if __name__=='__main__':
 zones={}
 for n,pts in points.items():
  if len(pts)!=1 or n not in q:continue
  x,y,z=pts[0];sp=q[n].get(7)
  if not sp or not sp.get(z) or len(sp[z])!=1:continue
  new=sp[z][1]
  if new[1]<0:continue
  zones.setdefault(z,[]).append((x,y,new[1],new[2]))
 for z,p in sorted(zones.items()):
  if len(p)<10:continue
  err=statistics.median(abs(a-c)+abs(b-d) for a,b,c,d in p)
  if err>.25:
   def reg(k,j):
    X=[v[k] for v in p];Y=[v[j] for v in p];mx=statistics.mean(X);my=statistics.mean(Y);a=sum((x-mx)*(y-my) for x,y in zip(X,Y))/sum((x-mx)**2 for x in X);b=my-a*mx;return a,b
   ax,bx=reg(0,2);ay,by=reg(1,3)
   errs=[abs(ax*a+bx-c)+abs(ay*b+by-d) for a,b,c,d in p]
   print(z,len(p),'median raw',round(err,3),'fit',tuple(round(v,6) for v in (ax,bx,ay,by)),'fit median',round(statistics.median(errs),3),'max',round(max(errs),2))
