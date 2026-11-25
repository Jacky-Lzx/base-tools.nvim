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
---@field private _options? base_tools.ConfigOptions
---@field private _committing? boolean
local Config = {}
Config.__index = Config

---@class base_tools.ConfigOptions : base_tools.ConfigMergeRules
---@field validate? fun(candidate: table) Raise an error if the candidate is invalid.

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
  return M.merge(self._defaults, opts, self._options)
end

---Validate and optionally apply a candidate before publishing it.
---@param candidate table
---@param apply? fun(candidate: table) Apply the validated configuration, raising on failure.
function Config:commit(candidate, apply)
  assert(type(candidate) == "table", "Config candidate must be a table")
  assert(apply == nil or type(apply) == "function", "Config apply must be a function")
  assert(not self._committing, "Cannot write config from a validation or apply callback")

  local snapshot = vim.deepcopy(candidate)
  local validate = self._options and self._options.validate
  if validate or apply then
    self._committing = true
    local ok, err = pcall(function()
      if validate then
        validate(vim.deepcopy(snapshot))
      end
      if apply then
        apply(vim.deepcopy(snapshot))
      end
    end)
    self._committing = false
    if not ok then
      error(err, 0)
    end
  end
  self._current = snapshot
end

---Restore the original defaults.
function Config:reset()
  self:commit(self._defaults)
end

---Replace an existing value in the current configuration.
---@param path (string|integer)[]
---@param value any
---@param apply? fun(candidate: table) Apply the validated configuration, raising on failure.
function Config:change(path, value, apply)
  assert(vim.islist(path) and #path > 0, "Config path must be a nonempty list")
  assert(value ~= nil, "Config value must not be nil")
  local candidate = self:get()
  local parent = candidate
  if #path > 1 then
    parent = vim.tbl_get(parent, unpack(path, 1, #path - 1))
  end
  local key = path[#path]
  assert(type(parent) == "table" and rawget(parent, key) ~= nil, "Config path does not exist: " .. vim.inspect(path))
  parent[key] = value
  self:commit(candidate, apply)
end

---Create an independent configuration initialized with a copy of its defaults.
---@param defaults table
---@param options? base_tools.ConfigOptions
---@return base_tools.Config
function M.new(defaults, options)
  local initial = M.merge(defaults, nil, options)
  local validate = options and options.validate
  assert(validate == nil or type(validate) == "function", "Config validate must be a function")

  local config = setmetatable({
    _defaults = initial,
    _current = initial,
    _options = vim.deepcopy(options),
  }, Config)
  config:reset()
  return config
end

return M
