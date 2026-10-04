  /* ------------------------------------------------------------------ player */
  function isPlaying() { return S.audio.playback.state === 'PLAYING' || S.audio.playback.state === 'STARTING'; }
  // Spotify started from the phone has no playlist of ours, and its title may arrive a moment later
  function isSpotify() { var np = S.audio.nowPlaying; return !!(np && (np.service === 'SPOTIFY' || np.service === 'DEEZER')); }
  function hasNow() { var np = S.audio.nowPlaying; return !!(np && ((np.playlistId && np.uri) || isSpotify())); }
  function nowTitle() {
    var np = S.audio.nowPlaying;
    if (isSpotify()) return cleanTitle(np.track) || (np.service === 'DEEZER' ? 'Deezer' : 'Spotify');
    return cleanTitle(np.track || trackTitle(np.trackId));
  }
  // under the title: for Spotify "artist / album" (the album, else what it plays from), else our playlist's name
  function nowSource(pl) {
    var np = S.audio.nowPlaying;
    if (isSpotify()) return [np.artist, np.album || np.source].filter(function (x) { return x && x !== 'unknown'; }).join(' / ');
    return np.source || (pl && pl.title) || '';
  }
  function curPos() {
    var pb = S.audio.playback;
    var p = Number(pb.position_ms) || 0;
    if (pb.state === 'PLAYING') p += Date.now() - posStamp;
    var d = Number(S.audio.nowPlaying.duration_ms) || 0;
    return d ? Math.min(p, d) : p;
  }
  // The cover of what plays. Spotify's daemon gives "spotify:image:<id>" or an address on Spotify's
  // image servers: the phone loads it from there (the page's CSP allows *.scdn.co and
  // *.spotifycdn.com), never through the Jooki. Local music keeps its /artwork/ file.
  function coverSrc(u) {
    u = String(u || '');
    var m = /^spotify:image:([0-9a-f]{16,64})$/i.exec(u);
    return m ? 'https://i.scdn.co/image/' + m[1] : u;
  }
  function playerBar() {
    var np = S.audio.nowPlaying;
    var pl = pls()[np.playlistId];
    var now = hasNow();
    var cover = h('div', { class: 'cover' });
    var fallback = function () { return now && pl && pl.star ? tokVisual(pl.star, 'sm') : icon('note'); };
    if (now && np.image) {
      var ci = h('img', { src: coverSrc(np.image), alt: '' });
      ci.onerror = function () { ci.replaceWith(fallback()); };
      cover.appendChild(ci);
    } else cover.appendChild(fallback());
    var d = Number(np.duration_ms) || 0;
    return h('div', { class: 'player' + (now ? '' : ' idle'), 'data-k': 'player' },
      h('div', { class: 'prog' }, h('i', { 'data-prog': '1', style: 'width:' + (d ? Math.round(curPos() / d * 100) : 0) + '%' })),
      cover,
      h('div', { class: 'info', role: 'button', tabindex: '0', 'aria-label': t('open_player'), onclick: function () { if (now) nowPlayingModal(); },
        onkeydown: function (e) { if (e.key === 'Enter' && now) nowPlayingModal(); } },
        h('div', { class: 't ellipsis' }, now ? nowTitle() : t('nothing_playing')),
        h('div', { class: 's ellipsis' }, sleepInfo() ? h('span', { class: 'sleepmini' }, icon('moon'), h('span', { 'data-sleep-short': '1' }, sleepShort())) : null,
          now ? nowSource(pl) : t('nothing_hint'))),
      now ? h('button', { class: 'icon-btn', 'aria-label': t('prev'), onclick: function () { send('DO_PREV', {}); } }, icon('prev')) : null,
      now ? h('button', { class: 'icon-btn accent', 'aria-label': isPlaying() ? t('pause') : t('play'), 'data-k': 'pp',
        onclick: function () { send(isPlaying() ? 'DO_PAUSE' : 'DO_PLAY', {}); } }, icon(isPlaying() ? 'pause' : 'play')) : null,
      now ? h('button', { class: 'icon-btn', 'aria-label': t('next'), onclick: function () { send('DO_NEXT', {}); } }, icon('next')) : null);
  }
  var seeking = false, volDrag = null;
  function nowPlayingModal() {
    openModal({
      live: true,
      sig: function () {
        var np = S.audio.nowPlaying, c = S.audio.config;
        var sl = sleepInfo() || {};
        return [np.playlistId, np.trackId, np.trackIndex, np.service, np.track, np.image, S.audio.playback.state, c.volume, c.shuffle_mode, c.repeat_mode, np.duration_ms, sl.mode, sl.total, sl.auto].join('|');
      },
      render: function () {
        var np = S.audio.nowPlaying, pl = pls()[np.playlistId];
        var cfg = S.audio.config;
        var d = Number(np.duration_ms) || 0;
        var stream = np.service === 'STREAM';
        var art = h('div', { class: 'art' });
        if (np.image) {
          var ai = h('img', { src: coverSrc(np.image), alt: '' });
          ai.onerror = function () { ai.replaceWith(tokVisual(pl && pl.star, '')); };
          art.appendChild(ai);
        } else art.appendChild(tokVisual(pl && pl.star, ''));
        var vol = volDrag !== null ? volDrag : Number(cfg.volume) || 0;
        return h('div', { class: 'np' }, art,
          h('div', { class: 't' }, nowTitle() || '—'),
          h('div', { class: 'muted' }, isSpotify() ? nowSource(pl) : [np.artist && np.artist !== 'unknown' ? np.artist : null, np.source || (pl && pl.title)].filter(Boolean).join(' · ')),
          stream ? h('div', { class: 'badge accent', style: 'margin-top:12px' }, t('live')) : [
            h('input', { class: 'range', type: 'range', min: '0', max: String(d || 1), value: String(Math.round(curPos())), 'aria-label': 'position', 'data-k': 'seek', 'data-seek': '1',
              oninput: function () { seeking = true; }, onchange: function (e) { seeking = false; send('SEEK', { position_ms: Math.max(1, Number(e.target.value)) }); } }),
            h('div', { class: 'times' }, h('span', { 'data-cur': '1' }, fmtTime(curPos() / 1000)), h('span', null, fmtTime(d / 1000)))],
          h('div', { class: 'controls' },
            h('button', { class: 'icon-btn', 'aria-label': t('prev'), onclick: function () { send('DO_PREV', {}); } }, icon('prev')),
            h('button', { class: 'icon-btn accent', 'aria-label': isPlaying() ? t('pause') : t('play'), 'data-k': 'nppp', onclick: function () { send(isPlaying() ? 'DO_PAUSE' : 'DO_PLAY', {}); } }, icon(isPlaying() ? 'pause' : 'play')),
            h('button', { class: 'icon-btn', 'aria-label': t('next'), onclick: function () { send('DO_NEXT', {}); } }, icon('next'))),
          h('div', { class: 'vol' }, icon('vol'), h('input', { class: 'range', type: 'range', min: '0', max: '100', step: '5', value: String(vol), 'aria-label': t('volume'), 'data-k': 'vol',
            oninput: function (e) { volDrag = Number(e.target.value); }, onchange: function (e) { volDrag = null; send('SET_VOL', { vol: Number(e.target.value) }); } })),
          h('div', { class: 'toggles' },
            h('button', { class: 'toggle' + (cfg.shuffle_mode ? ' on' : ''), 'aria-pressed': String(!!cfg.shuffle_mode), onclick: function () { send('SET_CFG', { shuffle_mode: !cfg.shuffle_mode }); } }, icon('shuffle'), t('shuffle')),
            h('button', { class: 'toggle' + (cfg.repeat_mode === 1 ? ' on' : ''), 'aria-pressed': String(cfg.repeat_mode === 1), onclick: function () { send('SET_CFG', { repeat_mode: cfg.repeat_mode === 1 ? 0 : 1 }); } }, icon('repeat'), t('repeat'))),
          // Spotify started from the phone: offer to put it on a character
          np.service === 'SPOTIFY' && !np.playlistId ? h('div', { class: 'actions', style: 'justify-content:center;margin-top:12px' },
            h('button', { class: 'btn primary', 'data-k': 'spsave', onclick: spotifySaveModal }, icon('plus'), t('sp_save'))) : null,
          S.bedtime.cfg.start !== undefined ? sleepPanel() : null,
          h('div', { class: 'foot' }, h('button', { class: 'btn block', onclick: closeModal }, t('close'))));
      }
    });
  }
  setInterval(function () {
    if (document.hidden) return;   // nobody looks: the next tick catches up (times are computed, not counted)
    if (sleepInfo()) {
      Array.prototype.forEach.call(document.querySelectorAll('[data-sleep]'), function (el) { el.textContent = sleepText(); });
      Array.prototype.forEach.call(document.querySelectorAll('[data-sleep-short]'), function (el) { el.textContent = sleepShort(); });
    }
    if (!hasNow() || S.audio.playback.state !== 'PLAYING') return;
    var d = Number(S.audio.nowPlaying.duration_ms) || 0;
    var p = curPos();
    var bar = document.querySelector('[data-prog]');
    if (bar && d) bar.style.width = Math.round(p / d * 100) + '%';
    if (!seeking) {
      var r = document.querySelector('[data-seek]'); if (r) r.value = String(Math.round(p));
      var c = document.querySelector('[data-cur]'); if (c) c.textContent = fmtTime(p / 1000);
    }
  }, 500);

