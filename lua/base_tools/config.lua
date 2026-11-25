require("base_tools")

local M = {}

---@class base_tools.ConfigMergeRules
---@field replace? (string|integer)[][] Paths whose supplied values replace their defaults.

--- Merge overrides into defaults and return a detached configuration.
---@param defaults table
---@param opts? table
---@param rules? base_tools.ConfigMergeRules
---@return table
function M.merge(defaults, opts, rules)
  assert(type(defaults) == "table", "Config defaults must be a table")
  assert(opts == nil or type(opts) == "table", "Config options must be a table")
  assert(rules == nil or type(rules) == "table", "Config merge rules must be a table")

  local overrides = vim.deepcopy(opts or {})
  local merged = vim.tbl_deep_extend("force", vim.deepcopy(defaults), overrides)

  local replace = rules and rules.replace
  assert(replace == nil or vim.islist(replace), "Config replacement paths must be a list")
  for _, path in ipairs(replace or {}) do
    assert(vim.islist(path) and #path > 0, "Config replacement paths must be nonempty lists")
    local value = vim.tbl_get(overrides, unpack(path))
    if value ~= nil then
      local parent = merged
      for i = 1, #path - 1 do
        parent = parent[path[i]]
      end
      parent[path[#path]] = value
    end
  end

  return merged
end

--- Read a copy of the full configuration or a value at the given path.
---@param config table
---@param ... string|integer
---@return any
function M.get(config, ...)
  if select("#", ...) == 0 then
    return vim.deepcopy(config)
  end

  return vim.deepcopy(vim.tbl_get(config, ...))
end

---@class base_tools.Config
---@field private _defaults table
---@field private _current table
---@field private _rules? base_tools.ConfigMergeRules
local Config = {}
Config.__index = Config

---Read the current configuration or a value at the given path as a copy.
---@param ... string|integer
---@return any
function Config:get(...)
  return M.get(self._current, ...)
end

---Build a candidate from defaults without changing the current configuration.
---@param opts? table
---@return table
function Config:resolve(opts)
  return M.merge(self._defaults, opts, self._rules)
end

---Store a copy of a candidate after the caller validates and applies it.
---@param candidate table
function Config:commit(candidate)
  assert(type(candidate) == "table", "Config candidate must be a table")
  self._current = vim.deepcopy(candidate)
end

---Restore the original defaults.
function Config:reset()
  self:commit(self._defaults)
end

---Replace an existing value in the current configuration.
---@param path (string|integer)[]
---@param value any
function Config:change(path, value)
  assert(vim.islist(path) and #path > 0, "Config path must be a nonempty list")
  assert(value ~= nil, "Config value must not be nil")
  local parent = self._current
  if #path > 1 then
    parent = vim.tbl_get(parent, unpack(path, 1, #path - 1))
  end
  local key = path[#path]
  assert(type(parent) == "table" and rawget(parent, key) ~= nil, "Config path does not exist: " .. vim.inspect(path))
  parent[key] = vim.deepcopy(value)
end

---Create an independent configuration initialized with a copy of its defaults.
---@param defaults table
---@param rules? base_tools.ConfigMergeRules
---@return base_tools.Config
function M.new(defaults, rules)
  local initial = M.merge(defaults, nil, rules)
  return setmetatable({
    _defaults = initial,
    _current = vim.deepcopy(initial),
    _rules = vim.deepcopy(rules),
  }, Config)
end

return M
