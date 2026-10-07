  /* ------------------------------------------------------------------ the story studio */
  // A story is read aloud on the project's site, in a tab this page opens: a page served by the Jooki
  // (http) has no right to the microphone, and a page of the site (https) has no right to write to the
  // Jooki. So the studio hands the finished story back from tab to tab (docs/studio.html, "oj-story").
  // A story can also come as one file (the studio's "Send or save the story": a zip with the pages, the
  // cover and story.json), opened here with "Open a story" (08c-story-file.js). Both end in storyArrives.
  var STUDIO = 'https://guillain-rdcde.github.io', storySeen = {};
  function openStudio() { window.open(STUDIO + '/OpenJooki/studio.html#jooki=' + encodeURIComponent(location.origin)); }
  // The story becomes a new playlist, an audiobook, its pages queued in order; then the question of the
  // token. told(ok) hears the outcome (the studio waits for it). This tab may have slept behind the
  // studio's for a whole book: its connection can look open and be dead, so the Jooki is asked to answer
  // first (whenAnswering), and a playlist that never shows up is asked for once more.
  function storyArrives(title, files, cover, told) {
    title = String(title || '').slice(0, 100) || t('story_default');
    // the same story sent twice (a second tap in the studio) is added once, and the studio hears of it each time
    var sig = title + '/' + files.map(function (f) { return f.size; }).join(',');
    var seen = storySeen[sig];
    if (seen && Date.now() - seen.at < 120000) { if (told) { if (seen.done) told(true); else seen.waiting.push(told); } return; }
    seen = storySeen[sig] = { at: Date.now(), done: false, waiting: told ? [told] : [] };
    var before = Object.keys(pls());
    function tell(ok) { var w = seen.waiting; seen.waiting = []; w.forEach(function (f) { f(ok); }); }
    function fail() { delete storySeen[sig]; toast(t('up_fail') + t('colon') + title, 'error'); tell(false); }
    function ask(again) {
      whenAnswering(function () {
        // asked once already: the Jooki may have made it and the answer got lost on the way
        var made = again ? Object.keys(pls()).filter(function (k) { return before.indexOf(k) < 0 && (pls()[k] || {}).title === title; })[0] : null;
        (made ? Promise.resolve(made) : createPlaylist(title, true)).then(function (id) {
          enqueue(files, id);
          seen.done = true; tell(true);
          toast(t('story_got', title));
          go('#/p/' + encodeURIComponent(id));
          charPickerModal(Object.assign({ id: id }, pls()[id]), { story: true, cover: cover || null });
        }, function () { if (again) fail(); else ask(true); });
      }, fail);
    }
    ask(false);
  }
  window.addEventListener('message', function (e) {
    var d = e.data, from = e.source;
    if (e.origin !== STUDIO || !d || d.type !== 'oj-story' || !Array.isArray(d.files)) return;
    var files = d.files.filter(function (f) { return f && f.blob instanceof Blob && f.blob.size; })
      .map(function (f) { return new File([f.blob], String(f.name || 'page.mp3').slice(0, 120), { type: 'audio/mpeg' }); });
    if (!files.length) return;
    var cover = d.cover && d.cover.blob instanceof Blob && d.cover.blob.size ? d.cover.blob : null;
    storyArrives(d.title, files, cover, function (ok) {
      // the studio closes itself on 'got', keeps the story on 'failed'; its tab may be gone: the story is here anyway
      try { from.postMessage({ type: ok ? 'oj-story-got' : 'oj-story-failed' }, STUDIO); } catch (err) {}
    });
  });

  // ---- a token put on the Jooki while a sheet waits for it ----------------
  // What the Jooki tells about its tokens: state.nfc carries the token on it right now (a character, a
  // flat token), and a foreign tag (an NFC sticker) only bumps its `seen` count in db.tokens. A watch
  // remembers both as they were, and calls back with the first character that changes. stop() ends it.
  function watchToken(cb) {
    var seen = {}, nfc = isUserChar(S.nfc.starId) ? S.nfc.starId : null, on = true;
    Object.keys(S.db.tokens).forEach(function (k) { seen[k] = Number((S.db.tokens[k] || {}).seen) || 0; });
    function fresh() {
      var now = S.nfc.starId;
      if (isUserChar(now) && now !== nfc) return now;
      var hit = null;
      Object.keys(S.db.tokens).forEach(function (k) {
        var tk = S.db.tokens[k] || {};
        if (!hit && isUserChar(tk.starId) && (Number(tk.seen) || 0) > (seen.hasOwnProperty(k) ? seen[k] : 0)) hit = tk.starId;
      });
      return hit;
    }
    waiters.push(function () {
      if (!on) return true;
      var s = fresh();
      if (!s) return false;
      on = false; cb(s); return true;
    });
    return { stop: function () { on = false; } };
  }

  // ---- the cover of the book becomes the token's picture ------------------
  // The middle of the cover, in a circle, 128 px, like a photo from the editor (16-token-photo.js);
  // only a token of its own (a flat token, an NFC tag) carries a picture: a character has its figure.
  function coverToToken(starId, blob, done) {
    var own = ownParts(starId);
    if (!own || !blob || !window.createImageBitmap) { done(false); return; }
    var tag = own.uid, OUT = 128;
    createImageBitmap(blob).then(function (img) {
      var s = Math.min(img.width, img.height), o = document.createElement('canvas');
      o.width = OUT; o.height = OUT;
      var c = o.getContext('2d');
      c.beginPath(); c.arc(OUT / 2, OUT / 2, OUT / 2, 0, Math.PI * 2); c.clip();
      c.drawImage(img, (img.width - s) / 2, (img.height - s) / 2, s, s, 0, 0, OUT, OUT);
      o.toBlob(function (png) {
        if (!png) { done(false); return; }
        uploadBlob(png, 'tok_' + tag + '.png', function (uploadId) {
          if (!uploadId) { done(false); return; }
          var before = (S.db.tokens[tag] || {}).image || '';
          send('TOKEN_SET_IMAGE', { tagId: tag, uploadId: uploadId });
          var tries = 0, tm = setInterval(function () {
            var now = (S.db.tokens[tag] || {}).image || '';
            if (now && now !== before) { clearInterval(tm); done(true); }
            else if (++tries > 60) { clearInterval(tm); done(false); }
          }, 250);
        });
      }, 'image/png');
    }, function () { done(false); });
  }

