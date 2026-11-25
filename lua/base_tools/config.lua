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
---@field fields? base_tools.ConfigField[] Option rules, in validation order.

---@alias base_tools.ConfigFieldValidator fun(value: any, get: fun(...: string|integer): any): boolean, string?

---@class base_tools.ConfigField
---@field path (string|integer)[]
---@field validate base_tools.ConfigFieldValidator Return true or false with a message describing the required value.

local function check_path(path)
  assert(vim.islist(path) and #path > 0, "Config path must be a nonempty list")
  for _, key in ipairs(path) do
    assert(
      type(key) == "string" or (type(key) == "number" and key % 1 == 0),
      "Config path keys must be strings or integers"
    )
  end
end

local function intersects(left, right)
  for i = 1, math.min(#left, #right) do
    if left[i] ~= right[i] then
      return false
    end
  end
  return true
end

local function validate_and_apply(self, snapshot, path, apply)
  assert(not self._committing, "Cannot write config from a validation or apply callback")
  local options = self._options or {}
  if not options.fields and not options.validate and not apply then
    return
  end

  self._committing = true
  local ok, err = pcall(function()
    local function get(...)
      return M.get(snapshot, ...)
    end

    for _, field in ipairs(options.fields or {}) do
      if not path or intersects(path, field.path) then
        local valid, message = field.validate(get(unpack(field.path)), get)
        if valid ~= true then
          error(table.concat(field.path, ".") .. " " .. (message or "is invalid"), 0)
        end
      end
    end

    if options.validate then
      options.validate(get())
    end

    if apply then
      apply(get())
    end
  end)

  self._committing = false
  if not ok then
    error(err, 0)
  end
end

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

---Validate a full candidate without applying or publishing it.
---@param candidate table
function Config:check(candidate)
  assert(type(candidate) == "table", "Config candidate must be a table")
  validate_and_apply(self, vim.deepcopy(candidate))
end

---Validate and optionally apply a candidate before publishing it.
---@param candidate table
---@param apply? fun(candidate: table) Apply the validated configuration, raising on failure.
function Config:commit(candidate, apply)
  assert(type(candidate) == "table", "Config candidate must be a table")
  assert(apply == nil or type(apply) == "function", "Config apply must be a function")
  local snapshot = vim.deepcopy(candidate)
  validate_and_apply(self, snapshot, nil, apply)
  self._current = snapshot
end

---Restore the original defaults.
function Config:reset()
  self:commit(self._defaults)
end

local function with_change(self, path, value)
  check_path(path)
  assert(value ~= nil, "Config value must not be nil")

  local candidate = self:get()
  local parent = candidate
  if #path > 1 then
    parent = vim.tbl_get(parent, unpack(path, 1, #path - 1))
  end

  local key = path[#path]
  assert(type(parent) == "table" and rawget(parent, key) ~= nil, "Config path does not exist: " .. vim.inspect(path))

  parent[key] = vim.deepcopy(value)
  return candidate
end

---Check a proposed replacement using the same rules as change(), without applying it.
---@param path (string|integer)[]
---@param value any
function Config:validate(path, value)
  validate_and_apply(self, with_change(self, path, value), vim.deepcopy(path))
end

---Replace an existing value and validate the affected paths before publishing.
---@param path (string|integer)[]
---@param value any
---@param apply? fun(candidate: table) Apply the validated configuration, raising on failure.
function Config:change(path, value, apply)
  assert(apply == nil or type(apply) == "function", "Config apply must be a function")
  local candidate = with_change(self, path, value)
  validate_and_apply(self, candidate, vim.deepcopy(path), apply)
  self._current = candidate
end

---Create an independent configuration initialized with a copy of its defaults.
---@param defaults table
---@param options? base_tools.ConfigOptions
---@return base_tools.Config
function M.new(defaults, options)
  local initial = M.merge(defaults, nil, options)
  local validate = options and options.validate
  assert(validate == nil or type(validate) == "function", "Config validate must be a function")
  local fields = options and options.fields
  assert(fields == nil or vim.islist(fields), "Config fields must be a list")
  for _, field in ipairs(fields or {}) do
    assert(type(field) == "table" and type(field.validate) == "function", "Config fields must define a validator")
    check_path(field.path)
  end

  local config = setmetatable({
    _defaults = initial,
    _current = initial,
    _options = vim.deepcopy(options),
  }, Config)
  config:reset()
  return config
end

return M
