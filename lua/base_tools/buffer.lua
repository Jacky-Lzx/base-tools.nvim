require("base_tools")

local Context = require("base_tools.context")

local M = {}
local api = vim.api

local function set_option(options, name, value)
  options[name] = value
end

--- Create an unlisted scratch buffer with `bufhidden=hide` by default.
---@param options? table<string, any> Buffer-local options, an optional name string or function, and an optional context.
---@return integer
function M.scratch(options)
  local values = options or {}
  local context = values.context
  local operation = "buffer.scratch"
  local buf = Context.call(context, operation, api.nvim_create_buf, false, true)

  local ok, err = pcall(function()
    local local_options = vim.bo[buf]
    Context.call(context, operation, set_option, local_options, "bufhidden", values.bufhidden or "hide")
    if values.name ~= nil then
      local name = values.name
      if type(name) == "function" then
        name = name(buf)
      end
      Context.check(context, operation, type(name) == "string", "Scratch buffer name must be a string")
      Context.call(context, operation, api.nvim_buf_set_name, buf, name)
    end

    for name, value in pairs(values) do
      if name ~= "name" and name ~= "context" then
        Context.call(context, operation, set_option, local_options, name, value)
      end
    end
  end)

  if not ok then
    if api.nvim_buf_is_valid(buf) then
      api.nvim_buf_delete(buf, { force = true })
    end
    error(err, 0)
  end

  return buf
end

return M
