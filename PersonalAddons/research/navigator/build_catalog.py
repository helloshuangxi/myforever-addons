# Reproducible small NPC catalog extraction; no upstream addon code is bundled.
from pathlib import Path
from collections import Counter
import re,json,statistics,sys
from inspect_points import points,entries,q,Parser
base=Path(__file__).parent

def names(file):
 return {int(m[1]):Parser(m[2]).parse() for m in re.finditer(r'^  \[(\d+)\] = ("(?:\\.|[^"\\])*"),$',(base/file).read_text(),re.M)}
cn=names('pfquest_db_zhCN_units.lua');en=names('pfquest_db_enUS_units.lua');zones=names('pfquest_db_zhCN_zones.lua')
# Area IDs -> public Classic/Forever UiMapIDs, cross checked against Forever DBC map relationships.
maps={1:1426,3:1418,4:1419,8:1435,10:1431,11:1437,12:1429,14:1411,15:1445,16:1447,17:1413,28:1422,33:1434,36:1416,38:1432,40:1436,41:1430,44:1433,45:1417,46:1428,47:1425,51:1427,85:1420,130:1421,139:1423,141:1438,148:1439,215:1412,267:1424,331:1440,357:1444,361:1448,400:1441,405:1443,406:1442,440:1446,490:1449,493:1450,618:1452,1377:1451,1497:1458,1519:1453,1537:1455,1637:1454,1638:1456,1657:1457}
# Legacy Vanilla map coordinates differ from the Classic/Forever map rectangles.
# Robust affine fits from many stationary NPCs in the two map frames. See SOURCES.
transforms={44:(0.9998560289682143,-5.096040796625896,0.9998057063169004,0.019870119101469186),139:(0.9,-1.655,0.9003508771929825,-3.77415789473684),215:(0.8345100556268723,7.016536157466824,0.8343427085170163,13.18408301005114),1519:(0.7736308316430021,19.686105476673426,0.7738144329896908,24.435567010309274)}
selected={}
def add(n,cat,service,tags='',note=''):
 if n in points and n in cn and n in en:selected[n]=(cat,service,tags,note)
# Exact character-class titles identify trainers; the generic trainer flag alone
# also covers professions, pets and portals and must not be used as a class label.
# Titles/flags are factual cross-checks from the existing Forever reference;
# published names, coordinates and explicit factions remain pfQuest-derived.
trainer_classes=[
 ('warrior','Warrior','战士'),('paladin','Paladin','圣骑士'),
 ('hunter','Hunter','猎人'),('rogue','Rogue','盗贼'),
 ('priest','Priest','牧师'),('shaman','Shaman','萨满祭司'),
 ('mage','Mage','法师'),('warlock','Warlock','术士'),
 ('druid','Druid','德鲁伊'),
]
trainer_titles={english+' Trainer':(key,english,chinese) for key,english,chinese in trainer_classes}
trainer_audit={}
for n,row in sorted(q.items()):
 title=row.get(14)
 if title not in trainer_titles:continue
 key,english,chinese=trainer_titles[title]
 flag=row.get(15)
 facmatch=re.search(r'\["fac"\] = "([AH]+)"',entries.get(n,''))
 fac=facmatch[1] if facmatch else None
 audit=dict(npcID=n,classKey=key,name=en.get(n,row.get(1)),title=title,
            npcFlags=flag,pfquestFaction=fac,referenceFaction=row.get(13))
 trainer_audit[n]=audit
 if not isinstance(flag,int) or not flag&16:
  audit.update(status='excluded',reason='missing_trainer_flag');continue
 if n not in cn or n not in en:
  audit.update(status='excluded',reason='missing_pfquest_name');continue
 if fac not in ('A','H','AH'):
  audit.update(status='excluded',reason='missing_pfquest_faction');continue
 if fac!=row.get(13):
  audit.update(status='excluded',reason='faction_disagreement');continue
 if not points.get(n):
  audit.update(status='excluded',reason='missing_pfquest_coordinates');continue
 add(n,'trainers',chinese+'训练师',chinese+' 职业训练师 '+title,
     '职业技能、等级及任务要求以游戏内实际可学内容为准。')
 audit.update(status='pending_coordinates',coordinateChecks=[])
# Authored reputation/service descriptions, selected by NPC identity rather than copied guide text.
rep={10839:('银色黎明：声望任务','银色黎明 天灾石'),10840:('银色黎明：声望任务','银色黎明 天灾石'),10856:('银色黎明：军需官','银色黎明 军需官'),10857:('银色黎明：军需官','银色黎明 军需官'),11536:('银色黎明：军需官','银色黎明 军需官'),11555:('木喉要塞：声望任务','木喉要塞 羽毛'),11556:('木喉要塞：声望任务','木喉要塞 串珠'),11557:('木喉要塞：声望商人','木喉要塞 配方'),13278:('海达希亚水元素：任务','海达希亚水元素 水之精粹 灭火'),10618:('冬刃豹训练师：声望任务','冬刃豹训练师 坐骑'),14753:('银翼要塞：军需官','战歌峡谷 银翼要塞 PVP'),14754:('战歌氏族：军需官','战歌峡谷 战歌氏族 PVP'),15126:('污染者：军需官','阿拉希盆地 污染者 PVP'),15127:('阿拉索联军：军需官','阿拉希盆地 阿拉索联军 PVP'),13217:('雷矛卫队：军需官','奥特兰克山谷 雷矛卫队 PVP'),14921:('赞达拉部族：声望商人','赞达拉部族 祖尔格拉布 配方'),14902:('赞达拉部族：装备任务','赞达拉部族 祖尔格拉布 套装'),14903:('赞达拉部族：装备任务','赞达拉部族 祖尔格拉布 套装'),14904:('赞达拉部族：装备任务','赞达拉部族 祖尔格拉布 套装'),14905:('赞达拉部族：装备任务','赞达拉部族 祖尔格拉布 套装'),15070:('赞达拉部族：声望任务','赞达拉部族 祖尔格拉布 硬币 宝石'),15176:('塞纳里奥议会：装备任务','塞纳里奥议会 希利苏斯 套装'),15180:('塞纳里奥议会：任务','塞纳里奥议会 流沙节杖'),15181:('塞纳里奥议会：任务','塞纳里奥议会 希利苏斯'),15183:('塞纳里奥议会：声望任务','塞纳里奥议会 暮光密文信'),15191:('塞纳里奥议会：任务','塞纳里奥议会 希利苏斯'),15282:('塞纳里奥议会：任务','塞纳里奥议会 希利苏斯'),15500:('塞纳里奥议会：装备任务','塞纳里奥议会 安其拉废墟 套装'),15540:('塞纳里奥议会：声望任务','塞纳里奥议会 深渊纹章')}
rep.update({13219:('霜狼氏族：军需官','奥特兰克山谷 霜狼氏族 PVP'),14624:('瑟银兄弟会：商人和任务','瑟银兄弟会 声望 任务'),14625:('瑟银兄弟会：声望任务','瑟银兄弟会 声望 任务'),14626:('瑟银兄弟会：任务','瑟银兄弟会 声望 任务'),14627:('瑟银兄弟会：任务','瑟银兄弟会 声望 任务'),14628:('瑟银兄弟会：任务','瑟银兄弟会 声望 任务'),14567:('瑟银兄弟会：任务','瑟银兄弟会 锻造 任务'),6707:('拉文霍德：任务','拉文霍德 盗贼 任务'),6768:('拉文霍德：任务','拉文霍德 盗贼 任务'),15498:('塞纳里奥议会：装备任务','塞纳里奥议会 安其拉废墟 套装'),15499:('塞纳里奥议会：装备任务','塞纳里奥议会 安其拉废墟 套装')})
for n,(svc,tags) in rep.items():add(n,'reputation',svc,tags,'部分交互或奖励需要对应声望、等级及前置任务。')
# Standard profession supply titles are functional facts; Chinese labels are authored here.
roles={'Alchemy Supplies':'炼金材料商人','Enchanting Supplies':'附魔材料商人','Tailoring Supplies':'裁缝材料商人','Engineering Supplies':'工程材料商人','Leatherworking Supplies':'制皮材料商人','Blacksmithing Supplies':'锻造材料商人','Reagents Vendor':'施法材料商人','Trade Supplies':'商贸材料商人','General & Trade Supplies':'杂货与商贸材料','Reagents and Herbs':'施法材料与草药','Leatherworking & Tailoring Supplies':'制皮与裁缝材料'}
# Aim for geographic coverage; up to 3 vendors per (zone, role) and 10 per zone.
counts={};zonecounts={}
for n,row in sorted(q.items()):
 title=row.get(14);pts=points.get(n,[])
 if title not in roles or not pts:continue
 zone=pts[0][2]
 if zone not in maps:continue
 key=(zone,title)
 if counts.get(key,0)>=2 or zonecounts.get(zone,0)>=8:continue
 if n not in cn:continue
 add(n,'materials',roles[title],roles[title]+' 材料 供应商 配方 图纸');counts[key]=counts.get(key,0)+1;zonecounts[zone]=zonecounts.get(zone,0)+1
special={12919:('钓鱼进阶任务','钓鱼 纳特'),8125:('烹饪进阶任务与补给','烹饪 加基森'),8736:('工程训练','工程 加基森'),7406:('侏儒工程任务','侏儒工程 专精'),11832:('月光林地任务','德鲁伊 月光林地'),11191:('武器锻造专精任务','锻造 铸剑'),11192:('武器锻造专精任务','锻造 铸斧'),7879:('菲拉斯任务','晨光麦研究'),14394:('暴风城任务','巨龙 头颅'),13840:('霜狼氏族任务','奥特兰克山谷 PVP'),12939:('急救进阶训练与任务','急救 联盟'),12920:('急救进阶训练与任务','急救 部落'),3181:('急救训练与任务','急救 部落'),2626:('钓鱼用品','钓鱼 技能书'),5164:('护甲锻造训练与任务','锻造 护甲 专精'),11867:('武器训练','武器大师'),11868:('武器训练','武器大师'),11869:('武器训练','武器大师'),11870:('武器训练','武器大师'),4730:('坐骑商人','坐骑 夜刃豹'),3362:('坐骑商人','坐骑 狼'),1261:('坐骑商人','坐骑 山羊'),7952:('坐骑商人','坐骑 迅猛龙'),3685:('坐骑商人','坐骑 科多兽'),4731:('坐骑商人','坐骑 亡灵马'),384:('坐骑商人','坐骑 马')}
for n,(svc,tags) in special.items():add(n,'special',svc,tags,'训练、任务或购买资格以游戏内实际要求为准。')
# Selected flight masters: one per map and faction, plus the six city auction/bank services.
seen=set()
for n,row in sorted(q.items()):
 pts=points.get(n,[])
 if not pts or not isinstance(row.get(15),int) or not row[15]&8:continue
 z=pts[0][2];f=row.get(13)
 if z not in maps or f not in ['A','H','AH'] or (z,f) in seen:continue
 if n not in cn:continue
 seen.add((z,f));add(n,'services','飞行管理员','交通 飞行点 飞行管理员','需要先发现飞行点；可用航线以角色解锁情况为准。')
# Generate static records only when an outdoor point can be cross-checked in both sources.
out=[];skipped=[]
for n,(cat,svc,tags,note) in selected.items():
 seenzones=set()
 for x,y,z in points[n]:
  if z not in maps or z in seenzones:continue
  # Cross-check the factual map-frame relationship and reject migrated or ambiguous spawn locations.
  oldx,oldy=x,y
  if z in transforms:
   ax,bx,ay,by=transforms[z];x=ax*x+bx;y=ay*y+by
  reference=q[n].get(7) if n in q else None
  matches=reference.get(z) if reference else None
  errors=[abs(x-p[1])+abs(y-p[2]) for p in matches.values()] if matches else []
  if cat=='trainers':
   trainer_audit[n]['coordinateChecks'].append(dict(areaID=z,mapID=maps[z],
    pfquest=[oldx,oldy],converted=[x,y],
    referenceMinError=min(errors) if errors else None))
  if not errors or min(errors)>0.65:
   skipped.append((n,z,oldx,oldy));continue
  if not (0<x<100 and 0<y<100):continue
  seenzones.add(z)
  fac=re.search(r'\["fac"\] = "([AH]+)"',entries[n]);faction={'A':'Alliance','H':'Horde','AH':'Neutral'}.get(fac[1] if fac else '', 'Neutral')
  out.append(dict(id=f'npc-{n}-{maps[z]}',name=cn[n],english=en[n],npcID=n,category=cat,faction=faction,mapID=maps[z],x=round(x/100,5),y=round(y/100,5),zone=zones[z],service=svc,note=note+'离线经典资料，Forever 尚待游戏实测。',tags=tags,source='pfquest-104f356'))
out.sort(key=lambda p:(['trainers','reputation','materials','special','services'].index(p['category']),p['mapID'],p['npcID']))
for n,audit in trainer_audit.items():
 if audit['status']!='pending_coordinates':continue
 accepted=[p for p in out if p['category']=='trainers' and p['npcID']==n]
 if accepted:
  audit.update(status='included',pointIDs=[p['id'] for p in accepted])
 else:
  audit.update(status='excluded',reason='no_coordinate_agreement')
def lua(v):
 if isinstance(v,str):return json.dumps(v,ensure_ascii=False)
 return str(v)
header='''local _, NS = ...

-- Small curated extraction of pfQuest's MIT-licensed Vanilla database.
-- Copyright (c) 2017-2021 Eric Mauser (Shagu). Full notice: SOURCES.md.
-- Classic/Forever map-frame conversions and selection authored 2026-11-08.
-- Static reference points, not live NPC tracking. Forever gameplay verification pending.
NS.Categories = {
    {id = "trainers", label = "职业训练师"},
    {id = "reputation", label = "声望与军需官"},
    {id = "materials", label = "材料商人"},
    {id = "special", label = "特殊 NPC"},
    {id = "services", label = "常用服务"},
}
NS.Points = {
'''
target=base.parents[2]/'_forever_/Interface/AddOns/MyForeverNavigator/Data.lua'
target.parent.mkdir(parents=True,exist_ok=True)
target.write_text(header+'\n'.join('    {'+', '.join(k+' = '+lua(v) for k,v in p.items())+'},' for p in out)+'\n}\n')
(base/'catalog-facts.json').write_text(json.dumps({'points':out,'skipped':skipped,'transforms':transforms},ensure_ascii=False,indent=2))
trainer_points=[p for p in out if p['category']=='trainers']
(base/'trainer-audit.json').write_text(json.dumps({
 'schemaVersion':1,
 'sources':{'pfquest':'104f35678ca39ab1fb78b655f815cc7016f5e0c8',
            'foreverReference':'aa1d7e7294596cf50a6fd0946dfae0d969cb9623'},
 'selection':{'exactTitles':trainer_titles,'requiredNpcFlagsBit':16,
              'requireExplicitPfquestFaction':True,'requireFactionAgreement':True,
              'maximumCoordinateError':0.65,'coordinateErrorUnit':'sum of map percentage-point X/Y differences'},
 'summary':{'candidates':len(trainer_audit),'points':len(trainer_points),
            'npcs':len(set(p['npcID'] for p in trainer_points)),
            'maps':len(set(p['mapID'] for p in trainer_points)),
            'classes':{key:sum(1 for p in trainer_points if trainer_audit[p['npcID']]['classKey']==key)
                       for key,_,_ in trainer_classes},
            'factions':dict(Counter(p['faction'] for p in trainer_points)),
            'excluded':dict(Counter(a['reason'] for a in trainer_audit.values() if a['status']=='excluded'))},
 'candidates':list(trainer_audit.values()),
},ensure_ascii=False,indent=2))
print('destination',target);print('points',len(out),'NPCs',len(set(p['npcID'] for p in out)),'maps',len(set(p['mapID'] for p in out)),Counter(p['category'] for p in out));print('skipped',skipped)
