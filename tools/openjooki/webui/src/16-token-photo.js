  /* ------------------------------------------------------------------ a picture for a tag */
  // The whole job happens in the browser: the photo (camera, gallery or a file on a computer) is
  // read into a canvas, the background is removed by flood fill (a tap = a magic wand on that
  // zone, "Remove the background" = the same from the edges), then rotation, zoom and drag frame
  // the object in a circle. The Jooki only receives a 128 px PNG (about 10 KB).
  function uploadBlob(blob, name, cb) {
    var uid = String(Math.floor(Math.random() * 9e6) + 1e6);
    var fd = new FormData(); fd.append(uid, blob, name);
    var xhr = new XMLHttpRequest();
    xhr.open('POST', '/upload'); xhr.timeout = 60000;
    xhr.onerror = xhr.ontimeout = xhr.onabort = function () { cb(null); };
    xhr.onload = function () { cb(xhr.status === 200 ? uid : null); };
    xhr.send(fd);
  }
  function tokenImageEditor(tag, file, sid) {
    sid = sid || ('tag.' + tag);   // the sheet to go back to
    var SRC_MAX = 640, VIEW = 320, OUT = 128, R = VIEW / 2 - 6;
    var src = document.createElement('canvas'), cut = document.createElement('canvas'), sw = 0, sh = 0;
    var keep = null, undo = [], rot = 0, zoom = 1, px = 0, py = 0, tol = 25, busy = false;
    // The background is what the flood reaches from the edges without crossing a contour: a
    // pixel is taken when its colour is close to the seed's AND the picture is flat there
    // (luminance Sobel under EDGE). So a silver sword on white keeps its outline even though
    // silver is within the colour tolerance of white. Then the thin anti-aliased rim left
    // along the contour is peeled when it is close to the background colour next to it.
    var EDGE = 28, pix = null, grad = null;
    function buildGrad() {
      pix = src.getContext('2d').getImageData(0, 0, sw, sh).data;
      var L = new Float32Array(sw * sh), n = sw * sh;
      for (var i = 0; i < n; i++) L[i] = 0.299 * pix[i * 4] + 0.587 * pix[i * 4 + 1] + 0.114 * pix[i * 4 + 2];
      grad = new Uint8Array(n);
      for (var y = 1; y < sh - 1; y++) for (var x = 1; x < sw - 1; x++) {
        var j = y * sw + x;
        var gx = (L[j - sw + 1] + 2 * L[j + 1] + L[j + sw + 1]) - (L[j - sw - 1] + 2 * L[j - 1] + L[j + sw - 1]);
        var gy = (L[j + sw - 1] + 2 * L[j + sw] + L[j + sw + 1]) - (L[j - sw - 1] + 2 * L[j - sw] + L[j - sw + 1]);
        grad[j] = Math.min(255, (Math.abs(gx) + Math.abs(gy)) / 4);
      }
    }
    function dist(i, j) { var dr = pix[i * 4] - pix[j * 4], dg = pix[i * 4 + 1] - pix[j * 4 + 1], db = pix[i * 4 + 2] - pix[j * 4 + 2]; return Math.sqrt(dr * dr + dg * dg + db * db); }
    function peel(lim) {
      var n = sw * sh, changed = false;
      for (var pass = 0; pass < 2; pass++) {
        var drop = [];
        for (var i = 0; i < n; i++) {
          if (!keep[i] || grad[i] <= EDGE) continue;
          var x = i % sw, y = (i - x) / sw, nb = [x > 0 ? i - 1 : -1, x < sw - 1 ? i + 1 : -1, y > 0 ? i - sw : -1, y < sh - 1 ? i + sw : -1];
          for (var k = 0; k < 4; k++) { var j = nb[k]; if (j >= 0 && !keep[j] && dist(i, j) <= lim) { drop.push(i); break; } }
        }
        for (var q = 0; q < drop.length; q++) keep[drop[q]] = 0;
        changed = changed || drop.length > 0;
      }
      return changed;
    }
    var view = h('canvas', { class: 'edcanvas', width: VIEW, height: VIEW, 'aria-label': t('ed_title') });
    var vctx = view.getContext('2d');
    var status = h('div', { class: 'small muted', style: 'min-height:18px' }, t('ed_hint'));
    function fitScale() { return (R * 2) / Math.max(sw, sh); }
    function rebuildCut() {
      var c = cut.getContext('2d'); c.clearRect(0, 0, sw, sh); c.drawImage(src, 0, 0);
      var d = c.getImageData(0, 0, sw, sh), a = d.data;
      for (var i = 0, n = sw * sh; i < n; i++) if (!keep[i]) a[i * 4 + 3] = 0;
      c.putImageData(d, 0, 0);
    }
    function place(ctx, cx, cy, k) {
      ctx.translate(cx + px * k, cy + py * k); ctx.rotate(rot * Math.PI / 180); var s = fitScale() * zoom * k; ctx.scale(s, s); ctx.translate(-sw / 2, -sh / 2);
    }
    function draw() {
      vctx.clearRect(0, 0, VIEW, VIEW);
      vctx.save(); vctx.globalAlpha = 0.25; place(vctx, VIEW / 2, VIEW / 2, 1); vctx.drawImage(cut, 0, 0); vctx.restore();
      vctx.save(); vctx.beginPath(); vctx.arc(VIEW / 2, VIEW / 2, R, 0, Math.PI * 2); vctx.clip(); place(vctx, VIEW / 2, VIEW / 2, 1); vctx.drawImage(cut, 0, 0); vctx.restore();
      vctx.save(); vctx.beginPath(); vctx.arc(VIEW / 2, VIEW / 2, R, 0, Math.PI * 2); vctx.strokeStyle = 'rgba(0,0,0,.35)'; vctx.lineWidth = 2; vctx.stroke(); vctx.restore();
    }
    function toSrc(vx, vy) {   // a point of the view -> a pixel of the source
      var x = vx - VIEW / 2 - px, y = vy - VIEW / 2 - py, a = -rot * Math.PI / 180, s = fitScale() * zoom;
      var rx = x * Math.cos(a) - y * Math.sin(a), ry = x * Math.sin(a) + y * Math.cos(a);
      return [Math.floor(rx / s + sw / 2), Math.floor(ry / s + sh / 2)];
    }
    function pushUndo() { undo.push(keep.slice(0)); if (undo.length > 10) undo.shift(); }
    var ready = function () { return !!keep && !busy; };   // nothing works before the picture is loaded
    function flood(seeds) {   // seeds: [[x, y]]; each zone is compared with the colour under its own seed
      var d = pix, lim = tol * 4.4, changed = false;
      seeds.forEach(function (sd) {
        var x0 = sd[0], y0 = sd[1];
        if (x0 < 0 || y0 < 0 || x0 >= sw || y0 >= sh) return;
        var i0 = (y0 * sw + x0), r0 = d[i0 * 4], g0 = d[i0 * 4 + 1], b0 = d[i0 * 4 + 2];
        if (!keep[i0]) return;
        var stack = [i0], seen = new Uint8Array(sw * sh); seen[i0] = 1;
        while (stack.length) {
          var i = stack.pop(), dr = d[i * 4] - r0, dg = d[i * 4 + 1] - g0, db = d[i * 4 + 2] - b0;
          if (grad[i] > EDGE) continue;   // a contour: the zone stops here
          if (Math.sqrt(dr * dr + dg * dg + db * db) > lim) continue;
          keep[i] = 0; changed = true;
          var x = i % sw, y = (i - x) / sw;
          if (x > 0 && !seen[i - 1]) { seen[i - 1] = 1; stack.push(i - 1); }
          if (x < sw - 1 && !seen[i + 1]) { seen[i + 1] = 1; stack.push(i + 1); }
          if (y > 0 && !seen[i - sw]) { seen[i - sw] = 1; stack.push(i - sw); }
          if (y < sh - 1 && !seen[i + sw]) { seen[i + sw] = 1; stack.push(i + sw); }
        }
      });
      return changed;
    }
    function act(seeds) { if (!ready()) return; pushUndo(); var f = flood(seeds); if (peel(tol * 4.4 * 0.4) || f) { rebuildCut(); draw(); } else undo.pop(); }
    function removeBackground() {   // from a clean slate, so the tolerance slider is what you see
      if (!ready()) return;
      pushUndo(); keep.fill(1);
      var e = 2, mx = Math.floor(sw / 2), my = Math.floor(sh / 2);
      flood([[e, e], [sw - 1 - e, e], [e, sh - 1 - e], [sw - 1 - e, sh - 1 - e], [mx, e], [mx, sh - 1 - e], [e, my], [sw - 1 - e, my]]);
      peel(tol * 4.4 * 0.4); rebuildCut(); draw();
    }
    // pointer: a drag moves the picture, a tap is the wand
    var down = null;
    function pt(e) { var b = view.getBoundingClientRect(); return [(e.clientX - b.left) * VIEW / b.width, (e.clientY - b.top) * VIEW / b.height]; }
    view.addEventListener('pointerdown', function (e) { if (busy) return; view.setPointerCapture(e.pointerId); var p = pt(e); down = { x: p[0], y: p[1], px: px, py: py, moved: false }; e.preventDefault(); });
    view.addEventListener('pointermove', function (e) {
      if (!down) return; var p = pt(e), dx = p[0] - down.x, dy = p[1] - down.y;
      if (Math.abs(dx) + Math.abs(dy) > 6) down.moved = true;
      if (down.moved) { px = down.px + dx; py = down.py + dy; draw(); }
    });
    view.addEventListener('pointerup', function (e) {
      if (!down) return; var d0 = down; down = null;
      if (!d0.moved) { var p = pt(e), s = toSrc(p[0], p[1]); act([s]); }
    });
    view.addEventListener('pointercancel', function () { down = null; });
    function range(key, label, min, max, step, get, set) {
      var out = h('span', { class: 'small muted' });
      var inp = h('input', { type: 'range', class: 'range', 'data-k': key, min: String(min), max: String(max), step: String(step), value: String(get()),
        'aria-label': label, oninput: function (e) { set(parseFloat(e.target.value)); out.textContent = fmt(); draw(); } });
      function fmt() { var v = get(); return key === 'edrot' ? Math.round(v) + '°' : key === 'edzoom' ? '×' + v.toFixed(1) : Math.round(v); }
      out.textContent = fmt();
      return h('label', { class: 'edrow' }, h('span', null, label), inp, out);
    }
    function save() {
      if (!ready()) return; busy = true; status.textContent = t('ed_sending');
      var o = document.createElement('canvas'); o.width = OUT; o.height = OUT; var c = o.getContext('2d');
      c.beginPath(); c.arc(OUT / 2, OUT / 2, OUT / 2, 0, Math.PI * 2); c.clip();
      place(c, OUT / 2, OUT / 2, OUT / (R * 2)); c.drawImage(cut, 0, 0);
      o.toBlob(function (blob) {
        if (!blob) { busy = false; status.textContent = t('photo_fail'); return; }
        uploadBlob(blob, 'tok_' + tag + '.png', function (uploadId) {
          if (!uploadId) { busy = false; status.textContent = t('photo_fail'); return; }
          var before = (S.db.tokens[tag] || {}).image || '';
          send('TOKEN_SET_IMAGE', { tagId: tag, uploadId: uploadId });
          var tries = 0, tm = setInterval(function () {
            var now = (S.db.tokens[tag] || {}).image || '';
            if (now && now !== before) { clearInterval(tm); closeModal(); toast(t('saved')); charModal(sid); }
            else if (++tries > 60) { clearInterval(tm); busy = false; status.textContent = t('photo_fail'); }
          }, 250);
        });
      }, 'image/png');
    }
    var body = h('div', null,
      h('h3', null, t('ed_title')),
      h('div', { class: 'edwrap' }, view),
      status,
      h('div', { class: 'edtools' },
        h('button', { class: 'btn', 'data-k': 'edbg', onclick: removeBackground }, t('ed_bg')),
        h('button', { class: 'btn', 'data-k': 'edundo', onclick: function () { if (ready() && undo.length) { keep = undo.pop(); rebuildCut(); draw(); } } }, t('ed_undo')),
        h('button', { class: 'btn', 'data-k': 'edrot90', onclick: function () { if (!ready()) return; rot = (rot + 90) % 360; rotInp.querySelector('input').value = String(rot > 180 ? rot - 360 : rot); draw(); } }, '↻ 90°')),
      range('edtol', t('ed_tol'), 0, 100, 1, function () { return tol; }, function (v) { tol = v; }),
      (function () { rotInp = range('edrot', t('ed_rot'), -180, 180, 1, function () { return rot; }, function (v) { rot = v; }); return rotInp; })(),
      range('edzoom', t('ed_zoom'), 0.5, 4, 0.1, function () { return zoom; }, function (v) { zoom = v; }),
      h('div', { class: 'foot' },
        h('button', { class: 'btn', onclick: function () { closeModal(); charModal(sid); } }, t('cancel')),
        h('button', { class: 'btn', 'data-k': 'edreset', onclick: function () { if (!ready()) return; pushUndo(); keep.fill(1); rot = 0; zoom = 1; px = py = 0; rebuildCut(); draw(); } }, t('ed_reset')),
        h('button', { class: 'btn primary', 'data-k': 'edsave', onclick: save }, t('ed_save'))));
    var rotInp;
    openModal({ render: function () { return body; } });
    // read as a data: URL, not a blob: URL: the page's content security policy allows img-src 'self' data:
    var img = new Image(), rd = new FileReader();
    rd.onerror = function () { status.textContent = t('photo_bad'); };
    rd.onload = function () { img.src = rd.result; };
    img.onload = function () {
      var k = Math.min(1, SRC_MAX / Math.max(img.naturalWidth, img.naturalHeight));
      sw = Math.max(1, Math.round(img.naturalWidth * k)); sh = Math.max(1, Math.round(img.naturalHeight * k));
      src.width = cut.width = sw; src.height = cut.height = sh;
      src.getContext('2d').drawImage(img, 0, 0, sw, sh);
      keep = new Uint8Array(sw * sh); keep.fill(1);
      buildGrad(); rebuildCut(); draw();
      removeBackground();   // the usual case is done at once; the tools are there to adjust
    };
    img.onerror = function () { status.textContent = t('photo_bad'); };
    rd.readAsDataURL(file);
  }

