require("base_tools")

local M = {}

--- Read the global definition of a highlight group, following its links.
--- Missing groups and link cycles return an empty definition.
---@param name string
---@return vim.api.keyset.hl_info
function M.resolve(name)
  local seen = {}
  while name and not seen[name] do
    seen[name] = true
    local definition = vim.api.nvim_get_hl(0, { name = name, link = true, create = false })
    if not definition.link then
      return definition
    end
    name = definition.link
  end
  return {}
end

return M
