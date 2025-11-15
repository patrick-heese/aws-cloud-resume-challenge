// main.js — fetch visitor count from your API
(async function () {
  try {
    // Expect a config.json alongside this file with: {"apiBaseUrl":"https://abc123.execute-api.us-east-1.amazonaws.com"}
    const cfg = await fetch('config.json', { cache: 'no-store' }).then(r => r.json());
    const res = await fetch(cfg.apiBaseUrl + '/count', { method: 'GET', cache: 'no-store' });
    if (!res.ok) throw new Error('bad status ' + res.status);
    const data = await res.json();
    const el = document.getElementById('count');
    if (el && typeof data.count !== 'undefined') el.textContent = data.count;
  } catch (e) {
    console.warn('Visitor counter unavailable:', e);
  }
})();