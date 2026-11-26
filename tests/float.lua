local test = dofile("tests/support.lua")

test.run("base-tools.float", function()
  local api = vim.api
  local float = require("base_tools.float")

  local eq = test.eq

  local owner = api.nvim_get_current_win()
  local config = { relative = "editor", row = 1, col = 2, width = 12, height = 2, focusable = false }
  local borrowed = float.scratch({ filetype = "base-tools-test" })
  eq("hide", vim.bo[borrowed].bufhidden)
  eq("base-tools-test", vim.bo[borrowed].filetype)
  local view = float.open({ config = config, buf = borrowed, win_options = { wrap = false } })
  eq(owner, api.nvim_get_current_win())
  eq(borrowed, view.buf)
  eq(false, vim.wo[view.win].wrap)
  assert(view:valid())
  local win = view.win
  assert(view:update({ width = 20 }))
  eq(win, view.win)
  eq(20, api.nvim_win_get_width(win))
  view:close()
  view:close()
  assert(not api.nvim_win_is_valid(win) and api.nvim_buf_is_valid(borrowed))
  assert(not view:update({ width = 30 }))

  local owned = float.open({ config = config })
  eq("wipe", vim.bo[owned.buf].bufhidden)
  owned:close()
  assert(not api.nvim_buf_is_valid(owned.buf))

  local closed_externally = float.open({ config = config })
  api.nvim_win_close(closed_externally.win, true)
  closed_externally:close()
  assert(not api.nvim_buf_is_valid(closed_externally.buf))

  local before = { #api.nvim_list_wins(), #api.nvim_list_bufs() }
  assert(not pcall(float.open, { config = config, win_options = { invalid_option = true } }))
  eq(before, { #api.nvim_list_wins(), #api.nvim_list_bufs() })
  assert(not pcall(float.scratch, { invalid_option = true }))
  eq(before, { #api.nvim_list_wins(), #api.nvim_list_bufs() })
  api.nvim_buf_delete(borrowed, { force = true })
end)

test.run("float mappings follow focus and the displayed buffer", function()
  local api = vim.api
  local float = require("base_tools.float")
  local origin = api.nvim_get_current_win()
  local first = float.scratch()
  local second = float.scratch()
  local previous = function() end
  local action = function() end
  local config = { relative = "editor", row = 1, col = 2, width = 12, height = 2 }
  vim.keymap.set("n", "q", previous, { buffer = first })

  local function mapping(buf)
    return api.nvim_buf_call(buf, function()
      return vim.fn.maparg("q", "n", false, true)
    end)
  end

  api.nvim_win_set_buf(origin, first)
  local view = float.open({ config = config, buf = first })
  local unmap = view:map("n", "q", action, { nowait = true })
  test.eq(previous, mapping(first).callback)

  -- Replacing a buffer in the background must not install the float's keys.
  api.nvim_win_set_buf(view.win, second)
  test.eq(nil, mapping(second).callback)
  api.nvim_win_set_buf(view.win, first)
  api.nvim_set_current_win(view.win)
  local installed = mapping(first)
  test.eq(1, installed.nowait)
  assert(installed.callback ~= previous)

  api.nvim_win_set_buf(view.win, second)
  test.eq(previous, mapping(first).callback)
  test.eq(1, mapping(second).nowait)
  api.nvim_set_current_win(origin)
  test.eq(nil, mapping(second).callback)
  api.nvim_set_current_win(view.win)
  test.eq(1, mapping(second).nowait)

  unmap()
  unmap()
  test.eq(nil, mapping(second).callback)
  view:map("n", "q", action, { nowait = true })
  api.nvim_win_close(view.win, true)
  test.eq(nil, mapping(second).callback)
  test.eq(previous, mapping(first).callback)
  view:close()
  api.nvim_buf_delete(first, { force = true })
  api.nvim_buf_delete(second, { force = true })
end)

test.run("preview detach restores mappings in its borrowed window", function()
  local api = vim.api
  local buf = api.nvim_get_current_buf()
  local win = api.nvim_open_win(buf, true, { relative = "editor", row = 1, col = 2, width = 12, height = 2 })
  local preview = require("base_tools.preview").attach(win)

  preview:map("n", "q", function() end, { nowait = true })
  test.eq(1, vim.fn.maparg("q", "n", false, true).nowait)
  assert(preview:detach())
  assert(api.nvim_win_is_valid(win))
  test.eq(nil, vim.fn.maparg("q", "n", false, true).callback)
  api.nvim_win_close(win, true)
end)
