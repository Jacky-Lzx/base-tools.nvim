local api = vim.api
local M = {}

local function parsed_fences(buf)
  local parser = vim.treesitter.get_parser(buf, "markdown")
  if not parser then
    return
  end
  local query = vim.treesitter.query.parse("markdown", "(fenced_code_block) @block")
  local delimiters, fenced = {}, {}
  for _, tree in ipairs(parser:parse()) do
    for _, node in query:iter_captures(tree:root(), buf) do
      local first, _, last, col = node:range()
      for row = first + 1, last + (col == 0 and 0 or 1) do
        fenced[row] = true
      end
      for child in node:iter_children() do
        if child:type() == "fenced_code_block_delimiter" then
          delimiters[child:start() + 1] = true
        end
      end
    end
  end
  return delimiters, fenced
end

local function scan_fences(buf)
  local delimiters, fenced = {}, {}
  local opened
  for row, line in ipairs(api.nvim_buf_get_lines(buf, 0, -1, false)) do
    local marker, rest = line:match("^ ? ? ?([`~]+)(.*)$")
    if marker and #marker >= 3 and (marker:match("^`+$") or marker:match("^~+$")) then
      local char = marker:sub(1, 1)
      if not opened then
        if char == "~" or not rest:find("`", 1, true) then
          opened = marker
          delimiters[row] = true
        end
      elseif char == opened:sub(1, 1) and #marker >= #opened and rest:match("^%s*$") then
        opened = nil
        delimiters[row] = true
      end
    end
    if opened or delimiters[row] then
      fenced[row] = true
    end
  end
  return delimiters, fenced
end

--- Hide Markdown fence delimiters, keeping the original buffer text for injections and copying.
---@param buf integer
---@param ns integer Namespace for the fence extmarks. The caller owns its lifecycle.
---@return table<integer, boolean> delimiters 1-based hidden row numbers.
---@return table<integer, boolean> fenced 1-based rows inside blocks, including the delimiters.
function M.conceal_fences(buf, ns)
  local ok, delimiters, fenced = pcall(parsed_fences, buf)
  if not ok or not delimiters then
    delimiters, fenced = scan_fences(buf)
  end
  for row in pairs(delimiters) do
    api.nvim_buf_set_extmark(buf, ns, row - 1, 0, { conceal_lines = "" })
  end
  return delimiters, fenced
end

return M
