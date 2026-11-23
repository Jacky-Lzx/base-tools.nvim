local M = {}

---@class base_tools.LabelOptions
---@field highlight? string Highlight group for the label.

--- Display a path, keeping its suffix when clipped.
---@param path string
---@param opts? base_tools.LabelOptions
---@return base_tools.FileBorderLabel
function M.path(path, opts)
  return { kind = "path", value = path, highlight = opts and opts.highlight }
end

--- Display the last component of a path.
---@param path string
---@param opts? base_tools.LabelOptions
---@return base_tools.FileBorderLabel
function M.filename(path, opts)
  return { kind = "filename", value = path, highlight = opts and opts.highlight }
end

--- Display the preview's scroll percentage while its contents overflow.
---@param opts? base_tools.LabelOptions
---@return base_tools.ScrollPercentBorderLabel
function M.scroll_percent(opts)
  return { kind = "scroll_percent", highlight = opts and opts.highlight }
end

return M
