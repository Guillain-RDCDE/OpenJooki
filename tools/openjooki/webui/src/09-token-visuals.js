  /* ------------------------------------------------------------------ token visuals */
  function tokVisual(starId, cls, live) {
    var c = charInfo(starId);
    var el = h('div', { class: 'tok ' + (cls || '') + (live ? ' live' : ''), title: charName(starId) });
    if (!starId) { el.className += ' none'; el.appendChild(icon('token')); return el; }
    var own = ownParts(starId), ftk = own && S.db.tokens[own.uid], src = ftk && tokImgSrc(ftk.image);
    if (src) {   // its picture: from the library, or a photo (a 128 px PNG on the Jooki, see tokenImageEditor)
      var pic = h('img', { src: src, alt: '' });
      pic.onerror = function () { pic.replaceWith(h('span', { class: 'letter' }, (charName(starId) || '?').charAt(0))); };
      el.appendChild(pic); return el;
    }
    if (own && own.kind !== 'tag') c = charInfo(own.kind === 'flat' ? 'Jooki.Flat' : 'Jooki.ThankYou');   // no picture yet: the round token
    if (c.art && c.art.charAt(0) === '#') el.appendChild(h('div', { class: 'disc', style: 'background:' + c.art }));
    else if (c.art) {
      var img = h('img', { src: MEDIA + c.art, alt: '' });
      img.onerror = function () { img.replaceWith(h('span', { class: 'letter' }, (charName(starId) || '?').charAt(0))); };
      el.appendChild(img);
    } else el.appendChild(h('span', { class: 'letter' }, (charName(starId) || '?').charAt(0)));
    return el;
  }

