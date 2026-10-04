  /* sort a playlist by one criterion; web radios keep their relative order at the end */
  var SORT_KEYS = ['name', 'title', 'artist', 'album', 'duration'];
  function fileName(tr) {
    var f = tr.userFilename || String(tr.filename || '').split('/').pop();
    return cleanTitle(f || tr.title || '');
  }
  function sortedTracks(list, by, desc) {
    var c = collator();
    function txt(id, k) {
      var tr = S.db.tracks[id] || {};
      if (k === 'name') return fileName(tr);
      if (k === 'title') return trackTitle(id);
      var v = tr[k]; return v && v !== 'unknown' ? String(v) : '';
    }
    function cmp(a, b) {
      var r;
      if (by === 'duration') r = (Number((S.db.tracks[a] || {}).duration) || 0) - (Number((S.db.tracks[b] || {}).duration) || 0);
      else r = c.compare(txt(a, by), txt(b, by));
      if (r === 0 && by !== 'title') r = c.compare(trackTitle(a), trackTitle(b));
      return r || (a < b ? -1 : a > b ? 1 : 0);
    }
    var files = list.filter(function (x) { return !(S.db.tracks[x] || {}).isUrl; }).sort(cmp);
    if (desc) files.reverse();
    return files.concat(list.filter(function (x) { return (S.db.tracks[x] || {}).isUrl; }));
  }
  function sortModal(p) {
    var by = 'name', desc = false;
    var cur = arr(p.tracks);
    function result() { return sortedTracks(cur, by, desc); }
    function apply() {
      var nt = result();
      closeModal();
      if (nt.join('|') === cur.join('|')) { toast(t('sort_same')); return; }
      optimisticTracks(p.id, nt);
      send('PLAYLIST_UPDATE', { playlist: { id: p.id, tracks: nt } });
      toast(t('sorted'));
    }
    openModal({
      autofocus: 'sortok',
      render: function () {
        var nt = result(), same = nt.join('|') === cur.join('|');
        var shown = nt.slice(0, 8);
        return [h('h3', null, t('sort_title')),
          h('div', { class: 'sortopts', role: 'group', 'aria-label': t('sort_title') }, SORT_KEYS.map(function (k) {
            var on = by === k;
            return h('button', { class: 'btn' + (on ? ' on' : ''), 'data-k': 'sortby-' + k, 'aria-pressed': String(on), onclick: function () {
              if (on) desc = !desc; else { by = k; desc = false; }
              renderModal();
            } }, h('span', { class: 'grow' }, t('sort_by_' + k)), h('span', { 'aria-hidden': 'true' }, on ? (desc ? '↓' : '↑') : ''));
          })),
          h('p', { class: 'small muted' }, t('sort_again')),
          h('div', { class: 'small muted', style: 'margin-top:10px' }, t('sort_preview')),
          h('ol', { class: 'sortpreview' }, shown.map(function (id) { var tr = S.db.tracks[id] || {}; return h('li', { class: 'ellipsis' }, (by === 'name' ? fileName(tr) : trackTitle(id)) + (by === 'duration' && tr.duration ? ' · ' + fmtTime(tr.duration) : '')); }),
            nt.length > shown.length ? h('li', { class: 'muted' }, '… +' + (nt.length - shown.length)) : null),
          modalFoot(same ? t('sort_same') : t('sort_apply'), apply, { k: 'sortok', disabled: same ? 'disabled' : null })];
      }
    });
  }

