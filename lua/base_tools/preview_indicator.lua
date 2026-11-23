local api = vim.api
local float = require("base_tools.float")
local text = require("base_tools.text")
local M = {}

---@class base_tools.PreviewIndicator
---@field private float? base_tools.Float
---@field private config? vim.api.keyset.win_config
---@field private value? string
---@field private highlight? string

local Indicator = {}
Indicator.__index = Indicator

function Indicator:close()
  if self.float then
    self.float:close()
    self.float = nil
  end
  self.config, self.value, self.highlight = nil, nil, nil
end

local function border_visible(border, index)
  local cell = type(border) == "table" and border[index]
  local glyph = type(cell) == "table" and cell[1] or cell
  return glyph and glyph ~= ""
end

function Indicator:update(win, position, percent, highlight)
  local target = api.nvim_win_get_config(win)
  local row = api.nvim_win_get_position(win)[1] + position.visible
  if border_visible(target.border, 1) or border_visible(target.border, 2) or border_visible(target.border, 3) then
    row = row + 1
  end
  if border_visible(target.border, 6) or row >= vim.o.lines - vim.o.cmdheight then
    self:close()
    return
  end

  local width = api.nvim_win_get_width(win)
  local value = text.clip(("%d%%"):format(percent), width, { side = "start" })
  local cells = vim.fn.strdisplaywidth(value)
  local config = {
    relative = "win",
    win = win,
    row = position.visible,
    col = width - cells,
    width = cells,
    height = 1,
    style = "minimal",
    border = "none",
    focusable = false,
    mouse = false,
    zindex = (target.zindex or 50) + 1,
  }
  if not self.float or not self.float:valid() then
    self:close()
    self.float = float.open({
      config = vim.tbl_extend("force", config, { noautocmd = true }),
      win_options = { wrap = false },
    })
    self.config = config
  elseif not vim.deep_equal(self.config, config) then
    self.float:update(config)
    self.config = config
  end

  highlight = highlight or "FloatFooter"
  if self.highlight ~= highlight then
    vim.wo[self.float.win].winhighlight = "Normal:" .. highlight
    self.highlight = highlight
  end
  if self.value ~= value then
    api.nvim_buf_set_lines(self.float.buf, 0, -1, false, { value })
    self.value = value
  end
end

function M.new()
  return setmetatable({}, Indicator)
end

return M
