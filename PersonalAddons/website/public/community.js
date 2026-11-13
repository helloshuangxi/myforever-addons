(() => {
  'use strict';
  const api = '/api/suggestions';
  const storageKey = 'myforeverchat:download-choice:v1';
  const notifyLayout = () => document.dispatchEvent(new Event('community:layout-change'));
  let config = { author: { name: 'Hyder' }, donation: {} };
  let configLoaded = false;
  let choiceMade = false;
  try { choiceMade = localStorage.getItem(storageKey) === 'chosen'; } catch { /* Keep this visit usable in private storage modes. */ }
  const saveChoice = () => {
    choiceMade = true;
    try { localStorage.setItem(storageKey, 'chosen'); } catch { /* In-memory fallback for this page. */ }
  };
  const safeAssetUrl = (value) => {
    if (typeof value !== 'string' || !value.trim()) return '';
    try {
      const url = new URL(value, location.origin + "/");
      return url.origin === location.origin && /^https?:$/.test(url.protocol) ? url.href : '';
    } catch { return ''; }
  };
  const safeText = (value) => typeof value === 'string' ? value.trim() : '';
  const donationEnabled = () => config.donation?.enabled === true;
  const applyAuthor = () => {
    const author = config.author || {};
    const name = safeText(author.name) || 'Hyder';
    document.getElementById('author-heading').textContent = `作者 ${name}`;
    const emailLink = document.querySelector('.author-email');
    const email = safeText(author.email);
    if (/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      emailLink.textContent = email;
      emailLink.href = `mailto:${email}`;
      emailLink.hidden = false;
    } else { emailLink.hidden = true; emailLink.removeAttribute('href'); }
    const avatar = document.querySelector('.author-avatar');
    const avatarUrl = safeAssetUrl(author.avatar_url);
    avatar.hidden = !avatarUrl;
    if (avatarUrl) { avatar.src = avatarUrl; avatar.alt = `作者 ${name}`; }
    const profile = document.querySelector('.author-game-profile');
    profile.replaceChildren();
    for (const [field, label] of [['server', '服务器'], ['faction', '阵营'], ['guild', '公会'], ['character', '角色']]) {
      const value = safeText(author[field]);
      if (!value) continue;
      const row = document.createElement('div');
      const term = document.createElement('dt');
      const detail = document.createElement('dd');
      term.textContent = label;
      detail.textContent = value;
      row.append(term, detail);
      profile.append(row);
    }
    profile.hidden = !profile.children.length;
    document.querySelector('.support-author').hidden = !donationEnabled();
    document.querySelector('.support-note').hidden = !donationEnabled();
    notifyLayout();
  };
  document.querySelector('.author-avatar').addEventListener('error', (event) => { event.currentTarget.hidden = true; });

  const donation = document.querySelector('.donation-dialog');
  const choicePanel = donation.querySelector('.donation-choice-panel');
  const paymentPanel = donation.querySelector('.donation-payment-panel');
  const paymentHeading = donation.querySelector('#donation-amount-heading');
  const paymentNote = donation.querySelector('.donation-payment-note');
  const qrFigure = donation.querySelector('.donation-qr');
  const qrImage = qrFigure.querySelector('img');
  const qrOriginal = qrFigure.querySelector('.donation-original-link');
  const qrStatus = donation.querySelector('.donation-qr-status');
  const downloadStatus = donation.querySelector('.donation-download-status');
  const retryDownload = donation.querySelector('.donation-retry-download');
  const allowedAmounts = new Set(['1', '5', '20', '100']);
  let selectedAmount = '';
  let pendingDownload = null;
  let lastDownload = null;
  let trigger = null;
  let bypassDownload = false;

  const startDownload = (link) => {
    if (!link || !link.matches('a[download]')) return;
    // Reuse the existing versioned link so release synchronization remains authoritative.
    bypassDownload = true;
    try { link.click(); } finally { bypassDownload = false; }
    lastDownload = link;
    downloadStatus.textContent = '已请求下载安装包。付款由你决定，不影响下载；若浏览器未响应，可点「重新下载」。';
    retryDownload.hidden = false;
  };
  const renderPayment = () => {
    if (!allowedAmounts.has(selectedAmount)) return;
    const settings = config.donation || {};
    const amountSettings = settings.amounts && typeof settings.amounts === 'object' ? settings.amounts[selectedAmount] : null;
    const specificQr = safeAssetUrl(amountSettings?.qr_url);
    const qrUrl = specificQr || safeAssetUrl(settings.qr_url);
    const provider = safeText(amountSettings?.provider) || safeText(settings.provider);
    const recipient = safeText(settings.recipient) || safeText(config.author?.name) || 'Hyder';
    paymentHeading.textContent = `自愿打赏 ${selectedAmount} 元`;
    paymentNote.textContent = specificQr ? `使用${provider || '支付应用'}扫码打赏 ${selectedAmount} 元。请核对收款方和金额后，自行决定是否付款。` : `如愿意支持，请扫码后手动填写 ${selectedAmount} 元，并核对收款方。`;
    qrFigure.hidden = true;
    qrImage.removeAttribute('src');
    if (!configLoaded) { qrStatus.textContent = '正在加载收款信息…'; return; }
    if (!qrUrl) {
      qrStatus.textContent = lastDownload ? '收款码暂未配置。你可以直接关闭这个窗口，安装包照常下载。' : '收款码暂未配置。感谢你的心意，可以先关闭这个窗口。';
      return;
    }
    qrImage.alt = `${recipient}${provider ? '的' + provider : ''}收款二维码，所选金额 ${selectedAmount} 元`;
    qrFigure.classList.toggle('is-alipay-screenshot', (amountSettings?.qr_presentation || settings.qr_presentation) === 'alipay-screenshot');
    qrFigure.querySelector('.donation-recipient').textContent = `收款方：${recipient}`;
    qrOriginal.href = qrUrl;
    qrOriginal.setAttribute('aria-label', `查看${provider}${selectedAmount}元原始收款码`);
    qrImage.src = qrUrl;
    qrFigure.hidden = false;
    qrStatus.textContent = '此处不验证付款，也不会显示付款成功状态。';
    notifyLayout();
  };
  qrImage.addEventListener('error', () => {
    qrFigure.hidden = true;
    qrStatus.textContent = '收款码暂时无法显示。下载不受影响，请稍后从作者区重试。';
  });
  const resetDonation = () => {
    selectedAmount = '';
    lastDownload = null;
    choicePanel.hidden = false;
    paymentPanel.hidden = true;
    retryDownload.hidden = true;
    qrFigure.hidden = true;
    qrImage.removeAttribute('src');
    downloadStatus.textContent = '';
    donation.setAttribute('aria-labelledby', 'donation-heading');
    donation.setAttribute('aria-describedby', 'donation-description');
  };
  const showDonation = (link, source) => {
    if (!donationEnabled()) { if (link) startDownload(link); return; }
    if (typeof donation.showModal !== 'function') { if (link) startDownload(link); return; }
    resetDonation();
    pendingDownload = link;
    trigger = source;
    donation.querySelector('#donation-description').textContent = link
      ? '如果这个插件帮到了你，可以随手支持一下。打赏完全自愿，选择「残忍拒绝」也能直接下载。'
      : '如果这个插件帮到了你，可以随手支持一下。打赏完全自愿，感谢你的鼓励。';
    donation.showModal();
    notifyLayout();
  };
  document.querySelectorAll('a[download]').forEach((link) => {
    link.addEventListener('click', (event) => {
      if (!donationEnabled() || bypassDownload || choiceMade || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
      if (typeof donation.showModal !== 'function') return;
      event.preventDefault();
      showDonation(link, link);
    });
  });
  document.querySelector('.support-author').addEventListener('click', (event) => showDonation(null, event.currentTarget));
  donation.querySelectorAll('[data-donation-amount]').forEach((button) => {
    button.addEventListener('click', () => {
      const amount = button.dataset.donationAmount;
      if (!allowedAmounts.has(amount)) return;
      selectedAmount = amount;
      saveChoice();
      choicePanel.hidden = true;
      paymentPanel.hidden = false;
      donation.setAttribute('aria-labelledby', 'donation-amount-heading');
      donation.removeAttribute('aria-describedby');
      if (pendingDownload) { startDownload(pendingDownload); pendingDownload = null; }
      else if (!lastDownload) { downloadStatus.textContent = '这只是自愿打赏入口，不会发起任何付款。'; retryDownload.hidden = true; }
      renderPayment();
      paymentHeading.focus({ preventScroll: true });
      notifyLayout();
    });
  });
  donation.querySelector('.donation-decline').addEventListener('click', () => {
    saveChoice();
    const download = pendingDownload;
    pendingDownload = null;
    donation.close();
    if (download) startDownload(download);
  });
  retryDownload.addEventListener('click', () => startDownload(lastDownload));
  donation.querySelector('.donation-back').addEventListener('click', () => {
    choicePanel.hidden = false;
    paymentPanel.hidden = true;
    donation.setAttribute('aria-labelledby', 'donation-heading');
    donation.setAttribute('aria-describedby', 'donation-description');
    donation.querySelector('[data-donation-amount]').focus();
  });
  donation.querySelector('.donation-close').addEventListener('click', () => donation.close());
  donation.querySelector('.donation-finish').addEventListener('click', () => donation.close());
  donation.addEventListener('click', (event) => {
    const rect = donation.getBoundingClientRect();
    if (event.target === donation && (event.clientX < rect.left || event.clientX > rect.right || event.clientY < rect.top || event.clientY > rect.bottom)) donation.close();
  });
  donation.addEventListener('close', () => {
    pendingDownload = null;
    notifyLayout();
    trigger?.focus({ preventScroll: true });
  });

  fetch('/community-config.json', { credentials: 'same-origin', cache: 'no-cache' })
    .then((response) => { if (!response.ok) throw new Error('config unavailable'); return response.json(); })
    .then((value) => { if (value && typeof value === 'object') config = value; applyAuthor(); })
    .catch(() => { /* The verified HTML author information remains visible if config cannot load. */ })
    .finally(() => { configLoaded = true; if (!paymentPanel.hidden) renderPayment(); });

  const form = document.getElementById('suggestion-form');
  const nickname = document.getElementById('suggestion-nickname');
  const body = document.getElementById('suggestion-body');
  const website = document.getElementById('suggestion-website');
  const submitButton = form.querySelector('button[type="submit"]');
  const submitStatus = document.getElementById('suggestion-submit-status');
  const listStatus = document.getElementById('suggestion-list-status');
  const list = document.querySelector('.suggestions-list');
  const more = document.getElementById('suggestions-more');
  const retry = document.getElementById('suggestions-retry');
  const suggestions = new Map();
  let nextBefore = null;
  let hasMore = false;
  let listBusy = false;
  let submitBusy = false;
  let failedBefore = null;
  let submission = null;
  const timestamp = new Intl.DateTimeFormat('zh-CN', { year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit' });
  const updateCount = () => { document.getElementById('suggestion-count').textContent = `${body.value.length} / 2000`; };
  body.addEventListener('input', updateCount);
  const uuid = () => {
    if (globalThis.crypto?.randomUUID) return crypto.randomUUID();
    const bytes = new Uint8Array(16);
    if (globalThis.crypto?.getRandomValues) crypto.getRandomValues(bytes);
    else for (let i = 0; i < bytes.length; i++) bytes[i] = Math.floor(Math.random() * 256);
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    const hex = [...bytes].map((byte) => byte.toString(16).padStart(2, '0')).join('');
    return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
  };
  const validItem = (item) => item && Number.isSafeInteger(Number(item.id)) && Number(item.id) > 0 && typeof item.body === 'string' && typeof item.created_at === 'string';
  const addItems = (items) => {
    for (const item of items) if (validItem(item)) suggestions.set(Number(item.id), item);
    const fragment = document.createDocumentFragment();
    for (const [id, item] of [...suggestions.entries()].sort((a, b) => b[0] - a[0])) {
      const entry = document.createElement('li');
      entry.className = 'suggestion-entry';
      const header = document.createElement('header');
      const byline = document.createElement('div');
      byline.className = 'suggestion-byline';
      const name = document.createElement('strong');
      name.textContent = safeText(item.nickname) || '匿名玩家';
      const floor = document.createElement('span');
      floor.className = 'suggestion-floor';
      floor.textContent = `第 ${id} 楼`;
      byline.append(name, floor);
      const time = document.createElement('time');
      const date = new Date(item.created_at);
      if (!Number.isNaN(date.getTime())) { time.dateTime = date.toISOString(); time.textContent = timestamp.format(date); }
      else time.textContent = '时间未提供';
      header.append(byline, time);
      const content = document.createElement('p');
      content.className = 'suggestion-content';
      content.textContent = item.body;
      entry.append(header, content);
      fragment.append(entry);
    }
    list.replaceChildren(fragment);
    notifyLayout();
  };
  const request = async (url, options = {}) => {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 15000);
    try {
      const response = await fetch(url, { credentials: 'same-origin', ...options, signal: controller.signal });
      let payload;
      try { payload = await response.json(); } catch { throw new Error('服务暂时没有返回有效结果，请稍后重试。'); }
      if (!response.ok) {
        if (response.status === 429) {
          const seconds = Number(response.headers.get('Retry-After'));
          throw new Error(`操作稍快，请${seconds > 0 && seconds <= 3600 ? `约 ${Math.ceil(seconds)} 秒后` : '稍后'}再试。`);
        }
        throw new Error(safeText(payload?.error?.message) || '暂时无法完成请求，请稍后重试。');
      }
      return payload;
    } finally { clearTimeout(timer); }
  };
  const errorMessage = (error) => error?.name === 'AbortError' ? '网络请求超时，请稍后重试。' : safeText(error?.message) || '网络连接失败，请稍后重试。';
  const loadSuggestions = async (before = null) => {
    if (listBusy) return;
    listBusy = true;
    more.disabled = true;
    retry.hidden = true;
    listStatus.classList.remove('is-error');
    listStatus.textContent = before ? '正在加载更多楼层…' : '正在加载建议…';
    try {
      const params = new URLSearchParams({ limit: '20' });
      if (before !== null) params.set('before', String(before));
      const result = await request(`${api}?${params}`);
      if (!Array.isArray(result.items)) throw new Error('建议列表格式有误，请稍后重试。');
      addItems(result.items);
      nextBefore = Number.isSafeInteger(Number(result.next_before)) && Number(result.next_before) > 0 ? Number(result.next_before) : null;
      hasMore = Boolean(result.has_more) && nextBefore !== null;
      more.hidden = !hasMore;
      listStatus.textContent = suggestions.size ? '' : '还没有留言。你希望插件怎样改进？来开第一层。';
    } catch (error) {
      failedBefore = before;
      listStatus.textContent = errorMessage(error);
      listStatus.classList.add('is-error');
      retry.hidden = false;
    } finally { listBusy = false; more.disabled = false; notifyLayout(); }
  };
  more.addEventListener('click', () => { if (hasMore) loadSuggestions(nextBefore); });
  retry.addEventListener('click', () => loadSuggestions(failedBefore));
  form.addEventListener('submit', async (event) => {
    event.preventDefault();
    if (submitBusy || !form.reportValidity()) return;
    const text = body.value.trim();
    const author = nickname.value.trim();
    if (!text) { submitStatus.textContent = '先写下想说的话吧。'; submitStatus.classList.add('is-error'); body.focus(); return; }
    if (author.length > 24 || text.length > 2000) { submitStatus.textContent = '昵称最多 24 字，正文最多 2000 字。'; submitStatus.classList.add('is-error'); return; }
    const signature = JSON.stringify([author, text, website.value]);
    if (!submission || submission.signature !== signature) submission = { signature, requestId: uuid() };
    const payload = { nickname: author, body: text, website: website.value, request_id: submission.requestId };
    submitBusy = true;
    submitButton.disabled = true;
    nickname.disabled = true;
    body.disabled = true;
    submitStatus.classList.remove('is-error');
    submitStatus.textContent = '正在发表…';
    try {
      const result = await request(api, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload) });
      if (!validItem(result.item)) throw new Error('提交未确认，内容已保留，请重试。');
      addItems([result.item]);
      body.value = '';
      submission = null;
      updateCount();
      submitStatus.textContent = `已发表到第 ${Number(result.item.id)} 楼。谢谢你的建议！`;
      if (!listBusy) { listStatus.textContent = ''; listStatus.classList.remove('is-error'); }
    } catch (error) {
      submitStatus.textContent = `${errorMessage(error)} 内容已保留，可直接重试。`;
      submitStatus.classList.add('is-error');
    } finally {
      submitBusy = false;
      submitButton.disabled = false;
      nickname.disabled = false;
      body.disabled = false;
      notifyLayout();
    }
  });
  loadSuggestions();
})();
