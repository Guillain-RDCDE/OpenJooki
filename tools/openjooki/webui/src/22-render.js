  /* ------------------------------------------------------------------ render */
  var root, rq = false, rendering = false, pendingRender = false;
  document.addEventListener('focusout', function (e) { if (pendingRender && e.target && e.target.tagName === 'SELECT') setTimeout(render, 0); });
  document.addEventListener('change', function (e) { if (pendingRender && e.target && e.target.tagName === 'SELECT') setTimeout(render, 0); });
  function scheduleRender() { if (rq) return; rq = true; requestAnimationFrame(function () { rq = false; render(); }); }
  function navLink(hash, name, ic, label) {
    var r = route().name;
    var active = r === name || (name === 'playlists' && r === 'p');
    return h('a', { href: hash, class: active ? 'active' : '', 'aria-current': active ? 'page' : null }, icon(ic), h('span', null, label));
  }
  function render() {
    if (!root) return;
    watchUpdateReconnect();
    if (ui.dragging || nightVolDrag !== null) return;
    var ae = document.activeElement;
    if (ae && ae.tagName === 'SELECT' && root.contains(ae)) { pendingRender = true; return; }
    pendingRender = false;
    var keep = captureFocus(root);
    var r = route();
    if (r.name !== 'settings' || !SUBS[r.arg]) shownSub = null;
    var title, body, back = null;
    // an airplane mode asked from this browser: the Jooki is away on purpose (and if it is still
    // here half a minute later, the request did not go through: forget it)
    if (online && gotState && airplane && Date.now() - airplane.sent > 30000) setAirplane(null);
    var air = !online ? airplaneNow() : null;
    if (!gotState) {
      body = h('div', { class: 'connect-screen' }, h('div', { class: 'spinner' }),
        h('div', null, air ? t('air_title') : online || !everOnline ? t('connecting') : t('offline')),
        air ? h('p', { class: 'small muted' }, t('air_offline', airplaneWhen(air))) : !online && retryDelay > 1600 ? h('p', { class: 'small muted' }, t('offline_long')) : null,
        !online && retryDelay > 1600 ? h('button', { class: 'btn', onclick: function () { retryDelay = 1000; connect(); } }, t('retry')) : null);
      title = t('my_jooki');
    } else if (r.name === 'p') {
      var p = pls()[r.arg];
      title = p ? (p.title || '—') : t('playlists');
      back = '#/';
      body = viewPlaylist(r.arg);
    } else if (r.name === 'tokens') { title = t('tokens'); body = viewTokens(); }
    else if (r.name === 'library') { title = t('library'); body = viewLibrary(r.arg); }
    else if (r.name === 'settings') {
      var sub = r.arg && SUBS[r.arg] ? r.arg : null;
      title = sub ? t(SUBS[sub].title) : t('settings');
      if (sub) back = '#/settings';
      body = sub ? settingsPage(sub) : viewSettings();
    }
    else { title = t('playlists'); body = viewPlaylists(); }
    document.title = gotState ? title + ' — OpenJooki' : 'OpenJooki';
    var conn = h('div', { class: 'conn ' + (online ? 'on' : 'off'), role: 'status', 'aria-live': 'polite' }, h('i'), online ? t('connected') : t('offline'));
    var shell = h('div', { class: 'shell' },
      h('header', { class: 'topbar' },
        back ? h('a', { class: 'icon-btn', href: back, 'aria-label': t('back') }, icon('back')) : h('div', { class: 'brand' }, h('div', { class: 'dot' }, 'J')),
        h('div', { class: 'titles' },
          h('a', { class: 'wordmark', href: '#/', 'aria-label': 'OpenJooki' }, 'Open', h('span', null, 'Jooki')),
          h('h1', null, title)), conn),
      !online && gotState ? h('div', { class: 'banner' + (air ? '' : ' danger'), style: 'margin:12px 16px 0' }, air ? t('air_offline', airplaneWhen(air)) : t('offline_long')) : null,
      h('main', { id: 'main' }, body),
      h('nav', { class: 'nav', 'aria-label': 'Navigation' },
        h('a', { class: 'nav-brand', href: '#/', 'aria-hidden': 'true', tabindex: '-1' }, h('span', { class: 'dot' }, 'J'), h('span', null, 'Open', h('b', null, 'Jooki'))),
        navLink('#/', 'playlists', 'list', t('playlists')),
        navLink('#/tokens', 'tokens', 'token', t('tokens')),
        navLink('#/library', 'library', 'lib', t('library')),
        navLink('#/settings', 'settings', 'gear', t('settings'))),
      gotState ? playerBar() : null);
    rendering = true;
    try {
      root.innerHTML = '';
      root.appendChild(shell);
      restoreFocus(root, keep);
    } finally { rendering = false; }
    if (modal && modal.live && volDrag === null && !seeking) {
      var sig = modal.sig ? modal.sig() : '';
      if (sig !== modal.lastSig) { modal.lastSig = sig; renderModal(); }
    }
  }

