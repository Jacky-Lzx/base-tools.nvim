local test = dofile("tests/support.lua")
local api = vim.api
local select_window = require("base_tools.select")

local function press(key)
  assert(vim.fn.maparg(key, "n", false, true).callback)()
end

test.run("selection keeps its prompt and returns the chosen index after closing", function()
  local origin = api.nvim_get_current_win()
  local result
  local handle = select_window.open({
    prompt = "Delete this file?",
    title = "Confirm",
    choices = { { label = "Yes", key = "y" }, { label = "No", key = "n" } },
    default = 2,
  }, function(index)
    test.eq(origin, api.nvim_get_current_win())
    result = index
  end)

  local win, buf = api.nvim_get_current_win(), api.nvim_get_current_buf()
  local before = api.nvim_buf_get_lines(buf, 0, -1, false)
  test.eq(false, vim.bo[buf].modifiable)
  assert(table.concat(before, "\n"):find("Delete this file?", 1, true))
  local default_column = api.nvim_win_get_cursor(win)[2]
  press("<Left>")
  assert(api.nvim_win_get_cursor(win)[2] < default_column)
  press("<Right>")
  test.eq(default_column, api.nvim_win_get_cursor(win)[2])
  test.eq(before, api.nvim_buf_get_lines(buf, 0, -1, false))
  press("<CR>")
  test.eq(2, result)
  assert(not api.nvim_win_is_valid(win) and not api.nvim_buf_is_valid(buf))
  handle.cancel()
  test.eq(2, result)
end)

test.run("selection cancels once on focus loss, native close and explicit cancellation", function()
  local origin = api.nvim_get_current_win()
  for _, action in ipairs({ "focus", "window", "escape", "handle" }) do
    local calls = 0
    local handle = select_window.open({ prompt = "Continue?", choices = { { label = "Yes" } } }, function(index)
      test.eq(nil, index)
      calls = calls + 1
    end)
    local win, buf = api.nvim_get_current_win(), api.nvim_get_current_buf()
    if action == "focus" then
      api.nvim_set_current_win(origin)
    elseif action == "window" then
      api.nvim_win_close(win, true)
    elseif action == "escape" then
      press("<Esc>")
    else
      handle.cancel()
    end
    assert(vim.wait(200, function()
      return calls > 0
    end))
    handle.cancel()
    test.eq(1, calls)
    assert(not api.nvim_win_is_valid(win) and not api.nvim_buf_is_valid(buf))
    test.eq(origin, api.nvim_get_current_win())
  end
end)

test.run("selection provides direct choice keys and rejects duplicate keys", function()
  local result
  local options = {
    prompt = "Choose",
    choices = { { label = "First", key = "f" }, { label = "Second", key = "s" } },
  }
  select_window.open(options, function(index)
    result = index
  end)
  press("S")
  test.eq(2, result)
  options.choices[2].key = "F"
  local ok, err = pcall(select_window.open, options, function() end)
  assert(not ok and tostring(err):find("Duplicate choice key: f", 1, true))
end)
