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

test.run("base-tools config toggles existing booleans through validation and apply", function()
  local store = config.new({ buffer = { signs = false, debounce = 100 }, disabled = false }, {
    schema = { disabled = validators.one_of({ false }) },
  })
  local path = { "buffer", "signs" }
  local calls = 0
  local function apply(candidate)
    test.eq(false, store:get("buffer", "signs"))
    test.eq(true, candidate.buffer.signs)
    calls = calls + 1
  end

  test.eq(true, store:toggle(path, nil, apply))
  test.eq(true, store:get("buffer", "signs"))
  test.eq(false, store:toggle(path))
  test.eq(true, store:toggle(path, true))
  test.eq(false, store:toggle(path, false))

  assert(not pcall(store.toggle, store, path, 1, apply))
  assert(not pcall(store.toggle, store, { "buffer", "debounce" }, nil, apply))
  assert(not pcall(store.toggle, store, { "buffer", "missing" }, nil, apply))
  assert(not pcall(store.toggle, store, { "disabled" }, nil, apply))
  assert(not pcall(store.toggle, store, path, nil, function()
    error("apply failed")
  end))
  test.eq(1, calls)
  test.eq({ buffer = { signs = false, debounce = 100 }, disabled = false }, store:get())
end)

test.run("base-tools configure resolves from defaults and applies only a valid candidate", function()
  local store = config.new({ enabled = true, size = 10 }, { schema = { size = validators.range(0) } })
  store:change({ "enabled" }, false)
  local calls = 0
  local function apply(candidate)
    calls = calls + 1
    test.eq({ enabled = false, size = 10 }, store:get())
    test.eq({ enabled = true, size = 20 }, candidate)
  end
  assert(not pcall(store.configure, store, { size = -1 }, apply))
  test.eq(0, calls)
  assert(not pcall(store.configure, store, { size = 20 }, function()
    error("apply failed")
  end))
  test.eq({ enabled = false, size = 10 }, store:get())
  store:configure({ size = 20 }, apply)
  test.eq(1, calls)
  test.eq({ enabled = true, size = 20 }, store:get())
  store:configure()
  test.eq({ enabled = true, size = 10 }, store:get())
end)

test.run("base-tools sets and clears declared optional fields", function()
  local store = config.new({ buffer = { signs = false }, disabled = false, extra = true }, {
    schema = {
      buffer = { signs = validators.type("boolean"), on_attach = validators.optional(validators.type("function")) },
      disabled = config.section({ on_attach = validators.optional(validators.type("function")) }, {
        allow = function(value)
          return value == false
        end,
      }),
    },
  })
  local path = { "buffer", "on_attach" }
  local function on_attach() end
  store:validate(path, on_attach)
  test.eq(nil, store:get(unpack(path)))
  store:change(path, on_attach)
  test.eq(on_attach, store:get(unpack(path)))
  store:validate(path, nil)
  test.eq(on_attach, store:get(unpack(path)))
  assert(not pcall(store.change, store, path, "invalid"))
  assert(not pcall(store.change, store, { "buffer", "ON_attach" }, on_attach))
  assert(not pcall(store.change, store, { "disabled", "on_attach" }, on_attach))
  assert(not pcall(store.change, store, { "buffer", "signs" }, nil))
  assert(not pcall(store.change, store, { "extra" }, nil))
  store:change(path, nil, function(candidate)
    test.eq(nil, candidate.buffer.on_attach)
    test.eq(on_attach, store:get(unpack(path)))
  end)
  test.eq(nil, store:get(unpack(path)))
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

test.run("base-tools compiles nested rules and skips disabled section descendants", function()
  local checks = {}
  local buffer = {
    signs = function(value)
      checks[#checks + 1] = "signs"
      return type(value) == "boolean", "must be boolean"
    end,
    refresh = {
      delay = function(value)
        checks[#checks + 1] = "delay"
        return type(value) == "number" and value >= 0, "must be nonnegative"
      end,
    },
  }
  local store = config.new({ buffer = false, menu = { max_width = 40 } }, {
    schema = {
      buffer = config.section(buffer, {
        allow = function(value)
          checks[#checks + 1] = "allow"
          return value == false, "must be a table or false"
        end,
      }),
      menu = {
        max_width = function(value)
          checks[#checks + 1] = "width"
          return type(value) == "number"
        end,
      },
    },
    fields = {
      {
        path = { "buffer", "refresh" },
        validate = function(value)
          checks[#checks + 1] = "extra"
          return value.delay <= 1000, "delay must not exceed 1000"
        end,
      },
    },
  })
  test.eq({ "allow", "width" }, checks)
  checks = {}
  store:change({ "menu", "max_width" }, 50)
  test.eq({ "width" }, checks)

  checks = {}
  store:change({ "buffer" }, { signs = true, refresh = { delay = 100 } })
  test.eq({ "delay", "signs", "extra" }, checks)
  buffer.refresh.delay = function()
    error("mutated input schema")
  end
  checks = {}
  store:change({ "buffer", "refresh", "delay" }, 300)
  test.eq({ "delay", "extra" }, checks)
  local called = false
  local ok, err = pcall(store.change, store, { "buffer", "refresh", "delay" }, -1, function()
    called = true
  end)
  assert(not ok and tostring(err):find("buffer.refresh.delay must be nonnegative", 1, true))
  test.eq(false, called)
  test.eq(300, store:get("buffer", "refresh", "delay"))
  ok, err = pcall(store.change, store, { "buffer" }, "off")
  assert(not ok and tostring(err):find("buffer must be a table or false", 1, true))
  assert(not pcall(store.change, store, { "buffer" }, { signs = true }))

  checks = {}
  store:change({ "buffer" }, false)
  test.eq({ "allow" }, checks)
  test.eq(false, store:get("buffer"))
  assert(not pcall(store.change, store, { "buffer", "signs" }, true))
end)

test.run("base-tools accepts numeric schema paths and rejects malformed schemas", function()
  local defaults = { row = { [1] = true, label = "row" } }
  local store = config.new(defaults, {
    schema = { row = { [1] = validators.type("boolean"), label = validators.type("string") } },
  })
  store:change({ "row", 1 }, false)
  test.eq(false, store:get("row", 1))
  assert(not pcall(store.change, store, { "row", 1 }, "off"))
  assert(not pcall(config.new, {}, { schema = { [false] = validators.type("boolean") } }))
  assert(not pcall(config.new, {}, { schema = { row = false } }))
  local cycle = {}
  cycle.self = config.section(cycle)
  assert(not pcall(config.new, {}, { schema = cycle }))
end)

test.run("base-tools derives defaults, validation and replacement from one definition", function()
  local panel = { q = "close" }
  local function on_attach() end
  local defaults, options = config.compile_definition({
    buffer = {
      default_choice = "enabled",
      choices = {
        disabled = { value = false },
        enabled = {
          validate = function(value)
            return not value.signs or value.debounce < 1000, "must refresh sooner to show signs"
          end,
          fields = {
            signs = { default = false, validate = validators.type("boolean") },
            debounce = { default = 100, validate = validators.range(0) },
            on_attach = { validate = validators.optional(validators.type("function")) },
          },
        },
      },
    },
    command = { fields = { default = { default = "menu" }, handler = { default = on_attach } } },
    panel = { default = panel, replace = true },
  })
  panel.q = "changed"
  local store = config.new(defaults, options)
  test.eq({ signs = false, debounce = 100 }, store:get("buffer"))
  test.eq("menu", store:get("command", "default"))
  test.eq(on_attach, store:get("command", "handler"))
  test.eq({ q = "close" }, store:get("panel"))
  test.eq({}, store:resolve({ panel = {} }).panel)

  assert(store:toggle({ "buffer", "signs" }))
  assert(not pcall(store.change, store, { "buffer", "debounce" }, -1))
  local ok, err = pcall(store.change, store, { "buffer", "debounce" }, 1000)
  assert(not ok and tostring(err):find("buffer must refresh sooner to show signs", 1, true))
  test.eq(100, store:get("buffer", "debounce"))
  store:commit(store:resolve({ buffer = false }))
  test.eq(false, store:get("buffer"))
  ok, err = pcall(store.change, store, { "buffer" }, true)
  assert(not ok and tostring(err):find("buffer must be a table or false", 1, true))
  store:change({ "buffer" }, { signs = true, debounce = 5 })
  test.eq({ signs = true, debounce = 5 }, store:get("buffer"))
  store:reset()
  test.eq({ signs = false, debounce = 100 }, store:get("buffer"))
end)

test.run("base-tools supports literal choice defaults and rejects ambiguous definitions", function()
  local store = config.new(config.compile_definition({
    mode = { default_choice = "off", choices = { off = { value = false }, auto = { value = "auto" } } },
    section = {
      default_choice = "off",
      choices = { off = { value = false }, on = { fields = { delay = { default = 20 } } } },
    },
  }))
  test.eq(false, store:get("mode"))
  test.eq(false, store:get("section"))
  store:change({ "mode" }, "auto")
  test.eq("auto", store:get("mode"))
  assert(not pcall(store.change, store, { "mode" }, true))
  store:change({ "section" }, { delay = 5 })
  test.eq(5, store:get("section", "delay"))
  local function invalid_choice(choices, default_choice)
    assert(not pcall(config.compile_definition, { mode = { choices = choices, default_choice = default_choice } }))
  end
  invalid_choice({ off = { value = false } }, "missing")
  invalid_choice({ off = { value = false }, duplicate = { value = false } }, "off")
  invalid_choice({ first = { fields = {} }, second = { fields = {} } }, "first")
  invalid_choice({ first = { value = false, fields = {} } }, "first")
end)

test.run("base-tools resolves overrides against the selected table branch defaults", function()
  local function off_by_default(fields, replace)
    return {
      default_choice = "off",
      choices = { off = { value = false }, on = { fields = fields } },
      replace = replace,
    }
  end
  local defaults, rules = config.compile_definition({
    buffer = off_by_default({
      signs = { default = false, validate = validators.type("boolean") },
      mapping = { default = { q = "close" }, replace = true },
      nested = off_by_default({ debounce = { default = 100, validate = validators.range(0) } }),
    }),
    replacement = off_by_default({ signs = { default = false } }, true),
  })
  local store = config.new(defaults, rules)
  local opts = { buffer = { signs = true, mapping = {}, nested = {} }, replacement = {} }
  local expected = { buffer = { signs = true, mapping = {}, nested = { debounce = 100 } }, replacement = {} }
  test.eq(expected, config.merge(defaults, opts, rules))
  store:configure(opts)
  test.eq(expected, store:get())
  test.eq({ buffer = false, replacement = false }, store:resolve())
  test.eq({ buffer = false, replacement = false }, store:resolve({ buffer = false }))
  local candidate = store:resolve(opts)
  candidate.buffer.nested.debounce = 2
  test.eq(expected, store:resolve(opts))
  test.eq({ buffer = { signs = true, mapping = {}, nested = {} }, replacement = {} }, opts)
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
