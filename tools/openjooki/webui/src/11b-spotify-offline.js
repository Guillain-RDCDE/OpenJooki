  var offlinePreviewAsked = {}, offlinePreviewCache = {}, offlinePageOffsets = {}, offlinePageBack = {};
  function offlineBusy() {
    return /^(resolving|downloading|verifying)$/.test(obj(obj(S.spotifyOffline).download).phase || '');
  }
  function offlineBytes(n) {
    n = Math.max(0, Number(n) || 0);
    return n >= 1073741824 ? (n / 1073741824).toFixed(1) + ' GiB' : (n / 1048576).toFixed(1) + ' MiB';
  }
  function offlineErrorText(code, context) {
    var key = { storage_full: 'of_space', unsupported_item: 'of_unsupported', unsupported_playlist: 'of_error',
      playlist_too_large: 'of_too_large', playlist_incomplete: 'of_incomplete', playlist_changed: 'of_changed',
      track_unavailable: 'of_unavailable', rate_limited: 'of_rate', network_timeout: 'of_network',
      authentication_required: 'of_auth_error', backend_start_failed: 'of_start_error', player_interrupted: 'of_start_error' }[code];
    if (code === 'unsupported_audio_format') key = 'of_audio_format';
    return t(key || (context === 'metadata' ? 'of_metadata_error' : context === 'playback' ? 'of_start_error' : 'of_error'));
  }
  function askSpotifyTitles(id, offset, force) {
    var key = (obj(S.spotifyOffline).account_id || '') + ':' + id + ':' + offset;
    if (!force && offlinePreviewAsked[key] && Date.now() - offlinePreviewAsked[key] < 10000) return;
    offlinePreviewAsked[key] = Date.now();
    setTimeout(function () { send('OJ_OFFLINE_PREVIEW', { playlistId: id, offset: offset }); }, 0);
  }
  function spotifyOfflineCard(p, id) {
    var o = obj(S.spotifyOffline), premium = !!o.account_ready;
    if (!o.available || !/^spotify:playlist:[A-Za-z0-9]{22}$/.test(p.spotify.uri || '')) return null;
    var snap = obj(obj(o.playlists)[p.spotify.uri]), latest = obj(obj(o.previews)[p.spotify.uri]);
    var pageKey = (o.account_id || '') + ':' + p.spotify.uri + ':' + (snap.snapshot_id || ''), wanted = offlinePageOffsets[pageKey] || 0;
    if (latest.phase) offlinePreviewCache[pageKey + ':' + (Number(latest.offset) || 0)] = latest;
    var meta = obj(offlinePreviewCache[pageKey + ':' + wanted]);
    var active = obj(o.download), mine = active.uri === p.spotify.uri, busy = offlineBusy();
    var own = mine ? active : obj(obj(o.jobs)[p.spotify.uri]);
    var ready = !!snap.ready, offset = Number(meta.offset) || wanted;
    var tracks = arr(meta.tracks).length ? arr(meta.tracks) : wanted === 0 && arr(snap.tracks).length ? arr(snap.tracks) : mine && wanted === 0 ? arr(active.tracks) : [];
    var total = Number(meta.total) || Number(snap.total_tracks) || Number(own.total) || tracks.length;
    var queue = arr(o.queue), queuedAt = -1;
    queue.forEach(function (item, index) { if (item.uri === p.spotify.uri) queuedAt = index; });
    var np = obj(S.audio.nowPlaying), offlineActive = np.service === 'SPOTIFY_OFFLINE' && !/^(STOPPED|ENDED)$/.test(S.audio.playback.state || '');
    var playing = offlineActive && (S.audio.playback.state !== 'PAUSED' || obj(o.player).state !== 'paused');
    var inUse = offlineActive && np.playlistId === id, storage = obj(o.storage), mode = obj(o.modes)[id] || 'online';
    var metadataReady = o.metadata_ready || premium;
    if (!metadataReady) tracks = [];
    function pageTo(next, backwards) {
      var history = offlinePageBack[pageKey] || (offlinePageBack[pageKey] = []);
      if (backwards) next = history.length ? history.pop() : Math.max(0, wanted - 50);
      else history.push(wanted);
      offlinePageOffsets[pageKey] = next; askSpotifyTitles(id, next, true);
    }
    if (metadataReady && !meta.phase && (!ready || !tracks.length || tracks.length < total)) askSpotifyTitles(id, wanted, false);
    var other = userPlaylists().filter(function (item) { return item.spotify && item.spotify.uri === active.uri; })[0];
    function command(kind) { send(kind, { playlistId: id }); }
    var titleBlock = h('section', { class: 'spotify-titles', 'data-k': 'spotify-titles' },
      h('div', { class: 'offline-heading' }, h('h3', null, t('of_songs')), h('span', { class: 'offline-count' }, total ? String(total) : '')),
      !metadataReady ? h('p', { class: 'small muted' }, t('of_titles_login'), ' ', h('a', { href: '#/settings/spotify' }, t('of_connect'))) : null,
      meta.phase === 'loading' && !tracks.length ? h('p', { class: 'small muted', role: 'status' }, t('of_titles_loading')) : null,
      meta.phase === 'error' ? h('div', { class: 'offline-notice', role: 'alert' }, offlineErrorText(meta.error, 'metadata'),
        h('button', { class: 'btn ghost', onclick: function () { askSpotifyTitles(id, offset, true); } }, t('of_retry'))) : null,
      tracks.length ? h('ol', { class: 'offline-tracks', start: offset + 1, 'data-k': 'offline-tracks' }, tracks.map(function (track, i) {
        var position = offset + i + 1, selected = np.service === 'SPOTIFY_OFFLINE' && np.playlistId === id && np.trackIndex === position;
        return h('li', { class: 'offline-track' + (selected ? ' selected' : '') },
          h('span', { class: 'offline-number', 'aria-hidden': 'true' }, selected ? '♪' : String(position)),
          h('span', { class: 'offline-track-info' }, h('span', { class: 'title' }, track.name || '—'),
            h('span', { class: 'small muted' }, arr(track.artists).join(', ')),
            track.problem ? h('span', { class: 'small muted' }, t('of_item_unavailable')) : null),
          h('span', { class: 'small muted offline-duration' }, fmtTime((track.duration_ms || 0) / 1000)),
          premium && ready ? h('button', { class: 'icon-btn', disabled: busy || !!track.problem, 'aria-label': t('of_play') + ': ' + (track.name || ''), onclick: function () {
            send('OJ_OFFLINE_PLAY', { playlistId: id, trackIndex: position });
          } }, icon('play')) : null);
      })) : metadataReady && !meta.phase ? h('button', { class: 'btn ghost', onclick: function () { askSpotifyTitles(id, 0, true); } }, t('of_load_titles')) : null,
      tracks.length && (offset > 0 || offset + tracks.length < total) ? h('div', { class: 'offline-paging' },
        h('button', { class: 'btn ghost', disabled: offset === 0 || meta.phase === 'loading', onclick: function () { pageTo(0, true); } }, t('of_previous')),
        h('span', { class: 'small muted' }, (offset + 1) + '–' + (offset + tracks.length) + ' / ' + total),
        h('button', { class: 'btn ghost', disabled: offset + tracks.length >= total || meta.phase === 'loading', onclick: function () { pageTo(offset + tracks.length, false); } }, t('of_next'))) : null);
    if (!premium) return h('div', { class: 'card offline-panel', 'data-k': 'spotify-metadata' }, titleBlock);
    return h('section', { class: 'card offline-panel', 'data-k': 'spotify-offline' },
      h('div', { class: 'offline-heading' }, h('h3', null, t('of_title')),
        h('span', { class: 'offline-badge' + (ready ? ' ready' : '') }, t(ready ? 'of_ready' : queuedAt >= 0 ? 'of_queued' : 'of_online_badge'))),
      h('div', { class: 'offline-toolbar' }, h('select', { class: 'input', 'aria-label': t('of_title'), 'data-k': 'offline-mode', onchange: function (e) {
        send('OJ_OFFLINE_MODE', { playlistId: id, mode: e.target.value });
      } }, ['online', 'auto', 'offline'].map(function (value, i) {
        return h('option', { value: value, selected: mode === value, disabled: value === 'offline' && !ready }, t(['of_online', 'of_auto', 'of_only'][i]));
      }))),
      h('p', { class: 'small muted' }, t('of_hint')),
      h('div', { class: 'offline-actions' },
        h('button', { class: 'btn primary', disabled: (busy && mine) || queuedAt >= 0, onclick: function () { command('OJ_OFFLINE_SYNC'); } },
          t(queuedAt >= 0 ? 'of_queued' : busy && mine ? 'of_busy' : busy || playing ? 'of_enqueue' : ready ? 'of_update' : 'of_download')),
        queuedAt >= 0 ? h('button', { class: 'btn ghost', onclick: function () { command('OJ_OFFLINE_CANCEL_QUEUED'); } }, t('of_cancel_queue')) : null,
        ready ? h('button', { class: 'btn ghost', disabled: busy || inUse, onclick: function () {
          confirmBox(t('of_remove_q'), t('of_remove_help'), t('of_remove'), true).then(function (yes) { if (yes) command('OJ_OFFLINE_REMOVE'); });
        } }, t('of_remove')) : null),
      playing && queue.length ? h('p', { class: 'offline-notice', role: 'status' }, t('of_pause_sync')) : null,
      o.queue_paused ? h('div', { class: 'offline-notice', role: 'status' }, offlineErrorText(o.queue_paused), ' ',
        h('button', { class: 'btn ghost', onclick: function () { send('OJ_OFFLINE_RESUME_QUEUE', {}); } }, t('of_resume_queue'))) : null,
      queuedAt >= 0 ? h('p', { class: 'small muted', role: 'status' }, t('of_queue_position', queuedAt + 1)) : null,
      busy ? h('div', { class: 'offline-progress', role: 'status', 'data-k': 'offline-progress' },
        h('div', { class: 'offline-heading' }, h('span', null, t('of_busy')), h('b', null, (active.completed || 0) + ' / ' + (active.total || '…'))),
        !mine ? h('p', { class: 'small' }, t('of_other'), other ? h('a', { href: '#/p/' + encodeURIComponent(other.id) }, other.title || 'Spotify') : 'Spotify') : null,
        h('progress', { max: Math.max(1, Number(active.total) || 1), value: Number(active.completed) || 0, 'aria-label': t('of_busy') }),
        h('span', { class: 'small muted' }, t('of_processed') + ': ' + offlineBytes(active.bytes))) : null,
      /^(error|interrupted)$/.test(own.phase || '') ? h('p', { class: 'offline-notice error', role: 'alert' },
        own.total ? own.phase === 'error' && /^(track_unavailable|unsupported_audio_format)$/.test(own.error || '') ? t('of_failed_at', (own.completed || 0) + 1, own.total) + ' ' : (own.completed || 0) + ' / ' + own.total + ' · ' : '', offlineErrorText(own.error)) : null,
      obj(o.player).playlist === id && obj(o.player).error ? h('p', { class: 'offline-notice error', role: 'alert' }, offlineErrorText(o.player.error, 'playback')) : null,
      ready ? h('p', { class: 'small', 'data-k': 'offline-ready' }, t('of_ready') + ' · ' + (snap.total_tracks || arr(snap.tracks).length) + ' · ' + offlineBytes(snap.bytes)) : null,
      h('div', { class: 'offline-storage small muted' }, h('span', null, t('of_storage') + ': ' + offlineBytes(storage.used_bytes)),
        h('span', null, t('of_free') + ': ' + offlineBytes(storage.free_bytes))),
      h('p', { class: 'small muted' }, t('of_auto_storage')),
      queue.length ? h('details', { class: 'offline-queue', 'data-k': 'offline-queue' }, h('summary', null, t('of_queue') + ' · ' + queue.length),
        h('ol', null, queue.map(function (item) { return h('li', null, h('a', { href: '#/p/' + encodeURIComponent(item.playlist) }, item.title || 'Spotify'),
          h('button', { class: 'icon-btn', 'aria-label': t('of_cancel_queue') + ': ' + (item.title || ''), onclick: function () { send('OJ_OFFLINE_CANCEL_QUEUED', { playlistId: item.playlist }); } }, icon('x'))); }))) : null,
      titleBlock);
  }
