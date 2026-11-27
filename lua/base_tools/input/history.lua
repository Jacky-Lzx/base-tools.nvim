-- Explicit, bounded session history. Nothing is written to disk.
local M = {}
local groups, order = {}, {}
local api = vim.api

function M.get(key)
  return vim.deepcopy(groups[key] or {})
end

function M.add(key, text)
  if not key or text == "" or #text > 8192 then
    return
  end
  local entries = groups[key] or {}
  for i = #entries, 1, -1 do
    if entries[i] == text then
      table.remove(entries, i)
    end
  end
  table.insert(entries, 1, text)
  entries[51] = nil
  groups[key] = entries
  for i = #order, 1, -1 do
    if order[i] == key then
      table.remove(order, i)
    end
  end
  order[#order + 1] = key
  if #order > 50 then
    groups[table.remove(order, 1)] = nil
  end
end

function M.attach(a, refresh)
  if not a.opts.history then
    return
  end
  local entries = M.get(a.opts.history)
  local index, draft, recalling = 0, nil, false
  api.nvim_buf_attach(a.buf, false, {
    on_lines = function()
      if a.closed then
        return true
      end
      if not recalling then
        index, draft = 0, nil
      end
    end,
  })
  local function recall(direction, key)
    if a.closed or a.closing then
      return
    end
    if vim.fn.pumvisible() == 1 then
      api.nvim_feedkeys(api.nvim_replace_termcodes(key, true, false, true), "ni", false)
      return
    end
    local next_index = math.max(0, math.min(#entries, index + direction))
    if next_index == index then
      return
    end
    if index == 0 then
      draft = table.concat(api.nvim_buf_get_lines(a.buf, 0, -1, false), "\n")
    end
    local mode = api.nvim_get_mode().mode:sub(1, 1)
    if mode == "s" then
      vim.cmd.normal({
        args = { api.nvim_replace_termcodes("<Esc>", true, false, true) },
        bang = true,
      })
    end
    local lines = vim.split(next_index == 0 and draft or entries[next_index], "\n", { plain = true })
    recalling = true
    api.nvim_buf_set_lines(a.buf, 0, -1, false, lines)
    recalling = false
    index = next_index
    api.nvim_win_set_cursor(a.win, { #lines, #lines[#lines] })
    if mode ~= "n" then
      vim.cmd("startinsert!")
    end
    refresh(a)
  end
  for key, direction in pairs({ ["<C-Up>"] = 1, ["<C-Down>"] = -1 }) do
    vim.keymap.set({ "n", "i", "s" }, key, function()
      recall(direction, key)
    end, { buffer = a.buf, silent = true, desc = "Input history" })
  end
  if not a.opts.multiline then
    for key, direction in pairs({ ["<Up>"] = 1, ["<Down>"] = -1 }) do
      vim.keymap.set({ "n", "i", "s" }, key, function()
        recall(direction, key)
      end, { buffer = a.buf, silent = true, desc = "Input history" })
    end
  end
end

return M
