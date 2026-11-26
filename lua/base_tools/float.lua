local buffer = require("base_tools.buffer")
local M = {}
local api = vim.api

---@class base_tools.FloatOptions
---@field config vim.api.keyset.win_config
---@field buf? integer
---@field enter? boolean
---@field buf_options? table<string, any>
---@field win_options? table<string, any>
---@field border_labels? base_tools.BorderLabels

---@class base_tools.FloatMapping
---@field install fun(buf: integer): fun()
---@field cleanup? fun()

---@class base_tools.FloatKeymaps
---@field focused boolean
---@field buf? integer
---@field events integer[]
---@field bindings base_tools.FloatMapping[]

---@class base_tools.Float
---@field win? integer
---@field buf integer
---@field private owned boolean
---@field private borrowed_win? boolean
---@field private border_labels? table
---@field private keymaps? base_tools.FloatKeymaps
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

local function unbind(binding)
  if binding.cleanup then
    binding.cleanup()
    binding.cleanup = nil
  end
end

local function deactivate(state)
  for _, binding in ipairs(state.bindings) do
    unbind(binding)
  end
  state.buf = nil
end

local function release_keymaps(view)
  local state = view.keymaps
  if state then
    view.keymaps = nil
    deactivate(state)
    for _, event in ipairs(state.events) do
      api.nvim_del_autocmd(event)
    end
  end
end

local function refresh_keymaps(view, state)
  if not state.focused or api.nvim_get_current_win() ~= view.win then
    return
  end
  local buf = api.nvim_get_current_buf()
  if state.buf == buf then
    return
  end
  deactivate(state)
  state.buf = buf
  for _, binding in ipairs(state.bindings) do
    binding.cleanup = binding.install(buf)
  end
end

local function watch_keymaps(view)
  local state = { focused = api.nvim_get_current_win() == view.win, bindings = {} }
  state.events = {
    api.nvim_create_autocmd("WinEnter", {
      callback = function()
        if api.nvim_get_current_win() == view.win then
          state.focused = true
          refresh_keymaps(view, state)
        end
      end,
    }),
    api.nvim_create_autocmd("WinLeave", {
      callback = function()
        if api.nvim_get_current_win() == view.win then
          state.focused = false
          deactivate(state)
        end
      end,
    }),
    -- An unfocused nvim_win_set_buf() temporarily reports its target as the
    -- current window during BufEnter. WinEnter and WinLeave track real focus.
    api.nvim_create_autocmd("BufEnter", {
      callback = function()
        refresh_keymaps(view, state)
      end,
    }),
    api.nvim_create_autocmd("WinClosed", {
      pattern = tostring(view.win),
      callback = function()
        release_keymaps(view)
      end,
    }),
  }

  view.keymaps = state
  return state
end

--- Bind a Lua action in the buffer displayed by this float while it has focus.
---@param mode string A single Neovim mode such as n or i.
---@param lhs string
---@param action function
---@param opts? table Options for vim.keymap.set(). The float chooses the buffer.
---@return fun() unmap
function Float:map(mode, lhs, action, opts)
  assert(self:valid(), "base-tools.float: cannot map a closed float")
  local keymap = require("base_tools.keymap")
  opts = vim.tbl_extend("force", {}, opts or {})
  local binding = {
    install = function(buf)
      local cleanup = keymap.install(mode, lhs, action, vim.tbl_extend("force", {}, opts, { buffer = buf }))
      return cleanup
    end,
  }
  local state = self.keymaps or watch_keymaps(self)
  refresh_keymaps(self, state)
  if state.buf then
    binding.cleanup = binding.install(state.buf)
  end
  state.bindings[#state.bindings + 1] = binding

  return function()
    if self.keymaps ~= state then
      return
    end
    for index, candidate in ipairs(state.bindings) do
      if candidate == binding then
        unbind(binding)
        table.remove(state.bindings, index)
        if #state.bindings == 0 then
          release_keymaps(self)
        end
        return
      end
    end
  end
end

--- Close the float and release its buffer when this handle owns it.
function Float:close()
  release_keymaps(self)

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
  local owned = opts.buf == nil
  local view = setmetatable({
    buf = owned and M.scratch(vim.tbl_extend("force", { bufhidden = "wipe" }, opts.buf_options or {})) or opts.buf,
    owned = owned,
  }, Float)

  local ok, err = pcall(function()
    view.win = api.nvim_open_win(view.buf, opts.enter == true, opts.config)
    for name, value in pairs(opts.win_options or {}) do
      vim.wo[view.win][name] = value
    end

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
---@return base_tools.Float
function M.attach(win)
  return setmetatable({ win = win, buf = api.nvim_win_get_buf(win), owned = false, borrowed_win = true }, Float)
end

return M
