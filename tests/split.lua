local test = dofile("tests/support.lua")
local split = require("base_tools.split")
local api = vim.api

local config = { split = "left", win = -1, width = 20 }

test.run("owned splits initialize their buffers and register local mappings", function()
  local origin = api.nvim_get_current_win()
  local tab = api.nvim_get_current_tabpage()
  local calls, closed = 0, 0
  local view = split.open({
    config = config,
    buf_options = { name = "base-tools://split" },
    win_options = { winfixbuf = true },
    on_buffer = function(buf)
      vim.bo[buf].filetype = "base-tools-split"
      test.eq(origin, api.nvim_get_current_win())
    end,
    on_close = function()
      closed = closed + 1
    end,
  })
  test.eq(origin, api.nvim_get_current_win())
  test.eq(tab, view.tab)
  test.eq("base-tools://split", api.nvim_buf_get_name(view.buf))
  test.eq("base-tools-split", vim.bo[view.buf].filetype)
  test.eq("wipe", vim.bo[view.buf].bufhidden)
  test.eq(true, vim.wo[view.win].winfixbuf)
  assert(view:valid())

  view:map("n", "q", function()
    calls = calls + 1
  end, { desc = "Fixture mapping" })
  local mappings = api.nvim_buf_get_keymap(view.buf, "n")
  test.eq("Fixture mapping", mappings[1].desc)
  assert(not vim.tbl_contains(
    vim.tbl_map(function(mapping)
      return mapping.desc
    end, api.nvim_get_keymap("n")),
    "Fixture mapping"
  ))
  mappings[1].callback()
  test.eq(1, calls)
  view:close()
  view:close()
  assert(not view:valid() and not api.nvim_buf_is_valid(view.buf))
  test.eq(1, closed)
  test.eq(origin, api.nvim_get_current_win())
end)

test.run("closing the last regular split keeps its tab and unrelated floats", function()
  local origin = api.nvim_get_current_win()
  local tabs = #api.nvim_list_tabpages()
  local view = split.open({ config = config, enter = true, win_options = { winfixbuf = true } })
  api.nvim_win_close(origin, true)
  local floating_buf = api.nvim_create_buf(false, true)
  local floating_win = api.nvim_open_win(floating_buf, false, {
    relative = "editor",
    row = 1,
    col = 1,
    height = 1,
    width = 5,
  })

  view:close()
  assert(api.nvim_win_is_valid(view.win) and not view:valid())
  assert(api.nvim_win_is_valid(floating_win))
  assert(not api.nvim_buf_is_valid(view.buf))
  test.eq("", vim.bo[api.nvim_win_get_buf(view.win)].buftype)
  test.eq(false, vim.wo[view.win].winfixbuf)
  test.eq(tabs, #api.nvim_list_tabpages())
  api.nvim_win_close(floating_win, true)
  api.nvim_buf_delete(floating_buf, { force = true })
end)

test.run("native split, buffer and tab closure notify the owner once", function()
  local home = api.nvim_get_current_tabpage()
  for _, command in ipairs({ "close", "bwipeout!", "tabclose" }) do
    vim.cmd.tabnew()
    local owner_tab = api.nvim_get_current_tabpage()
    local closed = 0
    local view = split.open({
      config = config,
      enter = true,
      win_options = { winfixbuf = true },
      on_close = function(split)
        assert(not split:valid())
        closed = closed + 1
      end,
    })
    vim.cmd(command)
    assert(not api.nvim_buf_is_valid(view.buf) and not view:valid(), command)
    test.eq(1, closed)
    view:close()
    test.eq(1, closed)
    if api.nvim_tabpage_is_valid(owner_tab) then
      vim.cmd.tabclose()
    end
    test.eq(home, api.nvim_get_current_tabpage())
  end
end)

test.run("native window closure also cleans up a surviving scratch buffer", function()
  local closed = 0
  local view = split.open({
    config = config,
    on_close = function()
      closed = closed + 1
    end,
  })
  vim.bo[view.buf].bufhidden = "hide"
  api.nvim_win_close(view.win, true)
  assert(vim.wait(500, function()
    return not api.nvim_buf_is_valid(view.buf)
  end))
  test.eq(1, closed)
end)

test.run("split open rolls back partial resources and close errors do not leak windows", function()
  local function count()
    return { #api.nvim_list_wins(), #api.nvim_list_bufs() }
  end
  local before = count()
  local context = require("base_tools.context").new("panel.nvim")
  local closed = 0
  local ok, err = pcall(split.open, {
    config = config,
    context = context,
    win_options = { not_an_option = true },
    on_close = function()
      closed = closed + 1
    end,
  })
  assert(not ok and vim.startswith(err, "panel.nvim [split.open]:"), tostring(err))
  test.eq(before, count())
  test.eq(1, closed)

  local view = split.open({
    config = config,
    on_close = function()
      error("close hook failed", 0)
    end,
  })
  ok, err = pcall(view.close, view)
  test.eq(false, ok)
  test.eq("close hook failed", err)
  test.eq(before, count())
  view:close()
end)
