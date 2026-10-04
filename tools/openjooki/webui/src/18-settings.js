  /* ---------------- settings: a short page; each topic opens on a page of its own (#/settings/<topic>) */
  // A row: icon tile, label (+ a small line), then a value and a chevron, or a switch, or `right`
  // (the row's own right-hand node(s)). `tag: 'label'` wraps a control, `col` stacks label and right.
  function sRow(o) {
    var right = [];
    if (o.value !== undefined && o.value !== null && o.value !== '') right.push(h('span', { class: 'val' + (o.vcls ? ' ' + o.vcls : '') }, o.value));
    if (o.sw) right.push(h('input', { type: 'checkbox', role: 'switch', class: 'sw', checked: !!o.on, 'data-k': o.k, 'aria-label': o.label, onchange: o.onchange }));
    if (o.check) right.push(h('span', { class: 'tick' }, icon('check')));
    if (o.href || (o.onclick && !o.nochev)) right.push(h('span', { class: 'chev' }, icon('chev')));
    if (o.right) right.push(o.right);
    var inner = [o.icon ? h('span', { class: 'ico ' + (o.color || 'gray') }, icon(o.icon)) : null,
      h('span', { class: 'lbl' }, h('span', { class: 'l1' }, o.label), o.sub ? h('span', { class: 'l2' }, o.sub) : null), right];
    var cls = 'srow' + (o.icon ? '' : ' noico') + (o.danger ? ' danger' : '') + (o.col ? ' col' : '');
    if (o.sw || o.tag === 'label') return h('label', { class: cls }, inner);
    if (o.href) return h('a', { class: cls, href: o.href, 'data-k': o.k }, inner);
    if (o.onclick) return h('button', { class: cls, type: 'button', 'data-k': o.k, lang: o.lang || null, disabled: o.disabled ? 'disabled' : null, onclick: o.onclick }, inner);
    return h('div', { class: cls, 'data-k': o.k }, inner);
  }
  function sGroup(title, rows, foot, k) {
    return [title ? h('div', { class: 'gtitle' }, title) : null, h('div', { class: 'group', 'data-k': k }, rows),
      foot ? h('div', { class: 'gfoot' }, foot) : null];
  }
  function stat(ic, label, value, sub, subCls, meter, meterCls, k) {
    return h('div', { class: 'stat', 'data-k': k },
      h('div', { class: 'k' }, icon(ic), h('span', { class: 'ellipsis' }, label)),
      h('div', { class: 'v ellipsis' }, value),
      sub ? h('div', { class: 's ellipsis' + (subCls ? ' ' + subCls : '') }, sub) : null,
      meter !== null && meter !== undefined ? h('div', { class: 'minibar' }, h('i', { class: meterCls || '', style: 'width:' + Math.max(0, Math.min(100, meter)) + '%' })) : null);
  }
  // the topic pages (#/settings/<topic>): the key of each one's title, and what draws it
  var SUBS = { bluetooth: { title: 's_bt', page: btPage }, night: { title: 'night_mode', page: nightPage }, airplane: { title: 'air_title', page: airPage },
               wifi: { title: 'wifi', page: wifiPage }, update: { title: 's_update', page: updateCard }, language: { title: 'language', page: langPage },
               parent: { title: 'parent_label', page: parentPage }, home: { title: 's_home', page: homePage }, maintenance: { title: 's_maint', page: maintPage },
               theme: { title: 's_theme', page: themePage }, mp3: { title: 's_mp3', page: mp3Page } };
  var shownSub = null; // the topic page on screen: it fades in once, not at each rebuild
  function settingsPage(sub) {
    var body = SUBS[sub] ? SUBS[sub].page() : null;
    var enter = sub !== shownSub;
    shownSub = body ? sub : null;
    return body ? h('div', { class: 'settings sub' + (enter ? ' enter' : '') }, body) : viewSettings();
  }
  function viewSettings() {
    var d = S.device, pw = S.power, w = S.wifi, cfg = S.audio.config, m = obj(S.maintenance), b = obj(S.bluetooth), c = S.bedtime.cfg;
    var lvl = pw.level && typeof pw.level === 'object' ? Number(pw.level.p) : NaN;
    var known = !(isNaN(lvl) || (lvl === 0 && pw.level && !pw.level.mv)), pct = known ? Math.round(lvl / 10) : null;
    var du = obj(d.diskUsage);
    var total = Number(du.total) * 1024, used = Number(du.used) * 1024, free = Number(du.available) * 1024;
    var avail = upd.state === 'checked' && updateAvailable();
    var name = (d.hostname || '—').replace(/\.local$/, '');
    var con = obj(b.connected);
    var hero = h('div', { class: 'hero' },
      h('div', { class: 'row' }, h('div', { class: 'avatar', 'aria-hidden': 'true' }, 'J'),
        h('div', { class: 'grow', style: 'min-width:0' }, h('div', { class: 'hname ellipsis' }, name),
          h('div', { class: 'hsub ellipsis' }, h('i', { class: 'dot' + (online ? ' on' : '') }), (online ? t('connected') : t('offline')) + (w.ssid ? ' · ' + w.ssid : ''))),
        d.core ? h('button', { class: 'pillbtn', 'data-k': 'rename', onclick: nameModal }, t('rename')) : null),
      h('div', { class: 'stats' },
        stat('bat', t('battery'), known ? pct + ' %' : '—', pw.charging ? t('charging') : pw.connected ? t('plugged') : null, null, known ? pct : null, pct !== null && pct < 20 ? 'low' : 'ok'),
        stat('disk', t('storage'), total ? fmtBytes(free) : '—', total ? t('s_storage_free') : null, null, total ? used / total * 100 : null),
        stat('tag', t('version'), d.openjooki || '—', avail ? t('s_avail', upd.latest) : upd.state === 'checked' ? t('s_uptodate') : null, avail ? 'accent-text' : 'ok-text', null, null, 'version')));
    return h('div', { class: 'settings' }, hero,
      avail ? sGroup(null, [sRow({ icon: 'up', color: 'orange', label: t('upd_banner', upd.latest), value: t('upd_see'), vcls: 'acc', href: '#/settings/update', k: 'updrow' })]) : null,
      sGroup(t('s_listen'), [
        sRow({ icon: 'vol', color: 'orange', label: t('toy_safe'), sw: true, on: d.toy_safe, k: 'toysafe', onchange: function (e) { send('SET_TOY_SAFE', { enable: e.target.checked }); } }),
        sRow({ icon: 'shuffle', color: 'indigo', label: t('shuffle'), sw: true, on: cfg.shuffle_mode, k: 'shuffle', onchange: function (e) { send('SET_CFG', { shuffle_mode: e.target.checked }); } }),
        sRow({ icon: 'repeat', color: 'indigo', label: t('repeat'), sw: true, on: cfg.repeat_mode === 1 || cfg.repeat_mode === true, k: 'repeat', onchange: function (e) { send('SET_CFG', { repeat_mode: e.target.checked ? 1 : 0 }); } }),
        canConvert() ? sRow({ icon: 'note', color: 'teal', label: t('s_mp3'), sub: t('s_mp3_sub'), value: mp3Kbps() + ' kbps', href: '#/settings/mp3', k: 'mp3nav' }) : null,
        typeof b.state === 'number' ? sRow({ icon: 'bt', color: 'blue', label: t('s_bt'), value: con.mac ? (con.name || t('bt_unnamed')) : t('s_none'), href: '#/settings/bluetooth', k: 'btrow' }) : null
      ]),
      c.start !== undefined || d.airplane !== undefined ? sGroup(t('s_night_trip'), [
        c.start !== undefined ? sRow({ icon: 'moon', color: 'indigo', label: t('night_mode'), value: c.enabled ? hm(c.start) + ' – ' + hm(c.stop) : t('s_off'), href: '#/settings/night', k: 'nightrow' }) : null,
        d.airplane !== undefined ? sRow({ icon: 'plane', color: 'orange', label: t('air_title'), value: t('s_off'), href: '#/settings/airplane', k: 'airrow' }) : null
      ]) : null,
      sGroup(t('s_general'), [
        sRow({ icon: 'wifi', color: 'blue', label: t('wifi'), value: w.ssid || '—', href: '#/settings/wifi', k: 'wifinav' }),
        sRow({ icon: 'up', color: 'green', label: t('s_update'), value: avail ? t('s_avail', upd.latest) : upd.state === 'checked' ? t('s_uptodate') : '', vcls: avail ? 'acc' : 'good', href: '#/settings/update', k: 'updnav' }),
        sRow({ icon: 'globe', color: 'teal', label: t('language'), value: (LANGS.filter(function (l) { return l[0] === lang; })[0] || ['', ''])[1], href: '#/settings/language', k: 'langnav' }),
        sRow({ icon: 'contrast', color: 'gray', label: t('s_theme'), value: t('s_theme_' + theme), href: '#/settings/theme', k: 'themenav' }),
        d.core ? sRow({ icon: 'sparkle', color: 'party', label: t('s_party'), sub: t('s_party_sub'), nochev: true, k: 'party', onclick: function () {
          if (send('OJ_PARTY', {}) !== false) toast(t('s_party_done'));
        } }) : null
      ]),
      typeof m.parent === 'boolean' ? sGroup(t('s_parents'), [
        sRow({ icon: 'lock', color: 'red', label: t('parent_label'), value: m.parent ? t('s_on') : t('s_off'), href: '#/settings/parent', k: 'parentnav' })
      ], t('s_parent_foot')) : null,
      typeof m.ssh === 'boolean' ? sGroup(t('s_advanced'), [
        sRow({ icon: 'home', color: 'gray', label: t('s_home'), sub: t('s_home_sub'), value: m.mqtt_lan ? t('s_on') : t('s_off'), href: '#/settings/home', k: 'homenav' }),
        sRow({ icon: 'wrench', color: 'gray', label: t('s_maint'), sub: t('s_maint_sub'), value: m.ssh ? t('s_open') : t('s_closed'), href: '#/settings/maintenance', k: 'maintnav' })
      ]) : null,
      sGroup(null, [sRow({ icon: 'power', color: 'red', label: t('power_off'), danger: true, nochev: true, k: 'poweroff', onclick: function () {
        confirmBox(t('power_off_q'), t('power_off_text'), t('power_off'), true).then(function (ok) {
          if (!ok) return;
          send('SHUTDOWN', { src: 'from-web' }); toast(t('power_off_done'));
        });
      } })]),
      h('div', { class: 'verline', 'data-k': 'verline' }, 'OpenJooki ' + (d.openjooki || '—') + ' · ' + t('web_page') + ' ' + VERSION + (d.firmware ? ' · ' + d.firmware : '')));
  }
  function langPage() {
    return sGroup(null, LANGS.map(function (l) {
      return sRow({ label: l[1], lang: l[0], check: lang === l[0], nochev: true, k: 'lang-' + l[0], onclick: function () { setLang(l[0]); } });
    }), t('s_lang_foot'));
  }
  // the MP3 quality for FLAC / WAV sent to the Jooki, kept on this phone or computer
  function mp3Page() {
    return sGroup(null, MP3_RATES.map(function (v) {
      return sRow({ label: t('s_mp3_' + v), check: mp3Kbps() === v, nochev: true, k: 'mp3-' + v, onclick: function () { lsSet('oj.mp3', String(v)); render(); } });
    }), t('s_mp3_foot'));
  }
  function themePage() {
    return sGroup(null, THEMES.map(function (v) {
      return sRow({ label: t('s_theme_' + v), check: theme === v, nochev: true, k: 'theme-' + v, onclick: function () { setTheme(v); } });
    }), t('s_theme_foot'));
  }
  // Bluetooth speaker or headphones (docs/26), only on a core that offers it. The ESP32 plays to the
  // speaker by itself once connected, and reconnects to it when it comes back.
  var btTried = null;   // the device this page asked to connect, to tell a failure from "nothing connected"
  function btPage() {
    var b = obj(S.bluetooth);
    if (typeof b.state !== 'number') return null;
    var st = b.state, devs = arr(b.devices), con = obj(b.connected);
    function name(d) { return d.name || t('bt_unnamed'); }
    if (arr(S.device.flags).indexOf('BT_OFF') >= 0) return h('div', { class: 'gfoot', 'data-k': 'btair' }, t('bt_air'));
    if (con.mac) {
      btTried = null;
      return [h('div', { class: 'statuscard', 'data-k': 'btcard' }, h('div', { class: 'bigico blue' }, icon('bt')),
          h('b', { 'data-k': 'bton' }, t('bt_on', name(con))), h('p', null, t('bt_on_help'))),
        sGroup(null, [sRow({ label: t('bt_off_btn'), danger: true, nochev: true, k: 'btforget', onclick: function () {
          confirmBox(t('bt_off_q'), t('bt_off_text'), t('bt_off_btn'), false).then(function (ok) { if (ok) send('OJ_BT_FORGET', { mac: con.mac }); });
        } })])];
    }
    // the speakers the Jooki already knows: reconnecting needs no pairing mode, and a paired
    // speaker does not show in a search, so they come first, whatever the search finds
    var known = arr(b.known).map(function (k) { return Object.assign({ known: true }, k); });
    devs = known.concat(devs.filter(function (d) { return !known.some(function (k) { return k.mac === d.mac; }); }));
    var rows = devs.map(function (d) {
      var busy = st === 4 && btTried === d.mac;
      return sRow({ label: name(d), sub: d.known ? t('bt_known') : null, value: busy ? t('bt_connecting') : t('bt_connect'), vcls: 'acc', nochev: true,
        k: 'btdev-' + d.mac, disabled: st === 4, onclick: function () { if (send('OJ_BT_CONNECT', { mac: d.mac }) !== false) { btTried = d.mac; } } });
    });
    return h('div', { 'data-k': 'btcard' },
      rows.length ? sGroup(null, rows) : null,
      st === 6 && btTried ? h('p', { class: 'gfoot accent-text', 'data-k': 'btfail' }, t('bt_failed'))
        : st === 2 && !devs.length ? h('p', { class: 'gfoot', 'data-k': 'btnone' }, t('bt_none')) : null,
      h('button', { class: 'btn block', 'data-k': 'btscan', disabled: st === 1 || st === 4 ? 'disabled' : null,
        onclick: function () { btTried = null; send('OJ_BT_SCAN', {}); } }, icon('search'), st === 1 ? t('bt_searching') : t('bt_search')),
      h('p', { class: 'gfoot' }, t('bt_help')));
  }
  // Airplane mode (docs/24), only on a core that offers it. Always bounded: the Jooki switches its
  // radios back on by itself at the chosen time, and in any case at its next start.
  var airChoice = '2';   // hours, or 'morning' (the night mode's end) or 'boot'
  function airPage() {
    if (S.device.airplane === undefined) return null;
    var stop = Number(S.bedtime.cfg.stop); if (isNaN(stop)) stop = 420;
    var now = new Date(), nowMin = now.getHours() * 60 + now.getMinutes();
    var toMorning = (stop - nowMin + 1440) % 1440;
    if (toMorning < 15) toMorning += 1440;
    if (toMorning > 1440) toMorning = 1440;
    var opts = [['1', t('air_h', 1)], ['2', t('air_h', 2)], ['4', t('air_h', 4)], ['8', t('air_h', 8)], ['morning', t('air_morning', hm(stop))], ['boot', t('air_boot')]];
    function askAirplane() {
      var minutes = airChoice === 'boot' ? null : airChoice === 'morning' ? toMorning : Number(airChoice) * 60;
      var a = { sent: Date.now(), ends: minutes ? Date.now() + minutes * 60000 : 0 };
      confirmBox(t('air_q'), t('air_text', airplaneWhen(a)), t('air_btn'), true).then(function (ok) {
        if (!ok) return;
        a.sent = Date.now();
        if (send('OJ_AIRPLANE', minutes ? { minutes: minutes } : {}) !== false) { setAirplane(a); toast(t('air_sent')); }
      });
    }
    return [h('p', { class: 'gfoot', style: 'margin:0 16px 14px' }, t('air_help')),
      sGroup(t('s_air_for'), [h('div', { class: 'choice', role: 'group', 'aria-label': t('s_air_for') }, opts.map(function (o) {
        return h('button', { class: airChoice === o[0] ? 'on' : '', 'data-k': 'air-' + o[0], 'aria-pressed': String(airChoice === o[0]),
          onclick: function () { airChoice = o[0]; render(); } }, o[1]);
      }))]),
      h('button', { class: 'btn primary block', 'data-k': 'airgo', onclick: askAirplane }, icon('plane'), t('air_btn'))];
  }
  // Security switches (docs/adr/0007): only shown on a core that offers them.
  function parentPage() {
    var m = obj(S.maintenance);
    if (typeof m.parent !== 'boolean') return null;
    var rows = [sRow({ icon: 'lock', color: 'red', label: t('parent_label'), sw: true, on: m.parent, k: 'parent',
      onchange: function (e) { e.target.checked = !!m.parent; parentModal(m.parent ? 'off' : 'set'); } })];
    if (m.parent) rows.push(sRow({ label: t('parent_change'), k: 'pchange', onclick: function () { parentModal('change'); } }));
    return sGroup(null, rows, [t('parent_help'), m.parent ? ' ' + t('parent_reset') : null]);
  }
  function homePage() {
    var m = obj(S.maintenance);
    if (typeof m.ssh !== 'boolean' && typeof m.parent !== 'boolean') return null;
    var out = [sGroup(null, [sRow({ icon: 'home', color: 'gray', label: t('mqtt_label'), sw: true, on: m.mqtt_lan, k: 'mqttlan',
      onchange: function (e) { send('OJ_MQTT_LAN', { on: e.target.checked }); } })], t('mqtt_help'))];
    if (m.mqtt_lan) {
      var host = (S.net && S.net.name ? String(S.net.name) : null) || (S.device && S.device.hostname) || location.hostname;
      out.push(sGroup(t('s_connect_info'), [
        sRow({ label: t('mqtt_host_l'), value: host }), sRow({ label: t('mqtt_port_l'), value: '1883' }), sRow({ label: t('mqtt_user_l'), value: 'jooki' }),
        sRow({ label: t('mqtt_pass_l'), col: true, right: h('span', { class: 'mono' }, CFG.mqttPass || '—') })]));
    }
    return out;
  }
  function maintPage() {
    var m = obj(S.maintenance);
    if (typeof m.ssh !== 'boolean') return null;
    var out = [sGroup(null, [sRow({ icon: 'wrench', color: 'gray', label: t('ssh_label'), sw: true, on: m.ssh, k: 'ssh',
      onchange: function (e) { send(e.target.checked ? 'OJ_SSH_ON' : 'OJ_SSH_OFF', {}); } })], t('ssh_help'))];
    // while the access is open: a public key, kept on the Jooki across updates
    if (m.ssh) out.push(sGroup(t('ssh_key_l') + ' · ' + t('ssh_keys_n', Number(m.ssh_keys) || 0), [h('div', { class: 'gpad' },
      h('textarea', { class: 'input', rows: '3', 'data-k': 'sshkey', spellcheck: 'false', autocomplete: 'off', 'aria-label': t('ssh_key_l'), style: 'font-family:monospace;font-size:12px',
        oninput: function (e) { ui.sshKey = e.target.value; } }, ui.sshKey || ''),
      h('div', { class: 'row', style: 'gap:8px;flex-wrap:wrap;margin-top:8px' },
        h('button', { class: 'btn primary', 'data-k': 'sshkeyadd', onclick: function () {
          var k = String(ui.sshKey || '').trim();
          if (!k) return;
          var before = Number(m.ssh_keys) || 0, done = false;
          waiters.push(function (partial) {
            if (done) return true;
            if (!partial.maintenance || !(Number(obj(S.maintenance).ssh_keys) > before || before >= 5)) return false;
            done = true; ui.sshKey = ''; toast(t('ssh_key_added')); render(); return true;
          });
          onCmdError = function () { done = true; };     // refused: the usual error toast says why
          send('OJ_SSH_KEY', { key: k });
        } }, t('ssh_key_add')),
        Number(m.ssh_keys) ? h('button', { class: 'btn ghost', 'data-k': 'sshkeyclear', onclick: function () { send('OJ_SSH_KEY', { clear: true }); } }, t('ssh_key_clear')) : null))],
      t('ssh_key_help')));
    return out;
  }
  // Ask for the parent code when the Jooki refuses a protected action, then retry it.
  function askParent(bad) {
    var code = '';
    function submit() { if (!/^\d{4}$/.test(code)) return; parentCode = code; lsSet('oj.parent', code); closeModal();
      if (pendingCmd) { var pc = pendingCmd; pc.payload.code = code; send(pc.type, pc.payload); } }
    openModal({ autofocus: 'pask', render: function () {
      return [h('h3', null, t('parent_prompt')),
        codeInput(t('parent_label'), 'pask', code, function (v) { code = v; }, submit),
        bad ? h('p', { class: 'small accent-text' }, t('parent_bad')) : null,
        h('p', { class: 'small muted' }, t('parent_reset')),
        modalFoot(t('save'), submit)];
    } });
  }
  // Set, change or turn off the parent code.
  function parentModal(mode) {
    var cur = '', next = '', bad = false;
    function submit() {
      if (mode === 'off') {
        if (!/^\d{4}$/.test(cur)) { bad = true; renderModal(); return; }
        send('OJ_PARENT_CLEAR', { current: cur }); closeModal(); return;
      }
      if (!/^\d{4}$/.test(next) || (mode === 'change' && !/^\d{4}$/.test(cur))) { bad = true; renderModal(); return; }
      send('OJ_PARENT_SET', mode === 'change' ? { code: next, current: cur } : { code: next });
      parentCode = next; lsSet('oj.parent', next); closeModal();
    }
    openModal({ autofocus: (mode === 'set') ? 'pnew' : 'pcur', render: function () {
      var rows = [h('h3', null, t('parent_label'))];
      if (mode !== 'set') rows.push(codeInput(t('parent_cur'), 'pcur', cur, function (v) { cur = v; }, submit));
      if (mode !== 'off') rows.push(codeInput(t('parent_new'), 'pnew', next, function (v) { next = v; }, submit));
      if (bad) rows.push(h('p', { class: 'small accent-text' }, t('parent_bad')));
      rows.push(modalFoot(t('save'), submit));
      return rows;
    } });
  }
  // The Jooki's network name (2.0 core only). The Jooki's web server answers only to its own name,
  // so after a rename the page lives at the new address and the old one stops answering.
  function nameModal() {
    var d = S.device, factory = String(d.id || '').toLowerCase();
    var cur = String(d.hostname || '').replace(/\.local$/, '').toLowerCase();
    var name = cur === factory ? '' : cur, bad = false;
    function valid(v) { return v === '' || (v.length <= 32 && v !== 'localhost' && /^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/.test(v)); }
    function save() {
      var v = name.trim().toLowerCase().replace(/\.local$/, '');
      if (!valid(v)) { bad = true; renderModal(); return; }
      var eff = v || factory, url = 'http://' + eff + '.local/';
      closeModal();
      if (eff === cur) return;
      send('OJ_SET_NAME', { name: v });
      confirmBox(t('name_done', eff), t('name_text', url), t('name_open'), false).then(function (ok) { if (ok) location.href = url; });
    }
    openModal({
      autofocus: 'devname',
      render: function () {
        return [h('h3', null, t('name_title')),
          field(t('device_name'), { 'data-k': 'devname', maxlength: '40', placeholder: factory, value: name, autocapitalize: 'none', autocorrect: 'off', spellcheck: 'false',
              oninput: function (e) { name = e.target.value; if (bad) { bad = false; renderModal(); } },
              onkeydown: function (e) { if (e.key === 'Enter') save(); } }),
          h('p', { class: 'small ' + (bad ? 'accent-text' : 'muted') }, bad ? t('name_invalid') : t('name_help', factory)),
          modalFoot(t('save'), save, { k: 'namesave' })];
      }
    });
  }
  function wifiPage() {
    var w = S.wifi, d = S.device, n = S.net, dbm = Number(w.signal);
    var has = w.signal !== undefined && w.signal !== null && !isNaN(dbm);
    var q = !has ? null : dbm >= -65 ? 'good' : dbm >= -75 ? 'fair' : 'weak';
    var drops = Number(n.drops) || 0, bars = h('span', { class: 'bars' });
    for (var i = 1; i <= 4; i++) bars.appendChild(h('i', { class: has && i <= (dbm >= -60 ? 4 : dbm >= -67 ? 3 : dbm >= -75 ? 2 : 1) ? 'on ' + q : null, style: 'height:' + (3 + i * 2.6) + 'px' }));
    return [h('div', { 'data-k': 'wifirow' }, sGroup(null, [
        sRow({ label: t('s_wifi_net'), value: w.ssid || '—' }),
        has ? sRow({ label: t('s_wifi_signal'), right: h('span', { class: 'val wifi-' + q, 'data-k': 'wifiq' }, bars, t('wifi_' + q) + ' · ' + dbm + ' dBm') }) : null,
        sRow({ label: t('s_wifi_drops'), value: String(drops) }),
        sRow({ label: t('ip'), value: d.ip || location.hostname }),
        n.name ? sRow({ label: t('s_wifi_page'), value: String(n.name) }) : null
      ], q === 'weak' ? t('wifi_advice') : null)),
      sGroup(t('s_wifi_change'), [h('a', { class: 'srow noico', href: WIFI_PAGE, target: '_blank', rel: 'noopener' },
        h('span', { class: 'lbl' }, h('span', { class: 'l1' }, 'Bluetooth')), h('span', { class: 'chev' }, icon('chev')))], wifiBluetoothLine())];
  }
  // The way back when the Jooki loses its network (docs/wifi.html, over Bluetooth): said here, while
  // the page can still be read, with the name the Jooki shows in a Bluetooth list (JOOKI2_ + its id).
  var WIFI_PAGE = 'https://guillain-rdcde.github.io/OpenJooki/wifi.html';
  function wifiBluetoothLine() {
    var id = String((S.device && S.device.id) || '');
    if (!id) return null;
    var bt = 'JOOKI2_' + id.replace(/^jooki2[-_]/i, '').toUpperCase();
    return h('span', { 'data-k': 'wifibt' }, t('wifi_bt'),
      h('a', { href: WIFI_PAGE, target: '_blank', rel: 'noopener' }, 'guillain-rdcde.github.io/OpenJooki/wifi'), ' ', t('wifi_bt_name', bt));
  }
  function setLang(l) { lang = l; lsSet('oj.lang', l); document.documentElement.lang = l; IDX = null; render(); }

