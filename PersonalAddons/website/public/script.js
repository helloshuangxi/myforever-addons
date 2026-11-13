(() => {
  'use strict';
  const dialog = document.querySelector('.image-dialog');
  let lastTrigger;
  if (dialog && typeof dialog.showModal === 'function') {
    const preview = dialog.querySelector('img');
    const caption = dialog.querySelector('.dialog-caption');
    const original = dialog.querySelector('.original-link');
    document.querySelectorAll('[data-lightbox]').forEach((link) => {
      link.addEventListener('click', (event) => {
        if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
        event.preventDefault();
        lastTrigger = link;
        preview.src = link.href;
        preview.alt = link.querySelector('img')?.alt || '插件实机截图';
        caption.textContent = preview.alt;
        original.href = link.href;
        dialog.showModal();
      });
    });
    dialog.querySelector('.close-dialog').addEventListener('click', () => dialog.close());
    dialog.addEventListener('click', (event) => {
      const rect = dialog.getBoundingClientRect();
      if (event.target === dialog && (event.clientX < rect.left || event.clientX > rect.right || event.clientY < rect.top || event.clientY > rect.bottom)) dialog.close();
    });
    dialog.addEventListener('close', () => lastTrigger?.focus({ preventScroll: true }));
  }
  const status = document.querySelector('.copy-status');
  document.querySelectorAll('[data-copy]').forEach((button) => {
    button.addEventListener('click', async () => {
      const text = button.dataset.copy;
      try {
        if (!navigator.clipboard || !window.isSecureContext) throw new Error('clipboard unavailable');
        await navigator.clipboard.writeText(text);
        status.textContent = `已复制 ${text}，请在游戏原生聊天框粘贴。`;
      } catch {
        const range = document.createRange();
        range.selectNodeContents(button.querySelector('code'));
        const selection = window.getSelection();
        selection.removeAllRanges();
        selection.addRange(range);
        status.textContent = `已选中 ${text}，请按系统复制快捷键。`;
      }
    });
  });
  // Keep the latest download within reach without covering reading or interaction.
  // The third link remains a regular page link when JavaScript is unavailable.
  const dock = document.querySelector('.latest-download-dock');
  if (dock && 'IntersectionObserver' in window) {
    dock.classList.add('is-suppressed');
    document.body.classList.add('download-dock-enabled');
    const primaryDownloads = [...document.querySelectorAll('.button[download]')];
    const collectProtectedContent = () => [...document.querySelectorAll('h1, h2, h3, p, a, button, summary, input, textarea, label, #community span, #community time, #author dt, #author dd')].filter((element) => element !== dock && !dock.contains(element) && !element.closest('dialog'));
    let protectedContent = collectProtectedContent();
    let queued = false;
    const overlaps = (a, b) => a.left < b.right && a.right > b.left && a.top < b.bottom && a.bottom > b.top;
    const updateDock = () => {
      queued = false;
      if (dock.contains(document.activeElement)) return;
      const width = window.innerWidth;
      const height = window.innerHeight;
      const rect = dock.getBoundingClientRect();
      const protectedArea = { left: rect.left - 12, right: rect.right + 12, top: rect.top - 12, bottom: rect.bottom + 12 };
      const primaryVisible = primaryDownloads.some((element) => {
        const item = element.getBoundingClientRect();
        return item.bottom > 0 && item.top < height && item.right > 0 && item.left < width;
      });
      const coversControl = protectedContent.some((element) => {
        const item = element.getBoundingClientRect();
        return item.width > 0 && item.height > 0 && overlaps(item, protectedArea);
      });
      const hidden = primaryVisible || coversControl || Boolean(document.querySelector('dialog[open]'));
      dock.classList.toggle('is-suppressed', hidden);
      dock.setAttribute('aria-hidden', String(hidden));
      dock.tabIndex = hidden ? -1 : 0;
    };
    const scheduleDock = () => {
      if (!queued) { queued = true; requestAnimationFrame(updateDock); }
    };
    const primaryObserver = new IntersectionObserver(scheduleDock, { threshold: [0, 1] });
    primaryDownloads.forEach((element) => primaryObserver.observe(element));
    addEventListener('scroll', scheduleDock, { passive: true });
    addEventListener('resize', scheduleDock, { passive: true });
    addEventListener('load', scheduleDock, { once: true });
    document.addEventListener('toggle', scheduleDock, true);
    document.addEventListener('focusout', scheduleDock);
    document.addEventListener('community:layout-change', () => {
      protectedContent = collectProtectedContent();
      scheduleDock();
    });
    if (dialog) dialog.addEventListener('close', scheduleDock);
    updateDock();
  }
  if ('IntersectionObserver' in window && !window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
    const observer = new IntersectionObserver((entries) => {
      entries.forEach(({ isIntersecting, target }) => {
        if (!isIntersecting) return;
        target.classList.add(target.matches('.screenshot-item') ? 'reveal-picture' : target.matches('li, details') ? 'reveal-row' : 'reveal-text');
        observer.unobserve(target);
      });
    }, { threshold: 0.08 });
    document.querySelectorAll('.features h2, .feature, .section-intro h2, .section-intro > p, .screenshot-item, .install-steps li, .folder-guide, .upgrade-note, .usage-notes article, .command-list, .latest-release, .release-detail, .history details, .faq h2, .faq-text p').forEach((element) => observer.observe(element));
  }
})();
