local test = dofile("tests/support.lua")
local commands = require("base_tools.user_command")
local api = vim.api

test.run("base-tools user command registries isolate global and buffer ownership", function()
  local first, second = commands.new(), commands.new()
  local name = "BaseToolsOwnedCommandFixture"
  local buffer = api.nvim_create_buf(false, true)
  local calls = {}

  local stale = first.create(name, function()
    calls[#calls + 1] = "old"
  end, { desc = "fixture" })
  local cleanup = first.create(name, function(args)
    calls[#calls + 1] = args.args
  end, { nargs = 1, desc = "fixture" })
  stale()
  local ok, err = pcall(second.create, name, function() end, { force = true })
  assert(not ok and tostring(err):find("Command already exists", 1, true))

  local local_cleanup = second.create(name, function()
    calls[#calls + 1] = "buffer"
  end, {}, buffer)
  api.nvim_buf_call(buffer, function()
    vim.cmd(name)
  end)
  first.delete(name, buffer)
  assert(api.nvim_buf_get_commands(buffer, {})[name])
  vim.cmd(name .. " fresh")
  test.eq({ "buffer", "fresh" }, calls)

  api.nvim_del_user_command(name)
  second.create(name, function()
    calls[#calls + 1] = "other owner"
  end, { desc = "fixture" })
  cleanup()
  first.delete(name)
  vim.cmd(name)
  test.eq({ "buffer", "fresh", "other owner" }, calls)

  api.nvim_buf_delete(buffer, { force = true })
  local_cleanup()
  second.delete(name)
  test.eq(nil, api.nvim_get_commands({})[name])
end)

test.run("base-tools batch shares snapshots and cleanup checks ownership once", function()
  local registry = commands.new()
  local get_commands = api.nvim_get_commands
  local snapshots = 0
  api.nvim_get_commands = function(opts)
    snapshots = snapshots + 1
    return get_commands(opts)
  end

  local first, second = "BaseToolsBatchFirst", "BaseToolsBatchSecond"
  local callback = function() end
  local cleanups = registry.create_many({ { first, callback }, { second, callback } })
  local registration_snapshots = snapshots
  cleanups[1]()
  local cleanup_snapshots = snapshots - registration_snapshots
  api.nvim_get_commands = get_commands

  test.eq(2, registration_snapshots)
  test.eq(1, cleanup_snapshots)
  test.eq(nil, get_commands({})[first])
  assert(get_commands({})[second])
  local replace = registry.create(second, callback, { desc = "new registration" })
  cleanups[2]()
  test.eq("new registration", get_commands({})[second].definition)
  replace()

  local buffer = api.nvim_create_buf(false, true)
  local local_cleanups = api.nvim_buf_call(buffer, function()
    return registry.create_many({ { first, callback }, { second, callback } }, 0)
  end)
  assert(api.nvim_buf_get_commands(buffer, {})[first])
  local_cleanups[2]()
  test.eq(nil, api.nvim_buf_get_commands(buffer, {})[second])
  api.nvim_buf_delete(buffer, { force = true })
  local_cleanups[1]()
end)

test.run("base-tools batch checks conflicts and retains successful registrations on error", function()
  local registry = commands.new()
  local first, foreign = "BaseToolsBatchValid", "BaseToolsBatchForeign"
  local callback = function() end
  api.nvim_create_user_command(foreign, callback, {})
  local previous = api.nvim_get_commands({})[foreign]

  local ok, err = pcall(registry.create_many, { { first, callback }, { foreign, callback, { force = true } } })
  assert(not ok and tostring(err):find("Command already exists", 1, true))
  test.eq(previous, api.nvim_get_commands({})[foreign])
  test.eq(nil, api.nvim_get_commands({})[first])

  ok, err = pcall(registry.create_many, { { first, callback }, { first, callback } })
  assert(not ok and tostring(err):find("Duplicate command in batch", 1, true))
  test.eq(nil, api.nvim_get_commands({})[first])

  ok = pcall(registry.create_many, { { first, callback }, { "BaseToolsBatchInvalid", callback, { nargs = 2 } } })
  assert(not ok and api.nvim_get_commands({})[first])
  registry.delete(first)
  test.eq(nil, api.nvim_get_commands({})[first])
  api.nvim_del_user_command(foreign)
end)

test.run("base-tools command groups dispatch actions and complete by argument position", function()
  local registry = commands.new()
  local calls, request = {}
  local function run(args)
    calls[#calls + 1] = args
  end
  local name = "BaseToolsGroupFixture"
  local spec = {
    default = "info",
    actions = {
      { name = "info", run = run },
      {
        name = "compare",
        run = run,
        complete = {
          { "中文 one", "second" },
          function(ctx)
            request = ctx
            return { "origin/main", "origin/topic" }
          end,
        },
      },
    },
  }
  local opts = { range = true, bang = true, bar = true }
  local cleanup = registry.create_group(name, spec, opts)
  assert(not opts.complete and not opts.nargs)
  vim.cmd(name)
  test.eq({}, calls[1].fargs)
  vim.cmd(name .. [[! compare 中文\ one origin/main]])
  test.eq({ "compare", "中文 one", "origin/main" }, calls[2].fargs)
  test.eq(true, calls[2].bang)

  local previous_wildoptions = vim.o.wildoptions
  vim.o.wildoptions = ""
  local function complete(line)
    return vim.fn.getcompletion(line, "cmdline", true)
  end
  test.eq({ "info", "compare" }, complete(name .. " "))
  test.eq({ "compare" }, complete("set number | silent 1,2BaseToolsGroupF! co"))
  test.eq({ [[中文\ one]] }, complete(name .. [[ compare 中文\ o]]))
  local prefix = name .. [[ compare 中文\ one origin/m]]
  local line = prefix .. " suffix"
  local definition = commands.group(name, spec, opts)
  test.eq({ "origin/main" }, definition[3].complete("origin/m", line, #prefix))
  test.eq({ "中文 one" }, request.args)
  test.eq({ "origin/m", line, #prefix, 2 }, { request.lead, request.line, request.cursor, request.index })
  test.eq({}, complete(name .. " compare second origin/main "))
  test.eq({}, complete(name .. " unknown "))
  test.eq(false, pcall(vim.cmd, name .. " unknown"))
  vim.o.wildoptions = "fuzzy"
  test.eq({ "compare" }, complete(name .. " cmp"))
  vim.o.wildoptions = previous_wildoptions

  local duplicate = { actions = { spec.actions[1], spec.actions[1] } }
  assert(not pcall(registry.create_group, name, duplicate))
  test.eq({}, complete(name .. " info "))
  cleanup()
  test.eq(0, vim.fn.exists(":" .. name))
end)

test.run("base-tools command groups delegate native path completion in a batch", function()
  local registry = commands.new()
  local folder = vim.fn.tempname()
  vim.fn.mkdir(folder)
  local path = folder .. '/file #中文|"name'
  vim.fn.writefile({}, path)
  local name = "BaseToolsGroupExport"
  local received
  local definition = commands.group(name, {
    actions = {
      {
        name = "export",
        run = function(args)
          received = args.fargs[2]
        end,
        complete = { "file" },
      },
    },
  }, { nargs = "+", bar = true })
  local buffer = api.nvim_create_buf(false, true)
  local cleanups = registry.create_many({ definition }, buffer)
  api.nvim_buf_call(buffer, function()
    local items = vim.fn.getcompletion(name .. " export " .. folder .. "/file", "cmdline", true)
    test.eq(1, #items)
    vim.cmd(name .. " export " .. items[1])
    test.eq(path, received)
  end)
  cleanups[1]()
  test.eq(nil, api.nvim_buf_get_commands(buffer, {})[name])
  api.nvim_buf_delete(buffer, { force = true })
  vim.fn.delete(folder, "rf")
end)

test.run("base-tools command groups generate a menu and support overriding items", function()
  local registry = commands.new()
  local name = "BaseToolsMenuFixture"
  local spec = {
    default = "menu",
    menu = true,
    actions = {
      { name = "status", run = function() end },
      { name = "export", run = function() end, complete = { "file" } },
    },
  }
  local select, feedkeys = vim.ui.select, api.nvim_feedkeys
  local items, format, prompt, choose, fed
  vim.ui.select = function(choices, opts, on_choice)
    items, format, prompt, choose = choices, opts.format_item, opts.prompt, on_choice
  end
  api.nvim_feedkeys = function(keys, mode, escape)
    test.eq({ "n", true }, { mode, escape })
    fed = keys
  end

  registry.create_group(name, spec)
  test.eq({ "menu" }, vim.fn.getcompletion(name .. " men", "cmdline", true))
  vim.cmd(name)
  test.eq(name, prompt)
  test.eq({ "status", "export" }, vim.tbl_map(format, items))
  choose(nil)
  test.eq(nil, fed)
  choose(items[2])
  test.eq(":" .. name .. " export ", fed)

  local selected, first_win = nil, api.nvim_get_current_win()
  spec.menu = {
    prompt = "Custom actions",
    items = function(defaults)
      test.eq("status", defaults[1].id)
      test.eq("export", defaults[2].label)
      defaults[2].label = "Export file"
      return {
        defaults[2],
        {
          id = "inspect",
          label = "Inspect",
          run = function()
            selected = api.nvim_get_current_win()
          end,
        },
      }
    end,
  }
  local cleanup = registry.create_group(name, spec)
  vim.cmd(name .. " menu")
  test.eq("Custom actions", prompt)
  test.eq({ "Export file", "Inspect" }, vim.tbl_map(format, items))
  vim.cmd(name .. " menu")
  local other = api.nvim_open_win(api.nvim_get_current_buf(), true, { split = "right" })
  choose(items[2])
  test.eq(first_win, selected)
  api.nvim_win_close(other, true)

  spec.actions[#spec.actions + 1] = { name = "menu", run = function() end }
  assert(not pcall(registry.create_group, name, spec), "Synthetic and explicit menu actions must not collide")
  cleanup()
  vim.ui.select, api.nvim_feedkeys = select, feedkeys
end)
