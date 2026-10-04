  /* ------------------------------------------------------------------ views */
  function viewPlaylists() {
    var list = userPlaylists();
    var np = S.audio.nowPlaying;
    var un = unusedIds().length;
    var cards = list.map(function (p) {
      var n = arr(p.tracks).length;
      var total = plDuration(p.tracks);
      var card = h('div', { class: 'card pl' + (np.playlistId === p.id ? ' active' : ''), role: 'link', tabindex: '0', 'data-pl': p.id,
        onclick: function () { go('#/p/' + encodeURIComponent(p.id)); },
        onkeydown: function (e) { if (e.key === 'Enter') go('#/p/' + encodeURIComponent(p.id)); } },
        h('div', { class: 'ph' }, tokVisual(p.star, 'sm', S.nfc.starId && S.nfc.starId === p.star)),
        h('div', { class: 'name' }, p.title || '—'),
        h('div', { class: 'meta' }, p.spotify ? t('sp_playlist') : t('n_tracks', n) + (total ? ' · ' + fmtTotal(total) : '') + (p.audiobook ? ' · ' + t('audiobook') : '')),
        n || p.spotify ? h('button', { class: 'icon-btn accent play', 'aria-label': t('play') + ' ' + (p.title || ''), onclick: function (e) {
          e.stopPropagation(); send('PLAYLIST_PLAY', { playlistId: p.id }); } }, icon('play')) : null);
      return card;
    });
    cards.push(h('button', { class: 'card pl newpl', onclick: newPlaylistModal, 'data-k': 'newpl' }, icon('plus'), t('new_playlist')));
    var addDisc = discButton();
    return [
      updateAvailable() && upd.state === 'checked' ? h('div', { class: 'banner row', 'data-k': 'updbanner' }, h('span', { class: 'grow' }, t('upd_banner', upd.latest)),
        h('a', { href: '#/settings/update' }, t('upd_see'))) : null,
      un ? h('div', { class: 'banner row' }, h('span', { class: 'grow' }, t('unused_banner', un)),
        h('a', { href: '#/library/unused' }, t('see'))) : null,
      list.length ? null : h('div', { class: 'empty' }, h('div', { class: 'big' }, '🎵'), t('no_playlists')),
      h('div', { class: 'plgrid' }, cards),
      discsBlock(),
      addDisc ? h('div', { class: 'actions', style: 'margin-top:14px' }, addDisc) : null,
      discDrop()
    ];
  }

  function newPlaylistModal(prefillTracks) {
    var name = '';
    function create() {
      var v = name.trim();
      if (!v) return;
      closeModal();
      whenNewPlaylist(notTrash).then(function (fresh) {
        if (Array.isArray(prefillTracks) && prefillTracks.length) {
          send('PLAYLIST_UPDATE', { playlist: { id: fresh, tracks: prefillTracks } });
          toast(t('added', prefillTracks.length));
        } else go('#/p/' + encodeURIComponent(fresh));
      });
      send('PLAYLIST_NEW', { title: v, audiobook: false });
    }
    openModal({
      autofocus: 'plname',
      render: function () {
        return [h('h3', null, t('new_playlist')),
          field(t('name'), { 'data-k': 'plname', maxlength: '100', placeholder: t('playlist_name_ph'), value: name,
              oninput: function (e) { name = e.target.value; var b = document.querySelector('[data-k="plcreate"]'); if (b) b.disabled = !name.trim(); },
              onkeydown: function (e) { if (e.key === 'Enter') create(); } }),
          modalFoot(t('create'), create, { k: 'plcreate', disabled: !name.trim() })];
      }
    });
  }

  // the grid of characters to pick from (the ones seen on this Jooki first); `none` adds "no token"
  function charGrid(chosen, selfId, pick, none) {
    var seen = {};
    Object.keys(S.db.tokens).forEach(function (k) { var s = S.db.tokens[k] && S.db.tokens[k].starId; if (isUserChar(s)) seen[s] = true; });
    function opt(id) {
      var other = id ? playlistOfChar(id) : null;
      if (other && other.id === selfId) other = null;
      return h('button', { class: 'charopt' + (chosen === id ? ' sel' : ''), 'data-char': id || 'none', 'aria-pressed': chosen === id ? 'true' : 'false',
        onclick: function () { pick(id); renderModal(); } },
        tokVisual(id, 'sm'), h('div', null, id ? charName(id) : t('no_token')), other ? h('div', { class: 'taken' }, t('used_by', other.title || '—')) : null);
    }
    var ids = CHARS.map(function (c) { return c[0]; }).filter(function (id) { return id !== 'Jooki.ThankYou'; });
    Object.keys(seen).forEach(function (s) { if (ids.indexOf(s) < 0) ids.push(s); });
    ids.sort(function (a, b) { return (seen[b] ? 1 : 0) - (seen[a] ? 1 : 0) || charInfo(a).order - charInfo(b).order; });
    return h('div', { class: 'chargrid' }, none ? opt(null) : null, ids.map(opt));
  }
  function charPickerModal(p) {
    var chosen = p.star || null;
    openModal({
      render: function () {
        var other = chosen ? playlistOfChar(chosen) : null;
        if (other && other.id === p.id) other = null;
        return [h('h3', null, t('token_for')), h('p', { class: 'small muted' }, t('token_help')),
          charGrid(chosen, p.id, function (id) { chosen = id; }, true),
          other ? h('div', { class: 'banner', style: 'margin-top:12px' }, t('token_moved', other.title || '—')) : null,
          modalFoot(t('save'), function () {
            if ((chosen || null) !== (p.star || null)) send('PLAYLIST_UPDATE', { playlist: { id: p.id, star: chosen || false } });
            closeModal();
          }, { k: 'charsave' })];
      }
    });
  }

  // What Spotify plays on the Jooki, put on a character (1.x "preset", the Muuselabs app had it):
  // the Jooki asks Spotify for a preset of what plays, the core stores it in a new playlist.
  function spotifySaveModal() {
    var np = S.audio.nowPlaying;
    var name = cleanTitle(np.source || np.track || '') || 'Spotify', chosen = null, saving = false;
    function save() {
      var v = name.trim();
      if (!v || !chosen || saving) return;
      saving = true; renderModal();
      var star = chosen, over = false;
      var wait = whenNewPlaylist(function (k) { return pls()[k] && pls()[k].spotify; }, 20000);
      wait.then(function (fresh) {
        over = true; closeModal();
        toast(t('sp_saved', charName(star), pls()[fresh].title || v));
        go('#/p/' + encodeURIComponent(fresh));
      }, function () { over = true; saving = false; renderModal(); toast(t('sp_timeout'), 'error'); });
      // an error answer (Spotify paused meanwhile) comes as the usual toast; let the parent try again
      onCmdError = function () { if (over) return; over = true; wait.cancel(); saving = false; renderModal(); };
      send('PLAYLIST_NEW_SPOTIFY', { title: v, star: star });
    }
    openModal({
      autofocus: 'spname',
      render: function () {
        var other = chosen ? playlistOfChar(chosen) : null;
        return [h('h3', null, t('sp_save_title')), h('p', { class: 'small muted' }, t('sp_save_help')),
          field(t('name'), { 'data-k': 'spname', maxlength: '100', value: name,
              oninput: function (e) { name = e.target.value; var b = document.querySelector('[data-k="spsaveok"]'); if (b) b.disabled = !name.trim() || !chosen; } }),
          h('div', { class: 'small muted', style: 'margin:12px 0 6px' }, t('sp_pick_char')),
          charGrid(chosen, null, function (id) { chosen = id; }, false),
          other ? h('div', { class: 'banner', style: 'margin-top:12px' }, t('token_moved', other.title || '—')) : null,
          modalFoot(saving ? t('sp_saving') : t('save'), save, { k: 'spsaveok', disabled: saving || !name.trim() || !chosen })];
      }
    });
  }

  // "Delete playlist": asks, then the tracks go to Unused and the page goes home
  function deletePlaylistBtn(p, id) {
    return h('div', { class: 'actions' }, h('button', { class: 'btn danger', onclick: function () {
      confirmBox(t('delete_playlist_q', p.title || '—'), t('delete_playlist_text'), t('delete'), true).then(function (ok) {
        if (!ok) return;
        send('PLAYLIST_DELETE', { playlistId: id });
        go('#/');
      });
    } }, icon('trash'), t('delete_playlist')));
  }
  function viewPlaylist(id) {
    if (id === 'TRASH') { setTimeout(function () { go('#/library/unused'); }, 0); return []; }
    var p = pls()[id];
    if (!p) return h('div', { class: 'empty' }, h('p', null, t('playlist_missing')), h('a', { class: 'btn', href: '#/' }, t('back')));
    p = Object.assign({ id: id }, p);
    var tracks = arr(p.tracks);
    var np = S.audio.nowPlaying;
    var total = plDuration(tracks);
    var editing = ui.editTitle !== null;
    function saveTitle() {
      var v = (ui.editTitle || '').trim();
      if (!v) { toast(t('err_empty_title'), 'error'); return; }
      if (v !== p.title) send('PLAYLIST_UPDATE', { playlist: { id: id, title: v } });
      ui.editTitle = null; render();
    }
    var head = h('div', { class: 'card plhead' },
      h('button', { class: 'tokbtn', 'aria-label': t('choose_token'), onclick: function () { charPickerModal(p); }, 'data-k': 'tokbtn' },
        tokVisual(p.star, '', S.nfc.starId && S.nfc.starId === p.star)),
      h('div', { class: 'grow' },
        editing ? h('div', { class: 'edit-title' },
          h('input', { class: 'input', 'data-k': 'title', maxlength: '100', value: ui.editTitle, 'aria-label': t('name'),
            oninput: function (e) { ui.editTitle = e.target.value; },
            onkeydown: function (e) { if (e.key === 'Enter') saveTitle(); if (e.key === 'Escape') { e.stopPropagation(); ui.editTitle = null; render(); } } }),
          h('button', { class: 'icon-btn', 'aria-label': t('save'), onclick: saveTitle }, icon('check')),
          h('button', { class: 'icon-btn', 'aria-label': t('cancel'), onclick: function () { ui.editTitle = null; render(); } }, icon('x')))
          : h('h2', { class: 'row' }, h('span', { class: 'grow' }, p.title || '—'),
            h('button', { class: 'icon-btn', 'aria-label': t('rename'), 'data-k': 'renamebtn', onclick: function () { ui.editTitle = p.title || ''; render(); setTimeout(function () {
              var el = document.querySelector('[data-k="title"]'); if (el) { el.focus(); el.select(); } }, 0); } }, icon('edit'))),
        h('div', { class: 'small muted' }, (p.star ? charName(p.star) : t('no_token')) + ' · ' + (p.spotify ? t('sp_playlist') : t('n_tracks', tracks.length) + (total ? ' · ' + fmtTotal(total) : '')))));
    if (p.spotify) {
      // a Spotify preset: it plays from Spotify, there is nothing of ours to add or sort
      return [head, h('div', { class: 'actions' },
          h('button', { class: 'btn primary', 'data-k': 'spplay', onclick: function () { send('PLAYLIST_PLAY', { playlistId: id }); } }, icon('play'), t('play'))),
        h('div', { class: 'card empty', 'data-k': 'sphelp' }, h('div', { class: 'big' }, '🎧'), h('div', null, t('sp_playlist')), h('div', { class: 'small' }, t('sp_playlist_help'))),
        deletePlaylistBtn(p, id)];
    }
    var actions = h('div', { class: 'actions' },
      tracks.length ? h('button', { class: 'btn primary', onclick: function () { send('PLAYLIST_PLAY', { playlistId: id }); } }, icon('play'), t('play')) : null,
      fileButton(t('add_files'), id, !tracks.length),
      h('button', { class: 'btn', onclick: function () { libraryPickerModal(p); } }, icon('lib'), t('from_library')),
      h('button', { class: 'btn', onclick: function () { radioModal(p); } }, icon('radio'), t('web_radio')),
      tracks.length > 1 ? h('button', { class: 'btn', 'data-k': 'sortbtn', onclick: function () { sortModal(p); } }, icon('sort'), t('sort')) : null);
    var list;
    if (!tracks.length) {
      list = h('div', { class: 'card empty' }, h('div', { class: 'big' }, '🎶'), h('div', null, t('empty_playlist')), h('div', { class: 'small' }, t('empty_playlist_hint')));
    } else {
      list = h('ul', { class: 'card list', 'data-list': 'tracks' }, tracks.map(function (tid, i) {
        var tr = S.db.tracks[tid];
        var playing = np.playlistId === id && np.trackIndex === i + 1;
        return h('li', { class: 'clickable' + (playing ? ' playing' : ''), 'data-i': i, 'data-track': tid,
          onclick: function (e) { if (e.target.closest('button,.handle')) return; send('PLAYLIST_PLAY', { playlistId: id, trackIndex: i + 1 }); } },
          h('span', { class: 'handle', 'aria-hidden': 'true', onpointerdown: function (e) { startDrag(e, id); } }, icon('grip')),
          h('span', { class: 'num' }, playing ? '♪' : String(i + 1)),
          h('div', { class: 'grow' }, h('div', { class: 'title ellipsis' }, trackTitle(tid)), h('div', { class: 'sub ellipsis' }, trackSub(tr))),
          h('button', { class: 'icon-btn', 'aria-label': t('removed_from') + t('colon') + trackTitle(tid), 'data-remove': i, onclick: function () {
            var old = tracks.slice();
            var nt = tracks.slice(); nt.splice(i, 1);
            optimisticTracks(id, nt);
            send('PLAYLIST_UPDATE', { playlist: { id: id, tracks: nt } });
            toast(t('removed_from'), null, { label: t('undo'), fn: function () { optimisticTracks(id, old); send('PLAYLIST_UPDATE', { playlist: { id: id, tracks: old } }); } });
          } }, icon('x')));
      }));
    }
    var rs = p.audiobook ? S.bedtime.resume[id] : null;
    var ri = rs ? tracks.indexOf(rs.id) : -1;
    var more = h('div', { class: 'card', style: 'margin-top:16px' },
      h('label', { class: 'switch' }, h('div', null, h('div', null, t('audiobook')), h('div', { class: 'small muted' }, t('audiobook_help'))),
        h('input', { type: 'checkbox', role: 'switch', checked: !!p.audiobook, 'data-k': 'audiobook', onchange: function (e) { send('PLAYLIST_UPDATE', { playlist: { id: id, audiobook: e.target.checked } }); } })),
      p.audiobook && S.bedtime.cfg.start !== undefined && tracks.length ? h('div', { class: 'kv col', 'data-k': 'resume' },
        h('span', { class: 'muted' }, ri >= 0 ? t('resume_at', ri + 1, Number(rs.pos) > 20000 ? fmtTime((Number(rs.pos) - 15000) / 1000) : '') : t('resume_done')),
        ri >= 0 ? h('button', { class: 'btn ghost', 'data-k': 'resumereset', onclick: function () { send('OJ_RESUME_RESET', { playlistId: id }); } }, t('resume_restart')) : null) : null);
    return [head, actions, uploadsBlock(id), canHover ? dropZone(id) : null, list, more, deletePlaylistBtn(p, id)];
  }
  function optimisticTracks(id, tracks) { if (pls()[id]) { pls()[id].tracks = tracks; IDX = null; render(); } }

