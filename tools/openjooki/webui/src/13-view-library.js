  // the tracks of `ids` whose title, artist or album contains `q`, by album then title
  function filterSortTracks(ids, q) {
    var c = collator(), qq = q.trim().toLowerCase();
    if (qq) ids = ids.filter(function (k) { var tr = S.db.tracks[k]; return [trackTitle(k), tr.artist, tr.album].join(' ').toLowerCase().indexOf(qq) >= 0; });
    return ids.sort(function (a, b) { var ta = S.db.tracks[a], tb = S.db.tracks[b]; return c.compare(ta.album || '', tb.album || '') || c.compare(trackTitle(a), trackTitle(b)); });
  }
  // a track row with its checkbox (the library, "From the library"): tapping the row toggles it too.
  // o: checked, set(v), title, track (data-track), inner (under the title), after (end of the row)
  function trackCheckRow(k, o) {
    var tr = S.db.tracks[k];
    return h('li', { class: 'clickable', 'data-track': o.track, onclick: function (e) { if (e.target.tagName !== 'INPUT') o.set(!o.checked); } },
      h('input', { type: 'checkbox', class: 'check', checked: o.checked, 'aria-label': trackTitle(k), onchange: function (e) { o.set(e.target.checked); } }),
      h('div', { class: 'grow' }, h('div', { class: 'title ellipsis' }, o.title), h('div', { class: 'sub ellipsis' }, trackSub(tr)), o.inner),
      o.after);
  }
  function libraryPickerModal(p) {
    var q = '', sel = {};
    var inPl = {};
    arr(p.tracks).forEach(function (x) { inPl[x] = true; });
    function ids() { return filterSortTracks(Object.keys(S.db.tracks).filter(function (k) { return !S.db.tracks[k].isUrl; }), q); }
    function count() { return Object.keys(sel).filter(function (k) { return sel[k] && S.db.tracks[k]; }).length; }
    openModal({
      autofocus: 'libq',
      render: function () {
        var list = ids();
        return [h('h3', null, t('from_library') + ' → ' + (p.title || '')),
          h('div', { class: 'search' }, icon('search'), h('input', { class: 'input', 'data-k': 'libq', placeholder: t('search'), value: q,
            oninput: function (e) { q = e.target.value; renderModal(); } })),
          list.length ? h('ul', { class: 'list card', style: 'max-height:50vh;overflow:auto;box-shadow:none;border:1px solid var(--line)' }, list.map(function (k) {
            return trackCheckRow(k, { checked: !!sel[k], set: function (v) { sel[k] = v; renderModal(); }, title: trackTitle(k),
              after: inPl[k] ? h('span', { class: 'badge' }, t('already_in')) : null });
          })) : h('div', { class: 'empty' }, t('library_empty')),
          modalFoot(count() ? t('add_n', count()) : t('add'), function () {
            var chosen = Object.keys(sel).filter(function (k) { return sel[k] && S.db.tracks[k]; });
            var cur = pls()[p.id] ? arr(pls()[p.id].tracks) : [];
            var nt = cur.concat(chosen);
            send('PLAYLIST_UPDATE', { playlist: { id: p.id, tracks: nt } });
            closeModal(); toast(t('added', chosen.length));
          }, { k: 'libadd', disabled: !count() })];
      }
    });
  }

  function radioModal(p) {
    var name = '', url = '', err = '';
    function ok() {
      var u = url.trim();
      if (!/^https?:\/\/[\w\[]/i.test(u)) { err = t('radio_url_bad'); renderModal(); return; }
      send('PLAYLIST_ADD_STREAM', { playlistId: p.id, title: name.trim() || u, url: u });
      closeModal();
    }
    openModal({
      autofocus: 'rname',
      render: function () {
        return [h('h3', null, t('radio_title')),
          field(t('radio_name'), { 'data-k': 'rname', value: name, maxlength: '100', oninput: function (e) { name = e.target.value; } }),
          field(t('radio_url'), { 'data-k': 'rurl', type: 'url', inputmode: 'url', value: url, placeholder: 'https://',
            oninput: function (e) { url = e.target.value; }, onkeydown: function (e) { if (e.key === 'Enter') ok(); } }),
          err ? h('div', { class: 'banner danger' }, err) : null,
          modalFoot(t('add'), ok)];
      }
    });
  }

  function viewLibrary(tab) {
    tab = tab === 'unused' ? 'unused' : 'all';
    var un = unusedIds();
    var unSet = {}; un.forEach(function (x) { unSet[x] = true; });
    var where = {};
    userPlaylists().forEach(function (p) { arr(p.tracks).forEach(function (x) { (where[x] = where[x] || []).push(p.title || '—'); }); });
    var all = filterSortTracks(Object.keys(S.db.tracks).filter(function (k) { return tab === 'all' || unSet[k]; }), ui.search);
    Object.keys(ui.sel).forEach(function (k) { if (all.indexOf(k) < 0) delete ui.sel[k]; });
    var chosen = all.filter(function (k) { return ui.sel[k]; });
    var nAll = Object.keys(S.db.tracks).length;
    var allChosen = all.length > 0 && chosen.length === all.length;
    return [
      h('div', { class: 'tabs', role: 'tablist' },
        h('button', { class: tab === 'all' ? 'on' : '', role: 'tab', 'aria-selected': String(tab === 'all'), onclick: function () { go('#/library'); } }, t('all') + ' (' + nAll + ')'),
        h('button', { class: tab === 'unused' ? 'on' : '', role: 'tab', 'aria-selected': String(tab === 'unused'), onclick: function () { go('#/library/unused'); } }, t('unused') + ' (' + un.length + ')')),
      h('div', { class: 'actions' }, fileButton(t('add_files'), null, false),
        // select / deselect every track currently listed (this tab, after the search filter)
        all.length ? h('button', { class: 'btn', 'data-k': 'selall', 'aria-pressed': String(allChosen), onclick: function () {
          all.forEach(function (k) { ui.sel[k] = !allChosen; }); render();
        } }, allChosen ? t('select_none') : t('select_all')) : null),
      uploadsBlock(null),
      h('div', { class: 'search' }, icon('search'), h('input', { class: 'input', 'data-k': 'libsearch', placeholder: t('search'), value: ui.search,
        oninput: function (e) { ui.search = e.target.value; render(); } })),
      all.length ? h('ul', { class: 'card list' }, all.map(function (k) {
        var tr = S.db.tracks[k];
        var w = where[k];
        return trackCheckRow(k, { track: k, checked: !!ui.sel[k], set: function (v) { ui.sel[k] = v; render(); }, title: (tr.isUrl ? '📻 ' : '') + trackTitle(k),
          inner: h('div', { class: 'sub ellipsis' }, w ? t('in_playlists') + w.join(', ') : t('in_none')) });
      })) : h('div', { class: 'card empty' }, tab === 'unused' ? t('unused_empty') : t('library_empty')),
      chosen.length ? h('div', { class: 'card selbar' },
        h('span', { class: 'grow small' }, t('selected', chosen.length)),
        h('button', { class: 'btn primary', onclick: function () { addToPlaylistModal(chosen); } }, t('add_to')),
        tab === 'unused' ? h('button', { class: 'btn danger', onclick: function () {
          confirmBox(t('delete_forever_q', chosen.length), t('delete_forever_text'), t('delete'), true).then(function (ok) {
            if (!ok) return;
            var keep = unusedIds().filter(function (x) { return chosen.indexOf(x) < 0; });
            send('PLAYLIST_UPDATE', { playlist: { id: 'TRASH', tracks: keep } });
            ui.sel = {}; toast(t('deleted'));
          });
        } }, icon('trash'), t('delete_forever')) : null) : null
    ];
  }

  function addToPlaylistModal(ids) {
    var list = userPlaylists();
    openModal({
      render: function () {
        return [h('h3', null, t('choose_playlist')),
          h('ul', { class: 'list card', style: 'box-shadow:none;border:1px solid var(--line)' },
            list.map(function (p) {
              return h('li', { class: 'clickable', 'data-pl': p.id, onclick: function () {
                var cur = arr(pls()[p.id] && pls()[p.id].tracks);
                send('PLAYLIST_UPDATE', { playlist: { id: p.id, tracks: cur.concat(ids) } });
                ui.sel = {}; closeModal(); toast(t('added', ids.length)); render();
              } }, tokVisual(p.star, 'xs'), h('div', { class: 'grow' }, h('div', { class: 'title' }, p.title || '—'), h('div', { class: 'sub' }, t('n_tracks', arr(p.tracks).length))));
            }),
            h('li', { class: 'clickable', onclick: function () { closeModal(); newPlaylistModal(ids); ui.sel = {}; } },
              h('div', { class: 'tok xs none' }, icon('plus')), h('div', { class: 'grow title' }, t('new_playlist')))),
          h('div', { class: 'foot' }, h('button', { class: 'btn', onclick: closeModal }, t('cancel')))];
      }
    });
  }

