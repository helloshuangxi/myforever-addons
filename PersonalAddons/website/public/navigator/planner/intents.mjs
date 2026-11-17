const professions = [ ['采矿','挖矿'],['草药学','采药','草药','采草'],['剥皮','扒皮'],['炼金','炼金术','做药剂'],['锻造','打铁'],['制皮'],['裁缝','做布甲'],['工程学','工程'],['附魔'],['急救','做绷带'],['烹饪','做饭','做菜'],['钓鱼','垂钓'] ];
const classes = ['战士','圣骑士','猎人','盗贼','牧师','萨满祭司','法师','术士','德鲁伊'];
const materials = ['炼金','附魔','裁缝','工程','制皮','锻造','施法'];
const factions = ['银色黎明','木喉要塞','塞纳里奥议会','瑟银兄弟会','赞达拉部族','海达希亚水元素','冬刃豹训练师','拉文霍德','银翼要塞','战歌氏族','阿拉索联军','污染者','雷矛卫队','霜狼氏族'];
const serviceRows = [
  ['银行职员','银行','存东西','存装备','存钱','取钱','存放物品','bank'], ['拍卖师','拍卖行','拍卖','ah','auction house'],
  ['旅店老板','旅馆','旅店','绑炉石','绑定炉石','定炉石','住店','innkeeper'], ['飞行管理员','飞行点','鸟点','飞行大师','flight master'],
  ['兽栏管理员','兽栏','寄存宠物','stable master'], ['修理','修装备','修理装备','修理商','维修','repair'],
  ['坐骑商人','买马','买坐骑'],['武器训练','武器大师','学武器'],['军需官','声望商人','军需商'],['材料商人','材料商','商贸材料商人'],
];
for (const [name, ...synonyms] of professions) {
  serviceRows.push([name+'训练师', ...[name,...synonyms].flatMap(s => [s,'学'+s,s+'训练师',s+'老师'])]);
}
for (const name of classes) serviceRows.push([name+'训练师',name+'职业训练师',name+'老师',...(name === '盗贼' ? ['潜行者训练师'] : [])]);
for (const name of materials) serviceRows.push([name+'材料商人',name+'材料商','买'+name+'材料']);
for (const name of factions) serviceRows.push([name,name+'声望',name+'军需官']);

// A short retrieval list keeps a tiny on-device model grounded in relevant services.
const cues = new Map([
  ['银行职员',/背包|袋子.*满|腾.*空间|装不下|储物|储存|寄存|存放|存起来|存钱|取钱|取回|保管|仓库|bank|stash|store/i],
  ['拍卖师',/拍卖|挂单|挂售|挂上|出价|竞价|交易|卖给.*玩家|玩家.*买|auction/i],
  ['旅店老板',/炉石|旅店|宾馆|旅馆|睡|休息|住宿|落脚|客栈|inn\b/i],
  ['飞行管理员',/飞行|狮鹫|双足飞龙|鸟点|坐鸟|flight|gryphon/i],
  ['修理',/修理|耐久|修装备|坏了|坏掉|破损|repair/i], ['兽栏管理员',/野兽|兽栏|宠物|stable/i],
  ['坐骑商人',/坐骑|买马|骑马|mount/i],['武器训练',/武器.*熟练|武器大师|学习武器|武器.*训练/],
  ['军需官',/军需|声望/], ['材料商人',/材料|物资/],
  ...professions.map(([name,...words])=>[name+'训练师',new RegExp([name,...words].join('|'))]),
  ...materials.map(name=>[name+'材料商人',new RegExp(name+'.*材料|材料.*'+name)]),
  ...classes.map(name=>[name+'训练师',new RegExp(name)]), ...factions.map(name=>[name,new RegExp(name)]),
]);
const cities = {'暴风城':['暴风','stormwind'], '铁炉堡':['铁堡','ironforge'], '奥格瑞玛':['奥格','orgrimmar'], '达纳苏斯':['darnassus'], '雷霆崖':['thunder bluff'], '幽暗城':['undercity']};
const utf8 = new TextEncoder();
export const byteLength = value => utf8.encode(value).length;
export const keyOf = value => value.normalize('NFKC').trim().toLowerCase().replace(/[\s·•'’.,，。！？!?、]/gu,'');
const tidy = value => value.trim().replace(/^[\s，,。.!！?？、]+|[\s，,。.!！?？、]+$/gu,'');
const invalid = /[\p{Cc}\p{Cf}~|<>\/\\]/u;
export const validQuestion = value => typeof value === 'string' && !!value.trim() && byteLength(value) <= 240 && !/[\p{Cc}\p{Cf}~|<\/\\]/u.test(value);

export function makeCatalog(source) {
  const zones = source.zones.map(name => [name,...cities[name] || []]);
  const npcs = source.npcs;
  const stops = source.stops || [];
  const rows = [...serviceRows,...npcs,...stops.map(([name])=>[name])];
  const names = new Set(rows.map(row => row[0]));
  const exact = new Map();
  for (const [name,...aliases] of rows) for (const raw of [name,...aliases]) {
    const key = keyOf(raw);
    if (!key) continue;
    if (exact.has(key) && exact.get(key) !== name) exact.set(key, null);
    else exact.set(key, name);
  }
  const zoneTerms = zones.flatMap(([name,...aliases]) => [name,...aliases].map(a=>[a,name])).sort((a,b)=>b[0].length-a[0].length);
  const allowed = new Set([...names, ...source.zones]);
  return { stops, zones: new Set(source.zones), zoneTerms, npcs, exact, names, allowed, services: serviceRows.map(row=>row[0]) };
}

export function validTerm(term, db) {
  if (typeof term !== 'string' || term !== term.trim() || !term || invalid.test(term) || byteLength(term)>64) return false;
  if (db.allowed.has(term)) return true;
  const [zone, ...tail] = term.split(' ');
  return db.zones.has(zone) && db.names.has(tail.join(' '));
}

export function fingerprint(question) {
  let value = 5381;
  for (const byte of utf8.encode(question)) value = (Math.imul(value, 33) + byte) >>> 0;
  return value.toString(16).padStart(8,'0');
}

export function commandFor(question, terms, db) {
  if (!validQuestion(question) || !Array.isArray(terms) || !terms.length || terms.length>6 || !terms.every(t=>validTerm(t,db))) return null;
  const code = `MFN1@${fingerprint(question)}~${terms.join('~')}`;
  return byteLength(code)<=240 ? `/mynav route ${code}` : null;
}

export function splitStops(query, db) {
  let text = tidy(query);
  // An explicit starting map is context. The add-on chooses the real origin from the character.
  const startMatch = text.match(/^从(.{1,24}?)(?:出发[，,、\s]*|前往|赶往|去|到)/u);
  if (startMatch && db.zoneTerms.some(([alias])=>keyOf(alias)===keyOf(startMatch[1]))) text=text.slice(startMatch[0].length);
  return text.split(/(?:[→>;；]|[，,、]\s*(?:(?:然后|接着|最后|之后|再)\s*(?:去|到|找)?)|(?:然后|接着|最后|之后|再去|再找|再到|再学|顺便去|顺路去|顺便找|顺路找|并前往)|\s+then\s+)/iu).map(tidy);
}

export function interpretStop(stop, db) {
  let text = stop.trim().toLowerCase();
  const exactFull = db.exact.get(keyOf(text));
  if (exactFull) return { term: exactFull };
  let uncovered = text;
  while (/^(?:先|请|帮我|去|到|找|前往)/u.test(uncovered)) {
    uncovered = uncovered.replace(/^(?:先|请|帮我|去|到|找|前往)\s*/u,'');
    const named = db.exact.get(keyOf(uncovered));
    if (named) return { term:named };
  }
  let zone = '';
  for (const [alias, name] of db.zoneTerms) {
    if (text.includes(alias) && (!zone || zone === name)) { zone=name; text=text.replace(alias,''); }
  }
  const remainder = tidy(text).replace(/^(?:(?:请问|帮我|我想|我要|我需要|想要|我|请|先|在|去|到|找|找个|找一位|前往|附近|的|哪里有|哪里能|有没有|怎么去|怎么找|寻找|学习|学会)\s*)+/u,'').replace(/(?:在哪里|在哪儿|在哪|怎么走|怎么去|怎么找|在哪里学|的位置|附近|呢|吧|吗|啊|呀|的)+$/u,'');
  const key=keyOf(remainder);
  if (!key && zone) return { term: zone };
  const result = db.exact.get(key);
  if (result) return { term: zone ? `${zone} ${result}` : result };
  // Never assign an unrecognised proper name to a random service just because it contains a shared character.
  const probe = key.replace(/(?:训练师|老师|商人|军需官|管理员)$/u,'');
  const nearNames = probe.length >= 2 ? db.npcs.filter(row=>row.some(alias=>{
    const name=keyOf(alias); return name.length>=2 && (name.includes(probe) || key.includes(name));
  })).map(row=>row[0]).slice(0,8) : [];
  const mode = /船|码头|港口/u.test(stop) ? '码头' : /地铁/u.test(stop) ? '地铁' : /飞艇/u.test(stop) ? '飞艇' : '';
  const transit = mode ? db.stops.filter(([name,map])=>(!zone || zone===map) && name.includes(mode)).map(([name])=>name) : [];
  const suggested = [...cues].filter(([,clue])=>clue.test(remainder)).map(([term])=>term);
  const action = /装不下|塞满|腾出|能不能|有没有办法|哪(里|儿)能|帮我把|我想把|怎么才能|去哪儿能|把.{1,14}(起来|换掉|放下|保管|卖掉|寄放)|东西|装备|落脚|休整|想.{1,15}(东西|装备|行李|背包|物品|货物|地方|一下)|how (can|do) i|where can i/iu.test(stop);
  if (!suggested.length && action) suggested.push('银行职员','拍卖师','旅店老板','修理','飞行管理员','兽栏管理员');
  return { zone, text: remainder || stop, choices: [...new Set([...transit,...nearNames,...suggested])] };
}

export function learn(cache, question, terms, db) {
  if (!commandFor(question,terms,db)) return cache;
  const key=keyForCache(question);
  return [[key,terms],...cache.filter(pair=>Array.isArray(pair) && pair[0] !== key)].slice(0,128);
}
const keyForCache = q => q.normalize('NFKC').trim().replace(/\s+/g,' ').toLowerCase();
export function recall(cache, question, db) {
  const entry=Array.isArray(cache) && cache.slice(0,128).find(row=>Array.isArray(row) && row[0]===keyForCache(question));
  return entry && commandFor(question,entry[1],db) ? entry[1] : null;
}

const phraseKey = q => q.trim().toLowerCase().replace(/[ \t\r\n]+/g,' ').replace(/[?？。.!！]+$/u,'').trim();
export function knownPhrase(document, question, db) {
  if (document?.version !== 1 || !Array.isArray(document.phrases)) return null;
  const key = phraseKey(question);
  const row = document.phrases.find(row=>Array.isArray(row?.aliases) && row.aliases.some(v=>typeof v==='string' && phraseKey(v)===key));
  return row && commandFor(question,row.terms,db) ? row.terms : null;
}
