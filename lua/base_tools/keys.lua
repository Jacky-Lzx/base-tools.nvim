require("base_tools")
local Context = require("base_tools.context")
local M = {}

--- Encode Neovim key notation for APIs that accept internal key sequences.
---@param notation string Textual key notation.
---@param do_lt? boolean Translate `<lt>` to a literal `<`. Defaults to false.
---@param opts? { context?: base_tools.Context }
---@return string
function M.encode(notation, do_lt, opts)
  return Context.call(
    opts and opts.context,
    "keys.encode",
    vim.api.nvim_replace_termcodes,
    notation,
    true,
    do_lt == true,
    true
  )
end

return M
