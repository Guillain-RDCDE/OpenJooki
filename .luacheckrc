-- luacheck configuration for the 2.0 core (run: luacheck core)
std = "lua51"
max_line_length = false
exclude_files = { "core/vendor/**" }
-- the four functions the C host provides
globals = { "c_syslog", "c_alsa_set_volume", "c_isTerminating", "c_sd_notify" }
files["core/spec/**"] = {
  -- the runner's vocabulary; handlers in specs often ignore (doc, event)
  globals = { "describe", "it", "before_each", "assert_eq", "assert_true", "assert_false", "assert_nil", "assert_error", "assert_match" },
  unused_args = false,
}
