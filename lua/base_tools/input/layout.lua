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

-- count may depend on the available width (wrapped, read-only prompts).
function M.input(w, count, source, focusable)
  local edge = (w.border == "none" or w.border == "") and 0 or 2
  local columns, rows = M.screen()
  local width = w.width or w.max_width
  if width <= 1 then
    width = math.floor(columns * width)
  end
  width = math.max(1, math.min(math.max(w.min_width, width), w.max_width, columns - edge - 2))
  count = type(count) == "function" and count(width) or count
  local height = math.max(1, math.min(count, w.max_height, rows - edge - w.bottom))
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

function M.win_options(style)
  return { winblend = style.winblend, winhighlight = style.winhighlight }
end

return M
