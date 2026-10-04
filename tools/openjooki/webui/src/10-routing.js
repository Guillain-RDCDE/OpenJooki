  /* ------------------------------------------------------------------ routing */
  function route() {
    var hs = (location.hash || '#/').replace(/^#/, '');
    var parts = hs.split('/').filter(Boolean).map(function (x) { try { return decodeURIComponent(x); } catch (e) { return x; } });
    return { name: parts[0] || 'playlists', arg: parts[1] || null };
  }
  function go(hash) { if (location.hash !== hash) location.hash = hash; else render(); }
  window.addEventListener('hashchange', function () { ui.sel = {}; ui.search = ''; ui.editTitle = null; window.scrollTo(0, 0); render(); });

  /* ------------------------------------------------------------------ UI state */
  var ui = { search: '', sel: {}, editTitle: null, dragging: false };

