local config = require("kernel.config")

describe("kernel.config", function()
  before_each(function() config.load({}) end)

  it("serves the defaults", function()
    assert_eq(config.get("mqtt_port"), 1883)
    assert_eq(config.get("data_dir"), "/jooki/external/jooki")
  end)

  it("applies overrides of the right type", function()
    config.load({ mqtt_port = 11883, data_dir = "/tmp/bench" })
    assert_eq(config.get("mqtt_port"), 11883)
    assert_eq(config.get("data_dir"), "/tmp/bench")
  end)

  it("refuses unknown keys and wrong types", function()
    assert_error(function() config.load({ mqtt_prot = 1 }) end, "unknown config key")
    assert_error(function() config.load({ mqtt_port = "1883" }) end, "expected number")
    assert_error(function() config.get("nope") end, "unknown config key")
  end)

  it("all() is a copy", function()
    local a = config.all()
    a.mqtt_port = 1
    assert_eq(config.get("mqtt_port"), 1883)
  end)
end)
