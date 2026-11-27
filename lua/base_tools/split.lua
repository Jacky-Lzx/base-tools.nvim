local buffer = require("base_tools.buffer")
local Context = require("base_tools.context")
local api = vim.api
local M = {}

---@class base_tools.SplitOptions
---@field config vim.api.keyset.win_config Split placement and dimensions.
---@field enter? boolean Focus the split on open.
---@field buf_options? table<string, any> Scratch buffer options.
---@field win_options? table<string, any> Window-local options.
---@field on_buffer? fun(buf: integer) Initialize the scratch buffer before displaying it.
---@field on_close? fun(split: base_tools.Split) Release resources when the split closes.
---@field context? base_tools.Context

---@class base_tools.Split
---@field buf integer
---@field win? integer
---@field tab? integer Tabpage where the split was opened.
---@field private context? base_tools.Context
---@field private group? integer
---@field private on_close? fun(split: base_tools.Split)
---@field private closed? boolean
---@field private closing? boolean
local Split = {}
Split.__index = Split

local function shows_buffer(split)
  return split.win and api.nvim_win_is_valid(split.win) and api.nvim_win_get_buf(split.win) == split.buf
end

function Split:valid()
  return not self.closed and shows_buffer(self) == true
end

--- Bind a key in the owned scratch buffer.
---@param mode string|string[]
---@param lhs string
---@param action string|function
---@param opts? table
function Split:map(mode, lhs, action, opts)
  Context.check(self.context, "split.map", self:valid(), "cannot map a closed split")
  local options = vim.tbl_extend("force", {}, opts or {}, { buffer = self.buf })
  options.desc = Context.keymap_desc(self.context, options.desc)
  Context.call(self.context, "split.map", vim.keymap.set, mode, lhs, action, options)
end

local function finish(split)
  if split.closed then
    return true
  end

  split.closed = true
  if split.group then
    pcall(api.nvim_del_augroup_by_id, split.group)
    split.group = nil
  end

  local on_close = split.on_close
  split.on_close = nil
  if on_close then
    return pcall(on_close, split)
  end
  return true
end

local function last_split(win)
  for _, other in ipairs(api.nvim_tabpage_list_wins(api.nvim_win_get_tabpage(win))) do
    if other ~= win then
      local config = api.nvim_win_get_config(other)
      if config.relative == "" and not config.external then
        return false
      end
    end
  end
  return true
end

local function release(split)
  if shows_buffer(split) then
    local win = split.win
    if last_split(win) then
      vim.wo[win].winfixbuf = false
      api.nvim_win_set_buf(win, api.nvim_create_buf(true, false))
    else
      api.nvim_win_close(win, true)
    end
  end

  if api.nvim_buf_is_valid(split.buf) then
    api.nvim_buf_delete(split.buf, { force = true })
  end
end

--- Close the split, preserving the tab if this is its last regular window.
function Split:close()
  if self.closing then
    return
  end

  self.closing = true
  local ok, err = finish(self)
  local released, failure = pcall(Context.call, self.context, "split.close", release, self)
  self.closing = false

  if not released then
    error(failure, 0)
  end
  if not ok then
    error(err, 0)
  end
end

local function observe(split)
  split.group = api.nvim_create_augroup("BaseToolsSplit" .. split.buf, { clear = true })
  api.nvim_create_autocmd("BufWipeout", {
    group = split.group,
    buffer = split.buf,
    callback = function()
      local ok, err = finish(split)
      if not ok then
        error(err, 0)
      end
    end,
  })
  api.nvim_create_autocmd("WinClosed", {
    group = split.group,
    pattern = tostring(split.win),
    once = true,
    callback = function()
      -- The buffer usually wipes synchronously. Clean it up after the event if it outlives the window.
      vim.schedule(function()
        if not split.closed then
          split:close()
        end
      end)
    end,
  })
end

--- Open a native split with a dedicated scratch buffer.
---@param opts base_tools.SplitOptions
---@return base_tools.Split
function M.open(opts)
  local context = opts.context
  Context.check(
    context,
    "split.open",
    type(opts.config) == "table" and opts.config.split ~= nil,
    "expected a native split configuration"
  )

  local split = setmetatable({
    context = context,
    on_close = opts.on_close,
    buf = buffer.scratch(vim.tbl_extend("force", {}, opts.buf_options or {}, {
      bufhidden = "wipe",
      context = context,
    })),
  }, Split)

  local ok, err = pcall(function()
    if opts.on_buffer then
      opts.on_buffer(split.buf)
    end
    Context.call(context, "split.open", function()
      split.win = api.nvim_open_win(split.buf, opts.enter == true, opts.config)
      split.tab = api.nvim_win_get_tabpage(split.win)
      for name, value in pairs(opts.win_options or {}) do
        vim.wo[split.win][name] = value
      end
      observe(split)
    end)
  end)

  if not ok then
    pcall(Split.close, split)
    error(err, 0)
  end

  return split
end

return M
