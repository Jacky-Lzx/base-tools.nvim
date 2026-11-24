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
