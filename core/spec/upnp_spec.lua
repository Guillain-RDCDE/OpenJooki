local upnp = require("services.upnp")
local net = require("adapters.upnp")
local playback = require("services.playback")

-- The UPnP player (#29): the pure parts of services.upnp (descriptions, SOAP, what the apps see,
-- what the Jooki does) and of adapters.upnp (SSDP packets, GENA headers), without a socket.

local SONG = "http://192.168.1.20:9790/minimserver/*/music/song.flac"
local DIDL = '<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:dc="http://purl.org/dc/elements/1.1/" '
  .. 'xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/"><item id="1" parentID="0" restricted="1">'
  .. "<dc:title>L&apos;&#233;t&#xE9; &amp; co</dc:title><dc:creator>Anne</dc:creator><upnp:album>Songs</upnp:album>"
  .. "<upnp:albumArtURI>http://192.168.1.20/a.jpg</upnp:albumArtURI><upnp:class>object.item.audioItem.musicTrack</upnp:class>"
  .. '<res protocolInfo="http-get:*:audio/flac:DLNA.ORG_OP=01" duration="0:03:25.500">' .. SONG .. "</res></item></DIDL-Lite>"

local function envelope(action, stype, args)
  local a = {}
  for _, kv in ipairs(args) do a[#a + 1] = "<" .. kv[1] .. ">" .. kv[2] .. "</" .. kv[1] .. ">" end
  return '<?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
    .. "<s:Body><u:" .. action .. ' xmlns:u="' .. stype .. '">' .. table.concat(a) .. "</u:" .. action .. "></s:Body></s:Envelope>"
end

local function doc_with(opts)
  opts = opts or {}
  return {
    config = { data_dir = "/d", system_dir = "/sys" },
    device = { hostname = "jooki", wifi_mac = "A8:EE:C6:04:26:E8", openjooki = "2.4.21" },
    net = { ip = "192.168.1.11" },
    library = { playlists = {}, tracks = {}, tokens = {} },
    audiocfg = { volume = opts.volume or 40, upnp = opts.off ~= true },
    playback = opts.playback or { state = "idle" },
    playback_int = {},
    upnp = opts.upnp,
  }
end

local function apply(doc, r)
  for k, v in pairs((r or {}).state or {}) do doc[k] = v end
  return doc
end

local function topics(r)
  local out = {}
  for _, c in ipairs((r or {}).commands or {}) do
    if c.kind == "bus.publish" then out[#out + 1] = c.topic:gsub("^/j/audio/out/", "") .. " " .. c.payload
    elseif c.kind == "host.volume" then out[#out + 1] = "volume " .. c.percent
    elseif c.kind == "files.write" then out[#out + 1] = "write " .. c.path end
  end
  table.sort(out)
  return out
end

local function out_of(r)
  local t = {}
  for _, kv in ipairs(r.out or {}) do t[kv[1]] = kv[2] end
  return t
end

--- An app's request, as the network side handles it: the answer, then its event on the Jooki.
local function act(doc, key, action, args)
  local r = upnp.request(doc, key, action, args)
  if r.event then
    local h = upnp.on_action(doc, r.event)
    apply(doc, h)
    r.handled = h
  end
  return r
end

describe("services.upnp — text and time", function()
  it("decodes entities, numeric references (to UTF-8) and CDATA; encodes the five", function()
    assert_eq(upnp.unescape("a &amp; b &lt;c&gt; &quot;d&quot; &apos;e&apos;"), "a & b <c> \"d\" 'e'")
    assert_eq(upnp.unescape("&#233;&#xE9;&#8364;"), "\195\169\195\169\226\130\172")
    assert_eq(upnp.unescape("<![CDATA[<b>&</b>]]>"), "<b>&</b>")
    assert_eq(upnp.escape('<a href="x">&</a>'), "&lt;a href=&quot;x&quot;&gt;&amp;&lt;/a&gt;")
  end)

  it("reads H:MM:SS[.F], MM:SS and seconds; writes H:MM:SS", function()
    assert_eq(upnp.parse_hms("0:03:25.500"), 205500)
    assert_eq(upnp.parse_hms("01:00:00"), 3600000)
    assert_eq(upnp.parse_hms("3:05"), 185000)
    assert_eq(upnp.parse_hms("42"), 42000)
    assert_nil(upnp.parse_hms("soon"))
    assert_eq(upnp.hms(205500), "0:03:25")
    assert_eq(upnp.hms(3725000), "1:02:05")
    assert_eq(upnp.hms(-5), "0:00:00")
  end)
end)

describe("services.upnp — the Jooki on the network", function()
  it("has a UDN made from its Wi-Fi address, the same at every start; without one, from its id", function()
    assert_eq(upnp.udn(doc_with()), "uuid:4a6f6f6b-6900-4f70-656e-a8eec60426e8")
    local d = doc_with(); d.device.wifi_mac = nil; d.device.id = "jooki2-0426E8"
    assert_match(upnp.udn(d), "^uuid:4a6f6f6b%-6900%-4f70%-656e%-%x%x%x%x%x%x%x%x%x%x%x%x$")
    assert_eq(upnp.udn(d), upnp.udn(d))
  end)

  it("describes a MediaRenderer named after the Jooki, with its three services", function()
    local x = upnp.description(doc_with())
    assert_match(x, "<deviceType>urn:schemas%-upnp%-org:device:MediaRenderer:1</deviceType>")
    assert_match(x, "<friendlyName>Jooki</friendlyName>")
    assert_match(x, "<UDN>uuid:4a6f6f6b%-6900%-4f70%-656e%-a8eec60426e8</UDN>")
    for _, k in ipairs({ "avt", "rc", "cm" }) do
      assert_match(x, "<SCPDURL>/upnp/" .. k .. ".xml</SCPDURL><controlURL>/upnp/ctl/" .. k .. "</controlURL><eventSubURL>/upnp/evt/" .. k .. "</eventSubURL>")
    end
    local d = doc_with(); d.device.hostname = "jooki2-0426e8"
    assert_match(upnp.description(d), "<friendlyName>Jooki2%-0426e8</friendlyName>")
  end)

  it("lists every action's arguments against a state variable it declares", function()
    for _, key in ipairs({ "avt", "rc", "cm" }) do
      local x = upnp.scpd(key)
      for _, a in ipairs(upnp.ACTIONS[key]) do
        assert_match(x, "<action><name>" .. a[1] .. "</name>")
        for _, g in ipairs(a[2]) do assert_match(x, "<name>" .. g[3] .. "</name><dataType>", key .. " " .. a[1] .. " " .. g[3]) end
      end
    end
    assert_nil(upnp.scpd("nope"))
    assert_match(upnp.scpd("rc"), "<name>Volume</name><dataType>ui2</dataType><allowedValueRange><minimum>0</minimum><maximum>100</maximum>")
  end)

  it("tells the apps the formats its player reads: MP3, FLAC, Ogg, WAV (no AAC)", function()
    assert_match(upnp.SINK_PROTOCOLS, "http%-get:%*:audio/mpeg:%*")
    assert_match(upnp.SINK_PROTOCOLS, "http%-get:%*:audio/flac:%*")
    assert_true(upnp.SINK_PROTOCOLS:find("mp4", 1, true) == nil)
    assert_true(upnp.mime_ok("audio/flac")); assert_true(upnp.mime_ok("AUDIO/MPEG")); assert_true(upnp.mime_ok(nil)); assert_true(upnp.mime_ok("*"))
    assert_false(upnp.mime_ok("audio/mp4")); assert_false(upnp.mime_ok("audio/aac")); assert_false(upnp.mime_ok("video/mp4"))
  end)
end)

describe("services.upnp — SOAP", function()
  it("reads an action and its arguments, whatever the prefixes, empty ones included", function()
    local a, args = upnp.parse_soap(envelope("SetAVTransportURI", "urn:schemas-upnp-org:service:AVTransport:1",
      { { "InstanceID", "0" }, { "CurrentURI", SONG }, { "CurrentURIMetaData", upnp.escape(DIDL) } }))
    assert_eq(a, "SetAVTransportURI")
    assert_eq(args.InstanceID, "0"); assert_eq(args.CurrentURI, SONG); assert_eq(args.CurrentURIMetaData, DIDL)
    a, args = upnp.parse_soap('<SOAP-ENV:Envelope xmlns:SOAP-ENV="x"><SOAP-ENV:Body><m:Play xmlns:m="y"><InstanceID>0</InstanceID><Speed/></m:Play></SOAP-ENV:Body></SOAP-ENV:Envelope>')
    assert_eq(a, "Play"); assert_eq(args, { InstanceID = "0", Speed = "" })
    a, args = upnp.parse_soap('<Envelope><Body>\n  <Stop xmlns="urn:x"><InstanceID>0</InstanceID></Stop>\n</Body></Envelope>')
    assert_eq(a, "Stop"); assert_eq(args, { InstanceID = "0" })
    assert_nil(upnp.parse_soap("<html>not soap</html>"))
    assert_nil(upnp.parse_soap(nil))
  end)

  it("answers with the out arguments in order, escaped; a fault carries the UPnP code", function()
    local x = upnp.soap_response("urn:schemas-upnp-org:service:RenderingControl:1", "GetVolume", { { "CurrentVolume", "40" } })
    assert_match(x, '<u:GetVolumeResponse xmlns:u="urn:schemas%-upnp%-org:service:RenderingControl:1"><CurrentVolume>40</CurrentVolume></u:GetVolumeResponse>')
    assert_match(upnp.soap_response("t", "X", { { "A", "<&>" } }), "<A>&lt;&amp;&gt;</A>")
    assert_match(upnp.soap_fault(714, "Illegal MIME-type"), "<errorCode>714</errorCode><errorDescription>Illegal MIME%-type</errorDescription>")
  end)

  it("reads the song's title, artist, album, picture, duration and format from DIDL-Lite", function()
    local i = upnp.didl_info(DIDL)
    assert_eq(i, { title = "L'\195\169t\195\169 & co", artist = "Anne", album = "Songs", image = "http://192.168.1.20/a.jpg", duration_ms = 205500, mime = "audio/flac" })
    assert_eq(upnp.didl_info(""), {})
    -- a picture that is not a web address (a phone's own path) is left out
    assert_nil(upnp.didl_info("<upnp:albumArtURI>content://x</upnp:albumArtURI>").image)
  end)

  it("gives back DIDL-Lite for what it plays, escaped", function()
    local x = upnp.didl({ title = "A & B", artist = "C", duration_ms = 61000, mime = "audio/flac" }, SONG)
    assert_match(x, "<dc:title>A &amp; B</dc:title><upnp:artist>C</upnp:artist>")
    assert_match(x, '<res protocolInfo="http%-get:%*:audio/flac:%*" duration="0:01:01.000">http://')
  end)
end)

describe("services.upnp — requests", function()
  it("refuses an unknown action, another instance, a channel other than Master", function()
    local d = doc_with()
    assert_eq(upnp.request(d, "avt", "Record", {}).fault.code, 401)
    assert_eq(upnp.request(d, "avt", "Play", { InstanceID = "1" }).fault.code, 718)
    assert_eq(upnp.request(d, "rc", "GetVolume", { InstanceID = "0", Channel = "LF" }).fault.code, 402)
  end)

  it("with nothing sent yet: NO_MEDIA_PRESENT, and Play is refused", function()
    local d = doc_with()
    assert_eq(out_of(upnp.request(d, "avt", "GetTransportInfo", { InstanceID = "0" })),
      { CurrentTransportState = "NO_MEDIA_PRESENT", CurrentTransportStatus = "OK", CurrentSpeed = "1" })
    assert_eq(upnp.request(d, "avt", "Play", { InstanceID = "0", Speed = "1" }).fault.code, 701)
    assert_eq(out_of(upnp.request(d, "avt", "GetCurrentTransportActions", { InstanceID = "0" })).Actions, "")
  end)

  it("refuses a song it cannot read (AAC, MP4) or an address that is not http(s)", function()
    local d = doc_with()
    local aac = DIDL:gsub("audio/flac", "audio/mp4")
    assert_eq(upnp.request(d, "avt", "SetAVTransportURI", { InstanceID = "0", CurrentURI = SONG, CurrentURIMetaData = aac }).fault.code, 714)
    assert_eq(upnp.request(d, "avt", "SetAVTransportURI", { InstanceID = "0", CurrentURI = "file:///etc/passwd", CurrentURIMetaData = "" }).fault.code, 714)
    assert_eq(upnp.request(d, "avt", "SetAVTransportURI", { InstanceID = "0", CurrentURI = "http://a/b c", CurrentURIMetaData = "" }).fault.code, 714)
    -- https: the Jooki's player has no TLS, refused at once with a word on why
    local r = upnp.request(d, "avt", "SetAVTransportURI", { InstanceID = "0", CurrentURI = "https://cdn.example/a.flac", CurrentURIMetaData = "" })
    assert_eq(r.fault.code, 714); assert_match(r.fault.text, "https")
    -- no metadata: tried (the player says it if it cannot)
    assert_nil(upnp.request(d, "avt", "SetAVTransportURI", { InstanceID = "0", CurrentURI = SONG, CurrentURIMetaData = "" }).fault)
  end)

  it("answers the protocol and connection questions of ConnectionManager", function()
    local d = doc_with()
    assert_eq(out_of(upnp.request(d, "cm", "GetProtocolInfo", {})).Sink, upnp.SINK_PROTOCOLS)
    assert_eq(out_of(upnp.request(d, "cm", "GetCurrentConnectionIDs", {})).ConnectionIDs, "0")
    assert_eq(out_of(upnp.request(d, "cm", "GetCurrentConnectionInfo", { ConnectionID = "0" })).Direction, "Input")
    assert_eq(upnp.request(d, "cm", "GetCurrentConnectionInfo", { ConnectionID = "3" }).fault.code, 706)
  end)
end)

describe("services.upnp — an app plays a song", function()
  it("SetAVTransportURI keeps the song (STOPPED); Play starts it on the Jooki's own player", function()
    local d = doc_with()
    local r = act(d, "avt", "SetAVTransportURI", { InstanceID = "0", CurrentURI = SONG, CurrentURIMetaData = DIDL })
    assert_nil(r.fault)
    assert_eq(d.upnp.uri, SONG); assert_eq(d.upnp.info.title, "L'\195\169t\195\169 & co")
    assert_eq(upnp.transport(d), "STOPPED")
    assert_eq(topics(r.handled), {})                        -- nothing played yet
    r = act(d, "avt", "Play", { InstanceID = "0", Speed = "1" })
    assert_eq(topics(r.handled), { "play 7\t" .. SONG })
    assert_eq(d.playback.now.service, "UPNP"); assert_eq(d.playback.now.title, "L'\195\169t\195\169 & co")
    assert_eq(d.playback.now.duration_ms, 205500); assert_eq(d.playback.now.image, "http://192.168.1.20/a.jpg")
    assert_eq(upnp.transport(d), "TRANSITIONING")
    d.playback.state = "playing"; d.playback.position_ms = 65000
    assert_eq(upnp.transport(d), "PLAYING")
    local pos = out_of(upnp.request(d, "avt", "GetPositionInfo", { InstanceID = "0" }))
    assert_eq(pos.RelTime, "0:01:05"); assert_eq(pos.TrackDuration, "0:03:25"); assert_eq(pos.TrackURI, SONG); assert_eq(pos.Track, "1")
    assert_match(pos.TrackMetaData, "<dc:title>L'")
    assert_eq(out_of(upnp.request(d, "avt", "GetCurrentTransportActions", { InstanceID = "0" })).Actions, "Pause,Stop,Seek")
    -- Play again while it plays: nothing (no restart from the top)
    assert_nil(act(d, "avt", "Play", { InstanceID = "0", Speed = "1" }).handled)
  end)

  it("pauses, plays on from where it was, seeks, stops", function()
    local d = doc_with({ upnp = { uri = SONG, info = { title = "S" } } })
    apply(d, playback.play_uri(d, SONG, { title = "S" }))
    d.playback.state = "playing"; d.playback.position_ms = 30000
    local r = act(d, "avt", "Pause", { InstanceID = "0" })
    assert_eq(topics(r.handled), { "pauz 7" })
    d.playback.state = "paused"
    assert_eq(upnp.transport(d), "PAUSED_PLAYBACK")
    r = act(d, "avt", "Play", { InstanceID = "0", Speed = "1" })
    assert_eq(topics(r.handled), { "cont 7" })
    d.playback.state = "playing"
    r = act(d, "avt", "Seek", { InstanceID = "0", Unit = "REL_TIME", Target = "0:02:00" })
    assert_eq(topics(r.handled), { "seek 7\t120000" })
    assert_eq(upnp.request(d, "avt", "Seek", { InstanceID = "0", Unit = "REL_TIME", Target = "later" }).fault.code, 711)
    assert_eq(upnp.request(d, "avt", "Seek", { InstanceID = "0", Unit = "X_DLNA_REL_BYTE", Target = "0" }).fault.code, 710)
    r = act(d, "avt", "Stop", { InstanceID = "0" })
    assert_eq(topics(r.handled), { "stop 7" })
  end)

  it("a new song while one plays starts at once; while paused it waits for Play", function()
    local d = doc_with({ upnp = { uri = SONG, info = {} } })
    apply(d, playback.play_uri(d, SONG, {}))
    d.playback.state = "playing"
    local next_song = "http://192.168.1.20:9790/b.mp3"
    local r = act(d, "avt", "SetAVTransportURI", { InstanceID = "0", CurrentURI = next_song, CurrentURIMetaData = "" })
    assert_eq(topics(r.handled), { "play 7\t" .. next_song, "stop 7" })
    assert_eq(d.playback.now.uri, next_song)
    d.playback.state = "paused"
    r = act(d, "avt", "SetAVTransportURI", { InstanceID = "0", CurrentURI = SONG, CurrentURIMetaData = "" })
    assert_eq(topics(r.handled), {})
    assert_eq(upnp.transport(d), "STOPPED")                 -- the new song is not loaded yet
  end)

  it("ended: STOPPED, so the app sends the next song; the heart plays it again from the start", function()
    local d = doc_with({ upnp = { uri = SONG, info = { title = "S" } } })
    apply(d, playback.play_uri(d, SONG, { title = "S" }))
    apply(d, playback.on_audio(d, { type = "audio.playing", id = 7 }))
    apply(d, playback.on_audio(d, { type = "audio.ended", id = 7 }))
    assert_eq(d.playback.state, "ended")
    assert_eq(upnp.transport(d), "STOPPED")
    local r = playback.on_resume(d, { now = 50 })
    assert_eq(topics(r), { "play 7\t" .. SONG })
  end)

  it("the player cannot play it (audio error): STOPPED, so the app moves on; a file's error changes nothing", function()
    local d = doc_with({ upnp = { uri = SONG, info = {} } })
    apply(d, playback.play_uri(d, SONG, {}))
    assert_eq(upnp.transport(d), "TRANSITIONING")
    local r = playback.on_audio(d, { type = "audio.error", id = 7 })
    apply(d, r)
    assert_eq(d.playback.state, "idle"); assert_eq(upnp.transport(d), "STOPPED")
    assert_nil(playback.on_audio(d, { type = "audio.error", id = 7 }))       -- already stopped
    local f = doc_with({ playback = { state = "playing", now = { service = "FILE", uri = "file:///a" } } })
    assert_nil(playback.on_audio(f, { type = "audio.error", id = 7 }))
  end)

  it("a token put on takes over: the app sees STOPPED, and pause / stop from it touch nothing", function()
    local d = doc_with({ upnp = { uri = SONG, info = {} } })
    d.library = { playlists = { music = { title = "M", tracks = { "a" } } }, tracks = { a = { title = "A", filename = "/d/a.mp3" } }, tokens = {} }
    apply(d, playback.play_uri(d, SONG, {}))
    d.playback.state = "playing"
    local r = playback.on_request(d, { playlist = "music", now = 10 })
    assert_eq(topics(r), { "play 7\tfile:///d/a.mp3", "stop 7" })
    apply(d, r)
    assert_eq(upnp.transport(d), "STOPPED")
    assert_nil(act(d, "avt", "Pause", { InstanceID = "0" }).handled)
    assert_nil(act(d, "avt", "Stop", { InstanceID = "0" }).handled)
    -- and Play from the app takes it back (the last one to start wins)
    assert_eq(topics(act(d, "avt", "Play", { InstanceID = "0", Speed = "1" }).handled), { "play 7\t" .. SONG, "stop 7" })
  end)

  it("Spotify playing: Play from an app stops Spotify first", function()
    local d = doc_with({ upnp = { uri = SONG, info = {} }, playback = { state = "playing", now = { service = "SPOTIFY" } } })
    local r = act(d, "avt", "Play", { InstanceID = "0", Speed = "1" })
    local saw_stop = false
    for _, c in ipairs(r.handled.commands) do if c.kind == "bus.publish" and c.topic:find("spotify") then saw_stop = true end end
    assert_true(saw_stop, "a stop for Spotify")
    assert_eq(d.playback.now.service, "UPNP")
  end)

  it("turned off: an app's order does nothing, and a song it plays stops", function()
    local d = doc_with({ off = true, upnp = { uri = SONG, info = {} } })
    assert_nil(upnp.on_action(d, { type = "upnp.action", act = "play" }))
    apply(d, playback.play_uri(d, SONG, {}))
    d.playback.state = "playing"
    local r = upnp.on_config(d)
    assert_eq(topics(r), { "stop 7" })
    assert_eq(r.state.upnp, {})
    d = doc_with({ upnp = { uri = SONG } })
    assert_nil(upnp.on_config(d))                           -- still on: nothing
  end)
end)

describe("services.upnp — volume", function()
  it("SetVolume is the page's volume (limits included, saved); GetVolume reads it", function()
    local d = doc_with({ volume = 40 })
    assert_eq(out_of(upnp.request(d, "rc", "GetVolume", { InstanceID = "0", Channel = "Master" })).CurrentVolume, "40")
    local r = act(d, "rc", "SetVolume", { InstanceID = "0", Channel = "Master", DesiredVolume = "65" })
    assert_eq(topics(r.handled), { "volume 65", "write /d/audiocfg.json" })
    assert_eq(d.audiocfg.volume, 65)
    d.limits = { maxvol = 50 }
    r = act(d, "rc", "SetVolume", { InstanceID = "0", Channel = "Master", DesiredVolume = "90" })
    assert_eq(topics(r.handled), { "volume 50", "write /d/audiocfg.json" })     -- the night limit still wins
    assert_eq(upnp.request(d, "rc", "SetVolume", { InstanceID = "0", Channel = "Master", DesiredVolume = "101" }).fault.code, 402)
    assert_eq(upnp.request(d, "rc", "SetVolume", { InstanceID = "0", Channel = "Master", DesiredVolume = "loud" }).fault.code, 402)
  end)

  it("mute silences without forgetting the volume; unmute brings it back", function()
    local d = doc_with({ volume = 40 })
    local r = act(d, "rc", "SetMute", { InstanceID = "0", Channel = "Master", DesiredMute = "1" })
    assert_eq(topics(r.handled), { "volume 0" })
    assert_eq(out_of(upnp.request(d, "rc", "GetMute", { InstanceID = "0", Channel = "Master" })).CurrentMute, "1")
    assert_eq(out_of(upnp.request(d, "rc", "GetVolume", { InstanceID = "0", Channel = "Master" })).CurrentVolume, "40")
    assert_nil(act(d, "rc", "SetMute", { InstanceID = "0", Channel = "Master", DesiredMute = "true" }).handled)   -- already
    r = act(d, "rc", "SetMute", { InstanceID = "0", Channel = "Master", DesiredMute = "0" })
    assert_eq(topics(r.handled), { "volume 40" })
    assert_eq(upnp.request(d, "rc", "SetMute", { InstanceID = "0", Channel = "Master", DesiredMute = "maybe" }).fault.code, 402)
  end)
end)

describe("services.upnp — events", function()
  it("LastChange of AVTransport says the state and the song, escaped once inside the property", function()
    local d = doc_with({ upnp = { uri = SONG, info = { title = "A & B" } } })
    local x = upnp.event_body(d, "avt")
    assert_match(x, '^<%?xml version="1.0" encoding="utf%-8"%?>\n<e:propertyset xmlns:e="urn:schemas%-upnp%-org:event%-1%-0"><e:property><LastChange>')
    assert_match(x, "&lt;TransportState val=&quot;STOPPED&quot;/&gt;")
    assert_match(x, "&lt;AVTransportURI val=&quot;http://")
    -- the title inside the metadata inside the attribute inside LastChange: escaped three times
    assert_match(x, "A &amp;amp;amp; B")
  end)

  it("RenderingControl says volume and mute on the Master channel; ConnectionManager its plain variables", function()
    local d = doc_with({ volume = 30 })
    assert_match(upnp.event_body(d, "rc"), "&lt;Volume channel=&quot;Master&quot; val=&quot;30&quot;/&gt;")
    assert_match(upnp.event_body(d, "cm"), "<e:property><SinkProtocolInfo>http%-get:")
  end)

  it("the signature changes with what the apps see, not with the position", function()
    local d = doc_with({ upnp = { uri = SONG, info = {} } })
    apply(d, playback.play_uri(d, SONG, {}))
    d.playback.state = "playing"; d.playback.position_ms = 1000
    local s1 = upnp.signature(d, "avt")
    d.playback.position_ms = 9000
    assert_eq(upnp.signature(d, "avt"), s1)
    d.playback.state = "paused"
    assert_true(upnp.signature(d, "avt") ~= s1)
  end)
end)

describe("adapters.upnp — SSDP", function()
  local UDN = "uuid:4a6f6f6b-6900-4f70-656e-a8eec60426e8"

  it("parses an M-SEARCH", function()
    local m, h = net.parse('M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: "ssdp:discover"\r\nMX: 2\r\nST: ssdp:all\r\n\r\n')
    assert_eq(m, "M-SEARCH"); assert_eq(h.st, "ssdp:all"); assert_eq(h.man, '"ssdp:discover"'); assert_eq(h.mx, "2")
    assert_nil(net.parse(""))
  end)

  it("answers ssdp:all with everything, a type with itself, a lower version too, others with nothing", function()
    assert_eq(#net.matching("ssdp:all", UDN), 6)
    assert_eq(net.matching("upnp:rootdevice", UDN), { { "upnp:rootdevice", UDN .. "::upnp:rootdevice" } })
    assert_eq(net.matching(UDN, UDN), { { UDN, UDN } })
    assert_eq(net.matching("urn:schemas-upnp-org:device:MediaRenderer:1", UDN)[1][2], UDN .. "::urn:schemas-upnp-org:device:MediaRenderer:1")
    assert_eq(#net.matching("urn:schemas-upnp-org:service:AVTransport:1", UDN), 1)
    assert_eq(#net.matching("urn:schemas-upnp-org:device:MediaServer:1", UDN), 0)
    assert_eq(#net.matching("urn:dial-multiscreen-org:service:dial:1", UDN), 0)
  end)

  it("writes the answer and the announcements (alive with its address, byebye without)", function()
    local loc = "http://192.168.1.11:80/upnp/desc.xml"
    local r = net.search_response("upnp:rootdevice", UDN .. "::upnp:rootdevice", loc)
    assert_match(r, "^HTTP/1.1 200 OK\r\n"); assert_match(r, "\r\nLOCATION: http://192%.168%.1%.11:80/upnp/desc%.xml\r\n")
    assert_match(r, "\r\nST: upnp:rootdevice\r\n"); assert_match(r, "\r\nEXT:\r\n"); assert_match(r, "\r\n\r\n$")
    local a = net.notify("upnp:rootdevice", UDN .. "::upnp:rootdevice", "ssdp:alive", loc)
    assert_match(a, "^NOTIFY %* HTTP/1.1\r\nHOST: 239%.255%.255%.250:1900\r\n"); assert_match(a, "NTS: ssdp:alive"); assert_match(a, "LOCATION: ")
    local b = net.notify("upnp:rootdevice", UDN .. "::upnp:rootdevice", "ssdp:byebye", loc)
    assert_match(b, "NTS: ssdp:byebye"); assert_true(b:find("LOCATION", 1, true) == nil)
  end)

  it("announces at 0, 1 and 3 s, then every 30 s, and again from the start on a new address", function()
    local sched, seen = {}, {}
    for t = 0, 70 do if net.due(sched, t, "a") then seen[#seen + 1] = t end end
    assert_eq(seen, { 0, 1, 3, 33, 63 })
    assert_true(net.due(sched, 71, "b"))
  end)
end)

describe("adapters.upnp — GENA", function()
  it("takes the first http callback, a timeout kept between 1 min and 1 h", function()
    assert_eq(net.callback("<http://192.168.1.20:49152/evt/1><http://other/>"), "http://192.168.1.20:49152/evt/1")
    assert_nil(net.callback("<https://x/>")); assert_nil(net.callback(nil))
    assert_eq(net.timeout("Second-300"), 300); assert_eq(net.timeout("Second-5"), 60)
    assert_eq(net.timeout("Second-86400"), 3600); assert_eq(net.timeout("infinite"), 1800); assert_eq(net.timeout(nil), 1800)
    assert_eq({ net.split_url("http://10.0.0.2:8058/cb") }, { "10.0.0.2", 8058, "/cb" })
    assert_eq({ net.split_url("http://host") }, { "host", 80, "/" })
  end)

  it("writes the NOTIFY request", function()
    local x = net.notify_request("http://10.0.0.2:8058/cb", "uuid:s", 3, "<body/>")
    assert_match(x, "^NOTIFY /cb HTTP/1.1\r\nHOST: 10%.0%.0%.2:8058\r\n")
    assert_match(x, "\r\nNT: upnp:event\r\nNTS: upnp:propchange\r\nSID: uuid:s\r\nSEQ: 3\r\nCONTENT%-LENGTH: 7\r\n")
    assert_match(x, "\r\n\r\n<body/>$")
  end)

  it("subscribes, renews, refuses an unknown SID, unsubscribes; turned off it answers 404", function()
    local r = net.new({ http_port = 80 })
    local d = doc_with()
    local st, _, _, hdr = r:http(d, "SUBSCRIBE", "/upnp/evt/avt", { callback = "<http://10.0.0.2:8058/cb>", nt = "upnp:event", timeout = "Second-300" }, "", 10)
    assert_eq(st, "200 OK")
    local sid = hdr[1]:match("^SID: (.+)$")
    assert_true(sid ~= nil); assert_eq(hdr[2], "TIMEOUT: Second-300")
    assert_eq(r.n_subs, 1)
    st = r:http(d, "SUBSCRIBE", "/upnp/evt/avt", { sid = sid, timeout = "Second-600" }, "", 20)
    assert_eq(st, "200 OK"); assert_eq(r.subs[sid].expires, 620)
    assert_eq(r:http(d, "SUBSCRIBE", "/upnp/evt/avt", { sid = "uuid:nope" }, "", 20), "412 Precondition Failed")
    assert_eq(r:http(d, "SUBSCRIBE", "/upnp/evt/avt", { callback = "<http://x/>" }, "", 20), "412 Precondition Failed")   -- no NT
    assert_eq(r:http(d, "UNSUBSCRIBE", "/upnp/evt/avt", { sid = sid }, "", 30), "200 OK")
    assert_eq(r.n_subs, 0)
    assert_eq(r:http(doc_with({ off = true }), "GET", "/upnp/desc.xml", {}, "", 30), "404 Not Found")
    assert_nil(r:http(d, "GET", "/index.html", {}, "", 30))                       -- not ours: the page's
  end)

  it("serves the descriptions and the SOAP control; a fault is a 500", function()
    local emitted = {}
    local r = net.new({ http_port = 80, emit = function(e) emitted[#emitted + 1] = e end })
    local d = doc_with()
    local st, ct, body = r:http(d, "GET", "/upnp/desc.xml", {}, "", 1)
    assert_eq(st, "200 OK"); assert_match(ct, "^text/xml"); assert_match(body, "MediaRenderer")
    assert_eq(r:http(d, "GET", "/upnp/avt.xml", {}, "", 1), "200 OK")
    assert_eq(r:http(d, "GET", "/upnp/zz.xml", {}, "", 1), "404 Not Found")
    local _, _, b = r:http(d, "POST", "/upnp/ctl/rc", {}, envelope("GetVolume", "urn:schemas-upnp-org:service:RenderingControl:1", { { "InstanceID", "0" }, { "Channel", "Master" } }), 1)
    assert_match(b, "<CurrentVolume>40</CurrentVolume>")
    st, _, b = r:http(d, "POST", "/upnp/ctl/avt", {}, envelope("Play", "urn:schemas-upnp-org:service:AVTransport:1", { { "InstanceID", "0" }, { "Speed", "1" } }), 1)
    assert_eq(st, "500 Internal Server Error"); assert_match(b, "<errorCode>701</errorCode>")
    st = r:http(d, "POST", "/upnp/ctl/avt", {}, envelope("SetAVTransportURI", "urn:schemas-upnp-org:service:AVTransport:1",
      { { "InstanceID", "0" }, { "CurrentURI", SONG }, { "CurrentURIMetaData", upnp.escape(DIDL) } }), 7)
    assert_eq(st, "200 OK")
    assert_eq(#emitted, 1); assert_eq(emitted[1].act, "set_uri"); assert_eq(emitted[1].uri, SONG); assert_eq(emitted[1].now, 7)
    assert_eq(r:http(d, "POST", "/upnp/ctl/nope", {}, "", 1), "404 Not Found")
  end)
end)
