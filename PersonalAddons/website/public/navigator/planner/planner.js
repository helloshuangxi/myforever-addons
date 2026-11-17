import { commandFor, interpretStop, knownPhrase, learn, makeCatalog, recall, splitStops, validQuestion } from './intents.mjs';

const el = id => document.getElementById(id);
const question = el('question'), status = el('status');
const storageKey = 'mfn.planner.confirmed.v1';
let db, phrases, generation = 0, current, inferring = false;
function readCache() {
  try { const v=JSON.parse(localStorage.getItem(storageKey) || '[]'); return Array.isArray(v) ? v.slice(0,128) : []; }
  catch { return []; }
}
function clear() {
  generation++; current=undefined;
  el('result').hidden=true; el('model-choice').hidden=true; el('command').value=''; el('stops').replaceChildren();
  status.textContent='';
}
function show(q, terms, source) {
  const code=commandFor(q,terms,db);
  if (!code) {status.textContent='路线太长或含有未收录的站点。请缩短问法，并拆成两条路线。';return;}
  current={q,terms}; el('model-choice').hidden=true;
  el('stops').replaceChildren(...terms.map(term=>{const row=document.createElement('li');row.textContent=term;return row;}));
  el('command').value=code; el('result').hidden=false; status.textContent=source;
}
function search() {
  clear();
  const q=question.value;
  if (!validQuestion(q)) {status.textContent='请输入简短的纯文本问法（最多 240 个 UTF-8 字节）。';return;}
  const cached=recall(readCache(),q,db);
  if (cached) {show(q,cached,'已找到你在此浏览器确认过的路线。');return;}
  const shared=knownPhrase(phrases,q,db);
  if (shared) {show(q,shared,'已从共享问法库找到目的地。');return;}
  const stops=splitStops(q,db);
  if (stops.length>6 || stops.some(s=>!s)) {status.textContent='一条路线支持 1 至 6 站，每一站都需要有目的地。';return;}
  const parts=stops.map(s=>interpretStop(s,db));
  if (parts.every(r=>r.term)) {show(q,parts.map(r=>r.term),'已从地点目录找到目的地。');return;}
  const missing=parts.findIndex(r=>!r.term && !r.choices?.length);
  if (missing>=0) {status.textContent=`第 ${missing+1} 站“${stops[missing]}”暂无匹配，请补充 NPC 名、地图或服务名。`;return;}
  current={q,parts}; el('model-choice').hidden=false; el('manual').open=false;
  const fields=[];
  parts.forEach((part,i)=>{
    if(part.term) return;
    const label=document.createElement('label'), select=document.createElement('select');
    label.textContent=`第 ${i+1} 站 · ${stops[i]}`;select.dataset.index=String(i);
    select.append(new Option('选择具体服务或地点',''));
    for (const option of part.choices) select.append(new Option(option,option));
    label.append(select);fields.push(label);
  });
  el('choices').replaceChildren(...fields);
  status.textContent='本地词典还不能确定全部目的地。';
}
el('search').addEventListener('submit',event=>{event.preventDefault();if(db)search();});
question.addEventListener('input',clear);
el('use-choices').addEventListener('click',()=>{
  if (!current?.parts) return;
  const {q,parts}=current, terms=[];
  for (const [i,part] of parts.entries()) {
    if(part.term) {terms.push(part.term);continue;}
    const select=el('choices').querySelector(`select[data-index="${i}"]`);
    if(!part.choices.includes(select?.value)) {status.textContent=`请选择第 ${i+1} 站。`;select?.focus();return;}
    terms.push(part.zone ? `${part.zone} ${select.value}` : select.value);
  }
  generation++;
  show(q,terms,'已按你选择的目的地排列路线。');
});
el('infer').addEventListener('click',async()=>{
  if (inferring || !current?.parts) return;
  const {q,parts}=current;const version=generation;const currentView=()=>version===generation;
  const progress=text=>{if(currentView()) status.textContent=text;};
  inferring=true;el('infer').disabled=true;
  try {
    const {modelChoice}=await import('./model.js'); const terms=[];
    for (const [index,part] of parts.entries()) {
      if (!currentView()) return;
      if (part.term) {terms.push(part.term);continue;}
      const match=await modelChoice(part.text,part.choices,progress);
      if (!currentView()) return;
      if (!match) {progress(`模型无法确定第 ${index+1} 站。请补充服务或 NPC 名称。`);return;}
      terms.push(part.zone ? `${part.zone} ${match}` : match);
    }
    if (currentView()) show(q,terms,'模型建议了以下目的地，请核对顺序后复制。');
  } catch (error) {
    progress(error?.message?.startsWith('此浏览器') ? error.message : '模型加载或推理失败。请检查网络和浏览器硬件加速，或输入具体地点重新查找。');
  } finally {inferring=false;el('infer').disabled=false;}
});
el('copy').addEventListener('click',async()=>{
  if (!current?.terms) return;
  const {q,terms}=current;const code=commandFor(q,terms,db);
  if (!code) return;
  try {localStorage.setItem(storageKey,JSON.stringify(learn(readCache(),q,terms,db)));} catch { /* private/full storage */ }
  try {await navigator.clipboard.writeText(code);status.textContent='已复制。回到游戏，在聊天框粘贴并发送。';}
  catch {el('command').focus();el('command').select();status.textContent='已选中命令，按 Ctrl+C 或 ⌘C 复制。';}
});
try {
  const response=await fetch('./catalog.json');if(!response.ok)throw Error();
  db=makeCatalog(await response.json());
  try { const shared=await fetch('./phrases.json'); if(shared.ok) phrases=await shared.json(); } catch { /* local catalogue remains usable */ }
  el('lookup').disabled=false;
  const query=new URLSearchParams(location.hash.slice(1)).get('q');
  if(query && validQuestion(query)){question.value=query;search();}
} catch {status.textContent='地点目录加载失败，请刷新重试。';}
