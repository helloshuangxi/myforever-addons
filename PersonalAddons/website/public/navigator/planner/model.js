/* Browser-only inference. Executable runtime and WASM are versioned on this site. */
const ID = 'Qwen2.5-0.5B-Instruct-q4f32_1-MLC';
const WEIGHTS = 'https://huggingface.co/mlc-ai/Qwen2.5-0.5B-Instruct-q4f32_1-MLC/resolve/8e6ec5f417c7d0e1414703ef619b8a24686e3ab0/';
const meanings = {
  '银行职员': '寄存、保管物品和钱，清空背包，后来再取', '拍卖师': '把货挂单让其他玩家出价购买，买卖玩家的物品',
  '旅店老板': '绑定炉石、住店和休息', '修理': '恢复装备的耐久度', '飞行管理员': '到飞行点，乘坐狮鹫或双足飞龙',
  '兽栏管理员': '在兽栏安置宠物', '坐骑商人': '购买坐骑', '武器训练': '学习武器熟练度',
};
let loading;

async function load(progress) {
  if (!navigator.gpu || !await navigator.gpu.requestAdapter()) {
    throw Error('此浏览器未提供 WebGPU。可以使用上面的地点搜索，或在启用硬件加速的 Chrome、Edge 中打开此页。');
  }
  const { CreateMLCEngine } = await import('./vendor/web-llm-0.2.80.js');
  return CreateMLCEngine(ID, {
    logLevel: 'WARN',
    initProgressCallback: ({ text, progress: value }) => progress(/fetch|cache|loading/i.test(text)
      ? `正在加载本机模型${value > 0 ? ` · ${Math.round(value * 100)}%` : '…'}` : '正在准备本机推理…'),
    appConfig: { model_list: [{ model_id: ID, model: WEIGHTS,
      model_lib: new URL('./vendor/qwen2-0.5b-q4f32.wasm', import.meta.url).href,
      overrides: { context_window_size: 2048 } }] },
  });
}

export async function modelChoice(text, choices, progress) {
  if (!loading) loading = load(progress).catch(error => { loading = undefined; throw error; });
  const engine = await loading;
  progress('正在理解问法…');
  const none = '无匹配';
  const entries = [...new Set(choices)];
  if (!entries.length || entries.length > 95) throw Error('当前目录没有合适的候选。');
  // A small model distinguishes similar services more reliably in a multiple-choice prompt.
  // Context examples can never become destinations outside the original retrieved candidates.
  const examples = entries.length < 5 ? [...new Set([...entries,'银行职员','拍卖师','旅店老板','修理'])] : entries;
  const result = await engine.chat.completions.create({
    messages: [
      { role: 'system', content: `你是魔兽世界的卫兵。根据玩家所描述的目的推荐最合适的一项。用服务本身的用途判断，不要求玩家说出 NPC 名称。选项有：\n${examples.map(s=>s+(meanings[s] ? " = " + meanings[s] : "")).join("\n")}\n没有合适的选项时回答无匹配。只输出规范名称。` },
      { role: 'user', content: text },
    ],
    temperature: 0, max_tokens: 45,
    response_format: { type: 'grammar', grammar: 'root ::= ' + [...examples, none].map(s => JSON.stringify(s)).join(' | ') },
  });
  const answer = result.choices[0]?.message?.content?.trim();
  return entries.includes(answer) ? answer : null;
}
