local test = dofile("tests/support.lua")

test.run("view window keys follow focus, buffer replacement, and detach", function()
  local api = vim.api
  local origin = api.nvim_get_current_win()
  local first = api.nvim_create_buf(false, true)
  local second = api.nvim_create_buf(false, true)
  local original_buf = api.nvim_win_get_buf(origin)
  api.nvim_win_set_buf(origin, first)
  local previous = function() end
  vim.keymap.set("n", "q", previous, { buffer = first })

  local function mapping(buf)
    for _, entry in ipairs(api.nvim_buf_get_keymap(buf, "n")) do
      if entry.lhs == "q" then
        return entry.callback
      end
    end
  end

  vim.cmd.tabnew()
  local tab, panel = api.nvim_get_current_tabpage(), api.nvim_get_current_win()
  local win = api.nvim_open_win(first, false, { win = panel, split = "right" })
  local original_number = vim.wo[win].number
  local closed = 0
  local window = require("base_tools.window")
  local view = require("base_tools.view").attach(tab, {
    on_close = function()
      closed = closed + 1
    end,
  })
  local pane = view:attach_window(win, { win_options = { number = not original_number } })
  pane:map("n", "q", function() end)

  assert(not pcall(view.attach_window, view, origin), "Windows from another tab must be rejected")
  test.eq(previous, mapping(first))
  test.eq(not original_number, vim.wo[win].number)

  api.nvim_set_current_win(win)
  local installed = mapping(first)
  assert(installed ~= previous)
  local identity = assert(window.mapping_id(win, installed))
  assert(not window.mapping_id(origin, installed))
  api.nvim_win_set_buf(win, second)
  test.eq(previous, mapping(first))
  assert(mapping(second))
  api.nvim_set_current_win(panel)
  test.eq(nil, mapping(second))
  assert(window.mapping_id(win, installed) == identity)
  api.nvim_win_set_buf(win, first)
  test.eq(previous, mapping(first))

  api.nvim_set_current_win(win)
  assert(mapping(first) ~= previous and window.mapping_id(win, mapping(first)) == identity)
  view:detach()
  view:detach()
  test.eq(previous, mapping(first))
  assert(not window.mapping_id(win, installed))
  assert(api.nvim_win_is_valid(win) and api.nvim_buf_is_valid(first))
  test.eq(0, closed)

  view = require("base_tools.view").attach(tab, {
    on_close = function()
      closed = closed + 1
    end,
  })
  view:attach_window(win):map("n", "q", function() end)
  vim.cmd.tabclose()
  assert(vim.wait(1000, function()
    return closed == 1
  end))
  test.eq(previous, mapping(first))
  assert(api.nvim_win_is_valid(origin) and api.nvim_buf_is_valid(first))
  api.nvim_win_set_buf(origin, original_buf)
  api.nvim_buf_delete(first, { force = true })
  api.nvim_buf_delete(second, { force = true })
end)
