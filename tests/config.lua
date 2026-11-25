local test = dofile("tests/support.lua")
local config = require("base_tools.config")

test.run("base-tools config merges dictionaries and replaces lists and explicit paths", function()
  local defaults = {
    buffer = { signs = true },
    lazygit = { args = { "--first", "--second" }, theme = true },
    compare = { keymap = { panel = { q = "close" }, extra = true } },
    status = { label = "Status" },
  }
  local overrides = {
    buffer = false,
    lazygit = { args = { "--only" }, theme = false },
    compare = { keymap = { panel = {} } },
    status = {},
  }
  local rules = { replace = { { "compare", "keymap", "panel" } } }
  local result = config.merge(defaults, overrides, rules)
  test.eq({
    buffer = false,
    lazygit = { args = { "--only" }, theme = false },
    compare = { keymap = { panel = {}, extra = true } },
    status = { label = "Status" },
  }, result)
  result.lazygit.args[1] = "mutated"
  result.status.label = "changed"
  result.compare.keymap.panel.q = false
  test.eq({ "--only" }, overrides.lazygit.args)
  test.eq("Status", defaults.status.label)
  test.eq({}, overrides.compare.keymap.panel)
  test.eq({ q = "close" }, defaults.compare.keymap.panel)
  test.eq({}, config.merge(defaults, { lazygit = { args = {} } }).lazygit.args)
  test.eq(defaults, config.merge(defaults))
  test.eq({}, config.merge(defaults, { status = {} }, { replace = { { "status" } } }).status)
end)

test.run("base-tools config paths return false, missing values and detached copies", function()
  local snapshot = { buffer = false, overlay = { signs = false, args = { "first" } } }
  test.eq(false, config.get(snapshot, "buffer"))
  test.eq(false, config.get(snapshot, "overlay", "signs"))
  test.eq(nil, config.get(snapshot, "buffer", "signs"))
  test.eq(nil, config.get(snapshot, "missing"))
  test.eq("first", config.get(snapshot, "overlay", "args", 1))
  local all = config.get(snapshot)
  all.overlay.args[1] = "changed"
  local overlay = config.get(snapshot, "overlay")
  overlay.signs = true
  test.eq({ signs = false, args = { "first" } }, snapshot.overlay)
end)
