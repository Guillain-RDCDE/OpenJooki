local lights = require("services.device.lights")
local buttons = require("services.device.buttons")
local power = require("services.device.power")
local device = require("services.device")
local function doc()
  return { audiocfg = { lights_off = false, heart_press = "next" }, config = { data_dir = "/d", wifi_anim_s = 0 },
           limits = {}, device = {}, net = { connected = true, ip = "10.0.0.1" } }
end
local function apply(d,r) for k,v in pairs((r or {}).state or {}) do d[k]=v end; return r end
local function has(r,kind,key,value)
  for _,c in ipairs((r or {}).commands or {}) do if c.kind==kind and (not key or c[key]==value) then return c end end
end
local function event(r,name)
  for _,c in ipairs((r or {}).commands or {}) do if c.kind=="emit" and c.event.type==name then return c.event end end
end
local function driver(r) return has(r,"bus.publish","topic","/j/ht/output/raw_write").payload end
describe("connected startup cue and silent manual shutdown", function()
  it("waits for association and a usable IP, then starts ten seconds once", function()
    local d=doc(); d.audiocfg.lights_off=true; d.net={connected=false}
    local r=apply(d,lights.on_boot(d,{audiocfg=d.audiocfg}))
    assert_eq(d.lights_boot_int.phase,"connecting")
    assert_nil(has(r,"timer.once","name","device.lights_boot"))
    assert_nil(lights.on_boot_frame(d))
    for _,ip in ipairs({"","0.0.0.0"}) do
      r=apply(d,lights.on_net_status(d,{connected=true,ip=ip}))
      assert_nil(has(r,"timer.once","name","device.lights_boot"))
    end
    r=apply(d,lights.on_net_status(d,{connected=true,ip="10.0.0.1"}))
    assert_eq(d.lights_boot_int.phase,"waiting")
    assert_eq(has(r,"timer.once","name","device.lights_boot").seconds,10)
    assert_nil(has(lights.on_net_status(d,{connected=true,ip="10.0.0.1"}),"timer.once","name","device.lights_boot"))
    r=apply(d,lights.on_net_status(d,{connected=false,ip=""}))
    assert_eq(d.lights_boot_int.phase,"connecting")
    assert_true(has(r,"timer.cancel","name","device.lights_boot") ~= nil)
    assert_nil(lights.on_boot_frame(d))
    r=apply(d,lights.on_net_status(d,{connected=true,ip="10.0.0.1"}))
    assert_eq(has(r,"timer.once","name","device.lights_boot").seconds,10)
    for _=1,7 do apply(d,lights.on_boot_frame(d)) end
    assert_nil(has(lights.on_net_status(d,{connected=true,ip="10.0.0.1"}),"timer.once","name","device.lights_boot"))
  end)
  it("shows three red flashes even in darkness, keeps output muted and shuts down only afterwards", function()
    for _,reason in ipairs({"button","page"}) do
      local d=doc(); d.audiocfg.lights_off=true; d.audiocfg.volume=72; d.lights_boot_int={phase="waiting"}
      local r=apply(d,power.on_off_request(d,{reason=reason,now=20}))
      assert_true(has(r,"bus.publish","payload","ALL,200,0,0") ~= nil)
      assert_eq(driver(r),"34 8")
      assert_eq(has(r,"host.volume").percent,0)
      assert_nil(event(r,"system.event")); assert_nil(event(r,"shutdown.request"))
      assert_eq(d.audiocfg.volume,72); assert_eq(device.effective_volume(d,100),0)
      assert_nil(power.on_off_request(d,{reason=reason}))
      assert_nil(lights.on_boot_frame(d))
      assert_nil(buttons.on_button(d,{button="circle",down=true,now=21}))
      assert_nil(event(buttons.on_tick(d,{now=30}),"power.off_request"))
      for step=2,6 do
        r=apply(d,power.on_off_frame(d))
        assert_eq(driver(r),step%2==1 and "34 8" or "34 0")
        assert_nil(event(r,"shutdown.request"))
      end
      r=power.on_off_frame(d)
      assert_eq(event(r,"shutdown.request").reason,reason)
      local shutdown=power.on_shutdown_request(d,{reason=reason})
      assert_nil(has(shutdown,"bus.publish","payload","CIRCLE,200,0,0"))
      assert_true(has(shutdown,"shell","action","poweroff") ~= nil)
    end
  end)
  it("does not delay protective shutdown or turn a termination signal into a manual blink cue", function()
    local d=doc()
    for _,reason in ipairs({"battery","inactivity"}) do
      local r=power.on_off_request(d,{reason=reason})
      assert_nil(r.state); assert_nil(has(r,"timer.once","name","device.poweroff"))
      assert_eq(event(r,"system.event").after.type,"shutdown.request")
    end
    assert_nil(power.on_off_frame(d))
    assert_nil(has(power.on_shutdown_request(d,{reason="signal"}),"shell","action","poweroff"))
  end)
end)

describe("heart presses without a light gesture", function()
  it("five rapid presses each act immediately and never change the light preference", function()
    for _,mode in ipairs({"next","pause"}) do
      local d=doc();d.audiocfg.heart_press=mode;d.audiocfg.lights_off=true
      for n=1,5 do
        apply(d,buttons.on_button(d,{button="circle",down=true,now=n*.2}))
        local r=apply(d,buttons.on_button(d,{button="circle",down=false,now=n*.2+.05}))
        assert_true(event(r,mode=="next" and "playback.next" or "playback.toggle_request") ~= nil)
        assert_nil(has(r,"timer.once")); assert_nil(event(r,"lights.toggle"))
        assert_true(d.audiocfg.lights_off)
      end
    end
  end)
end)
