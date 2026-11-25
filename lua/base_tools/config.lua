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

return M
