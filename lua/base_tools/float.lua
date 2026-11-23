require("base_tools")
local M = {}
local api = vim.api

---@class base_tools.FloatOptions
---@field config vim.api.keyset.win_config
---@field buf? integer
---@field enter? boolean
---@field buf_options? table<string, any>
---@field win_options? table<string, any>
---@field border_labels? base_tools.BorderLabels

---@class base_tools.Float
---@field win? integer
---@field buf integer
---@field private owned boolean
---@field private border_labels? table
local Float = {}
Float.__index = Float

local function set_options(options, values)
  for key, value in pairs(values or {}) do
    options[key] = value
  end
end

--- Create an unlisted scratch buffer that can be reused after hiding a window.
---@param options? table<string, any> Buffer-local options.
---@return integer
function M.scratch(options)
  local buf = api.nvim_create_buf(false, true)
  local ok, err = pcall(function()
    vim.bo[buf].bufhidden = options and options.bufhidden or "hide"
    set_options(vim.bo[buf], options)
  end)
  if not ok then
    api.nvim_buf_delete(buf, { force = true })
    error(err, 0)
  end
  return buf
end

function Float:valid()
  return self.win ~= nil and api.nvim_win_is_valid(self.win)
end

--- Apply a full or partial Neovim window configuration to the existing float.
---@param config vim.api.keyset.win_config
---@return boolean
function Float:update(config)
  if not self:valid() then
    return false
  end
  api.nvim_win_set_config(self.win, config)
  if self.border_labels then
    self.border_labels:refresh(config)
  end
  return true
end

--- Update the given border slots. Pass false to clear a slot or a whole edge.
---@param labels base_tools.BorderLabels
---@return boolean
function Float:set_border_labels(labels)
  if not self:valid() then
    return false
  end
  local layout = self.border_labels or require("base_tools.border_labels").new(self.win)
  self.border_labels = layout:set(labels) and layout or nil
  return true
end

--- Close the float and release its buffer when this handle owns it.
function Float:close()
  if self.border_labels then
    self.border_labels:close()
    self.border_labels = nil
  end
  local win, owned = self.win, self.owned
  self.win, self.owned = nil, false
  if win and api.nvim_win_is_valid(win) then
    api.nvim_win_close(win, true)
  end
  if owned and api.nvim_buf_is_valid(self.buf) then
    api.nvim_buf_delete(self.buf, { force = true })
  end
end

--- Open a float with an owned scratch buffer or a buffer supplied by the caller.
---@param opts base_tools.FloatOptions
---@return base_tools.Float
function M.open(opts)
  local owned = opts.buf == nil
  local view = setmetatable({
    buf = owned and M.scratch(vim.tbl_extend("force", { bufhidden = "wipe" }, opts.buf_options or {})) or opts.buf,
    owned = owned,
  }, Float)
  local ok, err = pcall(function()
    view.win = api.nvim_open_win(view.buf, opts.enter == true, opts.config)
    set_options(vim.wo[view.win], opts.win_options)
    if opts.border_labels then
      view:set_border_labels(opts.border_labels)
    end
  end)
  if not ok then
    view:close()
    error(err, 0)
  end
  return view
end

return M
