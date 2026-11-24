local float = require("base_tools.float")
local api = vim.api
local ns = api.nvim_create_namespace("base-tools-scrollbar")
local M = {}

---@class base_tools.ScrollPosition
---@field total integer Total screen rows, accounting for wrapping and concealment.
---@field visible integer Height of the visible window in screen rows.
---@field offset integer Number of screen rows scrolled from the top.
---@field progress number Scroll position from 0 at the top to 1 at the bottom.

---@param win integer Window ID or 0 for the current window.
---@return base_tools.ScrollPosition?
function M.position(win)
  if not api.nvim_win_is_valid(win) then
    return
  end

  local total = api.nvim_win_text_height(win, {}).all
  local visible = api.nvim_win_get_height(win)
  if total <= visible then
    return
  end

  local view = api.nvim_win_call(win, vim.fn.winsaveview)
  local before = api.nvim_win_text_height(win, {
    end_row = view.topline - 1,
    end_vcol = view.skipcol,
  }).all
  local offset = math.min(before, total - visible)

  return { total = total, visible = visible, offset = offset, progress = offset / (total - visible) }
end

---@class base_tools.ScrollbarOptions
---@field track_highlight? string Highlight for the track and its background. Defaults to FloatBorder.
---@field thumb_highlight? string Highlight for the thumb. Defaults to Title.

---@class base_tools.Scrollbar
---@field private opts base_tools.ScrollbarOptions
---@field private view? base_tools.Float
---@field private target? integer
---@field private close_event? integer
---@field private config? vim.api.keyset.win_config
---@field private thumb? string
local Scrollbar = {}
Scrollbar.__index = Scrollbar

--- Close the scrollbar and release its owned buffer.
function Scrollbar:close()
  if self.close_event then
    api.nvim_del_autocmd(self.close_event)
    self.close_event = nil
  end
  if self.view then
    self.view:close()
  end
  self.view, self.target, self.config, self.thumb = nil, nil, nil, nil
end

--- Update the track and thumb beside a target window. Returns the same position as M.position.
---@param win integer Window ID or 0 for the current window.
---@return base_tools.ScrollPosition?
function Scrollbar:update(win)
  win = win == 0 and api.nvim_get_current_win() or win
  local position = M.position(win)
  if not position then
    self:close()
    return
  end

  local target = api.nvim_win_get_config(win)
  local width = api.nvim_win_get_width(win)
  local left = type(target.border) == "table" and target.border[8] ~= "" and 1 or 0
  if api.nvim_win_get_position(win)[2] + left + width >= vim.o.columns then
    self:close()
    return position
  end

  local config = {
    relative = "win",
    win = win,
    row = 0,
    col = width,
    width = 1,
    height = position.visible,
    style = "minimal",
    border = "none",
    focusable = false,
    mouse = false,
    zindex = (target.zindex or 50) + 1,
  }

  if self.target ~= win or not self.view or not self.view:valid() then
    self:close()

    self.view = float.open({
      config = vim.tbl_extend("force", config, { noautocmd = true }),
      win_options = { wrap = false, winhighlight = "Normal:" .. (self.opts.track_highlight or "FloatBorder") },
    })
    self.target, self.config = win, config

    self.close_event = api.nvim_create_autocmd("WinClosed", {
      pattern = tostring(win),
      once = true,
      callback = function()
        self.close_event = nil
        self:close()
      end,
    })
  elseif not vim.deep_equal(self.config, config) then
    self.view:update(config)
    self.config = config
  end

  local height = position.visible
  local size = math.max(1, math.floor(height * height / position.total))
  local offset = math.floor((height - size) * position.progress)
  local thumb = height .. ":" .. offset .. ":" .. size

  if self.thumb ~= thumb then
    local lines = {}
    for row = 1, height do
      lines[row] = row > offset and row <= offset + size and "┃" or "│"
    end

    local buf = self.view.buf
    api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    api.nvim_buf_set_extmark(buf, ns, offset, 0, {
      end_row = offset + size - 1,
      end_col = #"┃",
      hl_group = self.opts.thumb_highlight or "Title",
    })
    self.thumb = thumb
  end

  return position
end

---@param opts? base_tools.ScrollbarOptions
---@return base_tools.Scrollbar
function M.new(opts)
  return setmetatable({ opts = opts or {} }, Scrollbar)
end

return M
