local test = dofile("tests/support.lua")
local config = require("base_tools.config")
local validators = require("base_tools.config.validators")

test.run("base-tools config merges dictionaries and replaces lists and explicit paths", function()
  local store = config.new({
    buffer = { default = { signs = true } },
    lazygit = { default = { args = { "--first", "--second" }, theme = true } },
    compare = {
      fields = {
        keymap = { fields = { panel = { default = { q = "close" }, replace = true }, extra = { default = true } } },
      },
    },
    status = { default = { label = "Status" } },
  })
  local defaults = store:get()
  local overrides = {
    buffer = false,
    lazygit = { args = { "--only" }, theme = false },
    compare = { keymap = { panel = {} } },
    status = {},
  }
  local result = store:resolve(overrides)
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
  test.eq("Status", store:get("status", "label"))
  test.eq({}, overrides.compare.keymap.panel)
  test.eq({ q = "close" }, store:get("compare", "keymap", "panel"))
  test.eq({}, store:resolve({ lazygit = { args = {} } }).lazygit.args)
  test.eq(defaults, store:resolve())
  local replacing = config.new({ status = { default = { label = "Status" }, replace = true } })
  test.eq({}, replacing:resolve({ status = {} }).status)
end)

test.run("base-tools config paths return false, missing values and detached copies", function()
  local store =
    config.new({ buffer = { default = false }, overlay = { default = { signs = false, args = { "first" } } } })
  test.eq(false, store:get("buffer"))
  test.eq(false, store:get("overlay", "signs"))
  test.eq(nil, store:get("buffer", "signs"))
  test.eq(nil, store:get("missing"))
  test.eq("first", store:get("overlay", "args", 1))
  local all = store:get()
  all.overlay.args[1] = "changed"
  local overlay = store:get("overlay")
  overlay.signs = true
  test.eq({ signs = false, args = { "first" } }, store:get("overlay"))
end)

test.run("base-tools config instances own defaults, candidates and changes", function()
  local definition = { signs = { default = false }, map = { default = { q = "close" }, replace = true } }
  local store = config.new(definition)
  local another = config.new(definition)
  definition.map.default.q = "changed"
  definition.map.replace = false

  local overrides = { map = {} }
  local candidate = store:resolve(overrides)
  test.eq({}, candidate.map)
  test.eq("close", store:get("map", "q"))
  store:configure(overrides)
  candidate.map.q = "changed"
  overrides.map.q = "also changed"
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
  local function validate(range)
    assert(range.min <= range.max, "range.min must not exceed range.max")
    range.max = -1
    return true
  end

  assert(not pcall(config.new, { range = { default = { min = 3, max = 2 }, validate = validate } }))
  local store = config.new({ range = { default = { min = 1, max = 3 }, validate = validate } })
  local calls = 0
  local function apply(candidate)
    calls = calls + 1
    test.eq(1, store:get("range", "min"))
    test.eq({ min = 2, max = 3 }, candidate.range)
    candidate.range.max = -2
  end

  local ok, err = pcall(store.change, store, { "range", "min" }, 4, apply)
  assert(not ok and tostring(err):find("range.min must not exceed range.max", 1, true))
  assert(not pcall(store.configure, store, { range = { min = 4, max = 3 } }, apply))
  assert(not pcall(store.resolve, store, { range = { min = 4, max = 3 } }))
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
  local store = config.new({
    buffer = { default = { signs = false, debounce = 100 } },
    disabled = { default = false, validate = validators.one_of({ false }) },
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
  local store = config.new({ enabled = { default = true }, size = { default = 10, validate = validators.range(0) } })
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
  local store = config.new({
    buffer = {
      fields = {
        signs = { default = false, validate = validators.type("boolean") },
        on_attach = { validate = validators.optional(validators.type("function")) },
      },
    },
    disabled = {
      default_choice = "off",
      choices = {
        off = { value = false },
        on = { fields = { on_attach = { validate = validators.optional(validators.type("function")) } } },
      },
    },
    extra = { default = true },
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
  local store = config.new({
    buffer = {
      validate = track("buffer", validators.type("table")),
      fields = {
        signs = { default = false, validate = track("signs", validators.type("boolean")) },
        debounce = {
          default = 100,
          validate = track("debounce", function(value, get)
            get("buffer").signs = "mutated"
            return debounce(value)
          end),
        },
      },
    },
    mode = { default = "quiet", validate = track("mode", validators.one_of({ "quiet", "verbose" })) },
  })
  test.eq({ "debounce", "signs", "mode", "buffer" }, calls)

  calls = {}
  store:validate({ "buffer", "debounce" }, 0)
  test.eq({ "debounce", "buffer" }, calls)
  test.eq(100, store:get("buffer", "debounce"))

  calls = {}
  local applied = false
  local ok, err = pcall(store.change, store, { "buffer", "debounce" }, 1001, function()
    applied = true
  end)
  assert(not ok and tostring(err):find("buffer.debounce must be a finite number between 0 and 1000", 1, true))
  test.eq({ "debounce" }, calls)
  test.eq(false, applied)
  test.eq(100, store:get("buffer", "debounce"))

  calls = {}
  store:change({ "buffer", "debounce" }, 1000)
  test.eq({ "debounce", "buffer" }, calls)
  test.eq({ signs = false, debounce = 1000 }, store:get("buffer"))

  calls = {}
  assert(not pcall(store.change, store, { "buffer" }, { signs = false }))
  test.eq({ "debounce" }, calls)
  test.eq({ signs = false, debounce = 1000 }, store:get("buffer"))

  calls = {}
  local candidate = store:resolve({ buffer = { debounce = 200 } })
  test.eq({ "debounce", "signs", "mode", "buffer" }, calls)
  test.eq(200, candidate.buffer.debounce)
  test.eq(1000, store:get("buffer", "debounce"))

  calls = {}
  store:configure({ buffer = { debounce = 200 } })
  test.eq({ "debounce", "signs", "mode", "buffer" }, calls)
  test.eq(200, store:get("buffer", "debounce"))
end)

test.run("base-tools compiles nested rules and skips disabled section descendants", function()
  local checks = {}
  local buffer = {
    signs = {
      default = false,
      validate = function(value)
        checks[#checks + 1] = "signs"
        return type(value) == "boolean", "must be boolean"
      end,
    },
    refresh = {
      validate = function(value)
        checks[#checks + 1] = "extra"
        return value.delay <= 1000, "delay must not exceed 1000"
      end,
      fields = {
        delay = {
          default = 100,
          validate = function(value)
            checks[#checks + 1] = "delay"
            return type(value) == "number" and value >= 0, "must be nonnegative"
          end,
        },
      },
    },
  }
  local store = config.new({
    buffer = {
      default_choice = "off",
      choices = { off = { value = false }, on = { fields = buffer } },
    },
    menu = {
      fields = {
        max_width = {
          default = 40,
          validate = function(value)
            checks[#checks + 1] = "width"
            return type(value) == "number"
          end,
        },
      },
    },
  })
  test.eq({ "width" }, checks)
  checks = {}
  store:change({ "menu", "max_width" }, 50)
  test.eq({ "width" }, checks)

  checks = {}
  store:change({ "buffer" }, { signs = true, refresh = { delay = 100 } })
  test.eq({ "delay", "signs", "extra" }, checks)
  buffer.refresh.fields.delay.validate = function()
    error("mutated input definition")
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
  test.eq({}, checks)
  test.eq(false, store:get("buffer"))
  assert(not pcall(store.change, store, { "buffer", "signs" }, true))
end)

test.run("base-tools accepts numeric paths and rejects malformed definitions", function()
  local store = config.new({
    row = { fields = { [1] = { default = true, validate = validators.type("boolean") }, label = { default = "row" } } },
  })
  store:change({ "row", 1 }, false)
  test.eq(false, store:get("row", 1))
  assert(not pcall(store.change, store, { "row", 1 }, "off"))
  assert(not pcall(config.new, { [false] = { default = false } }))
  assert(not pcall(config.new, { row = false }))
  local cycle = {}
  cycle.self = { fields = cycle }
  assert(not pcall(config.new, cycle))
end)

test.run("base-tools derives defaults, validation and replacement from one definition", function()
  local panel = { q = "close" }
  local function on_attach() end
  local store = config.new({
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
  store:configure({ buffer = false })
  test.eq(false, store:get("buffer"))
  ok, err = pcall(store.change, store, { "buffer" }, true)
  assert(not ok and tostring(err):find("buffer must be a table or false", 1, true))
  store:change({ "buffer" }, { signs = true, debounce = 5 })
  test.eq({ signs = true, debounce = 5 }, store:get("buffer"))
  store:reset()
  test.eq({ signs = false, debounce = 100 }, store:get("buffer"))
end)

test.run("base-tools supports literal choice defaults and rejects ambiguous definitions", function()
  local store = config.new({
    mode = { default_choice = "off", choices = { off = { value = false }, auto = { value = "auto" } } },
    section = {
      default_choice = "off",
      choices = { off = { value = false }, on = { fields = { delay = { default = 20 } } } },
    },
  })
  test.eq(false, store:get("mode"))
  test.eq(false, store:get("section"))
  store:change({ "mode" }, "auto")
  test.eq("auto", store:get("mode"))
  assert(not pcall(store.change, store, { "mode" }, true))
  store:change({ "section" }, { delay = 5 })
  test.eq(5, store:get("section", "delay"))
  local function invalid_choice(choices, default_choice)
    assert(not pcall(config.new, { mode = { choices = choices, default_choice = default_choice } }))
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
  local store = config.new({
    buffer = off_by_default({
      signs = { default = false, validate = validators.type("boolean") },
      mapping = { default = { q = "close" }, replace = true },
      nested = off_by_default({ debounce = { default = 100, validate = validators.range(0) } }),
    }),
    replacement = off_by_default({ signs = { default = false } }, true),
  })
  local opts = { buffer = { signs = true, mapping = {}, nested = {} }, replacement = {} }
  local expected = { buffer = { signs = true, mapping = {}, nested = { debounce = 100 } }, replacement = {} }
  test.eq(expected, store:resolve(opts))
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

test.run("base-tools config validates nonempty strings and contiguous lists", function()
  local nonempty = validators.nonempty_string()
  assert(nonempty("lua") and nonempty(" "))
  assert(not nonempty("") and not nonempty(1))

  local strings = validators.list_of(nonempty)
  assert(strings({}) and strings({ "path", "buffer" }))
  assert(not strings({ filetype = "lua" }))
  assert(not strings({ [1] = "path", [3] = "buffer" }))
  local valid, message = strings({ "path", "" })
  test.eq(false, valid)
  test.eq("[2] must be a nonempty string", message)
end)

test.run("base-tools config validates map keys and values and forwards the configuration getter", function()
  local boolean_map = validators.map_of(validators.type("boolean"), validators.type("string"))
  assert(boolean_map({}) and boolean_map({ lua = false, rust = true }))
  assert(not boolean_map("lua"))
  local valid, message = boolean_map({ [1] = true })
  test.eq(false, valid)
  test.eq("key 1 must be string", message)
  valid, message = boolean_map({ lua = "true" })
  test.eq(false, valid)
  test.eq('["lua"] must be boolean', message)
  assert(validators.map_of(validators.type("boolean"))({ [1] = true }))

  local items = validators.list_of(function(item, get)
    return vim.startswith(item, get("prefix")), "must start with the configured prefix"
  end)
  local groups = validators.map_of(items, function(key, get)
    return key == get("prefix"), "must match the configured prefix"
  end)
  local store = config.new({
    prefix = { default = "x" },
    groups = { default = { x = { "x-one" } }, replace = true, validate = groups },
  })
  store:configure({ prefix = "y", groups = { y = { "y-two" } } })
  test.eq({ y = { "y-two" } }, store:get("groups"))
  assert(not pcall(store.configure, store, { prefix = "y", groups = { x = { "y-two" } } }))
  assert(not pcall(store.configure, store, { prefix = "y", groups = { y = { "x-two" } } }))
end)
