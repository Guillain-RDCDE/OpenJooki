-- services.upnp: the Jooki as a UPnP / DLNA music player ("renderer", #29).
-- An app on the phone or a NAS (BubbleUPnP, mconnect, a TIDAL or Qobuz app that "casts" to UPnP,
-- a music server) finds the Jooki on the home network and sends it a song: an http:// address the
-- Jooki's own player fetches and plays, like a web radio. Off by default: Settings > Play from other
-- apps (audiocfg.upnp, services.device).
-- Pure: the device and service descriptions, the SOAP requests and their answers, what plays (from
-- state.playback and state.upnp), the evented variables. The network side (SSDP, the HTTP routes,
-- the event subscriptions) is adapters.upnp's; it calls `request` and emits what it returns.
-- Owns state.upnp = { uri, info = { title, artist, album, image, duration_ms, mime }, muted? }
-- (in memory only: a new start forgets the last song an app sent).
-- What the Jooki plays from an app is state.playback with now.service = "UPNP" (services.playback):
-- the heart button, the page and a token act on it like on any song; the last one to start wins.
local util = require("services.util")
local playback = require("services.playback")
local device = require("services.device")
local upnp = {}

local copy = util.copy

upnp.DEVICE = "urn:schemas-upnp-org:device:MediaRenderer:1"
upnp.SERVICES = {
  { key = "avt", type = "urn:schemas-upnp-org:service:AVTransport:1", id = "urn:upnp-org:serviceId:AVTransport" },
  { key = "rc", type = "urn:schemas-upnp-org:service:RenderingControl:1", id = "urn:upnp-org:serviceId:RenderingControl" },
  { key = "cm", type = "urn:schemas-upnp-org:service:ConnectionManager:1", id = "urn:upnp-org:serviceId:ConnectionManager" },
}
local BY_KEY = {}
for _, s in ipairs(upnp.SERVICES) do BY_KEY[s.key] = s end
upnp.BY_KEY = BY_KEY

-- what the Jooki's player can read (GStreamer plugins of the image: mpg123, flac, ogg/vorbis, wav;
-- no AAC, no MP4): an app asks this first and sends a format from the list, or converts
local MIMES = { "audio/mpeg", "audio/mp3", "audio/x-mpeg", "audio/flac", "audio/x-flac", "audio/ogg", "audio/x-ogg",
                "application/ogg", "audio/vorbis", "audio/wav", "audio/x-wav", "audio/wave" }
local MIME_OK = {}
for _, m in ipairs(MIMES) do MIME_OK[m] = true end
local sink = {}
for _, m in ipairs(MIMES) do sink[#sink + 1] = "http-get:*:" .. m .. ":*" end
upnp.SINK_PROTOCOLS = table.concat(sink, ",")

-- ------------------------------------------------------------------ small helpers
local ENT = { amp = "&", lt = "<", gt = ">", quot = '"', apos = "'" }
--- XML text to plain text (the five entities and numeric references).
function upnp.unescape(s)
  s = tostring(s or "")
  s = s:gsub("<!%[CDATA%[(.-)%]%]>", function(x) return (x:gsub("&", "&amp;"):gsub("<", "&lt;")) end)
  return (s:gsub("&(#?[%w]+);", function(e)
    if ENT[e] then return ENT[e] end
    local n = e:match("^#x(%x+)$") and tonumber(e:sub(3), 16) or e:match("^#(%d+)$") and tonumber(e:sub(2))
    if not n then return "&" .. e .. ";" end
    if n < 128 then return string.char(n) end
    if n < 2048 then return string.char(192 + math.floor(n / 64), 128 + n % 64) end
    if n < 65536 then return string.char(224 + math.floor(n / 4096), 128 + math.floor(n / 64) % 64, 128 + n % 64) end
    return string.char(240 + math.floor(n / 262144), 128 + math.floor(n / 4096) % 64, 128 + math.floor(n / 64) % 64, 128 + n % 64)
  end))
end

--- Plain text to XML text.
function upnp.escape(s)
  return (tostring(s or ""):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
end
local esc = upnp.escape

--- "H:MM:SS" for a number of milliseconds.
function upnp.hms(ms)
  local s = math.floor((tonumber(ms) or 0) / 1000)
  if s < 0 then s = 0 end
  return string.format("%d:%02d:%02d", math.floor(s / 3600), math.floor(s / 60) % 60, s % 60)
end

--- Milliseconds of "H+:MM:SS[.F+]" (or "MM:SS", or a plain number of seconds); nil if unreadable.
function upnp.parse_hms(s)
  s = tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local sign = 1
  if s:sub(1, 1) == "-" then sign, s = -1, s:sub(2) elseif s:sub(1, 1) == "+" then s = s:sub(2) end
  local h, m, sec = s:match("^(%d+):(%d+):(%d+%.?%d*)$")
  if not h then h, m, sec = "0", s:match("^(%d+):(%d+%.?%d*)$") end
  if not m then
    sec = s:match("^(%d+%.?%d*)$")
    if not sec then return nil end
    h, m = "0", "0"
  end
  return sign * math.floor((tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(sec)) * 1000 + 0.5)
end

-- ------------------------------------------------------------------ the Jooki on the network
--- The device's UDN: the same at every start, from the Wi-Fi address (or the Jooki's id).
function upnp.udn(doc)
  local d = doc.device or {}
  local hex = tostring(d.wifi_mac or ""):lower():gsub("[^%x]", "")
  if #hex ~= 12 then
    local h = 5381
    for i = 1, #tostring(d.id or "jooki") do h = (h * 33 + tostring(d.id or "jooki"):byte(i)) % 281474976710656 end
    hex = string.format("%012x", h)
  end
  return "uuid:4a6f6f6b-6900-4f70-656e-" .. hex
end

--- The name the apps show: the Jooki's name, with a capital.
function upnp.friendly_name(doc)
  local n = tostring((doc.device or {}).hostname or "jooki")
  if n == "" then n = "jooki" end
  return (n:gsub("^%l", string.upper))
end

--- Is the renderer on? (Settings > Play from other apps)
function upnp.enabled(doc) return (doc.audiocfg or {}).upnp == true end

--- The device description (GET /upnp/desc.xml).
function upnp.description(doc)
  local d = doc.device or {}
  local list = {}
  for _, s in ipairs(upnp.SERVICES) do
    list[#list + 1] = "<service><serviceType>" .. s.type .. "</serviceType><serviceId>" .. s.id .. "</serviceId>"
      .. "<SCPDURL>/upnp/" .. s.key .. ".xml</SCPDURL><controlURL>/upnp/ctl/" .. s.key .. "</controlURL>"
      .. "<eventSubURL>/upnp/evt/" .. s.key .. "</eventSubURL></service>"
  end
  return '<?xml version="1.0" encoding="utf-8"?>\n'
    .. '<root xmlns="urn:schemas-upnp-org:device-1-0" xmlns:dlna="urn:schemas-dlna-org:device-1-0">'
    .. "<specVersion><major>1</major><minor>0</minor></specVersion><device>"
    .. "<deviceType>" .. upnp.DEVICE .. "</deviceType>"
    .. "<friendlyName>" .. esc(upnp.friendly_name(doc)) .. "</friendlyName>"
    .. "<manufacturer>OpenJooki</manufacturer><manufacturerURL>https://github.com/Guillain-RDCDE/OpenJooki</manufacturerURL>"
    .. "<modelDescription>Jooki music player for children</modelDescription>"
    .. "<modelName>Jooki</modelName><modelNumber>" .. esc(d.openjooki or d.core or "") .. "</modelNumber>"
    .. "<UDN>" .. upnp.udn(doc) .. "</UDN><dlna:X_DLNADOC>DMR-1.50</dlna:X_DLNADOC>"
    .. "<presentationURL>/</presentationURL>"
    .. "<serviceList>" .. table.concat(list) .. "</serviceList></device></root>\n"
end

-- ------------------------------------------------------------------ the three services (SCPD)
-- { name, { {argument, "in"|"out", state variable}, ... } }
local ACTIONS = {
  avt = {
    { "SetAVTransportURI", { { "InstanceID", "in", "A_ARG_TYPE_InstanceID" }, { "CurrentURI", "in", "AVTransportURI" }, { "CurrentURIMetaData", "in", "AVTransportURIMetaData" } } },
    { "GetMediaInfo", { { "InstanceID", "in", "A_ARG_TYPE_InstanceID" }, { "NrTracks", "out", "NumberOfTracks" }, { "MediaDuration", "out", "CurrentMediaDuration" },
        { "CurrentURI", "out", "AVTransportURI" }, { "CurrentURIMetaData", "out", "AVTransportURIMetaData" }, { "NextURI", "out", "NextAVTransportURI" },
        { "NextURIMetaData", "out", "NextAVTransportURIMetaData" }, { "PlayMedium", "out", "PlaybackStorageMedium" }, { "RecordMedium", "out", "RecordStorageMedium" },
        { "WriteStatus", "out", "RecordMediumWriteStatus" } } },
    { "GetTransportInfo", { { "InstanceID", "in", "A_ARG_TYPE_InstanceID" }, { "CurrentTransportState", "out", "TransportState" },
        { "CurrentTransportStatus", "out", "TransportStatus" }, { "CurrentSpeed", "out", "TransportPlaySpeed" } } },
    { "GetPositionInfo", { { "InstanceID", "in", "A_ARG_TYPE_InstanceID" }, { "Track", "out", "CurrentTrack" }, { "TrackDuration", "out", "CurrentTrackDuration" },
        { "TrackMetaData", "out", "CurrentTrackMetaData" }, { "TrackURI", "out", "CurrentTrackURI" }, { "RelTime", "out", "RelativeTimePosition" },
        { "AbsTime", "out", "AbsoluteTimePosition" }, { "RelCount", "out", "RelativeCounterPosition" }, { "AbsCount", "out", "AbsoluteCounterPosition" } } },
    { "GetDeviceCapabilities", { { "InstanceID", "in", "A_ARG_TYPE_InstanceID" }, { "PlayMedia", "out", "PossiblePlaybackStorageMedia" },
        { "RecMedia", "out", "PossibleRecordStorageMedia" }, { "RecQualityModes", "out", "PossibleRecordQualityModes" } } },
    { "GetTransportSettings", { { "InstanceID", "in", "A_ARG_TYPE_InstanceID" }, { "PlayMode", "out", "CurrentPlayMode" }, { "RecQualityMode", "out", "CurrentRecordQualityMode" } } },
    { "GetCurrentTransportActions", { { "InstanceID", "in", "A_ARG_TYPE_InstanceID" }, { "Actions", "out", "CurrentTransportActions" } } },
    { "Stop", { { "InstanceID", "in", "A_ARG_TYPE_InstanceID" } } },
    { "Play", { { "InstanceID", "in", "A_ARG_TYPE_InstanceID" }, { "Speed", "in", "TransportPlaySpeed" } } },
    { "Pause", { { "InstanceID", "in", "A_ARG_TYPE_InstanceID" } } },
    { "Seek", { { "InstanceID", "in", "A_ARG_TYPE_InstanceID" }, { "Unit", "in", "A_ARG_TYPE_SeekMode" }, { "Target", "in", "A_ARG_TYPE_SeekTarget" } } },
    { "Next", { { "InstanceID", "in", "A_ARG_TYPE_InstanceID" } } },
    { "Previous", { { "InstanceID", "in", "A_ARG_TYPE_InstanceID" } } },
  },
  rc = {
    { "ListPresets", { { "InstanceID", "in", "A_ARG_TYPE_InstanceID" }, { "CurrentPresetNameList", "out", "PresetNameList" } } },
    { "SelectPreset", { { "InstanceID", "in", "A_ARG_TYPE_InstanceID" }, { "PresetName", "in", "A_ARG_TYPE_PresetName" } } },
    { "GetMute", { { "InstanceID", "in", "A_ARG_TYPE_InstanceID" }, { "Channel", "in", "A_ARG_TYPE_Channel" }, { "CurrentMute", "out", "Mute" } } },
    { "SetMute", { { "InstanceID", "in", "A_ARG_TYPE_InstanceID" }, { "Channel", "in", "A_ARG_TYPE_Channel" }, { "DesiredMute", "in", "Mute" } } },
    { "GetVolume", { { "InstanceID", "in", "A_ARG_TYPE_InstanceID" }, { "Channel", "in", "A_ARG_TYPE_Channel" }, { "CurrentVolume", "out", "Volume" } } },
    { "SetVolume", { { "InstanceID", "in", "A_ARG_TYPE_InstanceID" }, { "Channel", "in", "A_ARG_TYPE_Channel" }, { "DesiredVolume", "in", "Volume" } } },
  },
  cm = {
    { "GetProtocolInfo", { { "Source", "out", "SourceProtocolInfo" }, { "Sink", "out", "SinkProtocolInfo" } } },
    { "GetCurrentConnectionIDs", { { "ConnectionIDs", "out", "CurrentConnectionIDs" } } },
    { "GetCurrentConnectionInfo", { { "ConnectionID", "in", "A_ARG_TYPE_ConnectionID" }, { "RcsID", "out", "A_ARG_TYPE_RcsID" },
        { "AVTransportID", "out", "A_ARG_TYPE_AVTransportID" }, { "ProtocolInfo", "out", "A_ARG_TYPE_ProtocolInfo" },
        { "PeerConnectionManager", "out", "A_ARG_TYPE_ConnectionManager" }, { "PeerConnectionID", "out", "A_ARG_TYPE_ConnectionID" },
        { "Direction", "out", "A_ARG_TYPE_Direction" }, { "Status", "out", "A_ARG_TYPE_ConnectionStatus" } } },
  },
}
-- { name, type, sendEvents, allowed values | { min, max } }
local VARS = {
  avt = {
    { "TransportState", "string", false, { "STOPPED", "PLAYING", "PAUSED_PLAYBACK", "TRANSITIONING", "NO_MEDIA_PRESENT" } },
    { "TransportStatus", "string", false, { "OK", "ERROR_OCCURRED" } },
    { "PlaybackStorageMedium", "string", false, { "NONE", "NETWORK" } },
    { "RecordStorageMedium", "string", false, { "NOT_IMPLEMENTED" } },
    { "PossiblePlaybackStorageMedia", "string", false }, { "PossibleRecordStorageMedia", "string", false },
    { "CurrentPlayMode", "string", false, { "NORMAL" } },
    { "TransportPlaySpeed", "string", false, { "1" } },
    { "RecordMediumWriteStatus", "string", false, { "NOT_IMPLEMENTED" } },
    { "CurrentRecordQualityMode", "string", false, { "NOT_IMPLEMENTED" } },
    { "PossibleRecordQualityModes", "string", false },
    { "NumberOfTracks", "ui4", false, { 0, 1 } }, { "CurrentTrack", "ui4", false, { 0, 1 } },
    { "CurrentTrackDuration", "string", false }, { "CurrentMediaDuration", "string", false },
    { "CurrentTrackMetaData", "string", false }, { "CurrentTrackURI", "string", false },
    { "AVTransportURI", "string", false }, { "AVTransportURIMetaData", "string", false },
    { "NextAVTransportURI", "string", false }, { "NextAVTransportURIMetaData", "string", false },
    { "RelativeTimePosition", "string", false }, { "AbsoluteTimePosition", "string", false },
    { "RelativeCounterPosition", "i4", false }, { "AbsoluteCounterPosition", "i4", false },
    { "CurrentTransportActions", "string", false },
    { "LastChange", "string", true },
    { "A_ARG_TYPE_SeekMode", "string", false, { "REL_TIME", "ABS_TIME", "TRACK_NR" } },
    { "A_ARG_TYPE_SeekTarget", "string", false },
    { "A_ARG_TYPE_InstanceID", "ui4", false },
  },
  rc = {
    { "PresetNameList", "string", false }, { "LastChange", "string", true },
    { "Mute", "boolean", false }, { "Volume", "ui2", false, { 0, 100 } },
    { "A_ARG_TYPE_Channel", "string", false, { "Master" } },
    { "A_ARG_TYPE_InstanceID", "ui4", false },
    { "A_ARG_TYPE_PresetName", "string", false, { "FactoryDefaults" } },
  },
  cm = {
    { "SourceProtocolInfo", "string", true }, { "SinkProtocolInfo", "string", true }, { "CurrentConnectionIDs", "string", true },
    { "A_ARG_TYPE_ConnectionStatus", "string", false, { "OK", "ContentFormatMismatch", "InsufficientBandwidth", "UnreliableChannel", "Unknown" } },
    { "A_ARG_TYPE_ConnectionManager", "string", false },
    { "A_ARG_TYPE_Direction", "string", false, { "Input", "Output" } },
    { "A_ARG_TYPE_ProtocolInfo", "string", false },
    { "A_ARG_TYPE_ConnectionID", "i4", false }, { "A_ARG_TYPE_AVTransportID", "i4", false }, { "A_ARG_TYPE_RcsID", "i4", false },
  },
}
upnp.ACTIONS = ACTIONS

--- The service description of `key` ("avt", "rc", "cm"), or nil.
function upnp.scpd(key)
  if not ACTIONS[key] then return nil end
  local out = { '<?xml version="1.0" encoding="utf-8"?>\n<scpd xmlns="urn:schemas-upnp-org:service-1-0"><specVersion><major>1</major><minor>0</minor></specVersion><actionList>' }
  for _, a in ipairs(ACTIONS[key]) do
    out[#out + 1] = "<action><name>" .. a[1] .. "</name><argumentList>"
    for _, g in ipairs(a[2]) do
      out[#out + 1] = "<argument><name>" .. g[1] .. "</name><direction>" .. g[2] .. "</direction><relatedStateVariable>" .. g[3] .. "</relatedStateVariable></argument>"
    end
    out[#out + 1] = "</argumentList></action>"
  end
  out[#out + 1] = "</actionList><serviceStateTable>"
  for _, v in ipairs(VARS[key]) do
    out[#out + 1] = '<stateVariable sendEvents="' .. (v[3] and "yes" or "no") .. '"><name>' .. v[1] .. "</name><dataType>" .. v[2] .. "</dataType>"
    local allowed = v[4]
    if allowed and type(allowed[1]) == "number" then
      out[#out + 1] = "<allowedValueRange><minimum>" .. allowed[1] .. "</minimum><maximum>" .. allowed[2] .. "</maximum><step>1</step></allowedValueRange>"
    elseif allowed then
      out[#out + 1] = "<allowedValueList>"
      for _, x in ipairs(allowed) do out[#out + 1] = "<allowedValue>" .. x .. "</allowedValue>" end
      out[#out + 1] = "</allowedValueList>"
    end
    out[#out + 1] = "</stateVariable>"
  end
  out[#out + 1] = "</serviceStateTable></scpd>\n"
  return table.concat(out)
end

-- ------------------------------------------------------------------ SOAP
--- A SOAP request body -> action name, { argument = text } (entities decoded); nil if it is not one.
--- Any namespace prefix (u:, m:, none), empty arguments (<Speed/>).
function upnp.parse_soap(body)
  body = tostring(body or "")
  local inner = body:match("<[%w_%-]*:?Body[^>]*>(.*)</[%w_%-]*:?Body%s*>")
  if not inner then return nil end
  local tag, attrs, content = inner:match("<([%w_%-:%.]+)([^>]*)>(.*)")
  if not tag or attrs:sub(-1) == "/" then
    tag = inner:match("<([%w_%-:%.]+)[^>]*/>")
    if not tag then return nil end
    return (tag:match("([^:]+)$")), {}
  end
  local close = content:find("</" .. tag:gsub("%p", "%%%0") .. "%s*>")
  if close then content = content:sub(1, close - 1) end
  local args = {}
  local i = 1
  while true do
    local s, e, name, a = content:find("<([%w_%-:%.]+)([^>]*)>", i)
    if not s then break end
    local short = name:match("([^:]+)$")
    if a:sub(-1) == "/" then
      args[short] = ""
      i = e + 1
    else
      local cs, ce = content:find("</" .. name:gsub("%p", "%%%0") .. "%s*>", e + 1)
      if not cs then break end
      args[short] = upnp.unescape(content:sub(e + 1, cs - 1))
      i = ce + 1
    end
  end
  return (tag:match("([^:]+)$")), args
end

--- The SOAP answer to `action` of service `stype`, with the out arguments in order.
function upnp.soap_response(stype, action, out)
  local parts = {}
  for _, kv in ipairs(out or {}) do parts[#parts + 1] = "<" .. kv[1] .. ">" .. esc(kv[2]) .. "</" .. kv[1] .. ">" end
  return '<?xml version="1.0" encoding="utf-8"?>\n<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body>'
    .. "<u:" .. action .. 'Response xmlns:u="' .. stype .. '">' .. table.concat(parts) .. "</u:" .. action .. "Response></s:Body></s:Envelope>\n"
end

--- A UPnP error (HTTP 500 with a SOAP fault).
function upnp.soap_fault(code, text)
  return '<?xml version="1.0" encoding="utf-8"?>\n<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body>'
    .. "<s:Fault><faultcode>s:Client</faultcode><faultstring>UPnPError</faultstring><detail>"
    .. '<UPnPError xmlns="urn:schemas-upnp-org:control-1-0"><errorCode>' .. code .. "</errorCode><errorDescription>" .. esc(text)
    .. "</errorDescription></UPnPError></detail></s:Fault></s:Body></s:Envelope>\n"
end

-- ------------------------------------------------------------------ the song an app sends
local function tag_text(x, name)
  local v = x:match("<" .. name .. "[^>]*>(.-)</" .. name .. ">")
  if v == nil or v == "" then return nil end
  v = upnp.unescape(v):gsub("^%s+", ""):gsub("%s+$", "")
  return v ~= "" and v or nil
end

--- What the DIDL-Lite metadata says of the song: { title, artist, album, image, duration_ms, mime }.
function upnp.didl_info(didl)
  local x = tostring(didl or "")
  local info = {
    title = tag_text(x, "dc:title"), album = tag_text(x, "upnp:album"),
    artist = tag_text(x, "upnp:artist") or tag_text(x, "dc:creator"),
    image = tag_text(x, "upnp:albumArtURI"),
  }
  if info.image and not info.image:match("^https?://") then info.image = nil end
  local res = x:match("<res([^>]*)>")
  if res then
    local d = res:match('duration="([^"]+)"')
    info.duration_ms = d and upnp.parse_hms(d) or nil
    local pi = res:match('protocolInfo="([^"]+)"')
    if pi then info.mime = (upnp.unescape(pi):match("^[^:]*:[^:]*:([^:]*):") or ""):lower() end
  end
  return info
end

--- Can the Jooki play this format? (unknown = yes: the player says it if it cannot)
function upnp.mime_ok(mime)
  if not mime or mime == "" or mime == "*" then return true end
  return MIME_OK[mime:lower():gsub(";.*$", "")] == true
end

--- The DIDL-Lite the Jooki gives back for what it plays.
function upnp.didl(info, uri)
  info = info or {}
  local parts = { '<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">',
                  '<item id="0" parentID="-1" restricted="1"><dc:title>' .. esc(info.title or "") .. "</dc:title>" }
  if info.artist then parts[#parts + 1] = "<upnp:artist>" .. esc(info.artist) .. "</upnp:artist>" end
  if info.album then parts[#parts + 1] = "<upnp:album>" .. esc(info.album) .. "</upnp:album>" end
  if info.image then parts[#parts + 1] = "<upnp:albumArtURI>" .. esc(info.image) .. "</upnp:albumArtURI>" end
  parts[#parts + 1] = "<upnp:class>object.item.audioItem.musicTrack</upnp:class>"
  if uri then
    parts[#parts + 1] = '<res protocolInfo="http-get:*:' .. esc(info.mime or "audio/mpeg") .. ':*"'
      .. (info.duration_ms and (' duration="' .. upnp.hms(info.duration_ms) .. '.000"') or "") .. ">" .. esc(uri) .. "</res>"
  end
  parts[#parts + 1] = "</item></DIDL-Lite>"
  return table.concat(parts)
end

-- ------------------------------------------------------------------ what plays
--- The song of an app the Jooki has loaded, or nil (something else plays: a token, Spotify).
local function ours(doc)
  local n = (doc.playback or {}).now
  if n and n.service == "UPNP" then return n end
  return nil
end
upnp.ours = ours

--- TransportState, as the apps read it.
function upnp.transport(doc)
  local u = doc.upnp or {}
  if not u.uri then return "NO_MEDIA_PRESENT" end
  local n = ours(doc)
  if not n or n.uri ~= u.uri then return "STOPPED" end
  local s = (doc.playback or {}).state
  if s == "playing" then return "PLAYING" end
  if s == "starting" then return "TRANSITIONING" end
  if s == "paused" then return "PAUSED_PLAYBACK" end
  return "STOPPED"
end

local ACTIONS_FOR = { PLAYING = "Pause,Stop,Seek", TRANSITIONING = "Stop", PAUSED_PLAYBACK = "Play,Stop,Seek", STOPPED = "Play", NO_MEDIA_PRESENT = "" }
function upnp.transport_actions(doc) return ACTIONS_FOR[upnp.transport(doc)] end

local function position_ms(doc)
  local n = ours(doc)
  if not n or n.uri ~= (doc.upnp or {}).uri then return 0 end
  local s = (doc.playback or {}).state
  if s == "playing" or s == "paused" or s == "starting" then return tonumber((doc.playback or {}).position_ms) or 0 end
  return 0
end

local function duration_ms(doc)
  local n = ours(doc)
  local u = doc.upnp or {}
  if n and n.uri == u.uri and (n.duration_ms or 0) > 0 then return n.duration_ms end
  return (u.info or {}).duration_ms or 0
end

local function volume(doc) return math.floor(tonumber(device.audiocfg_of(doc).volume) or 0) end
local function muted(doc) return (doc.upnp or {}).muted == true end

--- The evented variables of a service, for its LastChange (avt, rc) or as they are (cm):
--- list of { name, value }.
function upnp.evented(doc, key)
  local u = doc.upnp or {}
  if key == "avt" then
    local meta = u.uri and upnp.didl(u.info, u.uri) or ""
    local dur = upnp.hms(duration_ms(doc))
    return { { "TransportState", upnp.transport(doc) }, { "TransportStatus", "OK" }, { "TransportPlaySpeed", "1" },
             { "CurrentPlayMode", "NORMAL" }, { "NumberOfTracks", u.uri and "1" or "0" }, { "CurrentTrack", u.uri and "1" or "0" },
             { "CurrentTrackDuration", dur }, { "CurrentMediaDuration", dur },
             { "AVTransportURI", u.uri or "" }, { "AVTransportURIMetaData", meta }, { "CurrentTrackURI", u.uri or "" },
             { "CurrentTrackMetaData", meta }, { "CurrentTransportActions", upnp.transport_actions(doc) },
             { "PlaybackStorageMedium", u.uri and "NETWORK" or "NONE" } }
  elseif key == "rc" then
    return { { "Volume", tostring(volume(doc)), ' channel="Master"' }, { "Mute", muted(doc) and "1" or "0", ' channel="Master"' } }
  elseif key == "cm" then
    return { { "SourceProtocolInfo", "" }, { "SinkProtocolInfo", upnp.SINK_PROTOCOLS }, { "CurrentConnectionIDs", "0" } }
  end
  return {}
end

--- The body of an event (GENA NOTIFY) for a service.
function upnp.event_body(doc, key)
  local vars = upnp.evented(doc, key)
  local inner
  if key == "cm" then
    local parts = {}
    for _, v in ipairs(vars) do parts[#parts + 1] = "<e:property><" .. v[1] .. ">" .. esc(v[2]) .. "</" .. v[1] .. "></e:property>" end
    inner = table.concat(parts)
  else
    local ns = key == "avt" and "urn:schemas-upnp-org:metadata-1-0/AVT/" or "urn:schemas-upnp-org:metadata-1-0/RCS/"
    local parts = { '<Event xmlns="' .. ns .. '"><InstanceID val="0">' }
    for _, v in ipairs(vars) do parts[#parts + 1] = "<" .. v[1] .. (v[3] or "") .. ' val="' .. esc(v[2]) .. '"/>' end
    parts[#parts + 1] = "</InstanceID></Event>"
    inner = "<e:property><LastChange>" .. esc(table.concat(parts)) .. "</LastChange></e:property>"
  end
  return '<?xml version="1.0" encoding="utf-8"?>\n<e:propertyset xmlns:e="urn:schemas-upnp-org:event-1-0">' .. inner .. "</e:propertyset>\n"
end

--- A short summary of what the apps see, to send an event only when it changes.
function upnp.signature(doc, key)
  local parts = {}
  for _, v in ipairs(upnp.evented(doc, key)) do parts[#parts + 1] = v[2] end
  return table.concat(parts, "\1")
end

-- ------------------------------------------------------------------ requests
local function fault(code, text) return { fault = { code = code, text = text } } end
local function out(list) return { out = list } end

--- A control request: service key, action name, arguments -> { out = { {name, value}... } } or
--- { fault = { code, text } }, and `event` when the Jooki has something to do (the caller emits it).
--- Reads the state, changes nothing.
function upnp.request(doc, key, action, args)
  args = args or {}
  local known = false
  for _, a in ipairs(ACTIONS[key] or {}) do if a[1] == action then known = true end end
  if not known then return fault(401, "Invalid Action") end
  if args.InstanceID ~= nil and args.InstanceID ~= "0" then return fault(718, "Invalid InstanceID") end
  local u = doc.upnp or {}
  if key == "cm" then
    if action == "GetProtocolInfo" then return out({ { "Source", "" }, { "Sink", upnp.SINK_PROTOCOLS } }) end
    if action == "GetCurrentConnectionIDs" then return out({ { "ConnectionIDs", "0" } }) end
    if args.ConnectionID ~= "0" then return fault(706, "Invalid connection reference") end
    return out({ { "RcsID", "0" }, { "AVTransportID", "0" }, { "ProtocolInfo", "" }, { "PeerConnectionManager", "" },
                 { "PeerConnectionID", "-1" }, { "Direction", "Input" }, { "Status", "OK" } })
  end
  if key == "rc" then
    if action == "ListPresets" then return out({ { "CurrentPresetNameList", "FactoryDefaults" } }) end
    if action == "SelectPreset" then
      if args.PresetName ~= "FactoryDefaults" then return fault(701, "Invalid Name") end
      return out({})
    end
    if args.Channel ~= nil and args.Channel ~= "Master" then return fault(402, "Invalid Args") end
    if action == "GetVolume" then return out({ { "CurrentVolume", tostring(volume(doc)) } }) end
    if action == "GetMute" then return out({ { "CurrentMute", muted(doc) and "1" or "0" } }) end
    if action == "SetVolume" then
      local v = tonumber(args.DesiredVolume)
      if not v or v < 0 or v > 100 or v ~= math.floor(v) then return fault(402, "Invalid Args") end
      local r = out({})
      r.event = { type = "upnp.action", act = "volume", percent = v }
      return r
    end
    -- SetMute
    local m = tostring(args.DesiredMute or ""):lower()
    if m ~= "1" and m ~= "0" and m ~= "true" and m ~= "false" and m ~= "yes" and m ~= "no" then return fault(402, "Invalid Args") end
    local r = out({})
    r.event = { type = "upnp.action", act = "mute", on = (m == "1" or m == "true" or m == "yes") }
    return r
  end
  -- AVTransport
  if action == "GetTransportInfo" then
    return out({ { "CurrentTransportState", upnp.transport(doc) }, { "CurrentTransportStatus", "OK" }, { "CurrentSpeed", "1" } })
  end
  if action == "GetPositionInfo" then
    local pos = upnp.hms(position_ms(doc))
    return out({ { "Track", u.uri and "1" or "0" }, { "TrackDuration", upnp.hms(duration_ms(doc)) },
                 { "TrackMetaData", u.uri and upnp.didl(u.info, u.uri) or "" }, { "TrackURI", u.uri or "" },
                 { "RelTime", pos }, { "AbsTime", pos }, { "RelCount", "2147483647" }, { "AbsCount", "2147483647" } })
  end
  if action == "GetMediaInfo" then
    return out({ { "NrTracks", u.uri and "1" or "0" }, { "MediaDuration", upnp.hms(duration_ms(doc)) }, { "CurrentURI", u.uri or "" },
                 { "CurrentURIMetaData", u.uri and upnp.didl(u.info, u.uri) or "" }, { "NextURI", "" }, { "NextURIMetaData", "" },
                 { "PlayMedium", u.uri and "NETWORK" or "NONE" }, { "RecordMedium", "NOT_IMPLEMENTED" }, { "WriteStatus", "NOT_IMPLEMENTED" } })
  end
  if action == "GetDeviceCapabilities" then return out({ { "PlayMedia", "NETWORK" }, { "RecMedia", "NOT_IMPLEMENTED" }, { "RecQualityModes", "NOT_IMPLEMENTED" } }) end
  if action == "GetTransportSettings" then return out({ { "PlayMode", "NORMAL" }, { "RecQualityMode", "NOT_IMPLEMENTED" } }) end
  if action == "GetCurrentTransportActions" then return out({ { "Actions", upnp.transport_actions(doc) } }) end
  if action == "SetAVTransportURI" then
    local uri = tostring(args.CurrentURI or ""):gsub("^%s+", ""):gsub("%s+$", "")
    -- http only: the Jooki's player has no TLS (no GIO TLS module in the image), an https song
    -- would never start; refused at once, the app can say it (or send it through its own proxy)
    if uri:match("^https://") then return fault(714, "Illegal MIME-type: https is not supported, http only") end
    if not uri:match("^http://[%w%[]") or #uri > 2048 or uri:find("[%c ]") then return fault(714, "Illegal MIME-type") end
    local info = upnp.didl_info(args.CurrentURIMetaData)
    if not upnp.mime_ok(info.mime) then return fault(714, "Illegal MIME-type") end
    local r = out({})
    r.event = { type = "upnp.action", act = "set_uri", uri = uri, info = info }
    return r
  end
  if action == "Play" then
    if not u.uri then return fault(701, "Transition not available") end
    local r = out({})
    r.event = { type = "upnp.action", act = "play" }
    return r
  end
  if action == "Pause" or action == "Stop" then
    local r = out({})
    r.event = { type = "upnp.action", act = action:lower() }
    return r
  end
  if action == "Seek" then
    local unit = args.Unit
    local ms
    if unit == "REL_TIME" or unit == "ABS_TIME" then ms = upnp.parse_hms(args.Target)
    elseif unit == "TRACK_NR" then ms = tostring(args.Target) == "1" and 0 or nil
    else return fault(710, "Seek mode not supported") end
    if not ms or ms < 0 then return fault(711, "Illegal seek target") end
    if not ours(doc) or upnp.transport(doc) == "STOPPED" then return fault(701, "Transition not available") end
    local r = out({})
    r.event = { type = "upnp.action", act = "seek", ms = ms }
    return r
  end
  -- Next, Previous: one song at a time, the app moves on by itself
  return out({})
end

-- ------------------------------------------------------------------ what the Jooki does
local function merge(into, r)
  if not r then return end
  for k, v in pairs(r.state or {}) do into.state[k] = v end
  for _, c in ipairs(r.commands or {}) do into.commands[#into.commands + 1] = c end
end

--- upnp.action { act, ... }: an app's order, on the Jooki (the request was already answered).
function upnp.on_action(doc, ev)
  if not upnp.enabled(doc) then return nil end
  local u = copy(doc.upnp or {})
  local res = { state = {}, commands = {} }
  local pb = doc.playback or {}
  local n = ours(doc)
  local active = n and n.uri == u.uri and (pb.state == "playing" or pb.state == "starting" or pb.state == "paused")
  if ev.act == "set_uri" then
    local was_playing = active and pb.state ~= "paused"
    u.uri, u.info = ev.uri, ev.info or {}
    res.state.upnp = u
    -- a new song while one plays: it plays at once (AVTransport); stopped or paused, it waits for Play
    if was_playing then merge(res, playback.play_uri(doc, u.uri, u.info)) end
    res.commands[#res.commands + 1] = { kind = "log", level = "info", key = "upnp.song", fields = { title = tostring(u.info.title or "") } }
  elseif ev.act == "play" then
    if not u.uri then return nil end
    if active and pb.state == "paused" then
      merge(res, playback.on_resume(doc, { now = ev.now }))
    elseif not (active and (pb.state == "playing" or pb.state == "starting")) then
      merge(res, playback.play_uri(doc, u.uri, u.info))
    end
  elseif ev.act == "pause" then
    if active and pb.state ~= "paused" then merge(res, playback.on_pause(doc, { source = "upnp", now = ev.now })) end
  elseif ev.act == "stop" then
    if active then merge(res, playback.on_stop(doc)) end
  elseif ev.act == "seek" then
    if active then merge(res, playback.on_seek(doc, { ms = math.max(1, ev.ms) })) end
  elseif ev.act == "volume" then
    u.muted = nil
    res.state.upnp = u
    merge(res, device.set_volume(doc, ev.percent))
  elseif ev.act == "mute" then
    -- silence without forgetting the volume (the page and the knob still show it); any new volume
    -- (here, the page, the knob) brings the sound back
    if ev.on == (u.muted == true) then return nil end
    u.muted = ev.on or nil
    res.state.upnp = u
    res.commands[#res.commands + 1] = { kind = "host.volume", percent = ev.on and 0 or device.effective_volume(doc, volume(doc)) }
  end
  if next(res.state) == nil and #res.commands == 0 then return nil end
  return res
end

--- Turned off (Settings): what an app had sent is forgotten, and a song it plays stops.
function upnp.on_config(doc)
  if upnp.enabled(doc) or not doc.upnp or not doc.upnp.uri then return nil end
  local res = { state = { upnp = {} }, commands = {} }
  if ours(doc) and (doc.playback or {}).state ~= "idle" then merge(res, playback.on_stop(doc)) end
  return res
end

function upnp.install(_, dispatch)
  dispatch.on("upnp.action", "upnp", upnp.on_action)
  dispatch.on("audiocfg.changed", "upnp", upnp.on_config)
end

return upnp
