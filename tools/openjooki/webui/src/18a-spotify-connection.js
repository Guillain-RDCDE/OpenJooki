  function spotifyConnectionCard() {
    var o = obj(S.spotifyOffline);
    if (!o.available) return null;
    var auth = obj(o.auth), pending = o.logging_out || /^(requested|working|checking)$/.test(auth.phase || '');
    var metadata = !!(o.metadata_ready || o.account_ready), premium = !!o.account_ready;
    function login(mode) { send('OJ_OFFLINE_LOGIN', { mode: mode }); }
    return h('section', { class: 'card offline-panel', 'data-k': 'spotify-connection' },
      h('div', { class: 'offline-heading' }, h('h3', null, t('oa_title')), h('span', { class: 'offline-badge' + (metadata ? ' ready' : '') }, t(metadata ? 'oa_connected' : 'oa_not_connected'))),
      h('p', { class: 'small muted' }, t('oa_intro')),
      o.account_name && metadata ? h('p', { class: 'small' }, t('oa_account') + ': ' + o.account_name) : null,
      h('p', { class: 'small' }, t(premium ? 'oa_premium_ready' : metadata ? 'oa_titles_ready' : 'oa_titles_help')),
      h('p', { class: 'small muted' }, t(o.helper_ready ? 'oa_computer_ready' : 'oa_computer_missing')),
      !o.helper_ready ? h('p', { class: 'small' }, h('a', { href: 'https://github.com/dirkdrutschmann/openjooki/blob/feature/spotify-offline-audit/guide/spotify-offline.de.md', target: '_blank', rel: 'noopener' }, t('oa_guide'))) : null,
      pending ? h('div', { class: 'offline-notice', role: 'status' }, t(o.logging_out ? 'oa_signing_out' : auth.phase === 'checking' ? 'oa_checking' : 'oa_browser'),
        auth.url ? h('p', null, h('a', { href: auth.url, target: '_blank', rel: 'noopener' }, t('oa_open'))) : null) : null,
      auth.phase === 'error' ? h('p', { class: 'offline-notice error', role: 'alert' }, t(auth.error === 'premium_required' ? 'oa_premium_required' : auth.error === 'account_mismatch' ? 'oa_mismatch' : auth.error === 'rate_limited' ? 'of_rate' : 'oa_failed')) : null,
      h('div', { class: 'offline-actions' },
        pending && !o.logging_out ? h('button', { class: 'btn ghost', onclick: function () { send('OJ_OFFLINE_CANCEL_LOGIN', {}); } }, t('cancel')) : null,
        h('button', { class: 'btn' + (!metadata ? ' primary' : ''), disabled: pending || !o.helper_ready || offlineBusy(), 'data-k': 'spotify-oauth', onclick: function () { login('metadata'); } }, t(metadata ? 'oa_reconnect' : 'oa_login')),
        h('button', { class: 'btn' + (!premium ? ' primary' : ''), disabled: pending || !o.helper_ready || offlineBusy(), 'data-k': 'spotify-premium-login', onclick: function () { login('premium'); } }, t(premium ? 'oa_premium_reconnect' : 'oa_enable_offline')),
        metadata ? h('button', { class: 'btn danger', 'data-k': 'spotify-oauth-logout', onclick: function () {
          confirmBox(t('oa_logout_q'), t('oa_logout_text'), t('oa_logout'), true).then(function (yes) { if (yes) send('OJ_OFFLINE_FORGET', {}); });
        } }, t('oa_logout')) : null));
  }
