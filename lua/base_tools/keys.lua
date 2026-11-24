require("base_tools")
local M = {}

--- Encode Neovim key notation for APIs that accept internal key sequences.
---@param notation string Textual key notation.
---@param do_lt? boolean Translate `<lt>` to a literal `<`. Defaults to false.
---@return string
function M.encode(notation, do_lt)
  return vim.api.nvim_replace_termcodes(notation, true, do_lt == true, true)
end

return M
