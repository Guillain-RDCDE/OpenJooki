  function offlineBusy() {
    return /^(resolving|downloading|verifying)$/.test(obj(obj(S.spotifyOffline).download).phase || '');
  }
  function offlineBytes(n) { return (Math.max(0, Number(n) || 0) / 1048576).toFixed(1) + ' MiB'; }
  function spotifyOfflineCard(p, id) {
    var o = obj(S.spotifyOffline);
    if (!o.available) return null;
    var snap = obj(obj(o.playlists)[p.spotify.uri]);
    var job = obj(o.download), mine = job.uri === p.spotify.uri, busy = offlineBusy();
    var downloading = userPlaylists().filter(function (item) { return item.spotify && item.spotify.uri === job.uri; })[0];
    var tracks = arr(snap.tracks), ready = !!snap.ready;
    if (!tracks.length && mine) tracks = arr(job.tracks);
    var mode = obj(o.modes)[id] || 'online';
    var np = obj(S.audio.nowPlaying), offlineActive = np.service === 'SPOTIFY_OFFLINE' && !/^(STOPPED|ENDED)$/.test(S.audio.playback.state || ''), inUse = offlineActive && np.playlistId === id, playing = offlineActive && (S.audio.playback.state !== 'PAUSED' || obj(o.player).state !== 'paused');
    var storage = obj(o.storage);
    function button(label, kind, disabled) {
      return h('button', { class: 'btn', disabled: disabled, onclick: function () { send(kind, { playlistId: id }); } }, label);
    }
    return h('div', { class: 'card', style: 'margin-top:16px;padding:16px', 'data-k': 'spotify-offline' },
      h('h3', null, t('of_title')),
      h('p', { class: 'small muted' }, t('of_premium')),
      o.error || (obj(o.player).playlist === id && obj(o.player).error) ? h('p', { class: 'banner', role: 'alert' }, t('of_backend_error')) : null,
      !o.account_ready ? h('p', { class: 'banner' }, t('of_login')) : null,
      h('select', { class: 'input', 'aria-label': t('of_title'), 'data-k': 'offline-mode', onchange: function (e) {
        send('OJ_OFFLINE_MODE', { playlistId: id, mode: e.target.value });
      } }, ['online', 'auto', 'offline'].map(function (value, i) {
        return h('option', { value: value, selected: mode === value, disabled: value === 'offline' && !ready }, t(['of_online', 'of_auto', 'of_only'][i]));
      })),
      h('p', { class: 'small muted' }, t('of_hint')),
      h('div', { class: 'actions' },
        button(t(ready ? 'of_update' : 'of_download'), 'OJ_OFFLINE_SYNC', !o.account_ready || busy || playing),
        ready ? h('button', { class: 'btn danger', disabled: busy || inUse, onclick: function () {
          confirmBox(t('of_remove_q'), t('of_remove_help'), t('of_remove'), true).then(function (yes) {
            if (yes) send('OJ_OFFLINE_REMOVE', { playlistId: id });
          });
        } }, t('of_remove')) : null),
      playing && !busy ? h('p', { class: 'banner', role: 'status' }, t('of_pause_sync')) : null,
      busy ? h('div', { role: 'status', 'data-k': 'offline-progress' },
        !mine ? h('p', null, t('of_other'), downloading ? h('a', { href: '#/p/' + encodeURIComponent(downloading.id) }, downloading.title || 'Spotify') : 'Spotify') : null,
        h('p', null, t('of_busy') + ' · ' + (job.completed || 0) + '/' + (job.total || '…')),
        h('progress', { max: Math.max(1, Number(job.total) || 1), value: Number(job.completed) || 0, 'aria-label': t('of_busy') }),
        h('p', { class: 'small muted' }, t('of_processed') + ': ' + offlineBytes(job.bytes))) : null,
      mine && /^(error|interrupted)$/.test(job.phase || '') ? h('p', { class: 'banner', role: 'alert' },
        t(job.error === 'storage_full' ? 'of_space' : 'of_error')) : null,
      ready ? h('p', { class: 'small', 'data-k': 'offline-ready' }, t('of_ready') + ' · ' + tracks.length + ' · ' + offlineBytes(snap.bytes)) : null,
      h('p', { class: 'small muted' }, t('of_storage') + ': ' + offlineBytes(storage.used_bytes) + ' / ' + offlineBytes(storage.quota_bytes)),
      h('h3', null, t('of_songs')),
      tracks.length ? h('ol', { class: 'tracks', 'data-k': 'offline-tracks' }, tracks.map(function (track, index) {
        return h('li', { class: 'row', style: 'padding:8px 0' },
          h('span', { class: 'grow' }, h('span', null, track.name || '—'),
            h('span', { class: 'small muted', style: 'display:block' }, arr(track.artists).join(', '))),
          h('span', { class: 'small muted' }, fmtTime((track.duration_ms || 0) / 1000)),
          ready ? h('button', { class: 'icon-btn', disabled: busy, 'aria-label': t('of_play') + ': ' + (track.name || ''), onclick: function () {
            send('OJ_OFFLINE_PLAY', { playlistId: id, trackIndex: index + 1 });
          } }, icon('play')) : null);
      })) : h('p', { class: 'small muted' }, t('of_empty')));
  }
