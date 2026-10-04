  /* ------------------------------------------------------------------ discs: FLAC / WAV -> MP3, in the browser */
  // A disc in FLAC weighs ~300 MB: a twentieth of the Jooki's card. The page turns lossless files into
  // MP3 here, on the phone or computer (the Jooki has neither the power nor the memory, and writing
  // while it plays makes the sound stutter), keeps the tags and a small cover, then sends the MP3 like
  // any other file. Decoding: the browser's own (FLAC since Chrome 56, Firefox 51, Safari 11),
  // resampled to 44.1 kHz; encoding: lamejs (LGPL-3.0, lame.LICENSE.txt) in mp3-worker.js.
  var LOSSLESS = /\.(flac|wav)$/i;
  var MP3_RATES = [192, 256, 320];
  function mp3Kbps() { var v = Number(lsGet('oj.mp3')); return MP3_RATES.indexOf(v) >= 0 ? v : 256; }
  function canConvert() { return !!(window.Worker && (window.OfflineAudioContext || window.webkitOfflineAudioContext)); }
  function readBytes(blob, from, len) {
    return new Promise(function (ok, ko) {
      var fr = new FileReader();
      fr.onload = function () { ok(new Uint8Array(fr.result)); };
      fr.onerror = function () { ko(fr.error); };
      fr.readAsArrayBuffer(blob.slice(from, from + len));
    });
  }
  function u32le(b, i) { return (b[i] | (b[i + 1] << 8) | (b[i + 2] << 16) | (b[i + 3] << 24)) >>> 0; }
  function u32be(b, i) { return ((b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3]) >>> 0; }
  var utf8 = window.TextDecoder ? new TextDecoder('utf-8') : null;
  function utf8At(b, from, len) { return utf8 ? utf8.decode(b.subarray(from, from + len)) : ''; }
  // A FLAC file's tags (Vorbis comments, upper-case keys) and its first picture (front cover first):
  // only the small metadata blocks at its start are read, never the audio.
  function flacTags(file, withPicture) {
    var tags = {};
    if (!/\.flac$/i.test(file.name)) return Promise.resolve(tags);
    var pos = 4;
    function block() {
      return readBytes(file, pos, 4).then(function (hd) {
        if (hd.length < 4) return tags;
        var last = hd[0] & 128, type = hd[0] & 127, len = (hd[1] << 16) | (hd[2] << 8) | hd[3], start = pos + 4;
        pos = start + len;
        var want = type === 4 || (type === 6 && withPicture && len < 16e6 && !(tags.picture && tags.picture.front));
        return (want ? readBytes(file, start, len).then(function (b) { if (type === 4) vorbisTags(b, tags); else flacPicture(b, tags); }) : Promise.resolve())
          .then(function () { return last || pos >= file.size ? tags : block(); });
      });
    }
    return readBytes(file, 0, 4).then(function (m) { return String.fromCharCode(m[0], m[1], m[2], m[3]) === 'fLaC' ? block() : tags; })
      .catch(function () { return tags; });
  }
  function vorbisTags(b, tags) {
    var i = 4 + u32le(b, 0), n = u32le(b, i);
    i += 4;
    for (var k = 0; k < n && i + 4 <= b.length; k++) {
      var len = u32le(b, i), kv = utf8At(b, i + 4, len), eq = kv.indexOf('=');
      i += 4 + len;
      if (eq > 0 && !tags[kv.slice(0, eq).toUpperCase()]) tags[kv.slice(0, eq).toUpperCase()] = kv.slice(eq + 1);
    }
  }
  function flacPicture(b, tags) {
    var kind = u32be(b, 0), ml = u32be(b, 4), mime = utf8At(b, 8, ml), i = 8 + ml;
    i += 4 + u32be(b, i) + 16;   // description, then width, height, depth, colours
    var len = u32be(b, i);
    tags.picture = { mime: mime || 'image/jpeg', data: b.slice(i + 4, i + 4 + len), front: kind === 3 };
  }
  // the cover, at most 300 px (a big cover inside the file slows the Jooki down), as JPEG bytes
  function smallCover(blob) {
    if (!blob || !window.createImageBitmap) return Promise.resolve(null);
    return createImageBitmap(blob).then(function (img) {
      var s = Math.min(1, 300 / Math.max(img.width, img.height)), c = document.createElement('canvas');
      c.width = Math.max(1, Math.round(img.width * s)); c.height = Math.max(1, Math.round(img.height * s));
      c.getContext('2d').drawImage(img, 0, 0, c.width, c.height);
      return new Promise(function (ok) { c.toBlob(ok, 'image/jpeg', 0.85); });
    }).then(function (jpg) { return jpg ? readBytes(jpg, 0, jpg.size) : null; }).catch(function () { return null; });
  }
  // An ID3v2.3 tag (UTF-16 text frames, an APIC front cover): what the Jooki reads from an MP3.
  function id3(tags, cover) {
    var frames = [];
    function text(id, v) {
      if (!v) return;
      v = String(v);
      var b = new Uint8Array(5 + v.length * 2);
      b[0] = 1; b[1] = 255; b[2] = 254;
      for (var i = 0; i < v.length; i++) { b[3 + 2 * i] = v.charCodeAt(i) & 255; b[4 + 2 * i] = v.charCodeAt(i) >> 8; }
      frames.push([id, b]);
    }
    var track = tags.TRACKNUMBER, total = tags.TRACKTOTAL || tags.TOTALTRACKS;
    text('TIT2', tags.TITLE); text('TPE1', tags.ARTIST); text('TALB', tags.ALBUM);
    text('TPE2', tags.ALBUMARTIST || tags['ALBUM ARTIST']); text('TCON', tags.GENRE);
    text('TRCK', track && total && String(track).indexOf('/') < 0 ? track + '/' + total : track);
    text('TPOS', tags.DISCNUMBER); text('TYER', (String(tags.DATE || '').match(/\d{4}/) || [])[0]);
    if (cover) {
      var head = [0].concat('image/jpeg'.split('').map(function (c) { return c.charCodeAt(0); }), [0, 3, 0]);
      var pic = new Uint8Array(head.length + cover.length);
      pic.set(head, 0); pic.set(cover, head.length);
      frames.push(['APIC', pic]);
    }
    var size = frames.reduce(function (s, f) { return s + 10 + f[1].length; }, 0), out = new Uint8Array(10 + size), at = 10;
    out.set([73, 68, 51, 3, 0, 0, (size >> 21) & 127, (size >> 14) & 127, (size >> 7) & 127, size & 127], 0);
    frames.forEach(function (f) {
      var n = f[1].length;
      out.set([f[0].charCodeAt(0), f[0].charCodeAt(1), f[0].charCodeAt(2), f[0].charCodeAt(3), (n >>> 24) & 255, (n >> 16) & 255, (n >> 8) & 255, n & 255, 0, 0], at);
      out.set(f[1], at + 10); at += 10 + n;
    });
    return out;
  }
  function decodeAudio(file) {
    return readBytes(file, 0, file.size).then(function (bytes) {
      var Ctx = window.OfflineAudioContext || window.webkitOfflineAudioContext, ctx = new Ctx(2, 1, 44100);
      return new Promise(function (ok, ko) { var p = ctx.decodeAudioData(bytes.buffer, ok, ko); if (p && p.then) p.then(ok, ko); });
    });
  }
  function encodeMp3(audio, kbps, onProgress) {
    return new Promise(function (ok, ko) {
      var w = new Worker('mp3-worker.js?v=' + VERSION);
      var ch = [audio.getChannelData(0)];
      if (audio.numberOfChannels > 1) ch.push(audio.getChannelData(1));
      ch = ch.map(function (c) { return new Float32Array(c); });   // copies the worker may take
      w.onmessage = function (e) {
        var d = e.data;
        if (d.progress !== undefined) { onProgress(d.progress); return; }
        w.terminate();
        if (d.mp3) ok(d.mp3); else ko(new Error(d.error || 'mp3'));
      };
      w.onerror = function (e) { w.terminate(); ko(new Error(e.message || 'mp3 worker')); };
      w.postMessage({ channels: ch, rate: audio.sampleRate, kbps: kbps }, ch.map(function (c) { return c.buffer; }));
    });
  }
  // file (FLAC / WAV) -> an MP3 File with its tags and cover; `cover` = the folder's picture, if any
  function toMp3(file, cover, onProgress) {
    var kbps = mp3Kbps();
    return Promise.all([flacTags(file, true), decodeAudio(file)]).then(function (r) {
      var tags = r[0], pic = tags.picture ? new Blob([tags.picture.data], { type: tags.picture.mime }) : cover;
      return Promise.all([encodeMp3(r[1], kbps, onProgress), smallCover(pic)]).then(function (x) {
        return new File([id3(tags, x[1]), x[0]], file.name.replace(LOSSLESS, '') + '.mp3', { type: 'audio/mpeg' });
      });
    });
  }
  // One file at a time, at most two ahead of the upload (each decoded disc track is ~100 MB of memory).
  var convBusy = false;
  function convPump() {
    if (convBusy) return;
    if (uploads.filter(function (x) { return x.conv && x.converted && x.status === 'queued'; }).length >= 2) return;
    var u = uploads.filter(function (x) { return x.conv && !x.converted && x.status === 'queued'; })[0];
    if (!u) return;
    convBusy = true; u.status = 'converting'; u.progress = 0; render();
    toMp3(u.file, u.cover, function (p) { u.progress = p; updateUploadRow(u); }).then(function (mp3) {
      u.file = mp3; u.name = mp3.name; u.size = mp3.size; u.converted = true; u.status = 'queued'; u.progress = 0; u.cover = null;
    }, function () {
      u.status = 'error'; u.error = t('up_conv_fail'); u.file = null; u.cover = null;
    }).then(function () { convBusy = false; render(); pump(); convPump(); });
  }

  // Folders: a dropped folder (or one chosen with "Add albums") is a disc. Its files come back as
  // groups, one per folder; files dropped loose make one group of their own (dir = null).
  function groupsFromList(files) {
    var groups = {}, order = [];
    Array.prototype.forEach.call(files, function (f) {
      var p = f.webkitRelativePath || '', dir = p.indexOf('/') > 0 ? p.slice(0, p.lastIndexOf('/')) : null;
      if (!groups.hasOwnProperty(dir)) { groups[dir] = []; order.push(dir); }
      groups[dir].push(f);
    });
    return order.map(function (d) { return { dir: d, files: groups[d] }; });
  }
  function groupsFromDrop(dt) {
    var entries = Array.prototype.map.call(dt.items || [], function (it) { return it.webkitGetAsEntry ? it.webkitGetAsEntry() : null; }).filter(Boolean);
    if (!entries.some(function (e) { return e.isDirectory; })) return Promise.resolve(groupsFromList(dt.files));
    var out = [], loose = [];
    function fileOf(e) { return new Promise(function (ok) { e.file(ok, function () { ok(null); }); }); }
    function children(dir) {
      var reader = dir.createReader(), all = [];
      return new Promise(function (ok) {
        (function more() { reader.readEntries(function (b) { if (!b.length) ok(all); else { all = all.concat(b); more(); } }, function () { ok(all); }); })();
      });
    }
    function walk(dir) {   // a folder: its own files are one group, its sub-folders (CD1, CD2…) are walked too
      return children(dir).then(function (list) {
        return Promise.all(list.filter(function (e) { return e.isFile; }).map(fileOf)).then(function (files) {
          files = files.filter(Boolean);
          if (files.length) out.push({ dir: dir.fullPath.replace(/^\//, ''), files: files });
          return list.filter(function (e) { return e.isDirectory; }).reduce(function (c, d) { return c.then(function () { return walk(d); }); }, Promise.resolve());
        });
      });
    }
    return entries.reduce(function (c, e) {
      return c.then(function () { return e.isDirectory ? walk(e) : fileOf(e).then(function (f) { if (f) loose.push(f); }); });
    }, Promise.resolve()).then(function () {
      out.sort(function (a, b) { return natural(a.dir, b.dir); });
      if (loose.length) out.push({ dir: null, files: loose });
      return out;
    });
  }
  var COVER_NAME = /^(cover|folder|front|album|pochette)[^/]*\.(jpe?g|png)$/i;
  function natural(a, b) { return collator().compare(a, b); }
  // one group -> { title, files (disc then track order), cover }; null when it holds no audio
  function discOf(group) {
    var audio = group.files.filter(function (f) { return AUDIO_EXT.test(f.name) && f.size > 5000; });
    if (!audio.length) return Promise.resolve(null);
    var cover = group.files.filter(function (f) { return COVER_NAME.test(f.name); })[0] || null;
    return Promise.all(audio.map(function (f) { return flacTags(f, false); })).then(function (tags) {
      var rows = audio.map(function (f, i) { return { f: f, d: parseInt(tags[i].DISCNUMBER, 10) || 0, n: parseInt(tags[i].TRACKNUMBER, 10) || 0, tags: tags[i] }; });
      rows.sort(function (a, b) { return a.d - b.d || a.n - b.n || natural(a.f.name, b.f.name); });
      var parts = (group.dir || '').split('/'), folder = parts[parts.length - 1] || '';
      var album = (rows.filter(function (r) { return r.tags.ALBUM; })[0] || { tags: {} }).tags.ALBUM;
      if (!album && /^(cd|disc|disk|disque|disco)\s*\d+$/i.test(folder) && parts.length > 1) album = parts[parts.length - 2] + ' – ' + folder;
      return { title: (album || folder || t('new_playlist')).slice(0, 100), files: rows.map(function (r) { return r.f; }), cover: cover };
    });
  }
  // The id of the next playlist the Jooki creates (one that `pred(id)` accepts), as a Promise: it
  // resolves on the state that brings it, or is rejected after `timeoutMs` (none: it waits). To
  // be called before the command is sent. `cancel()` stops the wait without settling it.
  function whenNewPlaylist(pred, timeoutMs) {
    var before = Object.keys(pls()), done = false, timer = null;
    var p = new Promise(function (ok, ko) {
      if (timeoutMs) timer = setTimeout(function () { if (done) return; done = true; ko(new Error('timeout')); }, timeoutMs);
      waiters.push(function (partial) {
        if (done) return true;
        if (!partial.db) return false;
        var fresh = Object.keys(pls()).filter(function (k) { return before.indexOf(k) < 0 && pred(k); })[0];
        if (!fresh) return false;
        done = true; clearTimeout(timer); ok(fresh); return true;
      });
    });
    p.cancel = function () { done = true; clearTimeout(timer); };
    return p;
  }
  function notTrash(k) { return k !== 'TRASH'; }
  function createPlaylist(title) {
    var p = whenNewPlaylist(notTrash, 20000);
    send('PLAYLIST_NEW', { title: title, audiobook: false });
    return p;
  }
  // Discs dropped on the playlists page: each folder becomes a playlist named after its album, its
  // tracks in disc order. Dropped in a playlist: everything goes into that playlist, folder by folder.
  function addDiscs(groups, playlistId) {
    return groups.reduce(function (chain, g) {
      return chain.then(function () { return discOf(g); }).then(function (d) {
        if (!d) return null;
        if (playlistId || !g.dir) { enqueue(d.files, playlistId || null, { cover: d.cover }); return null; }
        return createPlaylist(d.title).then(function (id) {
          enqueue(d.files, id, { cover: d.cover, disc: { id: ++discSeq, title: d.title } });
          toast(t('disc_created', d.title));
        }, function () { toast(t('up_fail') + t('colon') + d.title, 'error'); });
      });
    }, Promise.resolve());
  }

