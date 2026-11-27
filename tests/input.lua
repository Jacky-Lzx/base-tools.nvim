local t = dofile("tests/support.lua")
local input = require("base_tools.input")
local api = vim.api

t.run("input float options are shared and do not open a window", function()
  local style = { row = 3, width = 30, border = "single", winblend = 10 }
  local windows = #api.nvim_list_wins()
  local frame = input.float_options(style, { height = 4, title = "Authentication" })
  t.eq(windows, #api.nvim_list_wins())
  t.eq(3, frame.config.row)
  t.eq(30, frame.config.width)
  t.eq(4, frame.config.height)
  t.eq("single", frame.config.border)
  t.eq(10, frame.win_options.winblend)
  t.eq("Authentication", frame.config.title)
  t.eq(nil, style.title)
end)

t.run("input handle returns layout and cancels once after cleanup", function()
  local original = api.nvim_get_current_win()
  local calls = 0
  local opened
  local handle = input.open({ default = "draft" }, function(value)
    t.eq(nil, value)
    t.eq(original, api.nvim_get_current_win())
    t.eq(false, api.nvim_win_is_valid(opened.win))
    calls = calls + 1
  end)
  assert(vim.wait(1000, function()
    opened = handle:get_layout()
    return opened ~= nil
  end))
  t.eq({ "draft" }, api.nvim_buf_get_lines(opened.buf, 0, -1, false))
  handle:cancel()
  handle:cancel()
  assert(vim.wait(1000, function()
    return calls == 1
  end))
  t.eq(nil, handle:get_layout())
end)
