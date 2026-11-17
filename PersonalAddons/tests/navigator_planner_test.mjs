import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { commandFor, fingerprint, interpretStop, knownPhrase, learn, makeCatalog, recall, splitStops, validQuestion, validTerm } from '../website/public/navigator/planner/intents.mjs';
const base=new URL('../website/public/navigator/planner/',import.meta.url);
const load=name=>JSON.parse(readFileSync(new URL(name,base)));
const catalog=load('catalog.json'), db=makeCatalog(catalog), phrases=load('phrases.json');
const route=q=>splitStops(q,db).map(s=>interpretStop(s,db).term);
assert.equal(catalog.npcs.length,427);assert.equal(catalog.stops.length,36);
for(const [name] of catalog.stops){assert(validTerm(name,db));assert.equal(route('去'+name)[0],name);}
assert(interpretStop('坐船去藏宝海湾',db).choices.includes('藏宝海湾码头'));
assert.deepEqual(route('藏宝海湾码头；矮人区地铁入口'),['藏宝海湾码头','矮人区地铁入口']);
for (const [name,english] of catalog.npcs) {
  assert(validTerm(name,db)); assert.equal(route(name)[0],name);
  // Distinct NPCs can share an English alias. Speak only for unambiguous whole aliases.
  if (catalog.npcs.filter(row=>row[1].toLowerCase()===english.toLowerCase()).length===1) assert.equal(route(english)[0],name);
}
assert.deepEqual(route('先去暴风城的银行，再去铁炉堡的拍卖行'),['暴风城 银行职员','铁炉堡 拍卖师']);
assert.deepEqual(route('我想挖矿'),['采矿训练师']);
for (const separator of ['；',';','>','→']) assert.deepEqual(route('银行'+separator+'旅馆'),['银行职员','旅店老板']);
assert(interpretStop('我袋子已经塞满了，找个地方腾出空间',db).choices.includes('银行职员'));
assert(validQuestion('银行>旅馆'));
assert.deepEqual(route('从暴风城去铁炉堡的裁缝训练师'),['铁炉堡 裁缝训练师']);
assert.deepEqual(route('附近的银行在哪里？'),['银行职员']);
assert.deepEqual(route('暴风城'),['暴风城']);
assert.deepEqual(interpretStop('去青铜飞鱼幻影祭司',db).choices,[]);
assert.deepEqual(interpretStop('想把不用的装备寄存在城里以后再拿',db).choices,['银行职员']);
assert.deepEqual(interpretStop('炉石的回城点我想改到暴风城',db).choices,['旅店老板']);
assert(phrases.phrases.length>=1);
for (const row of phrases.phrases) for(const q of row.aliases) assert.deepEqual(knownPhrase(phrases,q+'？',db),row.terms);
assert.equal(knownPhrase(phrases,'想把不用的装备寄存在城里以后再拿',db),null);
assert.equal(knownPhrase({version:1,phrases:[{aliases:['x'],terms:['未知地点']}]},'x',db),null);
const q='先去银行，再去旅店', terms=['银行职员','旅店老板'];
const cmd=commandFor(q,terms,db);assert(cmd.includes('~银行职员~旅店老板'));assert.equal(fingerprint('abc'),'0b885c8b');
for(const t of ['',' 银行职员','银行职员~旅店老板','银行职员|r','暴风城 伪造 NPC','/script print(1)','暴风城 银行职员\n','虚构营地'])assert.equal(commandFor(q,[t],db),null);
assert.equal(commandFor(q,Array(7).fill(terms[0]),db),null);assert.equal(commandFor(q,[],db),null);
assert(!validQuestion('问'.repeat(81)));assert(!validQuestion('<a>'));assert(!validQuestion('银行\n旅店'));assert(validQuestion('问'.repeat(80)));
let cache=learn([],q,terms,db);assert.deepEqual(recall(cache,q,db),terms);
for(let i=0;i<140;i++)cache=learn(cache,'q'+i,terms,db);
assert.equal(cache.length,128);assert(!recall(cache,q,db));assert.deepEqual(recall(cache,'q139',db),terms);
assert(!recall([['x',['虚构营地']]],'x',db));
console.log('Planner catalogue, phrase corpus, bounded model candidates, protocol and confirmed cache passed.');
