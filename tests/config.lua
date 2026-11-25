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

test.run("base-tools config instances own defaults, candidates and changes", function()
  local defaults = { signs = false, map = { q = "close" } }
  local rules = { replace = { { "map" } } }
  local store = config.new(defaults, rules)
  local another = config.new(defaults, rules)
  defaults.map.q = "changed"
  rules.replace[1][1] = "signs"

  local candidate = store:resolve({ map = {} })
  test.eq({}, candidate.map)
  test.eq("close", store:get("map", "q"))
  store:commit(candidate)
  candidate.map.q = "changed"
  test.eq({}, store:get("map"))

  local map = { r = "refresh" }
  store:change({ "map" }, map)
  store:change({ "signs" }, true)
  store:change({ "map", "r" }, false)
  map.r = "changed"
  local snapshot = store:get()
  snapshot.map.r = "changed"
  test.eq({ signs = true, map = { r = false } }, store:get())
  test.eq(false, another:get("signs"))
  test.eq("close", another:get("map", "q"))

  assert(not pcall(store.change, store, {}, true))
  assert(not pcall(store.change, store, { "missing" }, true))
  assert(not pcall(store.change, store, { "signs", "missing" }, true))
  assert(not pcall(store.change, store, { "map", "r" }, nil))
  test.eq({ signs = true, map = { r = false } }, store:get())
  test.eq({ signs = false, map = { q = "close" } }, store:resolve())
  store:reset()
  test.eq({ signs = false, map = { q = "close" } }, store:get())
end)

test.run("base-tools config validates before applying and publishing writes", function()
  local function validate(candidate)
    local range = candidate.range
    assert(range.min <= range.max, "range.min must not exceed range.max")
    range.max = -1
  end

  assert(not pcall(config.new, { range = { min = 3, max = 2 } }, { validate = validate }))
  local store = config.new({ range = { min = 1, max = 3 } }, { validate = validate })
  local calls = 0
  local function apply(candidate)
    calls = calls + 1
    test.eq(1, store:get("range", "min"))
    test.eq({ min = 2, max = 3 }, candidate.range)
    candidate.range.max = -2
  end

  local ok, err = pcall(store.change, store, { "range", "min" }, 4, apply)
  assert(not ok and tostring(err):find("range.min must not exceed range.max", 1, true))
  assert(not pcall(store.commit, store, { range = { min = 4, max = 3 } }, apply))
  test.eq(0, calls)
  test.eq({ min = 1, max = 3 }, store:get("range"))

  assert(not pcall(store.change, store, { "range", "min" }, 2, function()
    error("apply failed")
  end))
  assert(not pcall(store.change, store, { "range", "min" }, 2, function()
    store:reset()
  end))
  test.eq({ min = 1, max = 3 }, store:get("range"))

  store:change({ "range", "min" }, 2, apply)
  test.eq(1, calls)
  test.eq({ min = 2, max = 3 }, store:get("range"))
  store:reset()
  test.eq({ min = 1, max = 3 }, store:get("range"))
end)
