require("base_tools")
local Context = require("base_tools.context")
local M = {}

--- Clip single-line display text to a cell budget.
---
--- These examples assume the ellipsis occupies one display cell.
---
--- ```lua
--- local clip = require("base_tools.text").clip
--- clip("abcdef", 4)                     -- "abc…", 0, 3, 0
--- clip("abcdef", 4, { side = "start" }) -- "…def", 3, 6, 3
---
--- ```
--- In the second result, `def` is `[3, 6)` in the source and starts at byte
--- offset 3 in the output because `…` occupies three UTF-8 bytes.
---
---@param text string
---@param cells integer
---@param opts? { side?: "start"|"end", ellipsis?: string|false, context?: base_tools.Context }
---@return string clipped
---@return integer first First retained source byte, zero-based.
---@return integer last End of the retained source range, exclusive.
---@return integer offset First retained byte in the clipped output, zero-based.
function M.clip(text, cells, opts)
  local context = opts and opts.context
  if context then
    Context.check(context, "text.clip", type(text) == "string", "Expected text to be a string")
    Context.check(context, "text.clip", type(cells) == "number", "Expected a numeric cell budget")
  end
  if cells <= 0 then
    return "", 0, 0, 0
  end

  local width = vim.fn.strdisplaywidth
  if width(text) <= cells then
    return text, 0, #text, 0
  end

  opts = opts or {}
  local marker = opts.ellipsis == false and "" or opts.ellipsis or "…"
  if context then
    Context.check(context, "text.clip", type(marker) == "string", "Expected an ellipsis string or false")
  end
  if width(marker) > cells then
    marker = width(".") <= cells and "." or ""
  end

  local chars = vim.fn.split(text, [[\zs]])
  local from_start = opts.side == "start"
  local first, last = 0, 0

  if from_start then
    first, last = #text, #text
    for index = #chars, 1, -1 do
      local next_first = first - #chars[index]
      if width(marker .. text:sub(next_first + 1)) > cells then
        break
      end

      first = next_first
    end

    return marker .. text:sub(first + 1), first, last, #marker
  end

  for _, char in ipairs(chars) do
    local next_last = last + #char
    if width(text:sub(1, next_last) .. marker) > cells then
      break
    end

    last = next_last
  end

  return text:sub(1, last) .. marker, first, last, 0
end

return M
