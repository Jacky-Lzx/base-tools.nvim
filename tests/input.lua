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

t.run("input float footer follows the border independently of the title", function()
  local footer = { { "Esc cancel", "Comment" } }
  local options = { footer = footer, footer_pos = "right" }
  local frame = input.float_options({ border = "single" }, options)
  t.eq(nil, frame.config.title)
  t.eq(footer, frame.config.footer)
  t.eq("right", frame.config.footer_pos)
  for _, border in ipairs({ "none", "" }) do
    frame = input.float_options({ border = border }, options)
    t.eq(nil, frame.config.footer)
    t.eq(nil, frame.config.footer_pos)
  end
end)

t.run("input float options pass through shared border labels", function()
  local labels = { top = { center = "Authentication" }, bottom = { right = "Esc cancel" } }
  local options = input.float_options({ border = "single", width = 30 }, { border_labels = labels })
  t.eq(labels, options.border_labels)
  local view = require("base_tools.float").open(options)
  local config = api.nvim_win_get_config(view.win)
  t.eq("Authentication", config.title[2][1])
  t.eq("Esc cancel", config.footer[#config.footer][1])
  view:close()
end)

t.run("editable input feedback keeps other border labels and restores the original left label", function()
  local handle = input.open({
    default = "draft",
    prompt = "Value: ",
    style = { width = 40 },
    border_labels = { bottom = { left = "Ready", right = "Esc cancel" } },
    validate = function(text)
      return text == "valid" or "Invalid value"
    end,
  }, function() end)
  local function has_labels(left)
    local layout = handle:get_layout()
    local config = layout and api.nvim_win_get_config(layout.frame_win)
    local footer = config and config.footer
    return footer and footer[1][1] == left and footer[#footer][1] == "Esc cancel"
  end
  assert(vim.wait(1000, function()
    return has_labels("Invalid value")
  end))
  local buf = handle:get_layout().buf
  api.nvim_buf_set_lines(buf, 0, -1, false, { "valid" })
  api.nvim_exec_autocmds("TextChanged", { buffer = buf })
  assert(vim.wait(1000, function()
    return has_labels("Ready")
  end))
  handle:cancel()
  assert(vim.wait(1000, function()
    return not api.nvim_buf_is_valid(buf)
  end))
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

t.run("input reserves prompt space and cleans up both windows on native close", function()
  local prompt = "编辑路径: "
  local path = "/some/long/directory/file.lua"
  for _, width in ipairs({ 40, 14 }) do
    local calls = 0
    local handle = input.open({ default = path, prompt = prompt, style = { width = width } }, function(value)
      t.eq(nil, value)
      calls = calls + 1
    end)
    assert(vim.wait(1000, function()
      return handle:get_layout() ~= nil
    end))

    local box = handle:get_layout()
    local editor, frame = api.nvim_win_get_config(box.win), api.nvim_win_get_config(box.frame_win)
    local prompt_buf = api.nvim_win_get_buf(box.frame_win)
    t.eq(false, frame.focusable)
    t.eq(box.frame_win, editor.win)
    t.eq({ prompt }, api.nvim_buf_get_lines(prompt_buf, 0, -1, false))
    t.eq({ path }, api.nvim_buf_get_lines(box.buf, 0, -1, false))
    t.eq(width == 40 and vim.fn.strdisplaywidth(prompt) or 0, editor.col)
    t.eq(width == 40 and 0 or 1, editor.row)
    t.eq(box.width - editor.col, editor.width)

    api.nvim_win_close(box.frame_win, true)
    assert(vim.wait(1000, function()
      return calls == 1
    end))
    handle.cancel()
    t.eq(1, calls)
    t.eq(false, api.nvim_win_is_valid(box.win))
    t.eq(false, api.nvim_buf_is_valid(box.buf))
    t.eq(false, api.nvim_buf_is_valid(prompt_buf))
  end
end)
