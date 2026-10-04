  /* ------------------------------------------------------------------ the picture library */
  // Ready-made pictures for the tokens of their own (docs/23 §5): Fluent Emoji 3D (Microsoft, MIT,
  // tokimg/LICENSE.txt), 128 px WebP shipped with the page, so it works without Internet.
  // tokimg/index.json = { cats: [[id, {fr, en, nl}, iconId]], img: [[id, cat, fr, en, nl, "search words"]] }.
  // The grid is filled here, not by renderModal: typing in the search keeps the field and the scroll.
  var libIdx = null, libWait = null;
  function loadLibIndex(cb) {
    if (libIdx) return cb(libIdx);
    if (libWait) { libWait.push(cb); return; }
    libWait = [cb];
    getText('/tokimg/index.json', function (txt) {
      var d = null; try { d = JSON.parse(txt); } catch (e) {}
      if (d && Array.isArray(d.img) && Array.isArray(d.cats)) libIdx = d;
      var w = libWait; libWait = null; w.forEach(function (f) { f(libIdx); });
    });
  }
  function libName(r) { return (lang === 'en' ? r[3] : lang === 'nl' ? r[4] : r[2]) || r[2]; }
  function libraryPicker(sid, tag) {
    var q = '', failed = false, chips = {}, picked = false;
    var body = h('div', { class: 'libbody', 'data-k': 'libgrid' });
    var cats = h('div', { class: 'libcats', role: 'tablist' });
    var input = h('input', { class: 'input', type: 'search', 'data-k': 'imgq', placeholder: t('lib_search_ph'), autocomplete: 'off', 'aria-label': t('lib_search_ph'),
      oninput: function (e) { q = e.target.value; fill(); body.scrollTop = 0; } });
    function pick(r) {
      var tk = S.db.tokens[tag] || {}, p = { tagId: tag, image: 'lib:' + r[0] };
      if (!tk.name) p.name = libName(r);   // an unnamed token takes the picture's name; it can be changed
      send('TOKEN_EDIT', p);
      picked = true; closeModal(); toast(t('lib_set', libName(r))); charModal(sid);
    }
    function cell(r) {
      return h('button', { class: 'libcell', 'data-img': r[0], title: libName(r), onclick: function () { pick(r); } },
        h('img', { src: '/tokimg/' + r[0] + '.webp', alt: '', loading: 'lazy', decoding: 'async' }), h('span', null, libName(r)));
    }
    function fill() {
      body.innerHTML = '';
      if (!libIdx) { body.appendChild(h('p', { class: 'small muted libempty' }, failed ? t('lib_fail') : t('lib_loading'))); return; }
      var nq = normTxt(q.trim());
      if (nq) {
        var hits = libIdx.img.filter(function (r) { return (' ' + r[5]).indexOf(' ' + nq) >= 0 || normTxt(libName(r)).indexOf(nq) >= 0; });
        hits.sort(function (a, b) { return (normTxt(libName(a)).indexOf(nq) === 0 ? 0 : 1) - (normTxt(libName(b)).indexOf(nq) === 0 ? 0 : 1); });
        if (!hits.length) { body.appendChild(h('p', { class: 'small muted libempty' }, t('lib_none', q.trim()))); return; }
        body.appendChild(h('div', { class: 'libsec' }, t('lib_n', hits.length)));
        body.appendChild(h('div', { class: 'libgrid' }, hits.map(cell)));
        return;
      }
      libIdx.cats.forEach(function (c) {
        body.appendChild(h('div', { class: 'libsec', 'data-cat': c[0] }, c[1][lang] || c[1].fr));
        body.appendChild(h('div', { class: 'libgrid' }, libIdx.img.filter(function (r) { return r[1] === c[0]; }).map(cell)));
      });
    }
    function spy() {
      if (q.trim() || !libIdx) return;
      var cur = libIdx.cats[0][0];
      Array.prototype.forEach.call(body.querySelectorAll('[data-cat]'), function (s) { if (s.offsetTop - 12 <= body.scrollTop) cur = s.getAttribute('data-cat'); });
      Object.keys(chips).forEach(function (k) { chips[k].classList.toggle('on', k === cur); });
    }
    body.addEventListener('scroll', spy, { passive: true });
    function buildCats() {
      cats.innerHTML = '';
      (libIdx ? libIdx.cats : []).forEach(function (c, i) {
        var name = c[1][lang] || c[1].fr;
        chips[c[0]] = h('button', { class: i ? '' : 'on', title: name, 'aria-label': name, 'data-libcat': c[0], onclick: function () {
          q = ''; input.value = ''; fill();
          var s = body.querySelector('[data-cat="' + c[0] + '"]'); if (s) body.scrollTop = s.offsetTop;
          spy();
        } }, h('img', { src: '/tokimg/' + c[2] + '.webp', alt: '' }));
        cats.appendChild(chips[c[0]]);
      });
    }
    var head = h('div', { class: 'libhead' },
      h('div', { class: 'row' }, h('h3', { class: 'grow', style: 'margin:0' }, t('lib_pick')),
        h('button', { class: 'btn ghost', 'data-k': 'libcancel', onclick: function () { closeModal(); } }, t('cancel'))),
      h('div', { class: 'search' }, icon('search'), input), cats);
    openModal({ cls: 'libsheet', autofocus: null, onclose: function () { if (!picked) charModal(sid); },
      render: function () { return [head, body]; } });
    fill();
    loadLibIndex(function (d) { failed = !d; buildCats(); fill(); });
  }

