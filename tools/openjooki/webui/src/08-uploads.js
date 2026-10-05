  /* ------------------------------------------------------------------ uploads */
  var uploads = [], upBusy = false, upSeq = 0;
  var AUDIO_EXT = /\.(mp3|m4a|mp4|aac|ogg|oga|flac|wav|wma|m4b)$/i;
  function enqueue(files, playlistId, opts) {
    opts = opts || {};
    var free = S.device.diskUsage && Number(S.device.diskUsage.available) ? Number(S.device.diskUsage.available) * 1024 : null;
    var reserved = 0, conv = canConvert();
    Array.prototype.forEach.call(files, function (f) {
      var u = { key: ++upSeq, file: f, name: f.name, size: f.size, playlistId: playlistId || null, status: 'queued', progress: 0, error: null,
                conv: conv && LOSSLESS.test(f.name), cover: opts.cover || null, disc: opts.disc || null };
      // the space an MP3 will take: FLAC is ~700 kbit/s or more, WAV 1411
      var need = u.conv ? f.size * mp3Kbps() / (/\.wav$/i.test(f.name) ? 1411 : 700) : f.size;
      if (f.size <= 5000) { u.status = 'error'; u.error = t('up_too_small'); }
      else if (!AUDIO_EXT.test(f.name) && !(f.type && f.type.indexOf('audio/') === 0)) { u.status = 'error'; u.error = t('up_type'); }
      else if (free !== null && reserved + need + 10e6 > free) { u.status = 'error'; u.error = t('up_no_space'); }
      else reserved += need;
      uploads.push(u);
    });
    render();
    convPump();
    pump();
  }
  // A weak Wi-Fi drops connections: a failed or stalled transfer is retried on its own
  // (after the Jooki is back), and a lost answer is checked again after reconnecting.
  var UP_TRIES = 4, UP_STALL_MS = 30000, UP_DELAYS = [3000, 8000, 20000];
  function pump() {
    if (upBusy) return;
    var now = Date.now();
    // in order: a file still to be converted holds back the ones after it (they keep the disc's order)
    var u = uploads.filter(function (x) { return x.status === 'queued' || x.status === 'converting'; })[0];
    if (u && (u.status === 'converting' || (u.conv && !u.converted) || u.retryAt > now)) u = null;
    if (!u) {
      var next = uploads.filter(function (x) { return x.status === 'queued' && x.retryAt; }).map(function (x) { return x.retryAt; })[0];
      if (next) setTimeout(pump, Math.max(200, next - now));
      return;
    }
    if (!online) { setTimeout(pump, 1500); return; }
    upBusy = true;
    u.status = 'uploading'; u.progress = 0; u.tries = (u.tries || 0) + 1; u.note = null;
    var uid = String(Math.floor(Math.random() * 9e6) + 1e6);
    var fd = new FormData();
    fd.append(uid, u.file, u.name);
    var xhr = new XMLHttpRequest();
    var lastMove = Date.now(), ended = false;
    var stall = setInterval(function () { if (Date.now() - lastMove > UP_STALL_MS) { xhr.abort(); } }, 2000);
    function netFail(why) {
      if (ended) return; ended = true; clearInterval(stall);
      retryOrFail(u, why);
    }
    xhr.open('POST', '/upload');
    xhr.upload.onprogress = function (e) { lastMove = Date.now(); if (e.lengthComputable) { u.progress = e.loaded / e.total; updateUploadRow(u); } };
    xhr.onerror = xhr.ontimeout = xhr.onabort = function () { netFail(t('up_net')); };
    xhr.onload = function () {
      if (ended) return; ended = true; clearInterval(stall);
      if (xhr.status !== 200) { retryOrFail(u, t('up_net') + ' (' + xhr.status + ')'); return; }
      u.progress = 1;
      u.status = 'processing';
      render();
      var beforePl = u.playlistId && pls()[u.playlistId] ? arr(pls()[u.playlistId].tracks).length : -1;
      var beforeLib = Object.keys(S.db.tracks).length;
      var p = { uploadId: uid, filename: u.name };
      if (u.playlistId) p.playlistId = u.playlistId;
      var resent = false;
      u.lost = false;
      var timer = setTimeout(function () { finishUp(u, 'error', t('up_timeout')); }, 240000);
      function added() {
        if (u.playlistId) return pls()[u.playlistId] && arr(pls()[u.playlistId].tracks).length > beforePl;
        return Object.keys(S.db.tracks).length > beforeLib;
      }
      waiters.push(function (partial) {
        if (u.status !== 'processing') return true;
        if (partial.audio) {                 // full state after a reconnection: did the Jooki get it?
          if (!u.lost) return false;
          u.lost = false;
          if (added()) { clearTimeout(timer); finishUp(u, 'done'); return true; }
          if (!resent) { resent = true; send('PLAYLIST_ADD_UPLOAD', p); }
          return false;
        }
        if (!(partial.db && partial.device)) return false; // end of an upload request
        clearTimeout(timer);
        if (u.failType) { finishUp(u, 'error', failText(u.failType)); return true; }
        if (u.playlistId && pls()[u.playlistId] && arr(pls()[u.playlistId].tracks).length <= beforePl) {
          if (resent && !u.failType) { finishUp(u, 'done'); return true; } // first request had worked
          finishUp(u, 'error', t('up_fail')); return true;
        }
        finishUp(u, 'done');
        return true;
      });
      if (!send('PLAYLIST_ADD_UPLOAD', p)) u.lost = true;
    };
    xhr.send(fd);
    render();
  }
  function retryOrFail(u, why) {
    upBusy = false;
    if (u.tries < UP_TRIES && u.file) {
      u.status = 'queued'; u.progress = 0;
      u.retryAt = Date.now() + UP_DELAYS[Math.min(u.tries - 1, UP_DELAYS.length - 1)];
      u.note = t('up_retrying', u.tries + 1, UP_TRIES);
      render(); soon(pump);
      return;
    }
    u.status = 'error'; u.error = why; u.canRetry = !!u.file;
    render(); soon(pump); soon(convPump);
  }
  function retryUpload(u) { u.status = 'queued'; u.tries = 0; u.retryAt = 0; u.error = null; u.canRetry = false; render(); pump(); }
  function finishUp(u, status, err) {
    if (!isActive(u)) return;
    u.status = status; u.error = err || null; u.file = null; u.note = null;
    upBusy = false;
    render();
    soon(function () { pump(); convPump(); });
  }
  // The next step starts as a microtask, never a timer: Chrome slows a hidden tab's timers to one a
  // second, and after five minutes to ONE A MINUTE, so a disc left to convert behind another tab
  // waited up to a minute between tracks. (A Web Lock would also keep the tab from being frozen, but
  // the page is served over plain http, where browsers do not offer them.)
  function soon(fn) { Promise.resolve().then(fn); }
  // an upload's statuses: queued, converting, uploading, processing (still going), then done or error
  var UP_ACTIVE = ['queued', 'converting', 'uploading', 'processing'];
  function isActive(u) { return UP_ACTIVE.indexOf(u.status) >= 0; }
  function uploadsActive() { return uploads.some(isActive); }
  window.addEventListener('beforeunload', function (e) { if (uploadsActive()) { e.preventDefault(); e.returnValue = t('uploads_running'); return e.returnValue; } });
  function updateUploadRow(u) {
    var el = document.querySelector('[data-up="' + u.key + '"] .bar > i');
    if (el) el.style.width = Math.round(u.progress * 100) + '%';
    var st = document.querySelector('[data-up="' + u.key + '"] .st');
    if (st) st.textContent = upLabel(u) + ' ' + Math.round(u.progress * 100) + ' %';
    if (u.disc) updateDiscRow(u.disc);
  }
  function upLabel(u) { return u.status === 'converting' ? t('converting', mp3Kbps()) : t('uploading'); }
  function uploadsBlock(playlistId) {
    var list = uploads.filter(function (u) { return u.playlistId === (playlistId || null); });
    if (!list.length) return null;
    var anyDone = list.some(function (u) { return !isActive(u); });
    return h('div', { class: 'card uploads' },
      list.map(function (u) {
        var st = u.status === 'queued' ? (u.note || (u.conv && !u.converted ? t('queued_conv', mp3Kbps()) : t('queued')))
          : u.status === 'uploading' || u.status === 'converting' ? upLabel(u) + ' ' + Math.round(u.progress * 100) + ' %'
          : u.status === 'processing' ? t('processing') : u.status === 'done' ? t('done') : u.error;
        return h('div', { class: 'up ' + u.status, 'data-up': u.key },
          h('div', { class: 'row' }, h('div', { class: 'grow ellipsis' }, u.name), h('span', { class: 'small muted' }, fmtBytes(u.size))),
          h('div', { class: 'bar' }, h('i', { style: 'width:' + (u.status === 'done' || u.status === 'processing' ? 100 : Math.round(u.progress * 100)) + '%' })),
          h('div', { class: 'st row' }, h('span', { class: 'grow' }, st),
            u.status === 'error' && u.canRetry ? h('button', { class: 'btn ghost', 'data-k': 'upretry-' + u.key, onclick: function () { retryUpload(u); } }, t('up_retry')) : null));
      }),
      anyDone && !uploadsActive() ? h('div', { class: 'up' }, h('button', { class: 'btn ghost block', onclick: function () {
        uploads = uploads.filter(function (u) { return u.playlistId !== (playlistId || null) || isActive(u); }); render();
      } }, t('clear_done'))) : null);
  }
  // A button that opens the file (or folder) picker: a label around a hidden input, the input last.
  // o: label, primary, k (the label's data-k), input (more attributes of the input), onFiles(files)
  function pickerButton(o) {
    var inp = h('input', Object.assign({ type: 'file', multiple: true, class: 'sr', 'aria-hidden': 'true', tabindex: '-1',
      onchange: function () { if (inp.files && inp.files.length) o.onFiles(inp.files); inp.value = ''; } }, o.input));
    return h('label', { class: 'btn' + (o.primary ? ' primary' : ''), tabindex: '0', role: 'button', 'data-k': o.k,
      onkeydown: function (e) { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); inp.click(); } } }, icon('upload'), o.label, inp);
  }
  // a drop target: lit while something hovers over it, `onDrop(dataTransfer)` when files are let go
  function dropTarget(z, onDrop) {
    z.addEventListener('dragover', function (e) { e.preventDefault(); z.classList.add('over'); });
    z.addEventListener('dragleave', function () { z.classList.remove('over'); });
    z.addEventListener('drop', function (e) { e.preventDefault(); z.classList.remove('over'); if (e.dataTransfer && e.dataTransfer.files.length) onDrop(e.dataTransfer); });
    return z;
  }
  // Files chosen together go in name order (a phone hands them over in no order). The pages of a story made
  // in Jookistory ("01 Title.mp3", "02 Title.mp3"…) make their playlist an audiobook: resumed, never shuffled.
  function pickedFiles(files, playlistId) {
    var list = Array.prototype.slice.call(files).sort(function (a, b) { return collator().compare(a.name, b.name); });
    var m = list.map(function (f) { return /^(\d\d) (.+)\.mp3$/i.exec(f.name); });
    var story = list.length > 1 && m.every(function (x, i) { return x && x[2] === m[0][2] && Number(x[1]) === i + 1; });
    var p = playlistId && pls()[playlistId];
    if (story && p && !p.audiobook) { send('PLAYLIST_UPDATE', { playlist: { id: playlistId, audiobook: true } }); toast(t('story_book')); }
    enqueue(list, playlistId);
  }
  function fileButton(label, playlistId, primary) {
    return pickerButton({ label: label, primary: primary, input: { accept: 'audio/*,.mp3,.m4a,.m4b,.aac,.ogg,.oga,.flac,.wav,.wma' },
      onFiles: function (files) { pickedFiles(files, playlistId); } });
  }
  function dropZone(playlistId) {
    // folders too: their files go into this playlist, folder after folder, in disc order
    return dropTarget(h('div', { class: 'drop' }, t('drop_here'), h('div', { class: 'small' }, t('files_hint'))),
      function (dt) { groupsFromDrop(dt).then(function (g) { addDiscs(g, playlistId); }); });
  }
  var canHover = window.matchMedia && window.matchMedia('(hover: hover) and (pointer: fine)').matches;

  // discs on the playlists page: one line per disc (folder) being sent, with its progress
  var discSeq = 0;
  function discInfo(disc) {
    var list = uploads.filter(function (u) { return u.disc === disc; });
    var done = list.filter(function (u) { return u.status === 'done'; }).length, bad = list.filter(function (u) { return u.status === 'error'; });
    var cur = list.filter(function (u) { return u.status === 'uploading' || u.status === 'processing' || u.status === 'converting'; })[0];
    var st = cur ? cur.name + ' · ' + (cur.status === 'processing' ? t('processing') : upLabel(cur) + ' ' + Math.round(cur.progress * 100) + ' %')
      : done + bad.length < list.length ? t('queued') : bad.length ? t('disc_errors', bad.length) : t('done');
    return { n: list.length, done: done, bad: bad, st: st, frac: (done + bad.length + (cur ? cur.progress : 0)) / Math.max(1, list.length),
             over: done + bad.length === list.length };
  }
  function updateDiscRow(disc) {
    var el = document.querySelector('[data-disc="' + disc.id + '"]');
    if (!el) return;
    var i = discInfo(disc);
    el.querySelector('.bar > i').style.width = Math.round(i.frac * 100) + '%';
    el.querySelector('.st').textContent = i.st;
  }
  function discsBlock() {
    var discs = [];
    uploads.forEach(function (u) { if (u.disc && discs.indexOf(u.disc) < 0) discs.push(u.disc); });
    if (!discs.length) return null;
    var running = discs.some(function (d) { return !discInfo(d).over; });
    return h('div', { class: 'card uploads', 'data-k': 'discs' }, discs.map(function (d) {
      var i = discInfo(d);
      return h('div', { class: 'up' + (i.over ? (i.bad.length ? ' error' : ' done') : ''), 'data-disc': d.id },
        h('div', { class: 'row' }, h('div', { class: 'grow ellipsis' }, '💿 ' + d.title), h('span', { class: 'small muted' }, t('disc_progress', i.done, i.n))),
        h('div', { class: 'bar' }, h('i', { style: 'width:' + Math.round(i.frac * 100) + '%' })),
        h('div', { class: 'st small' }, i.st),
        i.bad.map(function (u) { return h('div', { class: 'small accent-text ellipsis' }, u.name + t('colon') + u.error); }));
    }), running ? null : h('div', { class: 'up' }, h('button', { class: 'btn ghost block', 'data-k': 'discclear', onclick: function () {
      uploads = uploads.filter(function (u) { return !u.disc; }); render();
    } }, t('clear_done'))));
  }
  // "Add albums": a folder picker, on computers (phones cannot pick a folder)
  function discButton() {
    if (!canHover || !('webkitdirectory' in document.createElement('input'))) return null;
    return pickerButton({ label: t('disc_add'), k: 'discadd', input: { webkitdirectory: true, 'data-k': 'discinput' },
      onFiles: function (files) { addDiscs(groupsFromList(files), null); } });
  }
  function discDrop() {
    if (!canHover) return null;
    return dropTarget(h('div', { class: 'drop', 'data-k': 'discdrop' }, t('disc_drop'), h('div', { class: 'small' }, t('disc_hint', mp3Kbps()))),
      function (dt) { groupsFromDrop(dt).then(function (g) { addDiscs(g, null); }); });
  }

