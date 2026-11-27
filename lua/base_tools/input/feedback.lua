-- Input feedback lives outside the editable text and never enters its result.
local M = {}
local api = vim.api

local function clip(text, width)
  text = text:gsub("[\r\n]", " ")
  if vim.fn.strdisplaywidth(text) <= width then
    return text
  end
  local first, last, best = 0, vim.fn.strchars(text), ""
  while first <= last do
    local middle = math.floor((first + last) / 2)
    local part = vim.fn.strcharpart(text, 0, middle)
    if vim.fn.strdisplaywidth(part) < width then
      best, first = part, middle + 1
    else
      last = middle - 1
    end
  end
  return width > 0 and best .. "…" or ""
end

function M.close(a)
  if a.feedback_win and api.nvim_win_is_valid(a.feedback_win) then
    api.nvim_win_close(a.feedback_win, true)
  end
  if a.feedback_buf and api.nvim_buf_is_valid(a.feedback_buf) then
    api.nvim_buf_delete(a.feedback_buf, { force = true })
  end
  a.feedback_win, a.feedback_buf = nil, nil
end

function M.render(a, box)
  local error = a.validation_error or a.change_error
  local hint = ""
  if a.opts.hints then
    local mode = api.nvim_get_mode().mode:sub(1, 1)
    local enter = a.opts.multiline and "Enter: newline · Ctrl-S: confirm" or "Enter: confirm"
    hint = mode == "s" and ("SELECT · Type: replace · " .. enter .. " · Esc: Normal")
      or mode == "i" and ("INSERT · " .. enter .. " · Esc: Normal")
      or "NORMAL · i: edit · Enter: confirm · Esc: cancel"
  end
  local text = error or a.change_pending and "Checking…" or a.change_status or hint
  local group = error and a.style.error_group or a.style.hint_group
  text = clip(text, math.max(1, box.width - 2))
  local border = a.style.border ~= "none" and a.style.border ~= ""
  if border then
    M.close(a)
    if a.feedback_text ~= text or a.feedback_group ~= group then
      local label
      if text ~= "" then
        label = { { text, group } }
      else
        local bottom = a.opts.border_labels and a.opts.border_labels.bottom
        label = type(bottom) == "table" and bottom.left or false
      end
      local frame = a.frame or a.float
      frame:set_border_labels({ bottom = { left = label } })
    end
  elseif text ~= "" then
    local rows = vim.o.lines - vim.o.cmdheight
    local row = box.row + box.height
    if row >= rows then
      row = math.max(0, box.row - 1)
    end
    local config = {
      relative = "editor",
      row = row,
      col = box.col,
      width = box.width,
      height = 1,
      style = "minimal",
      border = "",
      focusable = false,
      zindex = box.zindex + 1,
      noautocmd = true,
    }
    if not a.feedback_buf then
      a.feedback_buf = api.nvim_create_buf(false, true)
      vim.bo[a.feedback_buf].bufhidden = "wipe"
    end
    if not a.feedback_win or not api.nvim_win_is_valid(a.feedback_win) then
      a.feedback_win = api.nvim_open_win(a.feedback_buf, false, config)
    else
      api.nvim_win_set_config(a.feedback_win, config)
    end
    api.nvim_buf_set_lines(a.feedback_buf, 0, -1, false, { text })
    vim.wo[a.feedback_win].winhighlight = "Normal:" .. group
  else
    M.close(a)
  end
  a.feedback_text, a.feedback_group = text, group
end

return M
