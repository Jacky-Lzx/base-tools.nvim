local api = vim.api
local float = require("base_tools.float")
local scrollbar = require("base_tools.scrollbar")
local ns = api.nvim_create_namespace("base-tools-preview")
local previews = {}
local M = {}

---@class base_tools.PreviewOptions: base_tools.FloatOptions
---@field lines? string[] Initial buffer contents.
---@field scrollbar? boolean|base_tools.ScrollbarOptions Show a scrollbar on overflow.

---@class base_tools.Preview
---@field win? integer
---@field buf integer
---@field private float base_tools.Float
---@field private scrollbar? base_tools.Scrollbar
---@field private close_event? integer
---@field private refresh_pending? boolean
local Preview = {}
Preview.__index = Preview

function Preview:valid()
  return self.float:valid()
end

--- Read the current scroll position when content overflows.
---@return base_tools.ScrollPosition?
function Preview:position()
  return self.win and scrollbar.position(self.win)
end

--- Refresh the scrollbar and return the current position.
---@return base_tools.ScrollPosition?
function Preview:refresh()
  if self.scrollbar and self:valid() then
    return self.scrollbar:update(self.win)
  end
  return self:position()
end

--- Replace the contents of the preview buffer.
---@param lines string[]
---@return boolean
function Preview:set_lines(lines)
  if not self:valid() then
    return false
  end
  api.nvim_buf_set_lines(self.buf, 0, -1, false, lines)
  self:refresh()
  return true
end

--- Update the Neovim window configuration used by this preview.
---@param config vim.api.keyset.win_config
---@return boolean
function Preview:update(config)
  if not self.float:update(config) then
    return false
  end
  self:refresh()
  return true
end

---@param labels base_tools.BorderLabels
---@return boolean
function Preview:set_border_labels(labels)
  return self.float:set_border_labels(labels)
end

--- Scroll by screen rows when wrapping is enabled. Stop at the last full viewport.
---@param rows integer Positive scrolls down, negative scrolls up.
---@return boolean
---@return base_tools.ScrollPosition?
function Preview:scroll(rows)
  if not self:valid() then
    return false
  end
  local win = self.win
  api.nvim_win_call(win, function()
    local count = math.abs(rows)
    if rows > 0 then
      local view = vim.fn.winsaveview()
      local remaining = api.nvim_win_text_height(win, {
        start_row = view.topline - 1,
        start_vcol = view.skipcol,
      }).all
      count = math.min(count, remaining - api.nvim_win_get_height(win))
    end
    if count > 0 then
      vim.cmd("normal! " .. count .. (rows > 0 and "\5" or "\25"))
    end
  end)
  return true, self:refresh()
end

local function close_scrollbar(self)
  if self.scrollbar then
    self.scrollbar:close()
    self.scrollbar = nil
    previews[self.win] = nil
    if not next(previews) then
      api.nvim_set_decoration_provider(ns, {})
    end
  end
end

--- Close the preview, its scrollbar, and any buffer it owns.
function Preview:close()
  if self.close_event then
    api.nvim_del_autocmd(self.close_event)
    self.close_event = nil
  end
  if self.win then
    close_scrollbar(self)
    self.win = nil
  end
  self.float:close()
end

--- Refresh after redraw so external scrolling and edits on unfocused previews
--- also update the thumb. Schedule window changes outside the redraw lock.
local function observe(self, win)
  if not next(previews) then
    api.nvim_set_decoration_provider(ns, {
      on_win = function(_, target)
        local view = previews[target]
        if view and not view.refresh_pending then
          view.refresh_pending = true
          vim.schedule(function()
            view.refresh_pending = false
            if previews[target] == view then
              view:refresh()
            end
          end)
        end
        return false
      end,
    })
  end
  previews[win] = self
end

--- Configure or disable the scrollbar for the existing preview window.
---@param opts? boolean|base_tools.ScrollbarOptions
---@return boolean
function Preview:set_scrollbar(opts)
  if not self:valid() then
    return false
  end
  close_scrollbar(self)
  if opts then
    self.scrollbar = scrollbar.new(type(opts) == "table" and opts or nil)
    observe(self, self.win)
    self:refresh()
  end
  return true
end

---@param opts base_tools.PreviewOptions
---@return base_tools.Preview
function M.open(opts)
  local target = float.open({
    config = opts.config,
    buf = opts.buf,
    enter = opts.enter,
    buf_options = opts.buf_options,
    border_labels = opts.border_labels,
    win_options = vim.tbl_extend("force", { wrap = true, smoothscroll = true }, opts.win_options or {}),
  })
  local view = setmetatable({ float = target, win = target.win, buf = target.buf }, Preview)
  local ok, err = pcall(function()
    local win = target.win
    view.close_event = api.nvim_create_autocmd("WinClosed", {
      pattern = tostring(win),
      once = true,
      callback = function()
        view.close_event = nil
        close_scrollbar(view)
        view.win = nil
      end,
    })
    if opts.lines then
      view:set_lines(opts.lines)
    end
    if opts.scrollbar then
      view:set_scrollbar(opts.scrollbar)
    end
  end)
  if not ok then
    view:close()
    error(err, 0)
  end
  return view
end

return M
