local Context = require("base_tools.context")
local window = require("base_tools.window")
local api = vim.api
local M = {}

---@class base_tools.View
---@field tab integer
---@field private context? base_tools.Context
---@field private windows table<integer, base_tools.Window>
---@field private close_event integer
---@field private detached? boolean
local View = {}
View.__index = View

--- Register a window belonging to the tab.
---@param win integer
---@param opts? base_tools.WindowOptions
---@return base_tools.Window
function View:attach_window(win, opts)
  local check = Context.checker(self.context, "view.attach_window")
  check(not self.detached, "cannot attach a window to a detached view")
  check(api.nvim_win_is_valid(win) and api.nvim_win_get_tabpage(win) == self.tab, "expected a window in the view's tab")
  check(not self.windows[win], "window is already attached")
  opts = vim.tbl_extend("force", { context = self.context }, opts or {})
  local on_detach = opts.on_detach
  opts.on_detach = function(handle)
    self.windows[win] = nil
    if on_detach then
      on_detach(handle)
    end
  end
  local handle = window.attach(win, opts)
  self.windows[win] = handle
  return handle
end

--- Detach all registered windows, leaving the tab and its buffers open.
function View:detach()
  if self.detached then
    return
  end
  self.detached = true
  api.nvim_del_autocmd(self.close_event)
  for _, handle in pairs(self.windows) do
    handle:detach()
  end
end

--- Manage multiple windows in an existing tab.
---@param tab integer
---@param opts? { context?: base_tools.Context, on_close?: fun(view: base_tools.View) }
---@return base_tools.View
function M.attach(tab, opts)
  opts = opts or {}
  Context.check(opts.context, "view.attach", api.nvim_tabpage_is_valid(tab), "expected a valid tab")
  local view = setmetatable({ tab = tab, context = opts.context, windows = {} }, View)
  view.close_event = api.nvim_create_autocmd("TabClosed", {
    callback = function()
      vim.schedule(function()
        if not view.detached and not api.nvim_tabpage_is_valid(tab) then
          view:detach()
          if opts.on_close then
            opts.on_close(view)
          end
        end
      end)
    end,
  })
  return view
end

return M
