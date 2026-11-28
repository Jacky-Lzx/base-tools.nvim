local Context = require("base_tools.context")
local keymap = require("base_tools.keymap")
local api = vim.api
local M = {}
local mappings = setmetatable({}, { __mode = "k" })

---@class base_tools.WindowOptions
---@field context? base_tools.Context
---@field keymap_scope? "focus"|"buffer" Use buffer scope only for dedicated buffers.
---@field win_options? table<string, any> Window-local options applied when attaching.
---@field on_detach? fun(window: base_tools.Window)

---@class base_tools.Window
---@field win integer
---@field private context? base_tools.Context
---@field private buffer_keymaps boolean
---@field private keymaps? table
---@field private close_event? integer
---@field private detached? boolean
---@field private on_detach? fun(window: base_tools.Window)
local Window = {}
Window.__index = Window

function Window:valid()
  return not self.detached and api.nvim_win_is_valid(self.win)
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
  local win = view.win
  if not view:valid() or not (state.focused or view.buffer_keymaps) then
    return
  end
  local buf = api.nvim_win_get_buf(win)
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
          if not view.buffer_keymaps then
            deactivate(state)
          end
        end
      end,
    }),
    -- An unfocused nvim_win_set_buf() temporarily reports its target as the
    -- current window during BufEnter. WinEnter and WinLeave track real focus.
    api.nvim_create_autocmd("BufEnter", {
      callback = function()
        if api.nvim_get_current_win() == view.win then
          refresh_keymaps(view, state)
        end
      end,
    }),
  }

  view.keymaps = state
  return state
end

--- Bind a Lua action in the displayed buffer while this window has focus, or for a dedicated buffer.
---@param mode string A single Neovim mode such as n or i.
---@param lhs string
---@param action function
---@param opts? table Options for vim.keymap.set(). The window chooses the buffer.
---@return fun() unmap
function Window:map(mode, lhs, action, opts)
  Context.check(self.context, "window.map", self:valid(), "cannot map a detached window")
  opts = vim.tbl_extend("force", {}, opts or {})
  local binding = { window = self }
  function binding.install(buf)
    local cleanup, _, installed =
      keymap.install(mode, lhs, action, vim.tbl_extend("force", {}, opts, { buffer = buf, context = self.context }))
    if not self.buffer_keymaps then
      mappings[installed.callback] = binding
    end
    return cleanup
  end
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

--- Identify a window mapping across focus changes and buffer reinstallation.
--- A removed registration or a mapping from a different window has no identity.
---@param win integer
---@param callback? function
---@return table? id Opaque identity for the current registration.
function M.mapping_id(win, callback)
  local binding = callback and mappings[callback]
  local window = binding and binding.window
  if window and window.win == win and window:valid() and window.keymaps then
    if vim.tbl_contains(window.keymaps.bindings, binding) then
      return binding
    end
  end
end

--- Release mappings. Leave the window and its buffers open.
function Window:detach()
  if self.detached then
    return
  end
  self.detached = true
  release_keymaps(self)
  if self.close_event then
    api.nvim_del_autocmd(self.close_event)
    self.close_event = nil
  end
  if self.on_detach then
    self.on_detach(self)
  end
end

--- Manage mappings and options in an existing split or float.
---@param win integer
---@param opts? base_tools.WindowOptions
---@return base_tools.Window
function M.attach(win, opts)
  opts = opts or {}
  local context = opts.context
  local scope = opts.keymap_scope or "focus"
  Context.check(context, "window.attach", api.nvim_win_is_valid(win), "expected a valid window")
  Context.check(context, "window.attach", scope == "focus" or scope == "buffer", "invalid keymap scope")
  local window = setmetatable({
    win = win,
    context = context,
    buffer_keymaps = scope == "buffer",
    on_detach = opts.on_detach,
  }, Window)
  local local_options = { win = win, scope = "local" }
  local previous = {}
  local ok, err = pcall(function()
    for name, value in pairs(opts.win_options or {}) do
      previous[name] = api.nvim_get_option_value(name, local_options)
      api.nvim_set_option_value(name, value, local_options)
    end
    window.close_event = api.nvim_create_autocmd("WinClosed", {
      pattern = tostring(win),
      callback = function()
        window:detach()
      end,
    })
  end)
  if not ok then
    for name, value in pairs(previous) do
      api.nvim_set_option_value(name, value, local_options)
    end
    error(err, 0)
  end
  return window
end

return M
