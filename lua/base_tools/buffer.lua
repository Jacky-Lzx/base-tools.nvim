require("base_tools")

local M = {}
local api = vim.api

--- Create an unlisted scratch buffer with `bufhidden=hide` by default.
---@param options? table<string, any> Buffer-local options and an optional name string or function of the buffer ID.
---@return integer
function M.scratch(options)
  local buf = api.nvim_create_buf(false, true)

  local ok, err = pcall(function()
    local values = options or {}
    local local_options = vim.bo[buf]
    local_options.bufhidden = values.bufhidden or "hide"
    if values.name ~= nil then
      local name = values.name
      if type(name) == "function" then
        name = name(buf)
      end
      assert(type(name) == "string", "Scratch buffer name must be a string")
      api.nvim_buf_set_name(buf, name)
    end

    for name, value in pairs(values) do
      if name ~= "name" then
        local_options[name] = value
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
