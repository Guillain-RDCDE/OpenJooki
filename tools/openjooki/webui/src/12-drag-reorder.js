  /* drag & drop reorder (mouse + touch through pointer events) */
  var drag = null;
  function startDrag(e, playlistId) {
    var li = e.target.closest('li');
    if (!li) return;
    e.preventDefault();
    var ul = li.parentNode;
    var items = Array.prototype.slice.call(ul.children);
    var from = items.indexOf(li);
    var rect = li.getBoundingClientRect();
    drag = { li: li, from: from, to: from, startY: e.clientY, h: rect.height, id: playlistId, items: items };
    ui.dragging = true;
    li.classList.add('dragging');
    try { li.setPointerCapture(e.pointerId); } catch (x) {}
    li.addEventListener('pointermove', onDragMove);
    li.addEventListener('pointerup', onDragEnd);
    li.addEventListener('pointercancel', onDragEnd);
  }
  function onDragMove(e) {
    if (!drag) return;
    var dy = e.clientY - drag.startY;
    drag.li.style.transform = 'translateY(' + dy + 'px)';
    var to = Math.max(0, Math.min(drag.items.length - 1, drag.from + Math.round(dy / drag.h)));
    drag.to = to;
    drag.items.forEach(function (it, i) {
      if (it === drag.li) return;
      var shift = 0;
      if (drag.from < to && i > drag.from && i <= to) shift = -drag.h;
      if (drag.from > to && i < drag.from && i >= to) shift = drag.h;
      it.style.transform = shift ? 'translateY(' + shift + 'px)' : '';
      it.style.transition = 'transform .12s';
    });
    var vh = window.innerHeight;
    if (e.clientY < 80) window.scrollBy(0, -12); else if (e.clientY > vh - 150) window.scrollBy(0, 12);
  }
  function onDragEnd() {
    if (!drag) return;
    var d = drag; drag = null; ui.dragging = false;
    d.items.forEach(function (it) { it.style.transform = ''; it.style.transition = ''; });
    d.li.classList.remove('dragging');
    d.li.removeEventListener('pointermove', onDragMove);
    d.li.removeEventListener('pointerup', onDragEnd);
    d.li.removeEventListener('pointercancel', onDragEnd);
    if (d.to !== d.from && pls()[d.id]) {
      var nt = arr(pls()[d.id].tracks).slice();
      var x = nt.splice(d.from, 1)[0];
      nt.splice(d.to, 0, x);
      optimisticTracks(d.id, nt);
      send('PLAYLIST_UPDATE', { playlist: { id: d.id, tracks: nt } });
    } else render();
  }

