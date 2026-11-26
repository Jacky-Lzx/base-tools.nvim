require("base_tools")

local Context = require("base_tools.context")
local text = require("base_tools.text")
local api = vim.api
local M = {}
local attached = {}
local group

---@class base_tools.FooterOptions
---@field context? base_tools.Context Attribution for the lifetime of the footer.
---@field left? string Left-aligned plain text.
---@field right? string Right-aligned plain text.

---@class base_tools.Footer
---@field private context? base_tools.Context
---@field private win integer
---@field private buf integer
---@field private left string
---@field private right string
---@field private previous string
---@field private applied string
---@field private closed? boolean
local Footer = {}
Footer.__index = Footer

local function label(value, previous, context, operation)
  if value == nil then
    return previous
  end
  Context.check(context, operation, type(value) == "string", "Footer labels must be strings")
  return (value:gsub("[%z\1-\31\127]", " "))
end

local function escape(value)
  return (value:gsub("%%", "%%%%"))
end

local function format(footer)
  local left, right = footer.left, footer.right
  local width = api.nvim_win_get_width(footer.win)
  local gap = left ~= "" and 1 or 0
  if right ~= "" and vim.fn.strdisplaywidth(left) + gap + vim.fn.strdisplaywidth(right) <= width then
    return escape(left) .. "%=" .. escape(right)
  end
  local clipped = text.clip(left, width)
  return clipped ~= "" and escape(clipped) or "%="
end

local function forget(footer)
  local slots = attached[footer.win]
  slots[footer.buf] = nil
  if next(slots) == nil then
    attached[footer.win] = nil
  end
end

local function synchronize(footer)
  local win = footer.win
  if not api.nvim_win_is_valid(win) or not api.nvim_buf_is_valid(footer.buf) then
    forget(footer)
    return false
  end
  if api.nvim_win_get_buf(win) ~= footer.buf then
    -- The local option for this buffer is restored when it returns to the window.
    return true
  end

  local options = vim.wo[win][0]
  if options.statusline ~= footer.applied then
    forget(footer)
    return false
  end
  if footer.closed then
    forget(footer)
    options.statusline = footer.previous
    return false
  end

  local formatted = format(footer)
  if formatted ~= footer.applied then
    footer.applied = formatted
    options.statusline = formatted
  end
  return true
end

local function watch()
  if group then
    return
  end
  group = api.nvim_create_augroup("BaseToolsFooter", { clear = true })
  api.nvim_create_autocmd({ "WinResized", "BufWinEnter" }, {
    group = group,
    callback = function()
      for win, slots in pairs(attached) do
        if api.nvim_win_is_valid(win) then
          local footer = slots[api.nvim_win_get_buf(win)]
          if footer then
            synchronize(footer)
          end
        end
      end
    end,
  })
  api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(event)
      local win = tonumber(event.match)
      if win then
        attached[win] = nil
      end
    end,
  })
end

--- Update the supplied labels. An empty string clears the corresponding label.
---@param opts base_tools.FooterOptions
---@return boolean updated Whether this footer still accepts updates.
function Footer:update(opts)
  local slots = attached[self.win]
  if self.closed or not slots or slots[self.buf] ~= self then
    return false
  end

  Context.check(self.context, "footer.update", type(opts) == "table", "Expected footer options")
  local left = label(opts.left, self.left, self.context, "footer.update")
  local right = label(opts.right, self.right, self.context, "footer.update")
  self.left, self.right = left, right
  return synchronize(self)
end

--- Release the footer and restore the previous local statusline if still owned.
function Footer:close()
  local slots = attached[self.win]
  if self.closed or not slots or slots[self.buf] ~= self then
    return
  end
  self.closed = true
  synchronize(self)
end

--- Attach a plain-text footer to the buffer currently displayed in a window.
--- It uses the native statusline of that window-buffer pair.
---@param win integer Window ID or 0 for the current window.
---@param opts? base_tools.FooterOptions
---@return base_tools.Footer
function M.attach(win, opts)
  win = win == 0 and api.nvim_get_current_win() or win
  opts = opts or {}
  local context = opts.context
  local buf = Context.call(context, "footer.attach", api.nvim_win_get_buf, win)
  local left = label(opts.left, "", context, "footer.attach")
  local right = label(opts.right, "", context, "footer.attach")
  local existing = attached[win] and attached[win][buf]
  if existing then
    existing:close()
  end

  local options = vim.wo[win][0]
  local footer = setmetatable({
    context = context,
    win = win,
    buf = buf,
    previous = options.statusline,
    left = left,
    right = right,
  }, Footer)
  footer.applied = format(footer)
  watch()
  attached[win] = attached[win] or {}
  attached[win][buf] = footer
  options.statusline = footer.applied
  return footer
end

return M
