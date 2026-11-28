local Context = require("base_tools.context")
local keys = require("base_tools.keys")
local api = vim.api
local M = {}

---@class base_tools.KeyBinding
---@field lhs string
---@field actions (string|function)[]
---@field desc? string Custom or inherited description.
---@field desc_inherited? boolean The description came from a single named action.

---@class base_tools.KeymapResolveOptions
---@field name? string
---@field actions? table<string, any> Named actions. A table entry may provide a desc.
---@field defaults? table<string, string|function|table|false> Baseline bindings to overlay by key.
---@field check_aliases? boolean
---@field context? base_tools.Context

local function action_description(actions, registry)
  if #actions == 1 and type(actions[1]) == "string" then
    local action = registry and registry[actions[1]]
    if type(action) == "table" then
      return action.desc
    end
  end
end

---Normalize a table of key bindings without installing any mappings.
---@param keymap? table<string, string|function|table|false> May be omitted when defaults are supplied.
---@param opts? base_tools.KeymapResolveOptions
---@return base_tools.KeyBinding[]
function M.resolve(keymap, opts)
  opts = opts or {}
  local check = Context.checker(opts.context, "keymap.resolve")
  local name = opts.name or "keymap"
  if opts.defaults ~= nil then
    check(type(opts.defaults) == "table", name .. " defaults must be a table")
    check(keymap == nil or type(keymap) == "table", name .. " must be a table")
    keymap = vim.tbl_extend("force", {}, opts.defaults, keymap or {})
  end
  check(type(keymap) == "table", name .. " must be a table")

  local bindings, used = {}, {}
  for lhs, value in pairs(keymap) do
    check(type(lhs) == "string" and lhs ~= "", name .. " keys must be nonempty strings")

    if value ~= false then
      if opts.check_aliases then
        local encoded = keys.encode(lhs, true)
        check(not used[encoded], name .. ": duplicate mapping " .. lhs)
        used[encoded] = true
      end

      local chain = type(value) == "table" and value or { value }
      local prefix = name .. "[" .. lhs .. "]"
      local actions = {}
      for index, action in pairs(chain) do
        if index ~= "desc" then
          check(
            type(action) == "function" or type(action) == "string" and (not opts.actions or opts.actions[action]),
            prefix .. ": invalid action " .. tostring(action)
          )
          actions[index] = action
        end
      end

      check(vim.islist(actions), prefix .. " must contain a contiguous action list")
      local desc, inherited = chain.desc, nil
      if desc == nil then
        desc = action_description(actions, opts.actions)
        inherited = desc ~= nil and true or nil
      end
      check(desc == nil or type(desc) == "string", prefix .. ".desc must be a string")
      bindings[#bindings + 1] = { lhs = lhs, actions = actions, desc = desc, desc_inherited = inherited }
    end
  end

  table.sort(bindings, function(a, b)
    return a.lhs < b.lhs
  end)

  return bindings
end

local managed = setmetatable({}, { __mode = "k" })
local single_modes = { n = true, i = true, c = true, x = true, s = true, o = true, t = true, l = true }

local function mappings(mode, buf)
  return buf and api.nvim_buf_get_keymap(buf, mode) or api.nvim_get_keymap(mode)
end

local function find(entries, field, value)
  for _, entry in ipairs(entries) do
    if entry[field] == value then
      return entry
    end
  end
end

---Install one Lua mapping and return its cleanup function and prior definition.
---Cleanup restores the previous mapping only while this registration owns the key.
---@param mode string A single Neovim mode such as n, i, s or c.
---@param lhs string
---@param action function
---@param opts? table Options for vim.keymap.set() and an optional base_tools.Context in context.
---@return fun() cleanup
---@return table? previous Prior mapping in the same scope, if any.
---@return table installed Native definition of the new mapping.
function M.install(mode, lhs, action, opts)
  local context = opts and opts.context
  local check = Context.checker(context, "keymap.install")
  check(single_modes[mode], "base-tools.keymap.install requires a single mode")
  check(type(action) == "function", "base-tools.keymap.install requires a Lua callback")

  opts = vim.tbl_extend("force", {}, opts or {})
  opts.context = nil
  opts.desc = Context.keymap_desc(context, opts.desc)
  local buf = opts.buffer
  if buf == true or buf == 0 then
    buf = api.nvim_get_current_buf()
    opts.buffer = buf
  end

  local before = Context.call(context, "keymap.install", mappings, mode, buf)
  local function callback(...)
    return action(...)
  end

  Context.call(context, "keymap.install", vim.keymap.set, mode, lhs, callback, opts)

  -- Use the actual stored LHS. Key notation can expand a leader or simplify
  -- distinct mappings such as <C-I> and <Tab> to the same typed sequence.
  local installed = check(find(mappings(mode, buf), "callback", callback), "Cannot find the installed mapping")
  local previous = find(before, "lhsraw", installed.lhsraw)
  local record = { previous = previous, prior = previous and managed[previous.callback] }
  managed[callback] = record

  local function cleanup()
    if record.closed then
      return
    end

    record.closed = true
    if buf and not api.nvim_buf_is_valid(buf) then
      return
    end

    local current = find(mappings(mode, buf), "lhsraw", installed.lhsraw)
    if not current or current.callback ~= callback then
      return
    end

    vim.keymap.del(mode, current.lhs, { buffer = buf })

    local restore, prior = record.previous, record.prior
    while prior and prior.closed do
      restore, prior = prior.previous, prior.prior
    end

    if restore then
      if buf then
        api.nvim_buf_call(buf, function()
          vim.fn.mapset(mode, false, restore)
        end)
      else
        vim.fn.mapset(mode, false, restore)
      end
    end
  end

  return cleanup, previous, installed
end

return M
