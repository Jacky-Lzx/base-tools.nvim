local api = vim.api
local M = {}

local function visit_nodes(buf, node_type, visit)
  local parser = vim.treesitter.get_parser(buf, "markdown")
  if not parser then
    return false
  end

  local query = vim.treesitter.query.parse("markdown", "(" .. node_type .. ") @node")
  for _, tree in ipairs(parser:parse()) do
    for _, node in query:iter_captures(tree:root(), buf) do
      visit(node)
    end
  end

  return true
end

local function parsed_fences(buf)
  local delimiters, fenced = {}, {}
  local parsed = visit_nodes(buf, "fenced_code_block", function(node)
    local first, _, last, col = node:range()
    for row = first + 1, last + (col == 0 and 0 or 1) do
      fenced[row] = true
    end

    for child in node:iter_children() do
      if child:type() == "fenced_code_block_delimiter" then
        delimiters[child:start() + 1] = true
      end
    end
  end)

  if parsed then
    return delimiters, fenced
  end
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

---@class base_tools.MarkdownOptions
---@field rule_highlight? string Highlight for thematic breaks. Defaults to FloatBorder.

local fence_ns = api.nvim_create_namespace("base-tools-markdown-fences")
local rule_ns = api.nvim_create_namespace("base-tools-markdown-rules")
local Renderer = {}
Renderer.__index = Renderer

function Renderer:refresh()
  local buf, win = self.buf, self.win
  local tick = api.nvim_buf_get_changedtick(buf)
  local changed = tick ~= self.tick
  if changed then
    api.nvim_buf_clear_namespace(buf, fence_ns, 0, -1)
    self.hidden, self.fenced = M.conceal_fences(buf, fence_ns)
    self.rules = {}
    pcall(visit_nodes, buf, "thematic_break", function(node)
      local row, col = node:start()
      self.rules[#self.rules + 1] = { row, col }
    end)
    self.tick = tick
  end

  local width = api.nvim_win_get_width(win)
  if changed or width ~= self.width then
    api.nvim_buf_clear_namespace(buf, rule_ns, 0, -1)
    for _, rule in ipairs(self.rules) do
      local row, col = rule[1], rule[2]
      local cells = width - vim.fn.virtcol({ row + 1, col + 1 }, false, win) + 1
      if cells > 0 then
        api.nvim_buf_set_extmark(buf, rule_ns, row, col, {
          virt_text = { { string.rep("─", cells), self.rule_highlight } },
          virt_text_pos = "overlay",
        })
      end
    end
    self.width = width
  end
end

function Renderer:set_options(opts)
  local group = opts and opts.rule_highlight or "FloatBorder"
  if self.rule_highlight ~= group then
    self.rule_highlight = group
    self.width = nil
  end
end

function Renderer:close()
  if api.nvim_buf_is_valid(self.buf) then
    api.nvim_buf_clear_namespace(self.buf, fence_ns, 0, -1)
    api.nvim_buf_clear_namespace(self.buf, rule_ns, 0, -1)
  end

  if api.nvim_win_is_valid(self.win) then
    local options = vim.wo[self.win]
    if options.conceallevel == 2 then
      options.conceallevel = self.conceallevel
    end

    if options.concealcursor == "nvic" then
      options.concealcursor = self.concealcursor
    end
  end
end

---@private
function M.renderer(win)
  local options = vim.wo[win]
  local view = setmetatable({
    win = win,
    buf = api.nvim_win_get_buf(win),
    conceallevel = options.conceallevel,
    concealcursor = options.concealcursor,
  }, Renderer)
  options.conceallevel = 2
  options.concealcursor = "nvic"

  return view
end

return M
