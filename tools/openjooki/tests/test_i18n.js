// Translation contracts and startup language selection; run with node, no network or browser.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const root = path.resolve(__dirname, '../webui');
const src = path.join(root, 'src');
function load(browserLanguage, saved) {
  const storage = Object.assign({}, saved);
  const ctx = { navigator: { language: browserLanguage }, localStorage: {
    getItem: k => storage[k] || null, setItem: (k, v) => { storage[k] = v; }
  }, document: { documentElement: { removeAttribute() {}, setAttribute() {} } }, render() {} };
  vm.createContext(ctx);
  for (const file of fs.readdirSync(src).filter(f => /^01.*\.js$/.test(f)).sort())
    vm.runInContext(fs.readFileSync(path.join(src, file), 'utf8'), ctx);
  return ctx;
}
const c = load('de-DE');
assert.equal(c.lang, 'de');
assert.equal(load('de-AT').lang, 'de');
assert.equal(load('de-CH').lang, 'de');
assert.equal(load('es-ES').lang, 'en');
assert.equal(load('de-DE', { 'oj.lang': 'nl' }).lang, 'nl');
assert(c.LANGS.some(l => l[0] === 'de' && l[1] === 'Deutsch'));
const keys = Object.keys(c.T.fr).sort();
for (const lang of ['en', 'nl', 'de']) {
  assert.deepEqual(Object.keys(c.T[lang]).sort(), keys, lang + ' keys');
  for (const key of keys) {
    const value = c.T[lang][key], original = c.T.fr[key];
    assert.equal(typeof value, typeof original, lang + '.' + key);
    if (typeof value === 'function') {
      assert.equal(value.length, original.length, lang + '.' + key + ' arguments');
      const args = Array.from({ length: value.length }, (_, i) => 'MARKER' + i);
      for (const arg of args) assert(value(...args).includes(arg), lang + '.' + key + ' placeholder ' + arg);
      for (const n of [0, 1, 2]) assert.equal(typeof value(n, 'title'), 'string');
    } else if (Array.isArray(value)) assert.equal(value.length, original.length);
    else assert(value.length > 0);
  }
}
assert.equal(c.T.de.n_tokens(1), '1 Figur');
assert.equal(c.T.de.n_tokens(2), '2 Figuren');
assert.equal(c.T.de.lib_n(1), '1 Bild');
assert.equal(c.T.de.lib_n(2), '2 Bilder');
vm.runInContext(fs.readFileSync(path.join(src, '02-characters.js'), 'utf8'), c);
assert.equal(c.charName('Jooki.Fox'), 'Fuchs');
assert.equal(c.CHAR['G2.Pink'].art, '#ec6ea6');
for (const char of Object.values(c.CHAR)) for (const lang of ['en', 'fr', 'nl', 'de']) assert(char[lang]);
const idx = JSON.parse(fs.readFileSync(path.join(root, 'tokimg/index.json')));
for (const cat of idx.cats) assert(cat[1].de);
for (const img of idx.img) assert(img[6] && img[5], img[0]);
for (const [id, term] of [['cat', 'katze'], ['rocket', 'rakete'], ['sleeping_face', 'schlafen']])
  assert(idx.img.find(r => r[0] === id)[5].includes(term), term);
assert(fs.readFileSync(path.join(root, 'index.html'), 'utf8').includes('<span lang="de">Diese Seite benötigt JavaScript.</span>'));
console.log('PASS four language tables, placeholders, plurals, German detection, characters and 659 picture names/search terms');
