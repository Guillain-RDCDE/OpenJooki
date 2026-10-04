  /* ------------------------------------------------------------------ MQTT connection */
  var client = null, online = false, everOnline = false, retryDelay = 1000, retryTimer = null, lastCmd = 0;
  var wsHost = location.hostname || '127.0.0.1';
  // The broker's WebSocket needs a per-Jooki password (docs/adr/0007). It is served
  // at the page's own origin: readable here, not by a booby-trapped website (no CORS,
  // and JSON is not runnable as a <script>). Fetched once at boot; if it is absent
  // (an older or un-hardened Jooki), we connect anonymously as before. Reconnects
  // reuse CFG, so this runs only at startup.
  function loadAuth(then) {
    if (!window.fetch) { then(); return; }
    var done = false, cont = function () { if (!done) { done = true; then(); } };
    setTimeout(cont, 4000);
    fetch('oj-auth.json', { cache: 'no-store', credentials: 'same-origin' })
      .then(function (r) { return r.ok ? r.json() : null; })
      .then(function (c) {
        if (c && typeof c === 'object') {
          if (c.mqttUser != null) CFG.mqttUser = c.mqttUser;
          if (c.mqttPass != null) CFG.mqttPass = c.mqttPass;
          if (c.wsPort != null) CFG.wsPort = c.wsPort;
        }
        cont();
      })
      .catch(cont);
  }
  function connect() {
    clearTimeout(retryTimer);
    if (client) { try { client.onclose = function () {}; client.close(); } catch (e) {} }
    var url = 'ws://' + (wsHost.indexOf(':') >= 0 ? '[' + wsHost + ']' : wsHost) + ':' + (CFG.wsPort || 8000) + '/mqtt';
    client = new window.MiniMqtt(url, { username: CFG.mqttUser, password: CFG.mqttPass, keepalive: 20 });
    client.onconnect = function () {
      online = true; everOnline = true; retryDelay = 1000;
      // back after an airplane mode (not a hiccup right after asking for it)
      if (airplane && Date.now() - airplane.sent > 15000) { setAirplane(null); toast(t('air_back')); }
      client.subscribe('/j/web/output/#');
      send('GET_STATE', {});
      sendTime();
      render();
    };
    client.onmessage = onMessage;
    client.onclose = function () {
      var was = online;
      online = false;
      uploads.forEach(function (u) { if (u.status === 'processing') u.lost = true; });
      if (was || !everOnline) render();
      retryTimer = setTimeout(connect, retryDelay);
      retryDelay = Math.min(retryDelay * 1.6, 8000);
    };
    client.connect();
  }
  // airplane mode started from the page (docs/24): the Jooki leaves the Wi-Fi on purpose, so this
  // browser remembers until when and says so, instead of "the Jooki is not answering".
  var airplane = null;
  try { airplane = JSON.parse(lsGet('oj.airplane') || 'null'); } catch (e) { airplane = null; }
  function setAirplane(v) { airplane = v; lsSet('oj.airplane', v ? JSON.stringify(v) : ''); }
  function airplaneNow() {
    if (!airplane) return null;
    if (airplane.ends && Date.now() > airplane.ends + 5 * 60000) { setAirplane(null); return null; }   // long over: back to normal
    return airplane;
  }
  function airplaneWhen(a) {
    if (!a.ends) return t('air_next_start');
    var e = new Date(a.ends);
    return t('air_at', hm(e.getHours() * 60 + e.getMinutes()));
  }
  // parent code (docs/adr/0007): remembered once per device, sent with every command;
  // the Jooki only checks it on the actions it protects. Playing music never needs it.
  var parentCode = lsGet('oj.parent') || '';
  var pendingCmd = null;
  function send(type, payload) {
    lastCmd = Date.now();
    if (!client || !online) { toast(t('offline'), 'error'); return false; }
    payload = payload || {};
    if (parentCode) payload.code = parentCode;
    pendingCmd = { type: type, payload: payload };
    return client.publish('/j/web/input/' + type, JSON.stringify(payload));
  }
  // The Jooki has no clock of its own: started without Internet it believes it is 1970, and night
  // mode stays off. This phone's time goes with every connection; the Jooki takes it only while its
  // own clock is unset (no code needed, nothing else changes).
  function sendTime() {
    var utc = Math.floor(Date.now() / 1000);
    if (!client || !online || utc < 1704067200) return;
    client.publish('/j/web/input/OJ_TIME', JSON.stringify({ utc: utc }));
  }
  var waiters = [], autoChecked = false, staleReload = false, onCmdError = null;
  // The Jooki serves index.html without cache headers: a phone may keep the old page after an
  // update (system 2.0.5, page 2.0.4). If the Jooki is newer than this page, load it again once,
  // under a new address so the phone cannot reuse its copy (?v= also stops any loop).
  function reloadIfStale() {
    var v = S.device.openjooki;
    if (staleReload || !v || !newer(v, VERSION) || location.search.indexOf('v=' + v) >= 0) return;
    staleReload = true;
    var busy = upd.state === 'running' || upd.state === 'rebooting';   // just updated: let the "done" toast show first
    setTimeout(function () { location.replace(location.pathname + '?v=' + encodeURIComponent(v) + location.hash); }, busy ? 3000 : 0);
  }
  // A connection the browser dropped without telling (a phone that slept, an iPhone tab left behind)
  // still looks open, and nothing ever tries again: the update screen then waits for ever. So when
  // the page comes back in front, and every 10 s during an update, ask for the state; if nothing
  // answers, connect again.
  var lastRx = 0, aliveTimer = null;
  function checkAlive() {
    if (!client || aliveTimer) return;
    if (!online) { retryDelay = 1000; connect(); return; }
    var asked = Date.now();
    client.publish('/j/web/input/GET_STATE', '{}');
    aliveTimer = setTimeout(function () { aliveTimer = null; if (lastRx < asked) connect(); }, 5000);
  }
  document.addEventListener('visibilitychange', function () { if (!document.hidden) checkAlive(); });
  window.addEventListener('pageshow', checkAlive);
  window.addEventListener('online', checkAlive);
  function onMessage(topic, text) {
    var data;
    lastRx = Date.now();
    try { data = JSON.parse(text); } catch (e) { return; }
    if (topic === '/j/web/output/state') {
      var posOnly = data && Object.keys(data).length === 1 && data.audio && Object.keys(data.audio).length === 1 && data.audio.playback &&
        obj(data.audio.playback).state === S.audio.playback.state;
      mergeState(data);
      if (posOnly) return;
      waiters = waiters.filter(function (w) { return !w(data); });
      if (!autoChecked && S.device.openjooki) { autoChecked = true; resumeUpdate(function (running) { if (!running) setTimeout(checkUpdate, 1500); }); }
      reloadIfStale();
      syncClock();
      handleUserMessages();
      scheduleRender();
    } else if (topic === '/j/web/output/error') {
      if (data && data.msg === 'PARENT_CODE_REQUIRED') {
        var bad = !!parentCode;                       // a stored code that no longer matches
        if (bad) { parentCode = ''; lsSet('oj.parent', ''); }
        askParent(bad);
        return;
      }
      if (Date.now() - lastCmd < 4000) toast(errorText(data && data.msg), 'error');
      if (onCmdError) { var f = onCmdError; onCmdError = null; f(data); }
    }
  }
  // the Jooki's error messages (the core's own words) -> what the page says
  var ERR_TEXT = { TRASH_READONLY: 'err_readonly', ERR_INTERNAL: 'err_internal', 'empty title': 'err_empty_title', 'invalid stream url': 'err_radio',
                   'invalid token type': 'err_unknown_char', 'Not playing spotify right now': 'err_sp_not_playing', SSH_KEY_INVALID: 'err_ssh_key', SSH_CLOSED: 'err_ssh_closed' };
  function errorText(msg) {
    msg = String(msg || '');
    if (ERR_TEXT.hasOwnProperty(msg)) return t(ERR_TEXT[msg]);
    if (/does not exist|invalid:|nil playlistId|unknown token/.test(msg)) return t('err_gone');
    return t('err_generic');
  }
  // an upload the Jooki refused: a file it cannot read, or anything else
  function failText(type) { return t(type === 'UPLOAD_FAIL_TYPE' ? 'up_type' : 'up_fail'); }
  var seenMsg = {};
  function handleUserMessages() {
    S.userMessages.forEach(function (m) {
      if (!m || seenMsg[m.id]) return;
      seenMsg[m.id] = true;
      var type = String(m.messageType || '');
      var ex = obj(m.extra);
      var mine = uploads.some(function (u) { return u.name === ex.filename && (u.status === 'processing' || u.status === 'uploading'); });
      if (type.indexOf('UPLOAD_FAIL') === 0) {
        uploads.forEach(function (u) {
          if (u.name === ex.filename && u.status === 'processing') { u.failType = type; }
        });
        if (!mine && ex.filename) toast(failText(type) + t('colon') + ex.filename, 'error');
      }
      if (client && online) client.publish('/j/web/input/MESSAGE_DISMISS', JSON.stringify({ id: m.id }));
    });
  }

