require("base_tools")

local M = {}
local api = vim.api

--- Create an unlisted scratch buffer with `bufhidden=hide` by default.
---@param options? table<string, any> Buffer-local options.
---@return integer
function M.scratch(options)
  local buf = api.nvim_create_buf(false, true)

  local ok, err = pcall(function()
    local values = options or {}
    local local_options = vim.bo[buf]
    local_options.bufhidden = values.bufhidden or "hide"
    for name, value in pairs(values) do
      local_options[name] = value
    end
  end)

  if not ok then
    api.nvim_buf_delete(buf, { force = true })
    error(err, 0)
  end

  return buf
end

return M
