local M = {}

---@class base_tools.Context
---@field private _owner string
local Context = {}

--- Create an error context shared by the modules a plugin uses.
---@param owner string Plugin name shown in diagnostics.
---@return base_tools.Context
function M.new(owner)
  assert(type(owner) == "string" and owner:find("%S") and not owner:find("%c"), "Expected a plugin name")
  return setmetatable({ _owner = owner }, Context)
end

---@private
function M.format(context, operation, message)
  if context == nil then
    return message
  end
  assert(getmetatable(context) == Context, "Expected a base-tools context")
  return ("%s [%s]: %s"):format(context._owner, operation, tostring(message))
end

---@private
function M.check(context, operation, condition, message)
  if not condition then
    error(M.format(context, operation, message), context and 0 or 2)
  end
  return condition
end

local function check_without_context(condition, message, level)
  if not condition then
    error(message, level or 2)
  end
  return condition
end

-- Bind an operation once when validation crosses several private functions.
---@private
function M.checker(context, operation)
  if context == nil then
    return check_without_context
  end
  return function(condition, message)
    return M.check(context, operation, condition, message)
  end
end

local function native_result(context, operation, ok, ...)
  if not ok then
    error(M.format(context, operation, (...)), 0)
  end
  return ...
end

-- Wrap a native operation whose failure is managed by base-tools.
---@private
function M.call(context, operation, fn, ...)
  if context == nil then
    return fn(...)
  end
  return native_result(context, operation, pcall(fn, ...))
end

return M
