  /* ------------------------------------------------------------------ toasts & modals */
  var toastBox;
  function toast(text, kind, action) {
    if (!toastBox) return;
    var el = h('div', { class: 'toast' + (kind === 'error' ? ' error' : ''), role: 'status' }, h('span', { class: 'grow' }, text));
    if (action) el.appendChild(h('button', { onclick: function () { action.fn(); el.remove(); } }, action.label));
    toastBox.appendChild(el);
    setTimeout(function () { el.remove(); }, action ? 6000 : 3500);
  }
  var modal = null; // {render: fn -> element, onclose}
  function openModal(m) { modal = m; renderModal(); }
  function closeModal() { var m = modal; modal = null; renderModal(); if (m && m.onclose) m.onclose(); }
  var modalRoot, modalRendering = false;   // true while a sheet is rebuilt: its inputs blur without meaning it
  function renderModal() {
    if (!modalRoot) return;
    var keep = captureFocus(modalRoot);
    modalRendering = true;
    try {
      modalRoot.innerHTML = '';
      if (!modal) { document.body.style.overflow = ''; return; }
      document.body.style.overflow = 'hidden';
      var sheet = h('div', { class: 'sheet' + (modal.cls ? ' ' + modal.cls : ''), role: 'dialog', 'aria-modal': 'true' }, modal.render());
      var ov = h('div', { class: 'overlay', onclick: function (e) { if (e.target === ov) closeModal(); } }, sheet);
      modalRoot.appendChild(ov);
      restoreFocus(modalRoot, keep, modal.autofocus);
    } finally { modalRendering = false; }
  }
  function confirmBox(title, text, okLabel, danger) {
    return new Promise(function (resolve) {
      var done = false;
      function fin(v) { if (done) return; done = true; modal = null; renderModal(); resolve(v); }
      openModal({
        onclose: function () { fin(false); },
        render: function () {
          return [h('h3', null, title), text ? h('p', { class: 'muted' }, text) : null,
            h('div', { class: 'foot' },
              h('button', { class: 'btn', onclick: function () { fin(false); } }, t('cancel')),
              h('button', { class: 'btn ' + (danger ? 'danger solid' : 'primary'), 'data-k': 'ok', onclick: function () { fin(true); } }, okLabel))];
        },
        autofocus: 'ok'
      });
    });
  }
  function captureFocus(root) {
    var a = document.activeElement;
    if (!a || !root.contains(a) || !a.getAttribute('data-k')) return null;
    return { k: a.getAttribute('data-k'), s: a.selectionStart, e: a.selectionEnd };
  }
  function restoreFocus(root, keep, auto) {
    var k = keep ? keep.k : auto;
    if (!k) return;
    var el = root.querySelector('[data-k="' + k + '"]');
    if (!el) return;
    el.focus({ preventScroll: true });
    if (keep && keep.s !== undefined && keep.s !== null && el.setSelectionRange) { try { el.setSelectionRange(keep.s, keep.e); } catch (e) {} }
  }
  // the usual end of a sheet: Cancel (closes it), then the one button that acts (opts: k, disabled)
  function modalFoot(okLabel, onOk, opts) {
    opts = opts || {};
    return h('div', { class: 'foot' }, h('button', { class: 'btn', onclick: closeModal }, t('cancel')),
      h('button', { class: 'btn primary', 'data-k': opts.k, disabled: opts.disabled, onclick: onOk }, okLabel));
  }
  // a labelled field: the label above, the input under it
  function field(label, attrs) { return h('label', { class: 'field' }, h('span', null, label), h('input', Object.assign({ class: 'input' }, attrs))); }
  // a 4-digit code (parent code): digits only, Enter submits
  function codeInput(label, k, value, set, enter) {
    return field(label, { 'data-k': k, inputmode: 'numeric', maxlength: '4', value: value, autocomplete: 'off',
      oninput: function (e) { set(e.target.value.replace(/\D/g, '')); }, onkeydown: function (e) { if (e.key === 'Enter') enter(); } });
  }

  document.addEventListener('keydown', function (e) { if (e.key === 'Escape' && modal) closeModal(); });

