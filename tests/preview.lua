local test = dofile("tests/support.lua")

test.run("base-tools.preview", function()
  local api = vim.api
  local float = require("base_tools.float")
  local preview = require("base_tools.preview")
  local eq = test.eq

  local config = { relative = "editor", row = 1, col = 2, width = 10, height = 3, border = "single" }
  local function anchored_to(win)
    return vim.tbl_filter(function(candidate)
      return api.nvim_win_get_config(candidate).win == win
    end, api.nvim_list_wins())
  end

  local view = preview.open({ config = config, lines = { "short" } })
  eq({ "short" }, api.nvim_buf_get_lines(view.buf, 0, -1, false))
  eq(nil, view:position())
  view:set_lines({ string.rep("x", 80) })
  eq(8, view:position().total)
  eq(0, #anchored_to(view.win))
  local owned = view.buf
  view:close()
  eq(false, api.nvim_buf_is_valid(owned))
  eq(false, view:scroll(1))

  local borrowed = float.scratch()
  view = preview.open({
    buf = borrowed,
    config = config,
    lines = { string.rep("x", 80) },
    scrollbar = { thumb_highlight = "Keyword" },
  })
  local win = view.win
  local children = anchored_to(win)
  eq(1, #children)
  eq(0, view:position().progress)

  local ok, position = view:scroll(20)
  assert(ok)
  eq(1, position.progress)
  local bottom = api.nvim_win_call(win, vim.fn.winsaveview)
  eq(50, bottom.skipcol)
  view:scroll(2)
  eq(bottom, api.nvim_win_call(win, vim.fn.winsaveview))
  view:scroll(-100)
  eq(0, view:position().progress)
  view:update({ height = 8 })
  eq(0, #anchored_to(win))
  view:update({ height = 3 })
  eq(1, #anchored_to(win))
  view:set_lines({ "fits" })
  eq(0, #anchored_to(win))
  view:set_lines({ string.rep("x", 80) })
  children = anchored_to(win)
  eq(1, #children)
  assert(view:set_scrollbar(false))
  eq(0, #anchored_to(win))
  assert(view:set_scrollbar(true))
  children = anchored_to(win)
  eq(1, #children)
  eq(win, view.win)
  api.nvim_win_close(win, true)
  eq(false, api.nvim_win_is_valid(children[1]))
  eq(false, view:valid())
  eq(nil, view:position())
  view:close()
  eq(true, api.nvim_buf_is_valid(borrowed))
  api.nvim_buf_delete(borrowed, { force = true })
end)

test.run("base-tools.preview scroll labels", function()
  local api = vim.api
  local eq = test.eq
  local lines = vim.split(string.rep("long line\n", 20), "\n", { trimempty = true })
  local labels = require("base_tools.label")
  local initial = {
    top = { center = labels.scroll_percent() },
    bottom = { left = "Doc", right = labels.scroll_percent({ highlight = "WarningMsg" }) },
  }
  local view = require("base_tools.preview").open({
    config = {
      relative = "editor",
      row = 1,
      col = 2,
      width = 16,
      height = 3,
      border = "single",
      title = "native",
    },
    lines = lines,
    border_labels = initial,
  })
  local function label(edge)
    local value = api.nvim_win_get_config(view.win)[edge]
    if type(value) ~= "table" then
      return value
    end
    return table.concat(vim.tbl_map(function(part)
      return part[1]
    end, value))
  end

  eq("────── 0% ──────", label("title"))
  eq("Doc───────── 0% ", label("footer"))
  view:scroll(100)
  eq("───── 100% ─────", label("title"))
  eq("Doc─────── 100% ", label("footer"))
  eq({ " 100% ", "WarningMsg" }, api.nvim_win_get_config(view.win).footer[3])

  view:update({ height = 20 })
  eq("native", label("title"))
  eq("Doc─────────────", label("footer"))
  view:update({ height = 3 })
  assert(label("title"):find("%%", 1))
  view:set_lines({ "fits" })
  eq("native", label("title"))
  view:set_lines(lines)
  eq("────── 0% ──────", label("title"))

  view:set_scrollbar(true)
  view:set_scrollbar(false)
  view:set_border_labels({ top = false, bottom = { right = "Ready" } })
  view:scroll(100)
  eq("native", label("title"))
  eq("Doc────────Ready", label("footer"))
  eq({ kind = "scroll_percent", highlight = "WarningMsg" }, initial.bottom.right)

  view:set_border_labels({ bottom = { right = { kind = "scroll_percent" } } })
  eq("Doc─────── 100% ", label("footer"))
  view:set_border_labels({ bottom = { right = false } })
  view:scroll(-100)
  eq("Doc─────────────", label("footer"))

  api.nvim_win_close(view.win, true)
  eq(nil, view:refresh())
  eq(false, view:set_border_labels({ top = false }))
end)

test.run("base-tools.preview content update", function()
  local api = vim.api
  local eq = test.eq
  local label = require("base_tools.label")
  local view = require("base_tools.preview").open({
    config = { relative = "editor", row = 1, col = 2, width = 24, height = 3, border = "single" },
    lines = { "original" },
    border_labels = { top = { left = "Original", right = "Lua" }, bottom = { right = label.scroll_percent() } },
    scrollbar = true,
  })
  local win = view.win
  local function scrollbar_windows()
    return vim.tbl_filter(function(candidate)
      return api.nvim_win_get_config(candidate).win == win
    end, api.nvim_list_wins())
  end

  local lines = { "one", "two", "three", "four" }
  assert(view:set_content({ lines = lines, border_labels = { top = { left = label.filename("src/first.lua") } } }))
  eq(lines, api.nvim_buf_get_lines(view.buf, 0, -1, false))
  local config = api.nvim_win_get_config(win)
  eq({ "first.lua", "FloatTitle" }, config.title[1])
  eq({ "Lua", "FloatTitle" }, config.title[3])
  eq({ " 0% ", "FloatFooter" }, config.footer[2])
  eq(1, #scrollbar_windows())

  assert(view:set_content({ lines = { "fits" }, border_labels = { top = { left = false } } }))
  config = api.nvim_win_get_config(win)
  eq({ "Lua", "FloatTitle" }, config.title[2])
  eq("", config.footer or "")
  eq(0, #scrollbar_windows())
  assert(view:set_lines(lines))
  eq({ " 0% ", "FloatFooter" }, api.nvim_win_get_config(win).footer[2])
  view:close()
  eq(false, view:set_content({ lines = lines }))
end)

test.run("base-tools.preview fits its height", function()
  local api = vim.api
  local eq = test.eq
  local view = require("base_tools.preview").open({
    config = { relative = "editor", row = 1, col = 2, width = 10, height = 1, border = "single" },
    lines = { "fence", string.rep("x", 30), "tail" },
    scrollbar = true,
  })
  eq(3, view:fit_height({ max_height = 3 }))
  eq(3, api.nvim_win_get_height(view.win))
  eq(5, view:position().total)
  eq(5, view:fit_height())
  eq(nil, view:position())

  vim.wo[view.win].conceallevel = 2
  vim.wo[view.win].concealcursor = "nvic"
  api.nvim_buf_set_extmark(view.buf, api.nvim_create_namespace("preview-fit-test"), 0, 0, {
    conceal_lines = "",
  })
  eq(4, view:fit_height())
  view:set_lines({})
  eq(1, view:fit_height())
  view:close()
  eq(nil, view:fit_height())
end)

test.run("base-tools.preview language highlighting", function()
  local api = vim.api
  local treesitter = vim.treesitter
  local active = treesitter.highlighter.active
  local eq = test.eq
  local preview = require("base_tools.preview")
  local buf = require("base_tools.float").scratch()
  local function open()
    return preview.open({
      config = { relative = "editor", row = 1, col = 2, width = 18, height = 3, border = "single" },
      buf = buf,
      language = "lua",
      lines = { "local value = true" },
    })
  end
  local view = open()
  local lua = assert(active[buf])
  eq("lua", lua.tree:lang())
  view:set_content({ lines = { "return true" }, language = "lua" })
  eq(lua, active[buf])
  view:set_lines({ "return false" })
  eq(lua, active[buf])
  view:set_content({ lines = { "# Markdown" }, language = "markdown" })
  eq("markdown", active[buf].tree:lang())
  view:set_content({ lines = { "plain" }, language = false })
  eq(nil, active[buf])
  view:set_content({ lines = { "return true" }, language = "lua" })
  view:set_content({ lines = { "plain" }, language = "nonexistent_preview_parser" })
  eq(nil, active[buf])
  view:set_content({ lines = { "return true" }, language = "lua" })
  api.nvim_win_close(view.win, true)
  eq(nil, active[buf])

  treesitter.start(buf, "markdown")
  local external = assert(active[buf])
  view = open()
  eq(external, active[buf])
  view:set_content({ lines = { "plain" }, language = false })
  eq(external, active[buf])
  view:close()
  eq(external, active[buf])
  treesitter.stop(buf)
  api.nvim_buf_delete(buf, { force = true })
end)

test.run("base-tools.preview content scroll policies", function()
  local api = vim.api
  local eq = test.eq
  local lines = vim.split(string.rep("original\n", 20), "\n", { trimempty = true })
  local view = require("base_tools.preview").open({
    config = { relative = "editor", row = 1, col = 2, width = 10, height = 3, border = "single" },
    lines = lines,
  })
  local function saved()
    return api.nvim_win_call(view.win, vim.fn.winsaveview)
  end

  view:scroll(9)
  eq(10, saved().topline)
  local before = saved()
  view:set_content({ lines = vim.tbl_map(string.upper, lines), scroll = "keep" })
  eq(before, saved())
  view:set_content({ lines = { "one", "two", "three", "four", "five" }, scroll = "keep" })
  eq(3, saved().topline)
  eq(1, view:position().progress)

  view:set_content({ lines = { string.rep("x", 80) }, scroll = "top" })
  view:scroll(5)
  eq(50, saved().skipcol)
  view:set_content({ lines = { string.rep("y", 80) }, scroll = "keep" })
  eq(50, saved().skipcol)
  view:set_content({ lines = { "short", "two", "three", "four" }, scroll = "keep" })
  eq(0, saved().skipcol)
  eq(1, saved().topline)
  view:scroll(1)
  view:set_content({ lines = lines, scroll = "top" })
  eq(1, saved().topline)
  eq({ 1, 0 }, api.nvim_win_get_cursor(view.win))
  eq(0, view:position().progress)
  view:close()
end)

test.run("base-tools.preview scroll indicator without a bottom border", function()
  local api = vim.api
  local eq = test.eq
  local label = require("base_tools.label")
  local lines = vim.split(string.rep("row\n", 20), "\n", { trimempty = true })
  local view = require("base_tools.preview").open({
    config = { relative = "editor", row = 1, col = 2, width = 16, height = 3, border = "none" },
    lines = lines,
    border_labels = { bottom = { right = label.scroll_percent({ fallback = "below", highlight = "Title" }) } },
  })
  local win = view.win
  local function labels()
    return vim.tbl_filter(function(candidate)
      return api.nvim_win_get_config(candidate).win == win
    end, api.nvim_list_wins())
  end
  local function text(target)
    return api.nvim_buf_get_lines(api.nvim_win_get_buf(target), 0, -1, false)
  end

  eq(1, #labels())
  local indicator = labels()[1]
  eq({ "0%" }, text(indicator))
  eq("Normal:Title", vim.wo[indicator].winhighlight)
  eq(14, api.nvim_win_get_config(indicator).col)
  view:scroll(100)
  eq(indicator, labels()[1])
  eq({ "100%" }, text(indicator))
  eq(12, api.nvim_win_get_config(indicator).col)
  assert(view:update({ width = 10 }))
  eq(6, api.nvim_win_get_config(indicator).col)

  assert(view:update({ border = "single" }))
  eq(0, #labels())
  eq({ " 100% ", "Title" }, api.nvim_win_get_config(win).footer[2])
  assert(view:update({ border = "none" }))
  eq(1, #labels())
  view:set_content({ lines = { "fits" }, scroll = "top" })
  eq(0, #labels())
  view:set_lines(lines)
  eq({ "0%" }, text(labels()[1]))
  view:set_border_labels({ bottom = false })
  eq(0, #labels())
  view:set_border_labels({ bottom = { right = label.scroll_percent({ fallback = "below" }) } })
  indicator = assert(labels()[1])
  api.nvim_win_close(win, true)
  eq(false, api.nvim_win_is_valid(indicator))
end)

test.run("base-tools.preview attaches to an existing float", function()
  local api = vim.api
  local eq = test.eq
  local preview = require("base_tools.preview")
  local label = require("base_tools.label")
  local source = api.nvim_get_current_win()
  local buf = api.nvim_create_buf(false, true)
  local lines = vim.split(string.rep("row\n", 20), "\n", { trimempty = true })
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  local win = api.nvim_open_win(buf, false, {
    relative = "editor",
    row = 1,
    col = 2,
    width = 20,
    height = 3,
    border = "single",
    title = "existing title",
    footer = "existing footer",
    footer_pos = "center",
  })
  vim.wo[win].wrap = false
  assert(not pcall(preview.attach, source))
  local options = {
    scrollbar = true,
    border_labels = { bottom = { right = label.scroll_percent({ arrows = true }) } },
  }
  local view = preview.attach(win, options)
  assert(view == preview.attach(win))
  eq(source, api.nvim_get_current_win())
  eq(false, vim.wo[win].wrap)
  eq(lines, api.nvim_buf_get_lines(buf, 0, -1, false))
  local function footer()
    return api.nvim_win_get_config(win).footer
  end
  local function child()
    return vim.iter(api.nvim_list_wins()):find(function(id)
      return api.nvim_win_get_config(id).win == win
    end)
  end
  eq({ " ↓ 0% ", "FloatFooter" }, footer()[2])
  view:scroll(100)
  eq({ " ↑ 100% ", "FloatFooter" }, footer()[2])
  local bar = assert(child())
  assert(view:detach())
  eq(false, view:detach())
  eq(false, view:valid())
  eq(false, api.nvim_win_is_valid(bar))
  eq(true, api.nvim_win_is_valid(win))
  eq(true, api.nvim_buf_is_valid(buf))
  local function native_text(value)
    return type(value) == "table" and value[1][1] or value
  end
  eq("existing title", native_text(api.nvim_win_get_config(win).title))
  eq("existing footer", native_text(footer()))
  eq("center", api.nvim_win_get_config(win).footer_pos)
  local attached = preview.attach(win, options)
  bar = assert(child())
  api.nvim_win_close(win, true)
  eq(false, api.nvim_win_is_valid(bar))
  eq(false, attached:valid())
  eq(true, api.nvim_buf_is_valid(buf))
  api.nvim_buf_delete(buf, { force = true })
end)
