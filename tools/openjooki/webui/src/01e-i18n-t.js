  var LANGS = [['en', 'English'], ['fr', 'Français'], ['nl', 'Nederlands']];
  function lsGet(k) { try { return localStorage.getItem(k); } catch (e) { return null; } }
  function lsSet(k, v) { try { localStorage.setItem(k, v); } catch (e) {} }
  // English by default; French or Dutch only when the browser itself is set to that language
  var lang = lsGet('oj.lang') || (navigator.language || 'en').slice(0, 2).toLowerCase();
  if (!T[lang]) lang = 'en';
  // Appearance, kept on this phone: 'auto' follows the phone, 'light' / 'dark' force it (app.css, html[data-theme])
  var THEMES = ['auto', 'light', 'dark'];
  var theme = lsGet('oj.theme');
  if (THEMES.indexOf(theme) < 0) theme = 'auto';
  function applyTheme() { if (theme === 'auto') document.documentElement.removeAttribute('data-theme'); else document.documentElement.setAttribute('data-theme', theme); }
  applyTheme();
  function setTheme(v) { theme = v; lsSet('oj.theme', v); applyTheme(); render(); }
  function t(k) {
    var v = T[lang][k];
    if (v === undefined) v = T.fr[k];   // French is the table kept complete; a hole then shows the key itself, so it is seen
    if (typeof v === 'function') return v.apply(null, Array.prototype.slice.call(arguments, 1));
    return v === undefined ? k : v;
  }

