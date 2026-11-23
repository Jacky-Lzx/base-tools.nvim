local api = vim.api
local float = require("base_tools.float")
local scrollbar = require("base_tools.scrollbar")
local ns = api.nvim_create_namespace("base-tools-preview")
local previews = {}
local views = {}
local M = {}

---@class base_tools.PreviewAttachOptions
---@field scrollbar? boolean|base_tools.ScrollbarOptions Show a scrollbar on overflow.
---@field border_labels? base_tools.BorderLabels Initial labels.

---@class base_tools.PreviewOptions: base_tools.FloatOptions
---@field lines? string[] Initial buffer contents.
---@field language? string|false Initial Tree-sitter language.
---@field scrollbar? boolean|base_tools.ScrollbarOptions Show a scrollbar on overflow.

---@class base_tools.PreviewContent
---@field lines string[] Replacement buffer contents.
---@field scroll? "keep"|"top" Keep the viewport or reset it to the top.
---@field language? string|false Set a Tree-sitter language, or clear the preview's highlighter.
---@field border_labels? base_tools.BorderLabels Labels to update with the contents.

---@class base_tools.Preview
---@field win? integer
---@field buf integer
---@field private float base_tools.Float
---@field private attached? boolean
---@field private scrollbar? base_tools.Scrollbar
---@field private indicator? base_tools.PreviewIndicator
---@field private close_event? integer
---@field private refresh_pending? boolean
---@field private scroll_labels table<string, table<string, base_tools.ScrollPercentBorderLabel>>
---@field private scroll_percent? integer
---@field private scroll_arrows? string
---@field private highlighter? vim.treesitter.highlighter
local Preview = {}
Preview.__index = Preview

function Preview:valid()
  return self.win ~= nil and self.float:valid()
end

--- Read the current scroll position when content overflows.
---@return base_tools.ScrollPosition?
function Preview:position()
  return self.win and scrollbar.position(self.win)
end

local function scroll_text(label, percent, arrows)
  local value = ("%d%%"):format(percent)
  return label.arrows and arrows ~= "" and arrows .. " " .. value or value
end

local function scroll_label(label, percent, arrows)
  return percent and { { " " .. scroll_text(label, percent, arrows) .. " ", label.highlight } } or false
end

local function render_labels(self, labels, percent, arrows)
  local changed = percent ~= self.scroll_percent or arrows ~= self.scroll_arrows
  if not labels and (not changed or not next(self.scroll_labels)) then
    return
  end

  local patch = {}
  for _, edge in ipairs({ "top", "bottom" }) do
    local updates = labels and labels[edge]
    local tracked = self.scroll_labels[edge]
    if updates == false then
      self.scroll_labels[edge] = nil
      patch[edge] = false
    elseif updates or tracked then
      tracked = tracked or {}
      local slots = {}
      for _, align in ipairs({ "left", "center", "right" }) do
        local label = updates and updates[align]
        if label ~= nil then
          if type(label) == "table" and label.kind == "scroll_percent" then
            tracked[align] = {
              kind = "scroll_percent",
              highlight = label.highlight,
              fallback = label.fallback,
              arrows = label.arrows,
            }
            slots[align] = scroll_label(label, percent, arrows)
          else
            tracked[align] = nil
            slots[align] = label
          end
        elseif changed and tracked[align] then
          slots[align] = scroll_label(tracked[align], percent, arrows)
        end
      end
      self.scroll_labels[edge] = next(tracked) and tracked or nil
      if next(slots) then
        patch[edge] = slots
      end
    end
  end

  if next(patch) then
    self.float:set_border_labels(patch)
  end
  self.scroll_percent, self.scroll_arrows = percent, arrows
end

local function unobserve(win)
  if previews[win] then
    previews[win] = nil
    if not next(previews) then
      api.nvim_set_decoration_provider(ns, {})
    end
  end
end

-- Redraw also covers scrolling and edits performed outside the preview API.
-- Schedule window changes outside the redraw lock.
local function update_observation(self)
  local win = self.win
  if not self.scrollbar and not next(self.scroll_labels) then
    unobserve(win)
    return
  end
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

local function close_indicator(self)
  if self.indicator then
    self.indicator:close()
    self.indicator = nil
  end
end

local function refresh_indicator(self, position, percent, arrows)
  local bottom = self.scroll_labels.bottom
  local label = bottom and bottom.right
  if position and label and label.fallback == "below" then
    self.indicator = self.indicator or require("base_tools.preview_indicator").new()
    self.indicator:update(self.win, position, scroll_text(label, percent, arrows), label.highlight)
  else
    close_indicator(self)
  end
end

local function refresh(self, labels)
  local position
  if self.scrollbar then
    position = self.scrollbar:update(self.win)
  else
    position = self:position()
  end
  local percent = position and math.floor(position.progress * 100)
  local arrows = position and ((position.offset > 0 and "↑" or "") .. (position.progress < 1 and "↓" or ""))
  render_labels(self, labels, percent, arrows)
  refresh_indicator(self, position, percent, arrows)
  return position
end

--- Refresh the scrollbar and scroll labels, and return the current position.
---@return base_tools.ScrollPosition?
function Preview:refresh()
  if self:valid() then
    return refresh(self)
  end
end

local function stop_highlight(self)
  if self.highlighter then
    if vim.treesitter.highlighter.active[self.buf] == self.highlighter then
      vim.treesitter.stop(self.buf)
    end
    self.highlighter = nil
  end
end

local function highlight(self, language)
  if not language or language == "" then
    stop_highlight(self)
    return
  end

  local treesitter = vim.treesitter
  local lang = treesitter.language.get_lang(language) or language
  local active = treesitter.highlighter.active[self.buf]
  if active and (active ~= self.highlighter or active.tree:lang() == lang) then
    return
  end
  stop_highlight(self)
  if pcall(treesitter.start, self.buf, lang) then
    self.highlighter = treesitter.highlighter.active[self.buf]
  end
end

local function remaining_rows(win, view)
  return api.nvim_win_text_height(win, {
    start_row = view.topline - 1,
    start_vcol = view.skipcol,
  }).all
end

local function restore_scroll(win, saved)
  api.nvim_win_call(win, function()
    if not saved then
      vim.fn.winrestview({
        topline = 1,
        lnum = 1,
        col = 0,
        leftcol = 0,
        skipcol = 0,
        coladd = 0,
        curswant = 0,
        topfill = 0,
      })
      return
    end
    vim.fn.winrestview(saved)
    local view = vim.fn.winsaveview()
    if view.skipcol > 0 then
      local row = view.topline - 1
      if api.nvim_win_text_height(win, { start_row = row, end_row = row, start_vcol = view.skipcol }).all == 0 then
        view.skipcol = 0
        vim.fn.winrestview(view)
      end
    end
    local missing = api.nvim_win_get_height(win) - remaining_rows(win, view)
    if missing > 0 then
      vim.cmd("normal! " .. missing .. "\25")
    end
  end)
end

local function apply_content(self, content)
  local win = self.win
  local saved = content.scroll == "keep" and api.nvim_win_call(win, vim.fn.winsaveview) or nil
  if content.lines then
    api.nvim_buf_set_lines(self.buf, 0, -1, false, content.lines)
  end
  if content.language ~= nil then
    highlight(self, content.language)
  end
  if content.scroll then
    restore_scroll(win, saved)
  end
  refresh(self, content.border_labels)
  update_observation(self)
end

--- Replace the preview contents and optionally update its border labels.
---@param content base_tools.PreviewContent
---@return boolean
function Preview:set_content(content)
  if not self:valid() then
    return false
  end
  apply_content(self, content)
  return true
end

--- Replace the contents of the preview buffer.
---@param lines string[]
---@return boolean
function Preview:set_lines(lines)
  return self:set_content({ lines = lines })
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

--- Measure rendered content at the current width.
---@param opts? { max_height?: integer }
---@return integer? height At least one row, or nil if closed.
function Preview:content_height(opts)
  if not self:valid() then
    return
  end
  local rows = api.nvim_win_text_height(self.win, {}).all
  return math.max(1, math.min(rows, opts and opts.max_height or rows))
end

--- Fit the window to its rendered contents at the current width.
---@param opts? { max_height?: integer }
---@return integer? height The resulting window height, or nil if closed.
function Preview:fit_height(opts)
  local height = self:content_height(opts)
  if not height then
    return
  end
  if height ~= api.nvim_win_get_height(self.win) then
    self:update({ height = height })
  end
  return api.nvim_win_get_height(self.win)
end

---@param labels base_tools.BorderLabels
---@return boolean
function Preview:set_border_labels(labels)
  if not self:valid() then
    return false
  end
  apply_content(self, { border_labels = labels })
  return true
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
      local remaining = remaining_rows(win, vim.fn.winsaveview())
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
  end
end

local function release(self)
  local win = self.win
  if win then
    views[win] = nil
    unobserve(win)
    close_scrollbar(self)
    close_indicator(self)
    stop_highlight(self)
    self.win = nil
  end
end

--- Close an owned preview, or release the decorations of an attached preview.
function Preview:close()
  if self.close_event then
    api.nvim_del_autocmd(self.close_event)
    self.close_event = nil
  end
  release(self)
  self.float:close()
end

--- Remove decorations and restore the existing window's title and footer.
---@return boolean
function Preview:detach()
  if not self.attached or not self:valid() then
    return false
  end
  self:close()
  return true
end

local function new_scrollbar(opts)
  if opts then
    return scrollbar.new(type(opts) == "table" and opts or nil)
  end
end

--- Configure or disable the scrollbar for the existing preview window.
---@param opts? boolean|base_tools.ScrollbarOptions
---@return boolean
function Preview:set_scrollbar(opts)
  if not self:valid() then
    return false
  end
  close_scrollbar(self)
  self.scrollbar = new_scrollbar(opts)
  if self.scrollbar then
    self:refresh()
  end
  update_observation(self)
  return true
end

local function mount(target, opts, attached)
  local view = setmetatable({
    float = target,
    win = target.win,
    buf = target.buf,
    scroll_labels = {},
    attached = attached,
  }, Preview)
  views[target.win] = view
  local ok, err = pcall(function()
    local win = target.win
    view.close_event = api.nvim_create_autocmd("WinClosed", {
      pattern = tostring(win),
      once = true,
      callback = function()
        view.close_event = nil
        release(view)
      end,
    })
    view.scrollbar = new_scrollbar(opts.scrollbar)
    if opts.lines or opts.language ~= nil or opts.border_labels or view.scrollbar then
      apply_content(view, opts)
    end
  end)
  if not ok then
    view:close()
    error(err, 0)
  end
  return view
end

--- Decorate a float that is already open. Repeated calls return the same attachment.
---@param win integer Window ID or 0 for the current window.
---@param opts? base_tools.PreviewAttachOptions
---@return base_tools.Preview
function M.attach(win, opts)
  win = win == 0 and api.nvim_get_current_win() or win
  local existing = views[win]
  if existing then
    assert(existing.attached, "window is already owned by a preview")
    return existing
  end
  assert(api.nvim_win_get_config(win).relative ~= "", "preview.attach requires a floating window")
  opts = opts or {}
  return mount(float.attach(win), { scrollbar = opts.scrollbar, border_labels = opts.border_labels }, true)
end

---@param opts base_tools.PreviewOptions
---@return base_tools.Preview
function M.open(opts)
  local target = float.open({
    config = opts.config,
    buf = opts.buf,
    enter = opts.enter,
    buf_options = opts.buf_options,
    win_options = vim.tbl_extend("force", { wrap = true, smoothscroll = true }, opts.win_options or {}),
  })
  return mount(target, opts)
end

return M
