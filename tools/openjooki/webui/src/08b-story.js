  /* ------------------------------------------------------------------ the story studio */
  // A story is read aloud on the project's site, in a tab this page opens: a page served by the Jooki
  // (http) has no right to the microphone, and a page of the site (https) has no right to write to the
  // Jooki. So the studio hands the finished story back from tab to tab (docs/studio.html, "oj-story").
  var STUDIO = 'https://guillain-rdcde.github.io', storySeen = {};
  function openStudio() { window.open(STUDIO + '/OpenJooki/studio.html#jooki=' + encodeURIComponent(location.origin)); }
  // this tab slept behind the studio's: the connection to the Jooki comes back a moment after it is shown again
  function whenOnline(fn, tries) {
    if (online) fn();
    else if (tries > 0) setTimeout(function () { whenOnline(fn, tries - 1); }, 500);
    else toast(t('offline'), 'error');
  }
  window.addEventListener('message', function (e) {
    var d = e.data;
    if (e.origin !== STUDIO || !d || d.type !== 'oj-story' || !Array.isArray(d.files)) return;
    var title = String(d.title || '').slice(0, 100) || t('story_default');
    var files = d.files.filter(function (f) { return f && f.blob instanceof Blob && f.blob.size; })
      .map(function (f) { return new File([f.blob], String(f.name || 'page.mp3').slice(0, 120), { type: 'audio/mpeg' }); });
    if (!files.length) return;
    try { e.source.postMessage({ type: 'oj-story-got' }, STUDIO); } catch (err) { /* the studio's tab is gone: the story is here anyway */ }
    // the same story sent twice (a second tap in the studio) is added once
    var sig = title + '/' + files.map(function (f) { return f.size; }).join(',');
    if (storySeen[sig] && Date.now() - storySeen[sig] < 120000) return;
    storySeen[sig] = Date.now();
    whenOnline(function () {
      createPlaylist(title).then(function (id) {
        send('PLAYLIST_UPDATE', { playlist: { id: id, audiobook: true } });
        enqueue(files, id);
        toast(t('story_got', title));
        go('#/p/' + encodeURIComponent(id));
      }, function () { delete storySeen[sig]; toast(t('up_fail') + t('colon') + title, 'error'); });
    }, 60);
  });

