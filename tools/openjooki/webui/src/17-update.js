  /* ---------------- OpenJooki updates (the Jooki itself talks to GitHub) */
  var upd = { state: 'idle', latest: null, startedFrom: null };
  function vparts(v) { return String(v || '0').split(/[.-]/).map(function (x) { return parseInt(x, 10) || 0; }); }
  function newer(a, b) {
    var x = vparts(a), y = vparts(b);
    for (var i = 0; i < Math.max(x.length, y.length); i++) { if ((x[i] || 0) !== (y[i] || 0)) return (x[i] || 0) > (y[i] || 0); }
    return false;
  }
  function installed() { return S.device.openjooki || null; }
  function updateAvailable() { return upd.latest && installed() && newer(upd.latest, installed()); }
  function getText(path, cb) {
    var x = new XMLHttpRequest();
    x.open('GET', path + (path.indexOf('?') < 0 ? '?' : '&') + 't=' + Date.now());
    x.timeout = 5000;
    x.onload = function () { cb(x.status === 200 ? x.responseText : null); };
    x.onerror = x.ontimeout = function () { cb(null); };
    x.send();
  }
  function checkUpdate() {
    if (upd.state === 'running' || upd.state === 'rebooting' || !installed()) return;
    upd.state = 'checking'; render();
    var t0 = Date.now();
    // the Jooki writes {"pending":true} right away, then the answer from GitHub
    send('OJ_UPDATE_CHECK', {});
    setTimeout(function poll() {
      getText('/oj-latest.json', function (txt) {
        var d = null;
        try { d = JSON.parse(txt); } catch (e) {}
        if (d && !d.pending) {
          if (d.error || !d.version) { upd.state = 'offline'; }
          else { upd.latest = String(d.version); upd.state = 'checked'; }
          render(); return;
        }
        if (Date.now() - t0 > 40000) { upd.state = 'offline'; render(); return; }
        setTimeout(poll, 1500);
      });
    }, 1500);
  }
  var UPD_BAD = /ERROR|SAFETY|INVALID|not performed|did not complete|download failed|no network|invalid manifest/i;
  // this browser remembers that it started an update (oj.upd, a time), to take it up again after a reload
  function updBegin() { upd.state = 'running'; upd.startedFrom = installed(); upd.step = 0; upd.pct = null; upd.reboot = false; upd.movedAt = Date.now(); lsSet('oj.upd', String(Date.now())); }
  function updOver(state) { upd.state = state; lsSet('oj.upd', ''); }
  // read the installer's report every 3 s while it runs
  function pollUpdate() {
    if (upd.state !== 'running') return;
    getText('/oj-status.txt', function (txt) {
      if (txt) {
        var p = updProgress(txt);
        if (p.step !== upd.step || p.pct !== upd.pct) upd.movedAt = Date.now();
        upd.step = p.step; upd.pct = p.pct;
        // what the installer wrote before it asked for the reboot: later lines come from a dying process
        var before = txt.split('REBOOT_NOW')[0];
        if (/already up to date/i.test(txt)) { updOver('checked'); toast(t('upd_uptodate')); render(); return; }
        if (!p.reboot && UPD_BAD.test(before) && !/retry/i.test(before.split('\n').filter(Boolean).pop() || '')) {
          updOver('failed'); render(); return;
        }
        upd.reboot = p.reboot;
      }
      render();
      setTimeout(pollUpdate, 3000);
    });
  }
  function startUpdate() {
    confirmBox(t('upd_q', upd.latest), t('upd_text'), t('upd_now'), false).then(function (ok) {
      if (!ok) return;
      updBegin();
      send('OJ_UPDATE_START', {});
      render();
      setTimeout(pollUpdate, 1500);
    });
  }
  // The page that started an update, reloaded while the Jooki is installing, takes the update where
  // it is: the installer's report is there and says neither "done" nor "failed". Only that browser
  // asks (within the hour): the report does not exist otherwise, and asking for it would be an error
  // in every other page's console. cb(true) when an update is running.
  function resumeUpdate(cb) {
    if (upd.state === 'running' || upd.state === 'rebooting') { cb(true); return; }
    var since = Number(lsGet('oj.upd')) || 0;
    if (!since || Date.now() - since > 3600000) { cb(false); return; }
    getText('/oj-status.txt', function (txt) {
      var live = !!txt && /\S/.test(txt) && !/already up to date/i.test(txt) && !UPD_BAD.test(txt.split('REBOOT_NOW')[0]);
      if (live) { updBegin(); render(); pollUpdate(); } else lsSet('oj.upd', '');
      cb(live);
    });
  }
  // while an update runs: a dead connection is noticed (checkAlive), and the screen is drawn again
  // so that the "nothing moving" help can appear even when no message comes
  setInterval(function () {
    if (upd.state !== 'running' && upd.state !== 'rebooting') return;
    checkAlive();
    if (route().name === 'settings') render();
  }, 10000);
  // "Reload the page", only once the Jooki answers (a reload while it restarts shows the browser's error page)
  function reloadWhenThere() {
    getText('/index.html', function (txt) { if (txt) location.reload(); else toast(t('upd_wait')); });
  }
  // The installer's report (oj-status.txt, its own words and curl's meter) -> which step, how far.
  // Steps: 0 looking, 1 downloading, 2 checking the download, 3 installing, 4 checking the install, 5 restarting.
  function updProgress(txt) {
    var step = 0, pct = null, lines = txt.split(/[\r\n]+/), dl = false;
    for (var i = 0; i < lines.length; i++) {
      var l = lines[i];
      if (/downloading/i.test(l)) { step = Math.max(step, 1); dl = true; }
      else if (/verifying sha256|image intact/i.test(l)) { step = Math.max(step, 2); dl = false; }
      else if (/A\/B install|writing to spare/i.test(l)) { step = Math.max(step, 3); dl = false; }
      else if (/bit-for-bit|bit-perfect/i.test(l)) step = Math.max(step, 4);
      else if (/arming|commit-on-boot|REBOOT_NOW/i.test(l)) step = Math.max(step, 5);
      var m = dl && /^\s*(\d{1,3})\s+\d+(\.\d+)?[kMG]?\s+\d{1,3}\s/.exec(l);   // curl: "  8 40.0M  8 3293k ..."
      if (m) pct = Math.min(100, +m[1]);
    }
    return { step: step, pct: step === 1 ? pct : null, reboot: /REBOOT_NOW/.test(txt) };
  }
  function updSteps() {
    var names = t('upd_steps'), cur = upd.state === 'rebooting' ? 5 : (upd.step || 0);
    return h('ol', { class: 'updsteps' }, names.map(function (n, i) {
      var done = i < cur, now = i === cur;
      return h('li', { class: done ? 'done' : now ? 'now' : '' }, h('span', { class: 'mark' }, done ? '✓' : now ? '•' : ''),
        h('span', null, n + (now && i === 1 && upd.pct !== null ? ' … ' + upd.pct + ' %' : now ? '…' : '')));
    }));
  }
  var UPD_STUCK_MS = CFG.updStuckMs || 180000;
  // the Update page's body (Settings > Update)
  function updateCard() {
    var cur = installed();
    if (upd.state === 'running' || upd.state === 'rebooting') {
      return h('div', { class: 'card', style: 'padding:16px', 'data-k': 'updcard' },
        h('div', { class: 'row' }, h('div', { class: 'spinner', style: 'width:28px;height:28px;border-width:3px;margin:0' }),
          h('b', { class: 'grow' }, upd.state === 'rebooting' ? t('upd_rebooting') : t('upd_running'))),
        updSteps(),
        h('p', { class: 'small muted' }, t('upd_keep')),
        // three minutes without any progress: say what may be going on, and offer a way out
        Date.now() - (upd.movedAt || 0) > UPD_STUCK_MS ? [h('p', { class: 'small', 'data-k': 'updstuck' }, t('upd_stuck')),
          h('button', { class: 'btn block', 'data-k': 'updreload', onclick: reloadWhenThere }, t('upd_reload'))] : null);
    }
    var avail = upd.state === 'checked' && updateAvailable();
    var bad = upd.state === 'failed' || upd.state === 'offline';
    var look = avail ? ['up', 'accent'] : bad ? ['x', 'danger'] : upd.state === 'checked' ? ['check', 'ok'] : ['up', 'muted'];
    var title = upd.state === 'checking' ? t('upd_checking') : upd.state === 'offline' ? t('upd_offline') : upd.state === 'failed' ? t('upd_failed')
      : avail ? t('upd_available', upd.latest) : upd.state === 'checked' ? t('upd_uptodate') : 'OpenJooki ' + (cur || '—');
    return [
      h('div', { class: 'statuscard', 'data-k': 'updcard' }, h('div', { class: 'bigico ' + look[1] }, icon(look[0])),
        h('b', null, title), h('p', null, avail ? t('upd_text') : 'OpenJooki ' + (cur || '—'))),
      avail ? h('button', { class: 'btn primary block', 'data-k': 'updnow', onclick: startUpdate }, icon('upload'), t('upd_now'))
        : h('button', { class: 'btn block', 'data-k': 'updcheck', disabled: upd.state === 'checking' || !cur, onclick: checkUpdate }, t('upd_check'))
    ];
  }
  var lastOnline = true, backAt = 0;
  function watchUpdateReconnect() {
    // only once the installer has asked for the reboot: before that, a lost connection (a busy Jooki,
    // a hiccup of the Wi-Fi) is not a restart, and the report is simply read again when it comes back
    if (upd.state === 'running' && !online && lastOnline && upd.reboot) { upd.state = 'rebooting'; upd.movedAt = Date.now(); }
    var busy = upd.state === 'running' || upd.state === 'rebooting';
    // back with the new version: done, whether or not we saw the "restarting" line (read every 3 s)
    if (busy && online && gotState && installed() && installed() !== upd.startedFrom) {
      updOver('checked'); toast(t('upd_done', installed())); upd.latest = installed(); backAt = 0;
    }
    // back with the old version after an announced restart: the Jooki went back on its own
    if (upd.state === 'rebooting' && online && gotState && installed()) {
      if (!backAt) {
        backAt = Date.now();
        setTimeout(function () { if (upd.state === 'rebooting' && installed() === upd.startedFrom) { updOver('failed'); render(); } }, 90000);
      }
    }
    lastOnline = online;
  }

