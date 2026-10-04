  /* ------------------------------------------------------------------ boot */
  function boot() {
    document.documentElement.lang = lang;
    root = document.getElementById('app');
    toastBox = h('div', { class: 'toasts', 'aria-live': 'polite' });
    modalRoot = h('div');
    document.body.appendChild(toastBox);
    document.body.appendChild(modalRoot);
    if (navigator.serviceWorker && navigator.serviceWorker.getRegistrations) {
      navigator.serviceWorker.getRegistrations().then(function (rs) { rs.forEach(function (r) { r.unregister(); }); }).catch(function () {});
    }
    render();
    loadAuth(connect);
  }
  window.OJ = { state: S, send: send, version: VERSION };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot); else boot();
