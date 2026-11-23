local api = vim.api
local text = require("base_tools.text")
local ns = api.nvim_create_namespace("base-tools-border-labels")
local watched = {}
local M = {}

---@class base_tools.FileBorderLabel
---@field kind "path"|"filename"
---@field value string Path to display.
---@field highlight? string

---@alias base_tools.BorderLabel string|[string, string?][]|base_tools.FileBorderLabel

---@class base_tools.BorderLabelEdge
---@field left? base_tools.BorderLabel|false
---@field center? base_tools.BorderLabel|false
---@field right? base_tools.BorderLabel|false

---@class base_tools.BorderLabels
---@field top? base_tools.BorderLabelEdge|false
---@field bottom? base_tools.BorderLabelEdge|false

local edges = {
  top = { border_index = 2, field = "title", position = "title_pos", highlight = "FloatTitle" },
  bottom = { border_index = 6, field = "footer", position = "footer_pos", highlight = "FloatFooter" },
}
local alignments = { "left", "center", "right" }
local empty = { parts = {}, width = 0 }
local Layout = {}
Layout.__index = Layout

local function normalize(label, highlight)
  if label == false then
    return
  end
  local clip_side
  if type(label) == "string" then
    label = { { label } }
  elseif label.kind then
    local value = label.value
    if label.kind == "filename" then
      value = vim.fs.basename(value)
    else
      clip_side = "start"
    end
    highlight = label.highlight or highlight
    label = { { vim.fn.strtrans(value) } }
  end

  local parts, strings = {}, {}
  for _, part in ipairs(label) do
    if part[1] ~= "" then
      parts[#parts + 1] = { part[1], part[2] or highlight }
      strings[#strings + 1] = part[1]
    end
  end
  if #parts > 0 then
    local value = table.concat(strings)
    return {
      parts = parts,
      text = value,
      width = vim.fn.strdisplaywidth(value),
      highlight = highlight,
      clip_side = clip_side,
    }
  end
end

local function fit(label, cells, side)
  if cells <= 0 then
    return empty
  end
  if label.width <= cells then
    return label
  end

  local clipped, first, last, offset = text.clip(label.text, cells, { side = label.clip_side or side })
  local parts = {}
  if offset > 0 then
    parts[#parts + 1] = { clipped:sub(1, offset), label.highlight }
  end
  local pos = 0
  for _, part in ipairs(label.parts) do
    local ending = pos + #part[1]
    local start = math.max(pos, first)
    local finish = math.min(ending, last)
    if start < finish then
      parts[#parts + 1] = { part[1]:sub(start - pos + 1, finish - pos), part[2] }
    end
    pos = ending
  end
  local retained_end = offset + last - first
  if retained_end < #clipped then
    parts[#parts + 1] = { clipped:sub(retained_end + 1), label.highlight }
  end
  return { parts = parts, width = vim.fn.strdisplaywidth(clipped) }
end

local function compose(labels, width, edge)
  local glyph = type(edge) == "table" and edge[1] or edge
  if not glyph or glyph == "" then
    return ""
  end
  local border_highlight = type(edge) == "table" and edge[2] or "FloatBorder"
  local left, right = labels.left or empty, labels.right or empty
  if left.width + right.width > width then
    local left_budget = math.max(width - right.width, math.ceil(width / 2))
    left = fit(left, left_budget, "end")
    right = fit(right, width - left.width, "start")
  end

  local center_budget = math.min(width - 2 * left.width, width - 2 * right.width + 1)
  local center = labels.center or empty
  if center.width > center_budget then
    center = center_budget > 1 and fit(center, center_budget, "end") or empty
  end
  local center_start = center.width > 0 and math.floor((width - center.width) / 2) or left.width
  local parts = {}
  local function fill(cells)
    if cells > 0 then
      parts[#parts + 1] = { glyph:rep(cells), border_highlight }
    end
  end

  vim.list_extend(parts, left.parts)
  fill(center_start - left.width)
  vim.list_extend(parts, center.parts)
  fill(width - right.width - center_start - center.width)
  vim.list_extend(parts, right.parts)
  return parts
end

function Layout:refresh(native_update, restore)
  local window = api.nvim_win_get_config(self.win)
  local width = api.nvim_win_get_width(self.win)
  local update = restore or {}
  for name, layout in pairs(self.edges) do
    local edge = edges[name]
    if native_update and (native_update[edge.field] ~= nil or native_update[edge.position] ~= nil) then
      layout.native, layout.native_position = window[edge.field], window[edge.position]
    end

    local border = type(window.border) == "table" and window.border[edge.border_index] or nil
    local label = compose(layout.slots, width, border)
    if not vim.deep_equal(window[edge.field] or "", label) or (label ~= "" and window[edge.position] ~= "left") then
      update[edge.field] = label
      update[edge.position] = "left"
    end
  end
  self.width = width
  if next(update) then
    api.nvim_win_set_config(self.win, update)
  end
end

function Layout:close()
  if watched[self.win] ~= self then
    return
  end
  if self.close_event then
    api.nvim_del_autocmd(self.close_event)
    self.close_event = nil
  end
  watched[self.win] = nil
  if not next(watched) then
    api.nvim_set_decoration_provider(ns, {})
  end
end

local function watch(layout)
  if watched[layout.win] then
    return
  end
  if not next(watched) then
    api.nvim_set_decoration_provider(ns, {
      on_win = function(_, win)
        local target = watched[win]
        if target and not target.pending and target.width ~= api.nvim_win_get_width(win) then
          target.pending = true
          vim.schedule(function()
            target.pending = false
            if watched[win] == target and api.nvim_win_is_valid(win) then
              target:refresh()
            end
          end)
        end
        return false
      end,
    })
  end
  watched[layout.win] = layout
  layout.close_event = api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(layout.win),
    once = true,
    callback = function()
      layout.close_event = nil
      layout:close()
    end,
  })
end

function Layout:set(labels)
  local current = api.nvim_win_get_config(self.win)
  local layouts = vim.tbl_extend("force", {}, self.edges)
  local update = {}
  for name, edge in pairs(edges) do
    local changes = labels[name]
    if changes ~= nil then
      local previous = layouts[name]
      local slots = {}
      if changes ~= false then
        slots = vim.tbl_extend("force", {}, previous and previous.slots or {})
        for _, alignment in ipairs(alignments) do
          if changes[alignment] ~= nil then
            slots[alignment] = normalize(changes[alignment], edge.highlight)
          end
        end
      end
      if next(slots) then
        previous = previous or { native = current[edge.field], native_position = current[edge.position] }
        layouts[name] = { slots = slots, native = previous.native, native_position = previous.native_position }
      elseif previous then
        update[edge.field] = previous.native or ""
        update[edge.position] = previous.native_position or "left"
        layouts[name] = nil
      end
    end
  end
  self.edges = layouts
  self:refresh(nil, update)
  if next(layouts) then
    watch(self)
    return true
  end
  self:close()
  return false
end

function M.new(win)
  return setmetatable({ win = win, edges = {} }, Layout)
end

return M
