local keys = require("base_tools.keys")
local api = vim.api
local M = {}

---@class base_tools.KeyBinding
---@field lhs string
---@field actions (string|function)[]
---@field desc? string

---Normalize a table of key bindings without installing any mappings.
---@param keymap table<string, string|function|table|false>
---@param opts? { name?: string, actions?: table<string, any>, check_aliases?: boolean }
---@return base_tools.KeyBinding[]
function M.resolve(keymap, opts)
  opts = opts or {}
  local name = opts.name or "keymap"
  assert(type(keymap) == "table", name .. " must be a table")

  local bindings, used = {}, {}
  for lhs, value in pairs(keymap) do
    assert(type(lhs) == "string" and lhs ~= "", name .. " keys must be nonempty strings")

    if value ~= false then
      if opts.check_aliases then
        local encoded = keys.encode(lhs, true)
        assert(not used[encoded], name .. ": duplicate mapping " .. lhs)
        used[encoded] = true
      end

      local chain = type(value) == "table" and value or { value }
      local prefix = name .. "[" .. lhs .. "]"
      local actions = {}
      for index, action in pairs(chain) do
        if index ~= "desc" then
          assert(
            type(action) == "function" or type(action) == "string" and (not opts.actions or opts.actions[action]),
            prefix .. ": invalid action " .. tostring(action)
          )
          actions[index] = action
        end
      end

      assert(vim.islist(actions), prefix .. " must contain a contiguous action list")
      assert(chain.desc == nil or type(chain.desc) == "string", prefix .. ".desc must be a string")
      bindings[#bindings + 1] = { lhs = lhs, actions = actions, desc = chain.desc }
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
---@param opts? table Options for vim.keymap.set().
---@return fun() cleanup
---@return table? previous Prior mapping in the same scope, if any.
function M.install(mode, lhs, action, opts)
  assert(single_modes[mode], "base-tools.keymap.install requires a single mode")
  assert(type(action) == "function", "base-tools.keymap.install requires a Lua callback")

  opts = vim.tbl_extend("force", {}, opts or {})
  local buf = opts.buffer
  if buf == true or buf == 0 then
    buf = api.nvim_get_current_buf()
    opts.buffer = buf
  end

  local before = mappings(mode, buf)
  local function callback(...)
    return action(...)
  end

  vim.keymap.set(mode, lhs, callback, opts)

  -- Use the actual stored LHS. Key notation can expand a leader or simplify
  -- distinct mappings such as <C-I> and <Tab> to the same typed sequence.
  local installed = assert(find(mappings(mode, buf), "callback", callback))
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

  return cleanup, previous
end

return M
