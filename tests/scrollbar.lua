local test = dofile("tests/support.lua")

test.run("base-tools.scrollbar", function()
  local api = vim.api
  local float = require("base_tools.float")
  local scrollbar = require("base_tools.scrollbar")
  local eq = test.eq

  local view = float.open({
    config = { relative = "editor", row = 1, col = 2, width = 10, height = 3, border = "single" },
    win_options = { wrap = true, smoothscroll = true, conceallevel = 2, concealcursor = "nvic" },
  })
  local win = view.win
  local bar = scrollbar.new()

  api.nvim_buf_set_lines(view.buf, 0, -1, false, { "short" })
  eq(nil, bar:update(win))
  local count = #api.nvim_list_wins()

  api.nvim_buf_set_lines(view.buf, 0, -1, false, { "~~~", string.rep("x", 80), "~~~" })
  local hidden = api.nvim_create_namespace("base-tools-test-scrollbar-hidden")
  for _, row in ipairs({ 0, 2 }) do
    api.nvim_buf_set_extmark(view.buf, hidden, row, 0, { conceal_lines = "" })
  end
  api.nvim_win_set_cursor(win, { 2, 0 })
  eq({ total = 8, visible = 3, offset = 0, progress = 0 }, bar:update(win))
  eq(count + 1, #api.nvim_list_wins())
  local bar_win
  for _, candidate in ipairs(api.nvim_list_wins()) do
    if api.nvim_win_get_config(candidate).win == win then
      bar_win = candidate
    end
  end
  assert(bar_win)
  local bar_buf = api.nvim_win_get_buf(bar_win)
  eq({ "┃", "│", "│" }, api.nvim_buf_get_lines(bar_buf, 0, -1, false))
  local tick = api.nvim_buf_get_changedtick(bar_buf)
  bar:update(win)
  eq(tick, api.nvim_buf_get_changedtick(bar_buf))

  api.nvim_win_call(win, function()
    vim.cmd("normal! 2\5")
  end)
  eq({ total = 8, visible = 3, offset = 2, progress = 0.4 }, bar:update(win))
  api.nvim_win_call(win, function()
    vim.cmd("normal! 10\5")
  end)
  eq({ total = 8, visible = 3, offset = 5, progress = 1 }, bar:update(win))
  eq({ "│", "│", "┃" }, api.nvim_buf_get_lines(bar_buf, 0, -1, false))

  view:close()
  eq(false, api.nvim_win_is_valid(bar_win))
  eq(false, api.nvim_buf_is_valid(bar_buf))
  bar:close()
end)
