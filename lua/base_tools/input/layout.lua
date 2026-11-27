local M = {}

local defaults = {
  border = "rounded",
  min_width = 1,
  max_width = 80,
  max_height = 8,
  row = 3,
  bottom = 1,
  col = 0,
  title = false,
  title_pos = "center",
  winblend = 0,
  zindex = 250,
  winhighlight = "Normal:NormalFloat,FloatBorder:FloatBorder,FloatTitle:FloatTitle",
  prompt_group = "Question",
  error_group = "DiagnosticError",
  hint_group = "Comment",
}

function M.resolve(style)
  return vim.tbl_extend("force", defaults, style or {})
end

function M.screen()
  return math.max(1, vim.o.columns), math.max(1, vim.o.lines - vim.o.cmdheight)
end

function M.box(row, col, width, height, border, zindex, focusable)
  return {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    focusable = focusable == true,
    border = border,
    zindex = zindex,
    noautocmd = true,
  }
end

-- The row count can depend on the available width and height.
function M.input(w, count, source, focusable)
  local edge = (w.border == "none" or w.border == "") and 0 or 2
  local columns, rows = M.screen()
  local width = w.width or w.max_width
  if width <= 1 then
    width = math.floor(columns * width)
  end
  width = math.max(1, math.min(math.max(w.min_width, width), w.max_width, columns - edge - 2))
  local available = math.max(1, math.min(w.max_height, rows - edge - w.bottom))
  count = type(count) == "function" and count(width, available) or count
  local height = math.max(1, math.min(count, available))
  local row = math.max(0, rows - height - edge - w.bottom)
  if w.row == "center" then
    row = math.max(0, math.floor((rows - height - edge) / 2))
  elseif w.row ~= nil and w.row ~= false then
    row = math.max(0, math.min(w.row, rows - height - edge))
  end
  local col = math.max(0, math.min(columns - width - edge, math.floor((columns - width - edge) / 2) + w.col))
  local point
  if source then
    local r, c, origin = require("base_tools.input.position").place(source, width + edge, height + edge, columns, rows)
    point = origin
    if r then
      row, col = r, c
    end
  end
  local box = M.box(row, col, width, height, w.border, w.zindex, focusable)
  if edge > 0 and w.title ~= false and w.title ~= "" then
    box.title, box.title_pos = w.title, w.title_pos
  end
  return box, edge, point
end

local function wrap_prompt(prompt, width, limit)
  local clip = require("base_tools.text").clip
  local lines = {}
  for row = 1, limit do
    local ellipsis = "…"
    if row < limit then
      ellipsis = false
    end
    local line, _, last = clip(prompt, width, { ellipsis = ellipsis })
    if last == 0 then
      lines[row] = clip(prompt, width)
      break
    end
    lines[row] = line
    prompt = prompt:sub(last + 1)
    if prompt == "" then
      break
    end
  end
  return lines
end

function M.editable(w, count, source, prompt)
  local slot = { row = 0, col = 0, lines = {} }
  if prompt == "" then
    local box, edge = M.input(w, count, source, true)
    return box, edge, slot
  end

  local prompt_width = vim.fn.strdisplaywidth(prompt)
  local box, edge = M.input(w, function(width, height)
    if width - prompt_width >= 8 then
      slot.lines, slot.col = { prompt }, prompt_width
    elseif height == 1 then
      local label = require("base_tools.text").clip(prompt, width - 1)
      slot.lines, slot.col = { label }, vim.fn.strdisplaywidth(label)
    else
      slot.lines = wrap_prompt(prompt, width, height - 1)
      slot.row = #slot.lines
    end
    return count + slot.row
  end, source, false)
  return box, edge, slot
end

function M.editor(box, slot, frame)
  local config = M.box(slot.row, slot.col, box.width - slot.col, box.height - slot.row, "none", box.zindex + 1, true)
  config.relative, config.win = "win", frame
  return config
end

function M.win_options(style)
  return { winblend = style.winblend, winhighlight = style.winhighlight }
end

return M
