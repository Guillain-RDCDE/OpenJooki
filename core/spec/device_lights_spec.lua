local lights = require("services.device.lights")

local function doc_with(o)
  o = o or {}
  return { config = { data_dir = "/d" }, audiocfg = o.audiocfg or { volume = 40, shuffle_mode = false, repeat_mode = 1 },
           limits = o.limits, playback = o.playback, nfc = o.nfc, net = o.net, flags = o.flags or {}, device = { toy_safe = true } }
end
local function kinds(r)
  local out = {}
  for _, c in ipairs((r and r.commands) or {}) do
    if c.kind == "bus.publish" then out[#out + 1] = c.topic:gsub("^/j/", "") .. " " .. c.payload
    elseif c.kind == "emit" then out[#out + 1] = "emit " .. c.event.type .. (c.event.name and " " .. c.event.name or "")
    else out[#out + 1] = c.kind end
  end
  return out
end
-- Assertion rule: the lights' commands are a set (each LED group is painted once, whatever the order),
-- so `same` compares the whole set regardless of order and `has` / `find` look for one command.
local function find(r, kind, key, val)
  for _, c in ipairs((r and r.commands) or {}) do
    if c.kind == kind and (key == nil or c[key] == val) then return c end
  end
  return nil
end
local function has(r, kind, key, val) return find(r, kind, key, val) ~= nil end
local function sorted(list) local out = {} for i, v in ipairs(list) do out[i] = v end table.sort(out) return out end
local function same(actual, expected, msg) assert_eq(sorted(actual), sorted(expected), msg) end

describe("services.device.lights — ring, dots and event pulses", function()
  it("idle ring white, token playing ring off, Wi-Fi dots orange/white, dimmed at night", function()
    local doc = doc_with({ playback = { state = "idle" }, net = { connected = true, ip = "" } })
    same(kinds(lights.on_lights_refresh(doc)), { "led/output/set_raw RING,200,200,200", "led/output/set_raw PREV,200,200,200", "led/output/set_raw NEXT,200,40,0" })
    doc.playback = { state = "playing" }; doc.nfc = { tagId = "04" }; doc.net = { connected = true, ip = "10.0.0.2" }; doc.limits = { dim = true }
    same(kinds(lights.on_lights_refresh(doc)), { "led/output/set_raw RING,0,0,0", "led/output/set_raw PREV,10,10,10", "led/output/set_raw NEXT,10,10,10" })
    doc.playback = { state = "starting" }
    assert_true(has(lights.on_lights_refresh(doc), "bus.publish", "payload", "PREV,0,1,10"))
  end)

  it("the 30 s network check paints the dots only when what they show changes (a running pulse is not cut)", function()
    local doc = doc_with({ playback = { state = "idle" }, net = { connected = true, ip = "10.0.0.2" } })
    local r = lights.on_net_status(doc)
    same(kinds(r), { "led/output/set_raw RING,200,200,200", "led/output/set_raw PREV,200,200,200", "led/output/set_raw NEXT,200,200,200" })
    doc.device = r.state.device
    assert_true(doc.device.toy_safe, "the rest of state.device is kept")
    assert_nil(lights.on_net_status(doc), "the same network again: nothing painted")
    doc.net = { connected = true, ip = "" }
    r = lights.on_net_status(doc)
    assert_true(has(r, "bus.publish", "payload", "NEXT,200,40,0"), "the address lost: painted again")
    doc.device = r.state.device
    assert_nil(lights.on_net_status(doc))
  end)

  it("event lights: detect, write, error and warning pulses", function()
    local doc = doc_with()
    assert_true(has(lights.on_lights_event(doc, { name = "Evt.Character.Detect" }), "bus.publish", "payload", "PREV,0,10,200"))
    assert_true(has(lights.on_lights_event(doc, { name = "Evt.Character.Detect.Empty" }), "bus.publish", "payload", "PREV,200,0,0,2,500,0.5"))
    assert_true(has(lights.on_lights_event(doc, { name = "Evt.ToySafe.On" }), "bus.publish", "payload", "NEXT,200,200,0,1,500,0.5"))
    assert_nil(lights.on_lights_event(doc, { name = "Evt.Unknown" }))
  end)
end)

describe("services.device.lights — the start-up Wi-Fi chase", function()
  it("refresh leaves the side dots to the chase (ring only) while waiting", function()
    local doc = doc_with({ playback = { state = "idle" }, net = { connected = false } })
    assert_eq(kinds(lights.on_lights_refresh(doc)), { "led/output/set_raw RING,200,200,200" })
  end)

  it("bright/dim orange ping-pongs left<->right", function()
    local doc = doc_with({ playback = { state = "idle" }, net = { connected = false } })
    same(kinds(lights.on_wifi_anim(doc, { now = 0 })),
         { "led/output/set_raw PREV,200,40,0", "led/output/set_raw NEXT,50,10,0" })
    same(kinds(lights.on_wifi_anim(doc, { now = 0.45 })),
         { "led/output/set_raw PREV,50,10,0", "led/output/set_raw NEXT,200,40,0" })
  end)

  it("stops and settles the dots once associated", function()
    local doc = doc_with({ playback = { state = "idle" }, net = { connected = true, ip = "10.0.0.2" } })
    local r = lights.on_wifi_anim(doc, { now = 1 })
    assert_true(has(r, "timer.cancel", "name", "device.wifi_anim"))
    assert_true(has(r, "bus.publish", "payload", "PREV,200,200,200")); assert_true(has(r, "bus.publish", "payload", "NEXT,200,200,200"))
  end)

  it("none in airplane mode, nor while a token plays", function()
    local air = doc_with({ playback = { state = "idle" }, net = { connected = false } }); air.device.airplane = { boot = true }
    assert_true(has(lights.on_wifi_anim(air, { now = 0 }), "timer.cancel", "name", "device.wifi_anim"))
    local play = doc_with({ playback = { state = "playing" }, net = { connected = false } })
    assert_true(has(lights.on_wifi_anim(play, { now = 0 }), "timer.cancel", "name", "device.wifi_anim"))
  end)

  it("boot starts the Wi-Fi chase timer (not when the bench sets wifi_anim_s to 0)", function()
    local r = lights.on_boot(doc_with())
    local found = false
    for _, c in ipairs(r.commands) do
      if c.kind == "timer.every" and c.name == "device.wifi_anim" then found = true end
    end
    assert_true(found)
    local bench = doc_with(); bench.config.wifi_anim_s = 0
    assert_false(has(lights.on_boot(bench), "timer.every", "name", "device.wifi_anim"))
  end)
end)

describe("services.device.lights — the Christmas tree", function()
  it("5 s of colour-wheel frames on the ring and the side dots, then the real lights come back", function()
    local doc = doc_with({ net = { connected = true, ip = "10.0.0.2" } })
    local r = lights.on_party(doc)
    assert_true(r.state.device.party)
    same(kinds(r), { "timer.every", "timer.once" })
    assert_eq(find(r, "timer.every").name, "device.party"); assert_eq(find(r, "timer.once").seconds, 5)
    doc.device = r.state.device
    local stop = lights.on_party(doc)                            -- a second tap while it runs stops it (#54)
    assert_nil(stop.state.device.party)
    assert_true(has(stop, "timer.cancel", "name", "device.party")); assert_true(has(stop, "timer.cancel", "name", "device.party_end"))
    local f = lights.on_timer(doc, { name = "device.party", now = 0 })
    same(kinds(f), { "led/output/set_raw RING,200,0,0", "led/output/set_raw PREV,0,200,0", "led/output/set_raw NEXT,0,0,200" })
    assert_eq(kinds(lights.on_lights_refresh(doc)), {})          -- nobody repaints over it meanwhile
    assert_nil(lights.on_wifi_anim(doc, { now = 1 }))
    local e = lights.on_timer(doc, { name = "device.party_end", now = 5 })
    assert_nil(e.state.device.party)
    same(kinds(e), { "timer.cancel", "timer.cancel", "led/output/set_raw RING,200,200,200", "led/output/set_raw PREV,200,200,200", "led/output/set_raw NEXT,200,200,200" })
    assert_nil(lights.on_timer(doc, { name = "other" }))
  end)

  it("night mode dims it like every other light", function()
    local doc = doc_with({ limits = { dim = true } }); doc.device.party = true
    assert_true(has(lights.on_party_frame(doc, { now = 0 }), "bus.publish", "payload", "RING,10,0,0"))
  end)

  it("the colour wheel goes all the way round", function()
    assert_eq(lights.wheel(60), { 200, 200, 0 }); assert_eq(lights.wheel(180), { 0, 200, 200 }); assert_eq(lights.wheel(300), { 200, 0, 200 })
    assert_eq(lights.wheel(360), { 200, 0, 0 })
  end)
end)

describe("services.device.lights — the Christmas tree, the parents' way (#54)", function()
  it("lasts as long as the parents chose; 0 runs until it is stopped", function()
    local doc = doc_with({ audiocfg = { party_s = 60 } })
    assert_eq(find(lights.on_party(doc), "timer.once").seconds, 60)
    doc.audiocfg.party_s = 0
    local r = lights.on_party(doc)
    assert_true(r.state.device.party); assert_nil(find(r, "timer.once"))
    assert_true(has(r, "timer.every", "name", "device.party"))
    doc.audiocfg.party_s = "x"
    assert_eq(find(lights.on_party(doc), "timer.once").seconds, 5)   -- anything else: the 5 s of old
  end)

  it("does nothing while the lights are off", function()
    local doc = doc_with({ audiocfg = { lights_off = true } })
    assert_eq(lights.on_party(doc), {})
  end)
end)

describe("services.device.lights — the parents' colours (#54)", function()
  local function cdoc(cols, o)
    o = o or {}
    local d = doc_with({ playback = o.playback or { state = "idle" }, net = { connected = true, ip = "10.0.0.2" }, nfc = o.nfc, limits = o.limits })
    d.audiocfg.colours = cols
    return d
  end
  it("reads #rrggbb on the lights' 0-200 scale", function()
    assert_eq(lights.rgb("#ff0080"), { 200, 0, 100 }); assert_eq(lights.rgb("#000000"), { 0, 0, 0 })
    assert_nil(lights.rgb("red")); assert_nil(lights.rgb("#ff00")); assert_nil(lights.rgb(nil))
  end)
  it("the ring, the side dots and a token's blue take the chosen colours; missing ones stay the Jooki's", function()
    local doc = cdoc({ ring = "#ff0000", dots = "#00ff00" })
    same(kinds(lights.on_lights_refresh(doc)), { "led/output/set_raw RING,200,0,0", "led/output/set_raw PREV,0,200,0", "led/output/set_raw NEXT,0,200,0" })
    doc.playback = { state = "starting" }
    assert_true(has(lights.on_lights_refresh(doc), "bus.publish", "payload", "PREV,0,10,200"))   -- token: not chosen
    doc.audiocfg.colours.token = "#ffff00"
    assert_true(has(lights.on_lights_refresh(doc), "bus.publish", "payload", "PREV,200,200,0"))
    assert_true(has(lights.on_lights_event(doc, { name = "Evt.Character.Detect" }), "bus.publish", "payload", "NEXT,200,200,0"))
    assert_true(has(lights.on_lights_event(doc, { name = "Evt.Mobile.connect" }), "bus.publish", "payload", "NEXT,200,200,0,1,500,0.5"))
  end)
  it("the warnings keep their colours: orange without Wi-Fi, red on an error", function()
    local doc = cdoc({ dots = "#00ff00" }); doc.net = { connected = false }
    doc.playback = { state = "playing" }
    assert_true(has(lights.on_lights_refresh(doc), "bus.publish", "payload", "PREV,200,40,0"))
    assert_true(has(lights.on_lights_event(doc, { name = "Evt.Disk.FullError" }), "bus.publish", "payload", "PREV,200,0,0,2,500,0.5"))
  end)
  it("switching off flashes in the chosen colour, start-up blinks too; night mode dims them", function()
    local doc = cdoc({ off = "#8000ff", start = "#00ffff" }); doc.poweroff_int = { step = 1 }
    assert_true(has(lights.on_apply(doc), "bus.publish", "payload", "ALL,100,0,200"))
    doc.poweroff_int = nil; doc.lights_boot_int = { phase = "blinking", step = 1 }
    assert_true(has(lights.on_apply(doc), "bus.publish", "payload", "ALL,0,200,200"))
    doc.limits = { dim = true }
    assert_true(has(lights.on_apply(doc), "bus.publish", "payload", "ALL,0,10,10"))
  end)
end)

describe("services.device.lights — a playlist's own lights (#54)", function()
  local function pdoc(l, state)
    local d = doc_with({ playback = { state = state or "playing", now = { playlist = "p1" } }, net = { connected = true, ip = "10.0.0.2" }, nfc = { tagId = "04" } })
    d.library = { playlists = { p1 = { title = "P", tracks = {}, lights = l } } }
    return d
  end
  it("none: the ring goes off while a token plays, as always", function()
    same(kinds(lights.on_lights_refresh(pdoc(nil))), { "led/output/set_raw RING,0,0,0", "led/output/set_raw PREV,200,200,200", "led/output/set_raw NEXT,200,200,200" })
  end)
  it("colour: the ring stays that colour, no frames", function()
    local r = lights.on_lights_refresh(pdoc({ fx = "colour", colour = "#0000ff" }))
    same(kinds(r), { "led/output/set_raw RING,0,0,200", "led/output/set_raw PREV,200,200,200", "led/output/set_raw NEXT,200,200,200" })
    assert_nil(find(r, "timer.every"))
  end)
  it("breathe: frames every 0.25 s that glow from dim to full and back in 3 s", function()
    local doc = pdoc({ fx = "breathe", colour = "#ff0000" })
    local r = lights.on_lights_refresh(doc)
    assert_eq(find(r, "timer.every").name, "device.pl_anim"); assert_eq(find(r, "timer.every").seconds, 0.25)
    assert_true(has(r, "bus.publish", "payload", "RING,30,0,0"))                                   -- dimmest
    assert_true(has(lights.on_timer(doc, { name = "device.pl_anim", now = 1.5 }), "bus.publish", "payload", "RING,200,0,0"))   -- fullest
  end)
  it("rainbow goes round the wheel on the ring; the tree takes the side dots too", function()
    local doc = pdoc({ fx = "rainbow" })
    same(kinds(lights.on_timer(doc, { name = "device.pl_anim", now = 0 })), { "led/output/set_raw RING,200,0,0" })
    doc.library.playlists.p1.lights = { fx = "tree" }
    local r = lights.on_lights_refresh(doc)
    same(kinds(r), { "led/output/set_raw RING,200,0,0", "led/output/set_raw PREV,0,200,0", "led/output/set_raw NEXT,0,0,200", "timer.every" })
    assert_eq(#lights.on_timer(doc, { name = "device.pl_anim", now = 0.25 }).commands, 3)
  end)
  it("paused, another playlist, lights off: back to the usual lights and the frames stop", function()
    local doc = pdoc({ fx = "rainbow" }, "paused")
    same(kinds(lights.on_lights_refresh(doc)), { "led/output/set_raw RING,200,200,200", "led/output/set_raw PREV,200,200,200", "led/output/set_raw NEXT,200,200,200" })
    same(kinds(lights.on_timer(doc, { name = "device.pl_anim", now = 1 })), { "timer.cancel" })
    doc = pdoc({ fx = "rainbow" }); doc.playback.now.playlist = "p2"
    same(kinds(lights.on_timer(doc, { name = "device.pl_anim", now = 1 })), { "timer.cancel" })
    doc = pdoc({ fx = "rainbow" }); doc.audiocfg.lights_off = true
    same(kinds(lights.on_timer(doc, { name = "device.pl_anim", now = 1 })), { "timer.cancel" })
    assert_eq(kinds(lights.on_lights_refresh(doc)), {})
  end)
  it("the Christmas tree keeps the lights while it runs; a colour without its #rrggbb is ignored", function()
    local doc = pdoc({ fx = "rainbow" }); doc.device.party = true
    assert_nil(lights.on_timer(doc, { name = "device.pl_anim", now = 1 }))
    assert_eq(kinds(lights.on_lights_refresh(doc)), {})
    doc = pdoc({ fx = "colour" })
    assert_nil(lights.playlist_fx(doc))
  end)
  it("night mode dims a playlist's lights", function()
    local doc = pdoc({ fx = "colour", colour = "#ffffff" }); doc.limits = { dim = true }
    assert_true(has(lights.on_lights_refresh(doc), "bus.publish", "payload", "RING,10,10,10"))
  end)
end)
