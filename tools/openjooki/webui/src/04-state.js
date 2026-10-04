  /* ------------------------------------------------------------------ state */
  var S = { db: { playlists: {}, tracks: {}, tokens: {} }, audio: { config: {}, playback: {}, nowPlaying: {} }, nfc: {}, device: {}, power: {}, wifi: {}, userMessages: [], bedtime: {}, maintenance: {} };
  var gotState = false;
  function normalize() {
    S.db = obj(S.db);
    S.db.playlists = obj(S.db.playlists);
    S.db.tracks = obj(S.db.tracks);
    S.db.tokens = obj(S.db.tokens);
    delete S.db.tokens._;
    S.audio = obj(S.audio);
    S.audio.config = obj(S.audio.config);
    S.audio.playback = obj(S.audio.playback);
    S.audio.nowPlaying = obj(S.audio.nowPlaying);
    S.nfc = obj(S.nfc); S.device = obj(S.device); S.power = obj(S.power); S.wifi = obj(S.wifi);
    S.userMessages = arr(S.userMessages);
    S.net = obj(S.net);
    S.bedtime = obj(S.bedtime);
    S.bedtime.cfg = obj(S.bedtime.cfg);
    S.bedtime.resume = obj(S.bedtime.resume);
  }
  function mergeState(p) {
    if (!p || typeof p !== 'object') return;
    Object.keys(p).forEach(function (k) {
      if (k === 'audio' && p.audio && typeof p.audio === 'object' && !Array.isArray(p.audio)) {
        S.audio = obj(S.audio);
        Object.keys(p.audio).forEach(function (s) { S.audio[s] = p.audio[s]; });
        if (p.audio.playback) posStamp = Date.now();
      } else if (k === 'bedtime') {
        S.bedtime = p.bedtime;
        sleepStamp = Date.now();
      } else {
        S[k] = p[k];
      }
    });
    if (p.db) gotState = true;
    normalize();
    IDX = null;
  }
  var posStamp = Date.now(), sleepStamp = Date.now();
  function pls() { return S.db.playlists; }
  // What a render asks again and again (each character tile, each option of a select…), derived
  // from S.db once: the user's playlists sorted by title, and the one each character starts.
  // Dropped (IDX = null) wherever S.db changes: mergeState, optimisticTracks; and by setLang, which changes the sort.
  var IDX = null;
  function index() {
    if (IDX) return IDX;
    var c = collator();
    var list = Object.keys(pls()).filter(function (id) { return id !== 'TRASH' && id !== 'system'; })
      .map(function (id) { return Object.assign({ id: id }, pls()[id]); })
      .sort(function (a, b) { return c.compare(a.title || '', b.title || ''); });
    var byStar = {};
    list.forEach(function (p) { if (typeof p.star === 'string' && p.star && !byStar.hasOwnProperty(p.star)) byStar[p.star] = p; });   // the first in title order, as before
    IDX = { userPlaylists: list, byStar: byStar };
    return IDX;
  }
  function userPlaylists() { return index().userPlaylists; }
  function trackTitle(id) { var tr = S.db.tracks[id]; if (!tr) return '?'; return cleanTitle(tr.title || tr.userFilename || id); }
  function trackSub(tr) {
    if (!tr) return '';
    if (tr.isUrl) return t('radio') + ' · ' + (tr.filename || '');
    var bits = [];
    if (tr.artist && tr.artist !== 'unknown') bits.push(tr.artist);
    if (tr.album && tr.album !== 'unknown') bits.push(tr.album);
    if (tr.duration) bits.push(fmtTime(tr.duration));
    return bits.join(' · ');
  }
  // the playing time of a playlist, in seconds (radios have none)
  function plDuration(tracks) { return arr(tracks).reduce(function (s, x) { var tr = S.db.tracks[x]; return s + (tr && !tr.isUrl ? Number(tr.duration) || 0 : 0); }, 0); }
  function playlistOfChar(starId) {
    var byStar = index().byStar;
    return typeof starId === 'string' && byStar.hasOwnProperty(starId) ? byStar[starId] : null;
  }
  function unusedIds() { var tr = pls().TRASH; return tr ? arr(tr.tracks).filter(function (x) { return S.db.tracks[x]; }) : []; }

