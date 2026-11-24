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
