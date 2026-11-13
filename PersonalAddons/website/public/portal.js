(() => {
  'use strict';
  // Preserve links shared before the homepage became the add-on catalog.
  const oldChatAnchors = new Set(['features', 'screenshots', 'install', 'usage', 'updates', 'faq', 'channel-reminders']);
  const routeLegacyLink = () => {
    const anchor = location.hash.slice(1);
    if (oldChatAnchors.has(anchor)) location.replace('/chat/#' + anchor);
  };
  routeLegacyLink();
  addEventListener('hashchange', routeLegacyLink);
})();
