local Context = require("base_tools.context")
local buffer = require("base_tools.buffer")
local M = {}
local api = vim.api

---@class base_tools.FloatOptions
---@field config vim.api.keyset.win_config
---@field context? base_tools.Context
---@field buf? integer
---@field enter? boolean
---@field buf_options? table<string, any>
---@field win_options? table<string, any>
---@field border_labels? base_tools.BorderLabels
---@field keymap_scope? "focus"|"buffer" Keep mappings during focus changes for dedicated buffers with "buffer".

---@class base_tools.Float
---@field win? integer
---@field buf integer
---@field private context? base_tools.Context
---@field private owned boolean
---@field private borrowed_win? boolean
---@field private border_labels? table
---@field private window? base_tools.Window
---@field private buffer_keymaps? boolean
local Float = {}
Float.__index = Float

--- Create an unlisted scratch buffer through `base_tools.buffer.scratch()`.
---@param options? table<string, any> Buffer-local options.
---@return integer
M.scratch = buffer.scratch

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

  Context.call(self.context, "float.update", api.nvim_win_set_config, self.win, config)
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

  local layout = self.border_labels or require("base_tools.border_labels").new(self.win, { context = self.context })
  self.border_labels = layout:set(labels) and layout or nil

  return true
end

--- Bind a Lua action in the displayed buffer for the selected keymap scope.
---@param mode string A single Neovim mode such as n or i.
---@param lhs string
---@param action function
---@param opts? table Options for vim.keymap.set(). The float chooses the buffer.
---@return fun() unmap
function Float:map(mode, lhs, action, opts)
  local message = self.context and "cannot map a closed float" or "base-tools.float: cannot map a closed float"
  Context.check(self.context, "float.map", self:valid(), message)
  if not self.window then
    self.window = require("base_tools.window").attach(self.win, {
      context = self.context,
      keymap_scope = self.buffer_keymaps and "buffer" or "focus",
    })
  end
  return self.window:map(mode, lhs, action, opts)
end

--- Close the float and release its buffer when this handle owns it.
function Float:close()
  if self.window then
    self.window:detach()
    self.window = nil
  end

  if self.borrowed_win and self:valid() and self.border_labels then
    self:set_border_labels({ top = false, bottom = false })
  end

  if self.border_labels then
    self.border_labels:close()
    self.border_labels = nil
  end

  local win, owned = self.win, self.owned
  self.win, self.owned = nil, false
  if not self.borrowed_win and win and api.nvim_win_is_valid(win) then
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
  local context = opts.context
  local scope = opts.keymap_scope or "focus"
  local message = context and "invalid keymap scope" or "base-tools.float: invalid keymap scope"
  Context.check(context, "float.open", scope == "focus" or scope == "buffer", message)
  local owned = opts.buf == nil
  local buf = opts.buf
  if owned then
    buf = M.scratch(vim.tbl_extend("force", { bufhidden = "wipe" }, opts.buf_options or {}, { context = context }))
  end
  local view = setmetatable({
    context = context,
    buf = buf,
    owned = owned,
    buffer_keymaps = scope == "buffer",
  }, Float)

  local ok, err = pcall(function()
    Context.call(context, "float.open", function()
      view.win = api.nvim_open_win(view.buf, opts.enter == true, opts.config)
      for name, value in pairs(opts.win_options or {}) do
        vim.wo[view.win][name] = value
      end
    end)

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

---@private
---@param win integer
---@param opts? { context?: base_tools.Context }
---@return base_tools.Float
function M.attach(win, opts)
  local context = opts and opts.context
  local buf = Context.call(context, "float.attach", api.nvim_win_get_buf, win)
  return setmetatable({ win = win, buf = buf, context = context, owned = false, borrowed_win = true }, Float)
end

return M
