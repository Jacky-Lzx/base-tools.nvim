local M = {}

---Require the given Lua type.
---@param expected string
---@return base_tools.ConfigFieldValidator
function M.type(expected)
  assert(type(expected) == "string", "Expected a Lua type name")
  local message = "must be " .. expected
  return function(value)
    return type(value) == expected, message
  end
end

local function finite(value)
  return type(value) == "number" and value > -math.huge and value < math.huge
end

---Require a finite number within the inclusive bounds. Either bound may be nil.
---@param min? number
---@param max? number
---@return base_tools.ConfigFieldValidator
function M.range(min, max)
  assert(min == nil or finite(min), "Minimum must be a finite number")
  assert(max == nil or finite(max), "Maximum must be a finite number")
  assert(min == nil or max == nil or min <= max, "Minimum must be less than or equal to maximum")
  local message = "must be a finite number"
  if min ~= nil and max ~= nil then
    message = message .. " between " .. min .. " and " .. max
  elseif min ~= nil then
    message = message .. " greater than or equal to " .. min
  elseif max ~= nil then
    message = message .. " less than or equal to " .. max
  end
  return function(value)
    return finite(value) and (min == nil or value >= min) and (max == nil or value <= max), message
  end
end

---Require an integer within the inclusive bounds. Either bound may be nil.
---@param min? number
---@param max? number
---@return base_tools.ConfigFieldValidator
function M.integer(min, max)
  local range = M.range(min, max)
  return function(value)
    if not finite(value) or value % 1 ~= 0 then
      return false, "must be an integer"
    end
    return range(value)
  end
end

---Require one of the supplied scalar values.
---@param values (string|number|boolean)[]
---@return base_tools.ConfigFieldValidator
function M.one_of(values)
  assert(vim.islist(values) and #values > 0, "Expected a nonempty list of allowed values")
  local allowed = vim.deepcopy(values)
  local message = "must be one of " .. vim.inspect(allowed)
  return function(value)
    return vim.tbl_contains(allowed, value), message
  end
end

---Also accept nil before checking the supplied rule.
---@param validate base_tools.ConfigFieldValidator
---@return base_tools.ConfigFieldValidator
function M.optional(validate)
  assert(type(validate) == "function", "Expected a validator function")
  return function(value, get)
    if value == nil then
      return true
    end
    return validate(value, get)
  end
end

return M
