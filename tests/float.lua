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
