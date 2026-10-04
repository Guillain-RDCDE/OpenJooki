  var nameDraft = {};
  var tokq = '';   // the Tokens screen's search box
  function normTxt(s) { return String(s || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, ''); }
  // characters with a known token (grouped by character), plus those that only have a playlist
  function tokenGroups() {
    var groups = {};
    Object.keys(S.db.tokens).forEach(function (tag) {
      var tk = S.db.tokens[tag];
      if (!tk || !isUserChar(tk.starId)) return;
      (groups[tk.starId] = groups[tk.starId] || []).push(tag);
    });
    var ids = Object.keys(groups).sort(function (a, b) { return charInfo(a).order - charInfo(b).order; });
    var linkedOnly = userPlaylists().filter(function (p) { return p.star && !groups[p.star]; }).map(function (p) { return p.star; });
    return { groups: groups, ids: ids, linkedOnly: linkedOnly };
  }
  // the details of one character (or foreign tag): its playlist, its physical tokens and their names
  function charModal(sid) {
    var foreign = !!foreignUid(sid), own = !!ownUid(sid);
    openModal({
      live: true,
      sig: function () {
        var g = tokenGroups(); var p = playlistOfChar(sid);
        return JSON.stringify([g.groups[sid], p && p.id, S.nfc.tagId, (g.groups[sid] || []).map(function (tag) { return (S.db.tokens[tag] || {}).image || ''; })]);
      },
      render: function () {
        var p = playlistOfChar(sid);
        var tags = (tokenGroups().groups[sid] || []).sort();
        var sel = h('select', { class: 'input', 'aria-label': t('launches') + ' — ' + charName(sid), 'data-char-select': sid, onchange: function (e) {
          var v = e.target.value;
          e.target.blur();
          if (!v) { if (p) send('PLAYLIST_UPDATE', { playlist: { id: p.id, star: false } }); return; }
          var pl = pls()[v]; var other = pl && pl.star && pl.star !== sid ? pl.star : null;
          if (!other) { send('PLAYLIST_UPDATE', { playlist: { id: v, star: sid } }); return; }
          // that playlist is already started by another character: say so before taking it
          confirmBox(t('launches'), t('pl_taken', pl.title || '—', charName(other)), t('save')).then(function (ok) {
            if (ok) send('PLAYLIST_UPDATE', { playlist: { id: v, star: sid } });
            charModal(sid);   // the question replaced the sheet: back to it either way
          });
        } }, h('option', { value: '' }, t('none_dash')), userPlaylists().map(function (x) { return h('option', { value: x.id, selected: p && p.id === x.id ? 'selected' : null }, x.title || '—'); }));
        if (p) sel.value = p.id; else sel.value = '';
        return [
          h('div', { class: 'row', style: 'margin-bottom:8px' }, tokVisual(sid, '', S.nfc.starId === sid),
            h('div', { class: 'grow' }, h('h3', { style: 'margin:0' }, charName(sid)),
              h('div', { class: 'small muted' }, tags.length ? t('n_tokens', tags.length) : t('no_token')))),
          h('p', { class: 'small muted' }, foreign ? t('foreign_hint') : own ? t('own_hint')
            : sid === 'Jooki.Flat' || sid === 'Jooki.ThankYou' ? t('flat_shared_hint') : t('tokens_intro')),
          h('label', { class: 'field' }, h('span', null, t('launches')), sel),
          tags.map(function (tag, i) {
            var tk = S.db.tokens[tag] || {};
            var live = S.nfc.tagId === tag;
            var key = 'name-' + tag;
            var val = nameDraft[tag] !== undefined ? nameDraft[tag] : (tk.name || '');
            function commit() {
              if (rendering || modalRendering || nameDraft[tag] === undefined) return;
              var v = nameDraft[tag].trim();
              delete nameDraft[tag];
              if (v !== (tk.name || '')) { send('TOKEN_EDIT', { tagId: tag, name: v }); toast(t('saved')); }
            }
            // a token of its own (tag, flat token) is its own character: its name IS the card's title, so the field says so
            return h('div', { class: 'physical', 'data-tag': tag },
              h('span', { class: 'badge' + (live ? ' accent' : '') }, live ? t('on_jooki') : own ? t(OWN[ownParts(sid).kind]) : t('token_n', i + 1)),
              h('input', { class: 'input grow', 'data-k': key, value: val, maxlength: '60', placeholder: own ? t('tag_name_ph') : t('token_name_ph'), 'aria-label': own ? t('tag_name_ph') : t('token_n', i + 1),
                oninput: function (e) { nameDraft[tag] = e.target.value; },
                onblur: commit, onkeydown: function (e) { if (e.key === 'Enter') { e.target.blur(); } } }),
              h('button', { class: 'icon-btn', 'aria-label': t('forget'), title: t('forget'), onclick: function () {
                confirmBox(t('forget_q'), t('forget_text'), t('forget'), true).then(function (ok) { if (ok) send('TOKEN_DELETE', { tagId: tag }); });
              } }, icon('x')));
          }),
          // a token of its own carries a picture: one of the library, or a photo (taken now, from the gallery or a computer)
          own && tags.length ? h('div', { class: 'picrow' },
            h('button', { class: 'btn primary', 'data-k': 'libpick', onclick: function () { libraryPicker(sid, tags[0]); } }, icon('sparkle'), t('lib_pick')),
            h('label', { class: 'btn', style: 'cursor:pointer' }, icon('camera'), t('photo_btn'),
              h('input', { type: 'file', accept: 'image/*', 'data-k': 'photo', style: 'display:none', onchange: function (e) {
                var f = e.target.files && e.target.files[0]; if (!f) return;
                closeModal(); tokenImageEditor(tags[0], f, sid);
              } }))) : null,
          own && tags.length && (S.db.tokens[tags[0]] || {}).image ? h('button', { class: 'btn ghost', 'data-k': 'photo-remove', style: 'color:var(--danger)',
            onclick: function () { send('TOKEN_EDIT', { tagId: tags[0], image: false }); } }, t('photo_remove')) : null,
          h('div', { class: 'foot' }, h('button', { class: 'btn primary', 'data-k': 'charclose', onclick: closeModal }, t('close')))
        ];
      }
    });
  }
  // the Tokens screen: the visuals only, searched by name; the details open on a tap
  function viewTokens() {
    var g = tokenGroups();
    var all = g.ids.concat(g.linkedOnly);
    var q = normTxt(tokq.trim());
    function matches(sid) {
      if (!q) return true;
      var p = playlistOfChar(sid);
      var names = [charName(sid), p && p.title].concat((g.groups[sid] || []).map(function (tag) { return (S.db.tokens[tag] || {}).name; }));
      return names.some(function (n) { return n && normTxt(n).indexOf(q) >= 0; });
    }
    var shown = all.filter(matches);
    function tile(sid) {
      var p = playlistOfChar(sid);
      var known = !!g.groups[sid];
      return h('button', { class: 'charopt' + (known ? '' : ' nojeton'), 'data-char': sid, onclick: function () { charModal(sid); } },
        tokVisual(sid, '', S.nfc.starId === sid),
        h('div', { class: 'title' }, charName(sid)),
        h('div', { class: 'sub' }, p ? (p.title || '—') : t('none_dash')));
    }
    return [
      all.length ? h('div', { class: 'search' }, icon('search'), h('input', { class: 'input', 'data-k': 'tokq', placeholder: t('tok_search_ph'), value: tokq,
        oninput: function (e) { tokq = e.target.value; render(); } })) : null,
      !all.length ? h('div', { class: 'card empty' }, h('div', { class: 'big' }, '🐉'), t('no_tokens'))
        : !shown.length ? h('div', { class: 'card empty' }, t('tok_no_match'))
        : h('div', { class: 'chargrid' }, shown.map(tile)),
      h('p', { class: 'small muted', style: 'text-align:center' }, t('tokens_hint')),
      g.ids.some(foreignUid) ? h('p', { class: 'small muted', style: 'text-align:center' }, t('foreign_hint')) : null
    ];
  }

