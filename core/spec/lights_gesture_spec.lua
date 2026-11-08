local lights = require("services.device.lights")
local buttons = require("services.device.buttons")
local function doc()
  return { audiocfg = { lights_off = false, heart_press = "next" }, config = { data_dir = "/d", wifi_anim_s = 0 },
           limits = {}, device = {}, net = { connected = true, ip = "10.0.0.1" } }
end
local function apply(d, r) for k, v in pairs((r or {}).state or {}) do d[k] = v end; return r end
local function has(r, kind, key, value)
  for _, c in ipairs((r or {}).commands or {}) do if c.kind == kind and (not key or c[key] == value) then return c end end
end
local function event(r, name)
  for _, c in ipairs((r or {}).commands or {}) do if c.kind == "emit" and c.event.type == name then return c.event end end
end
local function click(d, t, held)
  apply(d, buttons.on_button(d, { button="circle", down=true, now=t }))
  return apply(d, buttons.on_button(d, { button="circle", down=false, now=t+(held or 0.1) }))
end
local function driver(r) return has(r, "bus.publish", "topic", "/j/ht/output/raw_write").payload end

describe("five heart clicks", function()
  it("toggles only after five fast releases, without transport actions", function()
    for _, choice in ipairs({ "none", "next", "pause" }) do
      local d = doc(); d.audiocfg.heart_press = choice
      for i = 1, 5 do
        local r = click(d, i * 0.25)
        assert_nil(event(r, "playback.next")); assert_nil(event(r, "playback.toggle_request"))
        assert_eq(event(r, "lights.toggle") ~= nil, i == 5)
      end
      assert_nil(d.activity.heart_clicks)
      assert_nil(buttons.on_heart_clicks(d, { now=3 }))
    end
  end)
  it("counts valid edges delivered together with the same event timestamp", function()
    local d = doc()
    for i=1,5 do
      local r=click(d,1,0)
      assert_eq(event(r,"lights.toggle") ~= nil,i==5)
    end
  end)
  it("retains single and incomplete multi-click actions after the gap", function()
    for n = 1, 4 do
      local d = doc()
      for i = 1, n do click(d, i * 0.25) end
      local r = apply(d, buttons.on_heart_clicks(d, { now=3 }))
      local count = 0
      for _, c in ipairs(r.commands) do if c.kind == "emit" then assert_eq(c.event.type,"playback.next"); count=count+1 end end
      assert_eq(count,n); assert_nil(d.activity.heart_clicks)
    end
  end)
  it("slow or longer presses cannot trigger the five-click gesture", function()
    local d = doc()
    for i = 1, 8 do
      local r = click(d, i * 2, 0.8)
      assert_nil(event(r,"lights.toggle")); assert_true(event(r,"playback.next") ~= nil)
    end
    for i = 1, 8 do
      local r = click(d, i * 2 + 20)
      assert_nil(event(r,"lights.toggle")); assert_eq(d.activity.heart_clicks.count,1)
    end
  end)
  it("ignores duplicate downs and stray releases, and resets on another button", function()
    local d = doc(); click(d,1)
    apply(d,buttons.on_button(d,{button="circle",down=true,now=1.2}))
    assert_nil(buttons.on_button(d,{button="circle",down=true,now=1.21}))
    apply(d,buttons.on_button(d,{button="circle",down=false,now=1.3}))
    assert_eq(d.activity.heart_clicks.count,2)
    apply(d,buttons.on_button(d,{button="circle",down=false,now=1.31}))
    assert_eq(d.activity.heart_clicks.count,2)
    apply(d,buttons.on_button(d,{button="next",down=true,now=1.4}))
    assert_nil(d.activity.heart_clicks)
  end)
  it("long hold still powers off and cancels pending short clicks", function()
    local d = doc(); click(d,1)
    apply(d,buttons.on_button(d,{button="circle",down=true,now=1.2}))
    assert_nil(buttons.on_heart_clicks(d,{now=2}))
    local r = apply(d,buttons.on_tick(d,{now=6.3}))
    assert_true(event(r,"power.off_request") ~= nil); assert_nil(event(r,"playback.next"))
    assert_nil(d.activity.heart_clicks)
    assert_nil(event(click(d,8,0.01),"lights.toggle")) -- a single brief click cannot toggle the lights
  end)
end)

describe("startup darkness and physical overrides", function()
  it("does not replay the boot cue on reconnect or charging", function()
    local d = doc(); d.audiocfg.lights_off=true
    apply(d,lights.on_boot(d,{audiocfg=d.audiocfg}))
    assert_eq(driver(lights.on_apply(d)),"34 8")
    assert_nil(has(lights.on_apply(d),"timer.once","name","device.lights_boot"))
    for _=1,7 do apply(d,lights.on_boot_frame(d)) end
    assert_eq(driver(lights.on_apply(d)),"34 0")
    assert_eq(driver(lights.on_power(d,{type="power.plugged",on=true})),"34 0")
    assert_nil(lights.on_boot_frame(d))
  end)
  it("web changes and physical gestures cancel pending startup frames", function()
    for _, phase in ipairs({"waiting","blinking"}) do
      local d = doc(); d.audiocfg.lights_off=true
      d.lights_boot_int={phase=phase,step=1}
      local r=apply(d,lights.on_preference(d))
      assert_eq(driver(r),"34 0"); assert_nil(lights.on_boot_frame(d))
      assert_true(has(r,"timer.cancel","name","device.lights_boot") ~= nil)
      r=apply(d,lights.on_toggle(d,{physical=true}))
      assert_false(d.audiocfg.lights_off); assert_eq(driver(r),"34 8")
      assert_nil(lights.on_boot_frame(d))
    end
  end)
  it("persists the all-day switch and permits temporary light during a scheduled night", function()
    local d=doc();d.limits.lights_off=true
    assert_nil(lights.on_toggle(d,{}))
    local r=apply(d,lights.on_toggle(d,{physical=true}))
    assert_false(lights.off(d));assert_false(has(r,"files.write").doc.lights_off)
    assert_eq(driver(r),"34 8")
    assert_nil(has(lights.on_limits(d),"bus.publish","topic","/j/ht/output/raw_write"))
    d.limits.fade=0.5;assert_false(lights.off(d))
    r=apply(d,lights.on_toggle(d,{physical=true}))
    assert_true(lights.off(d));assert_true(has(r,"files.write").doc.lights_off)
    assert_eq(driver(r),"34 0")
  end)
  it("ends the night override at its boundary, on web changes and at restart", function()
    local d=doc();d.limits.lights_off=true
    apply(d,lights.on_toggle(d,{physical=true}));assert_false(lights.off(d))
    d.limits.lights_off=false
    apply(d,lights.on_limits(d));assert_nil(d.lights_override_int.on)
    d.limits.lights_off=true
    apply(d,lights.on_limits(d));assert_true(lights.off(d))
    apply(d,lights.on_toggle(d,{physical=true}))
    apply(d,lights.on_preference(d));assert_true(lights.off(d))
    apply(d,lights.on_toggle(d,{physical=true}))
    apply(d,lights.on_boot(d,{audiocfg=d.audiocfg,bedtime={enabled=true,lights_off=true,start=1200,stop=420,tzbase=0,tzdst="none"},wall=1768514400}))
    assert_nil(d.lights_override_int.on)
    for _=1,7 do apply(d,lights.on_boot_frame(d)) end
    assert_true(lights.off(d))
  end)
end)
