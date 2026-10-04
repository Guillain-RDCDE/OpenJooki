  /* ------------------------------------------------------------------ characters */
  var MEDIA = '/static/media/';
  // id, name in fr / en / nl (every page language: a missing column showed French to Dutch families), picture or colour
  var CHARS = [
    ['Jooki.Dragon', 'Dragon', 'Dragon', 'Draak', 'dragon.cffed3d7.png'],
    ['Jooki.Fox', 'Renard', 'Fox', 'Vos', 'fox.ac721aec.png'],
    ['Jooki.Ghost', 'Fantôme', 'Ghost', 'Spook', 'ghost.c2a43882.png'],
    ['Jooki.Knight', 'Chevalier', 'Knight', 'Ridder', 'knight.dc50962b.png'],
    ['Jooki.Whale', 'Baleine', 'Whale', 'Walvis', 'whale.da72da11.png'],
    ['Jooki.Black.Dragon', 'Dragon noir', 'Black dragon', 'Zwarte draak', 'dragon-black.27a71b2c.png'],
    ['Jooki.Black.Fox', 'Renard noir', 'Black fox', 'Zwarte vos', 'fox-black.7d23b82c.png'],
    ['Jooki.Black.Knight', 'Chevalier noir', 'Black knight', 'Zwarte ridder', 'knight-black.d995170a.png'],
    ['Jooki.Black.Whale', 'Baleine noire', 'Black whale', 'Zwarte walvis', 'whale-black.74e936a9.png'],
    ['Jooki.White.Dragon', 'Dragon blanc', 'White dragon', 'Witte draak', 'dragon-white.921a8110.png'],
    ['Jooki.White.Fox', 'Renard blanc', 'White fox', 'Witte vos', 'fox-white.8f5e5c27.png'],
    ['Jooki.White.Knight', 'Chevalier blanc', 'White knight', 'Witte ridder', 'knight-white.b0dd9a37.png'],
    ['Jooki.White.Whale', 'Baleine blanche', 'White whale', 'Witte walvis', 'whale-white.218d88b9.png'],
    ['G2.Orange', 'Jeton orange', 'Orange token', 'Oranje figuurtje', '#f28b24'],
    ['G2.DarkBlue', 'Jeton bleu foncé', 'Dark blue token', 'Donkerblauw figuurtje', '#23408e'],
    ['G2.Turquoise', 'Jeton turquoise', 'Turquoise token', 'Turquoise figuurtje', '#22b2ad'],
    ['G2.Yellow', 'Jeton jaune', 'Yellow token', 'Geel figuurtje', '#f4c21b'],
    ['G2.Red', 'Jeton rouge', 'Red token', 'Rood figuurtje', '#d7362c'],
    ['G2.Purple', 'Jeton violet', 'Purple token', 'Paars figuurtje', '#7c4db4'],
    ['G2.Green', 'Jeton vert', 'Green token', 'Groen figuurtje', '#3ba555'],
    ['G2.Pink', 'Jeton rose', 'Pink token', 'Roze figuurtje', '#ec6ea6'],
    ['Jooki.Flat', 'Jeton plat', 'Flat token', 'Plat figuurtje', 'flat.5534d75d.png'],
    ['Jooki.ThankYou', 'Jeton Merci', 'Thank-you token', 'Bedankt-figuurtje', 'flat.5534d75d.png']
  ];
  var CHAR = {};
  CHARS.forEach(function (c, i) { CHAR[c[0]] = { id: c[0], fr: c[1], en: c[2], nl: c[3], art: c[4], order: i }; });
  function charInfo(id) {
    if (CHAR[id]) return CHAR[id];
    return { id: id, fr: id || '?', en: id || '?', nl: id || '?', art: null, order: 999 };
  }
  // A token that is a character of its own (docs/23 §4): a foreign NFC tag "tag.<uid>" (amiibo,
  // sticker), a flat token "flat.<uid>" or a Thank-you token "thanks.<uid>" (one code for all of
  // them). Named by its nickname, else its kind + the end of its id; it can carry a picture.
  var OWN = { tag: 'nfc_tag', flat: 'flat_tok', thanks: 'thanks_tok' };
  function ownParts(id) { var m = /^(tag|flat|thanks)\.([0-9A-Fa-f]{14})$/.exec(id || ''); return m ? { kind: m[1], uid: m[2] } : null; }
  function ownUid(id) { var o = ownParts(id); return o ? o.uid : null; }
  function foreignUid(id) { var o = ownParts(id); return o && o.kind === 'tag' ? o.uid : null; }   // the ESP32 never says it was taken off
  function charName(id) {
    var o = ownParts(id);
    // the flat tokens of one batch differ only by the start of their id (04 03AA 6AE74C81, 04 333F 6AE74C81…)
    if (o) { var tk = S.db.tokens[o.uid]; return (tk && tk.name) || (t(OWN[o.kind]) + ' ' + (o.kind === 'tag' ? o.uid.slice(-4) : o.uid.slice(2, 6))); }
    var c = charInfo(id); return c[lang] || c.fr;
  }
  // a token's picture: "lib:<id>" = the page's library (tokimg/), else the photo's own address
  function tokImgSrc(v) {
    v = String(v || '');
    if (/^lib:[a-z0-9_]+$/.test(v)) return '/tokimg/' + v.slice(4) + '.webp';
    return /^\/artwork\/tok_[0-9A-Fa-f]+\.png\?v=\d+$/.test(v) ? v : null;
  }
  function isUserChar(id) { return !!id && id.indexOf('sys.') !== 0 && id.indexOf('test.') !== 0; }

