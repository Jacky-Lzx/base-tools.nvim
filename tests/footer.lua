local test = dofile("tests/support.lua")
local buffer = require("base_tools.buffer")
local footer = require("base_tools.footer")
local api = vim.api

local function split(buf, width)
  return api.nvim_open_win(buf, false, { win = 0, split = "right", width = width })
end

local function rendered(win)
  return api.nvim_eval_statusline(vim.wo[win][0].statusline, {
    winid = win,
    maxwidth = api.nvim_win_get_width(win),
  }).str
end

test.run("Window footers align plain text and prioritize left labels when narrow", function()
  local buf = buffer.scratch({ bufhidden = "wipe" })
  local win = split(buf, 24)
  local other = api.nvim_get_current_win()
  local other_status = vim.wo[other][0].statusline
  vim.wo[win][0].statusline = "original"
  local bar = footer.attach(win, { left = "100% 文", right = "2 files" })

  test.eq("100% 文          2 files", rendered(win))
  assert(bar:update({ right = "//" }))
  test.eq("100% 文               //", rendered(win))

  api.nvim_win_set_width(win, 8)
  api.nvim_exec_autocmds("WinResized", {})
  test.eq("100% 文", rendered(win))
  api.nvim_win_set_width(win, 5)
  api.nvim_exec_autocmds("WinResized", {})
  test.eq("100%…", rendered(win))

  bar:close()
  bar:close()
  test.eq("original", vim.wo[win][0].statusline)
  test.eq(other_status, vim.wo[other][0].statusline)
  api.nvim_win_close(win, false)
end)

test.run("Window footers restore their own options and preserve later replacements", function()
  local win = split(buffer.scratch({ bufhidden = "wipe" }), 24)
  local first = footer.attach(win, { left = "one" })
  local second = footer.attach(win, { left = "two" })
  first:close()
  test.eq(false, first:update({ left = "old" }))
  test.eq("two", rendered(win))
  second:close()
  test.eq("", vim.wo[win][0].statusline)

  local custom = footer.attach(win, { left = "custom" })
  vim.wo[win][0].statusline = "external"
  test.eq(false, custom:update({ left = "owned" }))
  custom:close()
  test.eq("external", vim.wo[win][0].statusline)
  local released = footer.attach(win, { left = "temporary" })
  api.nvim_win_close(win, false)
  test.eq(false, released:update({ left = "closed" }))
end)

test.run("Window footers keep buffer-specific options when the window switches buffers", function()
  local original = buffer.scratch()
  local temporary = buffer.scratch()
  local win = split(original, 24)
  vim.wo[win][0].statusline = "original"
  local bar = footer.attach(win, { left = "attached" })
  api.nvim_win_set_buf(win, temporary)
  vim.wo[win][0].statusline = "other buffer"
  assert(bar:update({ left = "updated" }))
  test.eq("other buffer", rendered(win))

  api.nvim_win_set_buf(win, original)
  test.eq("updated", rendered(win))
  api.nvim_win_set_buf(win, temporary)
  bar:close()
  test.eq("other buffer", rendered(win))
  api.nvim_win_set_buf(win, original)
  test.eq("original", rendered(win))

  api.nvim_win_close(win, false)
  api.nvim_buf_delete(original, { force = true })
  api.nvim_buf_delete(temporary, { force = true })
end)
