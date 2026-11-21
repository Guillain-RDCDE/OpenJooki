local update = require("services.update")
local shell = require("adapters.shell")

local function find(r, kind, key, val)
  for _, c in ipairs((r and r.commands) or {}) do
    if c.kind == kind and (key == nil or c[key] == val) then return c end
  end
  return nil
end

describe("services.update", function()
  local doc = { config = { web_public_dir = "/tmp/web_ctrl_dirs/public", update_manifest_url = "http://127.0.0.1:8090/oj-test/version.json",
                           update_script_url = "http://127.0.0.1:8090/oj-test/o.sh" } }

  it("check: the configured manifest address, the result file in the web server's public directory, a log", function()
    local r = update.on_check(doc)
    local sh = find(r, "shell", "action", "update_check")
    assert_eq(sh.args, { out = "/tmp/web_ctrl_dirs/public/oj-latest.json", url = "http://127.0.0.1:8090/oj-test/version.json" })
    assert_true(find(r, "log", "key", "update.check") ~= nil)
    assert_nil(r.state); assert_eq(#r.commands, 2)
    -- and adapters.shell accepts exactly these arguments (the bench's own server is an allowed address)
    local argv = shell._argv("update_check", sh.args)
    assert_eq(argv[1], "sh"); assert_eq(argv[#argv - 1], sh.args.out); assert_eq(argv[#argv], sh.args.url)
  end)

  it("start: the status file, its link in the public directory, the configured installer address", function()
    local r = update.on_start(doc)
    local sh = find(r, "shell", "action", "update_start")
    assert_eq(sh.args, { status = "/jooki/app/www/public/openjooki-status.txt", link = "/tmp/web_ctrl_dirs/public/oj-status.txt",
                         url = "http://127.0.0.1:8090/oj-test/o.sh" })
    assert_true(find(r, "log", "key", "update.start") ~= nil)
    local argv = shell._argv("update_start", sh.args)
    assert_eq(argv[#argv - 2], sh.args.status); assert_eq(argv[#argv - 1], sh.args.link); assert_eq(argv[#argv], sh.args.url)
  end)

  it("the addresses come from the configuration only: without one the shell refuses to fetch anything", function()
    local r = update.on_check({})
    local sh = find(r, "shell", "action", "update_check")
    assert_eq(sh.args.out, "/tmp/web_ctrl_dirs/public/oj-latest.json"); assert_nil(sh.args.url)
    assert_nil(shell._argv("update_check", sh.args))
    assert_nil(shell._argv("update_start", find(update.on_start(nil), "shell").args))
    -- the real Jooki's addresses (kernel.config defaults) pass
    local cfg = require("kernel.config").defaults
    local real = update.on_check({ config = { update_manifest_url = cfg.update_manifest_url } })
    assert_true(shell._argv("update_check", find(real, "shell").args) ~= nil)
    real = update.on_start({ config = { update_script_url = cfg.update_script_url } })
    assert_true(shell._argv("update_start", find(real, "shell").args) ~= nil)
  end)

  it("another public directory (the bench's) moves the files the page reads", function()
    local bench = { config = { web_public_dir = "/tmp/bench/public" } }
    assert_eq(find(update.on_check(bench), "shell").args.out, "/tmp/bench/public/oj-latest.json")
    assert_eq(find(update.on_start(bench), "shell").args.link, "/tmp/bench/public/oj-status.txt")
  end)

  it("install: the two events (api.v1 emits them) and the two v2 commands share the handlers", function()
    local on, cmds = {}, {}
    local dispatch = { on = function(t, m, fn) on[t] = { module = m, fn = fn } end }
    local api = { command = function(name, schema, fn) cmds[name] = { schema = schema, fn = fn } end }
    update.install(api, dispatch)
    assert_eq(on["update.check"], { module = "update", fn = update.on_check })
    assert_eq(on["update.start"], { module = "update", fn = update.on_start })
    assert_eq(cmds["update.check"].fn, update.on_check); assert_nil(cmds["update.check"].schema)
    assert_eq(cmds["update.start"].fn, update.on_start); assert_nil(cmds["update.start"].schema)
    for _, op in ipairs({ "status", "try", "back" }) do
      assert_eq(on["chip." .. op], { module = "update", fn = update["on_chip_" .. op] })
      assert_eq(cmds["chip." .. op].fn, update["on_chip_" .. op])
    end
  end)

  it("the Wi-Fi chip on trial (docs/32): the answer file for the page, the package address, the shell's checks", function()
    local d = { config = { web_public_dir = "/tmp/web_ctrl_dirs/public", chip_package_url = "http://127.0.0.1:8090/oj-test/chip.tgz" } }
    for _, op in ipairs({ "status", "try", "back" }) do
      local r = update["on_chip_" .. op](d)
      local sh = find(r, "shell", "action", "chip_trial")
      assert_eq(sh.args, { op = op, out = "/tmp/web_ctrl_dirs/public/oj-chip.txt", url = "http://127.0.0.1:8090/oj-test/chip.tgz" })
      assert_true(find(r, "log", "key", "update.chip_" .. op) ~= nil)
      local argv = shell._argv("chip_trial", sh.args)
      assert_eq(argv[1], "sh"); assert_eq(argv[#argv - 2], sh.args.out); assert_eq(argv[#argv - 1], op); assert_eq(argv[#argv], sh.args.url)
    end
    -- trying fetches only from an allowed address; status and going back fetch nothing
    assert_nil(shell._argv("chip_trial", { op = "try", out = "/tmp/x", url = "https://example.com/chip.tgz" }))
    assert_nil(shell._argv("chip_trial", { op = "try", out = "/tmp/x" }))
    assert_true(shell._argv("chip_trial", { op = "status", out = "/tmp/x" }) ~= nil)
    assert_true(shell._argv("chip_trial", { op = "back", out = "/tmp/x" }) ~= nil)
    assert_nil(shell._argv("chip_trial", { op = "rm -rf", out = "/tmp/x" }))
    assert_nil(shell._argv("chip_trial", { op = "status", out = "relative" }))
    assert_nil(shell._argv("chip_trial", { op = "status", out = "/tmp/'x" }))
    -- the real Jooki's package address (kernel.config) passes, and names the pinned package
    local url = require("kernel.config").defaults.chip_package_url
    assert_true(shell._argv("chip_trial", { op = "try", out = "/tmp/x", url = url }) ~= nil)
    assert_match(url, "d87df74a")
  end)

  it("trying and going back are behind the parent code; asking where it stands is not", function()
    local sec = require("services.security")
    assert_true(sec.PROTECTED_V2["chip.try"]); assert_true(sec.PROTECTED_V2["chip.back"]); assert_nil(sec.PROTECTED_V2["chip.status"])
  end)
end)
