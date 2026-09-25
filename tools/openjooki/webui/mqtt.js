/* OpenJooki — minimal MQTT 3.1.1 client over WebSocket (QoS 0 only).
   No dependency, no network access other than the Jooki itself.
   API: const c = new MiniMqtt(url, {clientId, username, password, keepalive})
        c.onconnect = () => {}; c.onclose = (reason) => {}; c.onmessage = (topic, text) => {}
        c.connect(); c.subscribe(topic); c.publish(topic, text); c.close() */
(function (global) {
  'use strict';
  var enc = new TextEncoder();
  var dec = new TextDecoder('utf-8');

  function varint(n) {
    var out = [];
    do {
      var b = n % 128;
      n = Math.floor(n / 128);
      if (n > 0) b |= 0x80;
      out.push(b);
    } while (n > 0);
    return out;
  }
  function str(s) {
    var b = enc.encode(s);
    return [b.length >> 8, b.length & 255].concat(Array.from(b));
  }
  function packet(type, flags, body) {
    return new Uint8Array([(type << 4) | flags].concat(varint(body.length), body));
  }

  function MiniMqtt(url, opts) {
    opts = opts || {};
    this.url = url;
    this.clientId = opts.clientId || ('oj' + Math.random().toString(16).slice(2, 10));
    this.username = opts.username || null;
    this.password = opts.password || null;
    this.keepalive = opts.keepalive || 30;
    this.connected = false;
    this.buf = new Uint8Array(0);
    this.pid = 1;
    this.onconnect = function () {};
    this.onclose = function () {};
    this.onmessage = function () {};
  }

  MiniMqtt.prototype.connect = function () {
    var self = this;
    var ws;
    try {
      ws = new WebSocket(this.url, ['mqtt']);
    } catch (e) {
      setTimeout(function () { self.onclose('ws-error'); }, 0);
      return;
    }
    this.ws = ws;
    ws.binaryType = 'arraybuffer';
    var closed = false;
    function finish(reason) {
      if (closed) return;
      closed = true;
      self.connected = false;
      clearInterval(self.pingTimer);
      clearTimeout(self.ackTimer);
      try { ws.close(); } catch (e) {}
      self.onclose(reason);
    }
    this._finish = finish;
    ws.onopen = function () {
      var flags = 0x02; // clean session
      var payload = str(self.clientId);
      if (self.username) { flags |= 0x80; payload = payload.concat(str(self.username)); }
      if (self.password) { flags |= 0x40; payload = payload.concat(str(self.password)); }
      var body = str('MQTT').concat([4, flags, self.keepalive >> 8, self.keepalive & 255], payload);
      ws.send(packet(1, 0, body));
      self.ackTimer = setTimeout(function () { finish('timeout'); }, 5000);
    };
    ws.onmessage = function (ev) { self._data(new Uint8Array(ev.data)); };
    ws.onerror = function () { finish('ws-error'); };
    ws.onclose = function () { finish('closed'); };
  };

  MiniMqtt.prototype._data = function (chunk) {
    var b = new Uint8Array(this.buf.length + chunk.length);
    b.set(this.buf, 0);
    b.set(chunk, this.buf.length);
    this.buf = b;
    for (;;) {
      if (this.buf.length < 2) return;
      var mult = 1, len = 0, i = 1, byte;
      do {
        if (i >= this.buf.length) return; // incomplete length
        byte = this.buf[i++];
        len += (byte & 127) * mult;
        mult *= 128;
      } while (byte & 128);
      if (this.buf.length < i + len) return; // incomplete packet
      var head = this.buf[0];
      var body = this.buf.subarray(i, i + len);
      this.buf = this.buf.slice(i + len);
      this._packet(head >> 4, head & 15, body);
    }
  };

  MiniMqtt.prototype._packet = function (type, flags, body) {
    var self = this;
    if (type === 2) { // CONNACK
      clearTimeout(this.ackTimer);
      if (body[1] !== 0) { this._finish('refused-' + body[1]); return; }
      this.connected = true;
      this.pingTimer = setInterval(function () {
        if (self.connected) self._send(new Uint8Array([0xC0, 0]));
      }, this.keepalive * 1000 / 2);
      this.onconnect();
    } else if (type === 3) { // PUBLISH
      var tl = (body[0] << 8) | body[1];
      var topic = dec.decode(body.subarray(2, 2 + tl));
      var off = 2 + tl;
      var qos = (flags >> 1) & 3;
      if (qos > 0) off += 2;
      var text = dec.decode(body.subarray(off));
      try { this.onmessage(topic, text); } catch (e) { if (global.console) console.error(e); }
    }
    // SUBACK (9), PINGRESP (13): nothing to do
  };

  MiniMqtt.prototype._send = function (bytes) {
    if (this.ws && this.ws.readyState === 1) { this.ws.send(bytes); return true; }
    return false;
  };

  MiniMqtt.prototype.subscribe = function (topic) {
    this.pid = (this.pid % 65535) + 1;
    return this._send(packet(8, 2, [this.pid >> 8, this.pid & 255].concat(str(topic), [0])));
  };

  MiniMqtt.prototype.publish = function (topic, text) {
    if (!this.connected) return false;
    var body = str(topic).concat(Array.from(enc.encode(text)));
    return this._send(packet(3, 0, body));
  };

  MiniMqtt.prototype.close = function () {
    this._send(new Uint8Array([0xE0, 0]));
    if (this._finish) this._finish('user');
  };

  global.MiniMqtt = MiniMqtt;
})(window);
