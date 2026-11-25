local test = dofile("tests/support.lua")
local config = require("base_tools.config")
local validators = require("base_tools.config.validators")

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
  store:check(candidate)
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
  assert(not pcall(store.check, store, { range = { min = 4, max = 3 } }))
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

test.run("base-tools config validates only affected field paths for a change", function()
  local calls = {}
  local debounce = validators.range(0, 1000)
  local function track(name, validate)
    return function(value, get)
      calls[#calls + 1] = name
      return validate(value, get)
    end
  end
  local store = config.new({ buffer = { debounce = 100, signs = false }, mode = "quiet" }, {
    fields = {
      { path = { "buffer" }, validate = track("buffer", validators.type("table")) },
      { path = { "buffer", "signs" }, validate = track("signs", validators.type("boolean")) },
      {
        path = { "buffer", "debounce" },
        validate = track("debounce", function(value, get)
          get("buffer").signs = "mutated"
          return debounce(value)
        end),
      },
      { path = { "mode" }, validate = track("mode", validators.one_of({ "quiet", "verbose" })) },
    },
  })
  test.eq({ "buffer", "signs", "debounce", "mode" }, calls)

  calls = {}
  store:validate({ "buffer", "debounce" }, 0)
  test.eq({ "buffer", "debounce" }, calls)
  test.eq(100, store:get("buffer", "debounce"))

  calls = {}
  local applied = false
  local ok, err = pcall(store.change, store, { "buffer", "debounce" }, 1001, function()
    applied = true
  end)
  assert(not ok and tostring(err):find("buffer.debounce must be a finite number between 0 and 1000", 1, true))
  test.eq({ "buffer", "debounce" }, calls)
  test.eq(false, applied)
  test.eq(100, store:get("buffer", "debounce"))

  calls = {}
  store:change({ "buffer", "debounce" }, 1000)
  test.eq({ "buffer", "debounce" }, calls)
  test.eq({ signs = false, debounce = 1000 }, store:get("buffer"))

  calls = {}
  assert(not pcall(store.change, store, { "buffer" }, { signs = false }))
  test.eq({ "buffer", "signs", "debounce" }, calls)
  test.eq({ signs = false, debounce = 1000 }, store:get("buffer"))

  calls = {}
  store:commit(store:get())
  test.eq({ "buffer", "signs", "debounce", "mode" }, calls)
end)

test.run("base-tools config validator templates support bounds, choices and optional values", function()
  local function accepts(rule, value)
    return (rule(value))
  end
  local range = validators.range(-1, 1)
  test.eq(true, accepts(range, -1))
  test.eq(true, accepts(range, 1))
  test.eq(true, accepts(range, 0.5))
  test.eq(false, accepts(range, -1.01))
  test.eq(false, accepts(range, "0"))
  test.eq(false, accepts(validators.range(0), math.huge))
  test.eq(false, accepts(validators.range(nil, 5), 0 / 0))
  test.eq(true, accepts(validators.range(nil, 5), -10))
  assert(not pcall(validators.range, 5, 4))

  local integer = validators.integer(1, 3)
  test.eq(true, accepts(integer, 3))
  test.eq(false, accepts(integer, 3.5))
  test.eq(false, accepts(integer, 0))

  local values = { "auto", false }
  local choice = validators.one_of(values)
  values[1] = "always"
  test.eq(true, accepts(choice, false))
  test.eq(true, accepts(choice, "auto"))
  test.eq(false, accepts(choice, "always"))

  local optional = validators.optional(validators.type("function"))
  test.eq(true, accepts(optional, nil))
  test.eq(false, accepts(optional, false))
  local either = validators.any_of(validators.type("boolean"), validators.one_of({ "auto" }))
  test.eq(true, accepts(either, false))
  test.eq(true, accepts(either, "auto"))
  test.eq(false, accepts(either, "true"))
  local branch = validators.any_of(function(value)
    value.enabled = true
    return false, "first alternative failed"
  end, function(value)
    return value.enabled == true, "must be enabled"
  end)
  local value = { enabled = false }
  test.eq(false, accepts(branch, value))
  test.eq(false, value.enabled)
end)
