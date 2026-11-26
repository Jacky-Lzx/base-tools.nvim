local test = dofile("tests/support.lua")
local context = require("base_tools.context")
local first = context.new("one.nvim")
local second = context.new("two.nvim")

local function fails(expected, fn, ...)
  local ok, err = pcall(fn, ...)
  assert(not ok and type(err) == "string", vim.inspect({ ok, err }))
  test.eq(expected, err:sub(1, #expected))
  return err
end

test.run("error contexts isolate config owners and inherit through sections", function()
  local config = require("base_tools.config")
  local validators = require("base_tools.config.validators")
  local schema = { tree = { fields = { width = { default = 40, validate = validators.range(10) } } } }
  local alpha = config.new(schema, { context = first })
  local beta = config.new(schema, { context = second })

  fails("one.nvim [config.resolve]: Config options must be a table", alpha.resolve, alpha, false)
  fails("two.nvim [config.configure]: tree.width must be", beta.configure, beta, { tree = { width = 2 } })
  local section = alpha:section("tree")
  fails("one.nvim [config.section.merge]: tree.width must be", section.merge, section, { width = 2 })
  fails("one.nvim [config.change]: Config path does not exist", alpha.change, alpha, { "absent" }, 1)
  fails("one.nvim [config.new]: tree.width must be", config.new, {
    tree = { fields = { width = { default = 2, validate = validators.range(10) } } },
  }, { context = first })
  test.eq(40, alpha:get("tree", "width"))
  test.eq(40, beta:get("tree", "width"))

  local problem = {}
  local ok, err = pcall(alpha.configure, alpha, { tree = { width = 45 } }, function()
    error(problem, 0)
  end)
  test.eq(false, ok)
  assert(err == problem)
  test.eq(40, alpha:get("tree", "width"))
  alpha:configure({ tree = { width = 45 } })
  test.eq(45, alpha:get("tree", "width"))
end)

test.run("error contexts distinguish registration and command execution", function()
  local commands = require("base_tools.user_command")
  local alpha = commands.new({ context = first })
  local beta = commands.new({ context = second })
  local cleanup = alpha.create("ContextTest", function() end)
  fails(
    "two.nvim [user_command.create]: Command already exists: ContextTest",
    beta.create,
    "ContextTest",
    function() end
  )
  cleanup()

  local definition = commands.group("ContextTest", {
    actions = { { name = "run", run = function() end } },
  }, { context = first })
  local cleanups = alpha.create_many({ definition })
  fails("one.nvim [user_command.run]: Unknown ContextTest action: bad", definition[2], { fargs = { "bad" } })
  cleanups[1]()
end)

test.run("error contexts follow nested float resources and preserve cleanup", function()
  local float = require("base_tools.float")
  local preview = require("base_tools.preview")
  local api = vim.api
  local original = { #api.nvim_list_wins(), #api.nvim_list_bufs() }
  local window = { relative = "editor", row = 1, col = 2, width = 12, height = 2, border = "single" }
  fails("one.nvim [buffer.scratch]: Scratch buffer name must be a string", float.open, {
    config = window,
    buf_options = { name = 42 },
    context = first,
  })
  fails("two.nvim [float.open]:", float.open, {
    config = window,
    win_options = { invalid_option = true },
    context = second,
  })
  test.eq(original, { #api.nvim_list_wins(), #api.nvim_list_bufs() })

  local view = float.open({ config = window, context = first, enter = true })
  fails("one.nvim [keymap.install]:", view.map, view, "v", "q", function() end)
  fails("one.nvim [border_labels.set]: Expected labels", view.set_border_labels, view, { top = 42 })
  view:close()

  local lines = {}
  for index = 1, 20 do
    lines[index] = tostring(index)
  end
  fails("two.nvim [scrollbar.update]:", preview.open, {
    config = window,
    context = second,
    lines = lines,
    scrollbar = { thumb_highlight = true },
  })
  test.eq(original, { #api.nvim_list_wins(), #api.nvim_list_bufs() })
end)

test.run("error contexts preserve asynchronous process results", function()
  local process = require("base_tools.process")
  local alpha = process.new({ context = first })
  local beta = process.new({ context = second })
  local alpha_error, beta_error, completed
  alpha:run({ vim.fn.tempname() }, nil, function(result, err)
    test.eq(nil, result)
    alpha_error = err
  end)
  beta:run({ vim.fn.tempname() }, nil, function(result, err)
    test.eq(nil, result)
    beta_error = err
  end)
  beta:run({ "sh", "-c", "printf warning >&2; exit 7" }, nil, function(result, err)
    test.eq(nil, err)
    completed = result
  end)
  assert(vim.wait(1000, function()
    return alpha_error and beta_error and completed
  end, 1))
  assert(vim.startswith(alpha_error, "one.nvim [process.run]:"))
  assert(vim.startswith(beta_error, "two.nvim [process.run]:"))
  test.eq(7, completed.code)
  test.eq("warning", completed.stderr)
  alpha:close()
  beta:close()
end)

test.run("timers, lifecycle and stateless helpers accept the same context", function()
  local timer = require("base_tools.timer").new({ context = vim.deepcopy(first) })
  timer:close()
  fails("one.nvim [timer.start]: cannot start a closed timer", timer.start, timer, 0, function() end)

  local lifecycle = require("base_tools.lifecycle").new("missing_module_for_error_context", {}, { context = second })
  fails("two.nvim [lifecycle.ensure]:", lifecycle.ensure, lifecycle)
  fails("one.nvim [text.clip]: Expected a numeric cell budget", require("base_tools.text").clip, "text", false, {
    context = first,
  })
  fails("two.nvim [color.hex]: Expected an RGB color", require("base_tools.color").hex, "bad", { context = second })
  fails("one.nvim [keys.encode]:", require("base_tools.keys").encode, false, nil, { context = first })
end)

test.run("context notifications preserve the level and attach the owner once", function()
  local notify = vim.notify
  local calls = {}
  vim.notify = function(message, level, opts)
    calls[#calls + 1] = { message, level, opts }
  end

  local warn, err = vim.log.levels.WARN, vim.log.levels.ERROR
  local opts = { source = "override", title = "Files" }
  local ok, failure = pcall(function()
    first:notify("No file selected", warn, opts)
    local config = require("base_tools.config").new({}, { context = first })
    local _, config_error = pcall(config.resolve, config, false)
    first:notify(config_error, err)
    second:notify("two.nvim: Already attributed", err)
  end)
  vim.notify = notify
  assert(ok, failure)
  test.eq({ source = "override", title = "Files" }, opts)
  test.eq({
    { "one.nvim: No file selected", warn, { source = "one.nvim", title = "Files" } },
    { "one.nvim [config.resolve]: Config options must be a table", err, { source = "one.nvim" } },
    { "two.nvim: Already attributed", err, { source = "two.nvim" } },
  }, calls)
end)
