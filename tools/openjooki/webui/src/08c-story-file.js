  /* ------------------------------------------------------------------ a story as one file */
  // Jookistory's "Send or save the story" gives one zip: "01 Title.mp3", "02 Title.mp3"…, cover.jpg and
  // story.json ({jookistory: 1, title, pages…}). Sent by message from far away, it is opened here:
  // "Open a story" on the playlists page, or picked with "Add files" in a playlist. The zip is read
  // in the browser: its files are stored as they are (any phone opens it), a zip made again on a
  // computer may hold them deflated, which the browser inflates itself.
  var ZIP_NAME = /\.zip$/i;
  function isZip(f) { return ZIP_NAME.test(f.name) || f.type === 'application/zip' || f.type === 'application/x-zip-compressed'; }
  function zipU16(b, i) { return b[i] | (b[i + 1] << 8); }
  // file -> Promise of [{name, blob}] (folders, Mac leftovers and hidden files left out)
  function readZip(file) {
    return readBytes(file, 0, file.size).then(function (b) {
      var n = b.length, eocd = -1;
      for (var i = n - 22; i >= 0 && i >= n - 66000; i--) if (b[i] === 0x50 && b[i + 1] === 0x4b && b[i + 2] === 0x05 && b[i + 3] === 0x06) { eocd = i; break; }
      if (eocd < 0) throw new Error('not a zip');
      var count = zipU16(b, eocd + 10), at = u32le(b, eocd + 16), out = [];
      for (var k = 0; k < count; k++) {
        if (u32le(b, at) !== 0x02014b50) break;
        var method = zipU16(b, at + 10), csize = u32le(b, at + 20), usize = u32le(b, at + 24), nl = zipU16(b, at + 28), el = zipU16(b, at + 30), cl = zipU16(b, at + 32), local = u32le(b, at + 42);
        var name = utf8At(b, at + 46, nl);
        at += 46 + nl + el + cl;
        var base = name.split('/').pop();
        if (!base || name.indexOf('__MACOSX/') === 0 || base.charAt(0) === '.' || name.slice(-1) === '/') continue;
        var start = local + 30 + zipU16(b, local + 26) + zipU16(b, local + 28);
        var data = b.subarray(start, start + csize);
        if (method === 0) out.push({ name: base, blob: new Blob([data]) });
        else if (method === 8 && window.DecompressionStream) out.push({ name: base, blob: new Response(new Blob([data]).stream().pipeThrough(new DecompressionStream('deflate-raw'))).blob(), size: usize });
        else throw new Error('unsupported');
      }
      return Promise.all(out.map(function (e) { return Promise.resolve(e.blob).then(function (blob) { return { name: e.name, blob: blob }; }); }));
    });
  }
  // the story in the zip: its title, its pages as Files in order, its cover; null when there is no page
  function storyOfZip(entries) {
    var meta = null, pages = [], cover = null;
    return Promise.all(entries.map(function (e) {
      if (e.name.toLowerCase() === 'story.json') return readBytes(e.blob, 0, Math.min(e.blob.size, 10000)).then(function (b) { try { meta = JSON.parse(utf8At(b, 0, b.length)); } catch (err) { meta = null; } });
      if (/^cover\.(jpe?g|png)$/i.test(e.name)) cover = e.blob;
      else if (AUDIO_EXT.test(e.name) && e.blob.size > 5000) pages.push(new File([e.blob], e.name, { type: 'audio/mpeg' }));
      return null;
    })).then(function () {
      if (!pages.length) return null;
      pages.sort(function (a, b) { return collator().compare(a.name, b.name); });
      var m = /^\d\d (.+)\.\w+$/.exec(pages[0].name);
      var title = meta && typeof meta.title === 'string' && meta.title.trim() ? meta.title.trim() : m ? m[1] : cleanTitle(pages[0].name);
      return { title: title, pages: pages, cover: cover };
    });
  }
  // a zip picked or dropped: into that playlist (an audiobook from then on), or as a new playlist named after the story
  function openStoryFile(file, playlistId) {
    readZip(file).then(storyOfZip).then(function (st) {
      if (!st) { toast(t('story_file_bad') + t('colon') + file.name, 'error'); return; }
      if (playlistId) {
        var p = pls()[playlistId];
        if (p && !p.audiobook) { send('PLAYLIST_UPDATE', { playlist: { id: playlistId, audiobook: true } }); toast(t('story_book')); }
        enqueue(st.pages, playlistId);
      } else storyArrives(st.title, st.pages, st.cover);
    }, function () { toast(t('story_file_bad') + t('colon') + file.name, 'error'); });
  }
  // the files of a pick or a drop, their zips taken out and opened as stories; the rest comes back
  function takeStoryFiles(files, playlistId) {
    var rest = [];
    Array.prototype.forEach.call(files, function (f) { if (isZip(f)) openStoryFile(f, playlistId); else rest.push(f); });
    return rest;
  }
  // the card on the playlists page: a file picker that looks like "New playlist"
  function storyFileCard() {
    var inp = h('input', { type: 'file', accept: '.zip,application/zip', class: 'sr', 'aria-hidden': 'true', tabindex: '-1', 'data-k': 'storyfile',
      onchange: function () { if (inp.files && inp.files.length) takeStoryFiles(inp.files, null); inp.value = ''; } });
    return h('label', { class: 'card pl newpl', role: 'button', tabindex: '0', 'data-k': 'storyopen',
      onkeydown: function (e) { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); inp.click(); } } },
      icon('upload'), t('story_open'), h('div', { class: 'small', style: 'font-weight:400' }, t('story_open_sub')), inp);
  }

