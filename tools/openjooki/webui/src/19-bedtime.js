  /* ------------------------------------------------------------------ bedtime */
  function sleepInfo() { var s = S.bedtime.sleep; return s && typeof s === 'object' && s.mode ? s : null; }
  function sleepLeft() {
    var s = sleepInfo();
    if (!s || s.remaining === undefined || s.remaining === null) return null;
    return Math.max(0, Number(s.remaining) - (Date.now() - sleepStamp) / 1000);
  }
  function sleepText() {
    var s = sleepInfo();
    if (!s) return t('sleep_timer');
    return (s.mode === 'track' ? t('sleep_at_end') : t('sleep_left', fmtTime(sleepLeft()))) + (s.auto ? ' · ' + t('sleep_auto') : '');
  }
  function sleepShort() { var s = sleepInfo(); return !s ? '' : s.mode === 'track' ? t('sleep_track') : fmtTime(sleepLeft()); }
  function hm(m) { m = Number(m) || 0; var hh = Math.floor(m / 60) % 24, mm = m % 60; return (hh < 10 ? '0' : '') + hh + ':' + (mm < 10 ? '0' : '') + mm; }
  // the Jooki keeps UTC: tell it the family's time zone (Europe: summer time rule handled on the Jooki)
  function browserClock() {
    var y = new Date().getFullYear();
    var jan = new Date(y, 0, 1).getTimezoneOffset(), jul = new Date(y, 6, 1).getTimezoneOffset();
    var zone = '';
    try { zone = Intl.DateTimeFormat().resolvedOptions().timeZone || ''; } catch (e) {}
    if (jan !== jul && /^Europe\//.test(zone)) return { tzbase: -Math.max(jan, jul), tzdst: 'EU' };
    return { tzbase: -new Date().getTimezoneOffset(), tzdst: 'none' };
  }
  var clockSynced = false;
  function syncClock() {
    var c = S.bedtime.cfg;
    if (clockSynced || c.tzbase === undefined || !online) return;
    clockSynced = true;
    var b = browserClock();
    if (b.tzbase !== c.tzbase || b.tzdst !== c.tzdst) send('OJ_BEDTIME_SET', b);
  }
  function setBedtime(p) { var b = browserClock(); p.tzbase = b.tzbase; p.tzdst = b.tzdst; send('OJ_BEDTIME_SET', p); }
  function sleepPanel() {
    var s = sleepInfo();
    return h('div', { class: 'sleep' },
      h('div', { class: 'row small muted sleephead' }, icon('moon'), h('span', { 'data-sleep': '1' }, sleepText())),
      h('div', { class: 'chips' },
        [10, 20, 30, 45, 60].map(function (m) {
          return h('button', { class: 'toggle', 'data-sleep-min': String(m), onclick: function () { send('OJ_SLEEP', { minutes: m }); } }, t('sleep_min', m));
        }),
        h('button', { class: 'toggle' + (s && s.mode === 'track' ? ' on' : ''), 'data-sleep-min': 'track', onclick: function () { send('OJ_SLEEP', { mode: 'track' }); } }, t('sleep_track')),
        s ? h('button', { class: 'toggle', 'data-k': 'sleepoff', 'aria-label': t('sleep_cancel'), onclick: function () { send('OJ_SLEEP', { cancel: true }); } }, icon('x'), t('sleep_off')) : null));
  }
  var nightVolDrag = null;
  function nightPage() {
    var c = S.bedtime.cfg;
    if (c.start === undefined) return null; // firmware without bedtime
    var mv = nightVolDrag !== null ? nightVolDrag : Number(c.maxvol) || 100;
    var timers = [0, 10, 15, 20, 30, 45, 60];
    if (timers.indexOf(Number(c.timer)) < 0) { timers.push(Number(c.timer)); timers.sort(function (a, b) { return a - b; }); }
    function volLabel(v) { return v >= 100 ? t('night_nolimit') : v + ' %'; }
    var out = [sGroup(null, [sRow({ icon: 'moon', color: 'indigo', label: t('night_mode'), sw: true, on: c.enabled, k: 'nighton',
      onchange: function (e) { setBedtime({ enabled: e.target.checked }); } })], t('night_help'), 'bedcard')];
    if (!c.enabled) return out;
    out.push(sGroup(t('s_night_hours'), [
      sRow({ k: 'nightstatus', label: S.bedtime.night ? h('b', { class: 'accent-text' }, t('night_now')) : h('span', { class: 'muted' }, t('night_next', hm(c.start))) }),
      h('div', { class: 'timepair' },
        field(t('night_from'), { type: 'time', value: hm(c.start), 'data-k': 'nightstart',
          onchange: function (e) { if (e.target.value) setBedtime({ start: e.target.value }); } }),
        field(t('night_to'), { type: 'time', value: hm(c.stop), 'data-k': 'nightstop',
          onchange: function (e) { if (e.target.value) setBedtime({ stop: e.target.value }); } }))
    ], t('night_clock')));
    out.push(sGroup(t('s_night_during'), [
      sRow({ tag: 'label', label: t('night_timer'),
        right: h('select', { class: 'input mini', 'data-k': 'nighttimer', onchange: function (e) { e.target.blur(); setBedtime({ timer: Number(e.target.value) }); } },
          timers.map(function (m) { return h('option', { value: String(m), selected: Number(c.timer) === m ? 'selected' : null }, m ? t('sleep_min', m) : t('night_timer_none')); })) }),
      h('label', { class: 'srow noico col' }, h('span', { class: 'row', style: 'width:100%' }, h('span', { class: 'l1 grow' }, t('night_maxvol')),
          h('span', { class: 'val', 'data-nightvol': '1' }, volLabel(mv))),
        h('input', { class: 'range', type: 'range', min: '10', max: '100', step: '5', value: String(mv), 'data-k': 'nightvol', 'aria-label': t('night_maxvol'),
          oninput: function (e) { nightVolDrag = Number(e.target.value); var l = document.querySelector('[data-nightvol]'); if (l) l.textContent = volLabel(nightVolDrag); },
          onchange: function (e) { nightVolDrag = null; setBedtime({ maxvol: Number(e.target.value) }); } })),
      sRow({ label: t('night_dim'), sw: true, on: c.dim, k: 'nightdim', onchange: function (e) { setBedtime({ dim: e.target.checked }); } })
    ]));
    return out;
  }
