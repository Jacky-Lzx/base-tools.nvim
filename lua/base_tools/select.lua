local api = vim.api
local Context = require("base_tools.context")
local float = require("base_tools.float")
local layout = require("base_tools.input.layout")
local ns = api.nvim_create_namespace("base_tools.select")
local M = {}

---@class base_tools.SelectChoice
---@field label string Single-line choice.
---@field key? string One ASCII letter or digit that confirms this choice.

---@class base_tools.SelectOptions
---@field prompt string Question or instruction above the choices.
---@field choices base_tools.SelectChoice[]
---@field default? integer Initially selected choice, defaulting to 1.
---@field title? string Border title, defaulting to "Select".
---@field context? base_tools.Context

---@class base_tools.SelectHandle
---@field cancel fun() Close the window and report cancellation.

local function content(prompt, labels, width)
  local pad = width >= 8 and "  " or ""
  local lines = { "" }
  for _, line in ipairs(prompt) do
    lines[#lines + 1] = pad .. line
  end
  lines[#lines + 1] = ""

  local positions = {}
  local horizontal = vim.fn.strdisplaywidth(table.concat(labels, "  ")) + #pad * 2 <= width
  local buttons = pad
  for index, label in ipairs(labels) do
    positions[index] = { row = #lines, first = #buttons, last = #buttons + #label }
    buttons = buttons .. label
    if horizontal and index < #labels then
      buttons = buttons .. "  "
    else
      lines[#lines + 1] = buttons
      buttons = pad
    end
  end
  lines[#lines + 1] = ""
  return lines, positions
end

--- Open a focused choice window and report its selected index after cleanup.
--- Cancellation reports nil.
---@param opts base_tools.SelectOptions
---@param on_choice fun(index: integer?)
---@return base_tools.SelectHandle
function M.open(opts, on_choice)
  local context = type(opts) == "table" and opts.context or nil
  local check = Context.checker(context, "select.open")
  check(type(opts) == "table", "Expected selection options")
  check(type(on_choice) == "function", "Expected a selection callback")
  check(type(opts.prompt) == "string" and opts.prompt ~= "", "Expected a selection prompt")
  check(opts.title == nil or type(opts.title) == "string", "Expected a title string")
  check(type(opts.choices) == "table" and vim.islist(opts.choices) and #opts.choices > 0, "Expected a list of choices")

  local count = #opts.choices
  local selected = opts.default == nil and 1 or opts.default
  check(
    type(selected) == "number" and selected % 1 == 0 and selected >= 1 and selected <= count,
    "Default choice is out of range"
  )
  local labels, keys = {}, {}
  for index, choice in ipairs(opts.choices) do
    check(
      type(choice) == "table"
        and type(choice.label) == "string"
        and choice.label:match("%S")
        and not choice.label:find("[\r\n]"),
      "Expected a single-line choice label"
    )
    labels[index] = " " .. vim.fn.strtrans(choice.label) .. " "
    if choice.key ~= nil then
      check(type(choice.key) == "string" and choice.key:match("^[a-zA-Z0-9]$"), "Expected an ASCII letter or digit")
      local key = choice.key:lower()
      check(keys[key] == nil, "Duplicate choice key: " .. key)
      keys[key] = index
    end
  end

  local prompt = vim.tbl_map(vim.fn.strtrans, vim.split(opts.prompt, "\n", { plain = true }))
  local width = vim.fn.strdisplaywidth(table.concat(labels, "  "))
  for _, line in ipairs(prompt) do
    width = math.max(width, vim.fn.strdisplaywidth(line))
  end
  local style = layout.resolve({
    row = "center",
    width = width + 4,
    min_width = 24,
    max_width = 72,
    max_height = 14,
    title = " " .. vim.fn.strtrans(opts.title or "Select") .. " ",
    title_pos = "left",
  })

  local lines, positions
  local function geometry()
    local config = layout.input(style, function(available)
      lines, positions = content(prompt, labels, available)
      local rows = 0
      for _, line in ipairs(lines) do
        rows = rows + math.max(1, math.ceil(vim.fn.strdisplaywidth(line) / available))
      end
      return rows
    end, nil, true)
    config.noautocmd = nil
    return config
  end

  local win_options = layout.win_options(style)
  win_options.wrap = true
  win_options.linebreak = false
  win_options.smoothscroll = true
  win_options.winfixbuf = true
  win_options.cursorline = false
  local window = float.open({
    context = context,
    config = geometry(),
    enter = true,
    buf_options = { swapfile = false, undolevels = -1 },
    win_options = win_options,
  })
  local group
  local settled = false
  local function release()
    if settled then
      return false
    end
    settled = true
    if group then
      api.nvim_del_augroup_by_id(group)
    end
    window:close()
    return true
  end

  local function finish(index)
    if release() then
      on_choice(index)
    end
  end
  local function cancel()
    finish(nil)
  end
  local function highlight()
    local position = positions[selected]
    api.nvim_buf_clear_namespace(window.buf, ns, 0, -1)
    api.nvim_buf_set_extmark(window.buf, ns, position.row, position.first, {
      end_col = position.last,
      hl_group = "PmenuSel",
    })
    api.nvim_win_set_cursor(window.win, { position.row + 1, position.first })
  end
  local function draw()
    vim.bo[window.buf].modifiable = true
    api.nvim_buf_set_lines(window.buf, 0, -1, false, lines)
    vim.bo[window.buf].modifiable = false
    highlight()
  end
  local function map(key, action, desc)
    window:map("n", key, action, { nowait = true, silent = true, desc = desc })
  end

  local ok, err = pcall(function()
    draw()
    local function move(offset)
      selected = (selected - 1 + offset) % count + 1
      highlight()
    end
    for _, key in ipairs({ "<Left>", "<Up>" }) do
      map(key, function()
        move(-1)
      end, "Previous choice")
    end
    for _, key in ipairs({ "<Right>", "<Down>" }) do
      map(key, function()
        move(1)
      end, "Next choice")
    end
    map("<CR>", function()
      finish(selected)
    end, "Confirm choice")
    map("<Esc>", cancel, "Cancel selection")
    for key, index in pairs(keys) do
      local function choose()
        finish(index)
      end
      map(key, choose, opts.choices[index].label)
      if key ~= key:upper() then
        map(key:upper(), choose, opts.choices[index].label)
      end
    end

    group = api.nvim_create_augroup("BaseToolsSelect" .. window.buf, { clear = true })
    api.nvim_create_autocmd({ "WinLeave", "BufWipeout" }, {
      group = group,
      buffer = window.buf,
      callback = function()
        vim.schedule(cancel)
      end,
    })
    api.nvim_create_autocmd("WinClosed", {
      group = group,
      pattern = tostring(window.win),
      callback = function()
        vim.schedule(cancel)
      end,
    })
    api.nvim_create_autocmd("VimResized", {
      group = group,
      callback = function()
        if window:update(geometry()) then
          draw()
        end
      end,
    })
  end)
  if not ok then
    release()
    error(err, 0)
  end

  return { cancel = cancel }
end

return M
