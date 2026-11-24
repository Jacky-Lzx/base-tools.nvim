local test = dofile("tests/support.lua")
local buffer = require("base_tools.buffer")
local api = vim.api

test.run("Scratch buffer keeps its contents after leaving a split by default", function()
  local owner = api.nvim_get_current_win()
  local buf = buffer.scratch()
  test.eq("hide", vim.bo[buf].bufhidden)
  test.eq("nofile", vim.bo[buf].buftype)
  test.eq(false, vim.bo[buf].buflisted)
  test.eq(false, vim.bo[buf].swapfile)
  api.nvim_buf_set_lines(buf, 0, -1, false, { "Temporary output" })

  local win = api.nvim_open_win(buf, false, { win = owner, split = "right" })
  api.nvim_win_close(win, false)
  win = api.nvim_open_win(buf, false, { win = owner, split = "right" })
  test.eq({ "Temporary output" }, api.nvim_buf_get_lines(buf, 0, -1, false))
  api.nvim_win_close(win, false)
  api.nvim_buf_delete(buf, { force = true })
end)

test.run("Scratch buffer with wipe is released after the last split closes", function()
  local owner = api.nvim_get_current_win()
  local buf = buffer.scratch({ bufhidden = "wipe", modifiable = false })
  test.eq(false, vim.bo[buf].modifiable)
  local first = api.nvim_open_win(buf, false, { win = owner, split = "right" })
  local second = api.nvim_open_win(buf, false, { win = first, split = "right" })
  api.nvim_win_close(first, false)
  test.eq(true, api.nvim_buf_is_valid(buf))
  api.nvim_win_close(second, false)
  test.eq(false, api.nvim_buf_is_valid(buf))
end)

test.run("Scratch buffers accept names and clean up failed naming", function()
  local named = buffer.scratch({ name = "base-tools://scratch" })
  test.eq("base-tools://scratch", api.nvim_buf_get_name(named))

  local computed = buffer.scratch({
    name = function(buf)
      return "base-tools://scratch/" .. buf
    end,
  })
  test.eq("base-tools://scratch/" .. computed, api.nvim_buf_get_name(computed))

  local before = api.nvim_list_bufs()
  test.eq(false, pcall(buffer.scratch, { name = "base-tools://scratch" }))
  test.eq(false, pcall(buffer.scratch, { name = "base-tools://invalid", invalid_option = true }))
  test.eq(before, api.nvim_list_bufs())
  api.nvim_buf_delete(named, { force = true })
  api.nvim_buf_delete(computed, { force = true })
end)
