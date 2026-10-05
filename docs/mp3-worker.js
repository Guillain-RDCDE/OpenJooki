/* OpenJooki: turns decoded audio into MP3, off the page's main thread (docs/studio.html; a copy of tools/openjooki/webui/mp3-worker.js).
   In:  { channels: [Float32Array, ...] (1 or 2, 44.1 kHz), rate: 44100, kbps: 192 | 256 | 320 }
   Out: { progress: 0..1 } now and then, then { mp3: Uint8Array } (MPEG frames, no tags) or { error }.
   The encoder is lamejs 1.2.1 (LGPL-3.0, lame.LICENSE.txt), served next to the page. */
/* global lamejs */
importScripts('lame.min.js');

var BLOCK = 1152 * 20;   // samples per encode call (a multiple of the MP3 frame)

function toInt16(f) {
  var out = new Int16Array(f.length);
  for (var i = 0; i < f.length; i++) {
    var s = f[i];
    out[i] = s >= 1 ? 32767 : s <= -1 ? -32768 : (s < 0 ? s * 32768 : s * 32767);
  }
  return out;
}

self.onmessage = function (e) {
  try {
    var ch = e.data.channels, kbps = e.data.kbps || 256, rate = e.data.rate || 44100;
    var stereo = ch.length > 1;
    var l = toInt16(ch[0]), r = stereo ? toInt16(ch[1]) : null;
    var enc = new lamejs.Mp3Encoder(stereo ? 2 : 1, rate, kbps);
    var parts = [], size = 0, n = l.length, lastTick = 0;
    for (var i = 0; i < n; i += BLOCK) {
      var a = l.subarray(i, Math.min(i + BLOCK, n));
      var buf = stereo ? enc.encodeBuffer(a, r.subarray(i, Math.min(i + BLOCK, n))) : enc.encodeBuffer(a);
      if (buf.length) { parts.push(new Uint8Array(buf)); size += buf.length; }
      var now = Date.now();
      if (now - lastTick > 250) { lastTick = now; self.postMessage({ progress: i / n }); }
    }
    var end = enc.flush();
    if (end.length) { parts.push(new Uint8Array(end)); size += end.length; }
    var mp3 = new Uint8Array(size), at = 0;
    parts.forEach(function (p) { mp3.set(p, at); at += p.length; });
    self.postMessage({ mp3: mp3 }, [mp3.buffer]);
  } catch (err) {
    self.postMessage({ error: String(err && err.message || err) });
  }
};
