-- Resolve composed defaults before opening or replacing an input window.
local M = {}

local function point(lines, byte)
  for row, line in ipairs(lines) do
    if byte <= #line then
      return { row, byte }
    end
    byte = byte - #line - 1
  end
end

function M.resolve(default)
  assert(
    default == nil or type(default) == "string" or type(default) == "table",
    "default must be a string or a list of fragments"
  )
  local parts, length, selected, cursor = {}, 0
  if type(default) == "table" then
    assert(vim.islist(default), "default fragments must be a list")
    for _, part in ipairs(default) do
      local text = part
      if type(part) == "table" then
        assert(part.selected == nil or type(part.selected) == "boolean", "fragment selected must be a boolean")
        if part.text == nil and part.cursor == true and not part.selected then
          assert(cursor == nil, "default allows at most one cursor marker")
          cursor, text = length, ""
        else
          assert(type(part.text) == "string", "fragment text must be a string")
          assert(
            part.cursor == nil or part.selected == true and (part.cursor == "start" or part.cursor == "end"),
            "fragment cursor must be start or end on a selected fragment"
          )
          text = part.text
          if part.selected then
            assert(selected == nil, "default allows at most one selected fragment")
            selected = { first = length, last = length + #text, cursor = part.cursor or "start" }
          end
        end
      end
      assert(type(text) == "string", "default fragments must be strings or fragment tables")
      parts[#parts + 1], length = text, length + #text
    end
  else
    parts[1], length = default or "", #(default or "")
  end
  assert(not (selected and cursor ~= nil), "a selected fragment cannot be combined with a cursor marker")
  local text = table.concat(parts)
  local lines = vim.split(text, "\n", { plain = true })
  local result = { lines = lines, cursor = point(lines, cursor or length) }
  if selected then
    if selected.first == selected.last then
      result.cursor = point(lines, selected.first)
    else
      result.selection = selected
    end
  end
  return result
end

function M.start(initial, win)
  local api = vim.api
  local selected = initial.selection
  if selected then
    vim.cmd.stopinsert()
    local text = table.concat(initial.lines, "\n")
    if vim.o.selection == "old" and text:sub(selected.last, selected.last) == "\n" then
      -- The historical "old" setting cannot include an end-of-line character.
      -- Normalize only while this initial selection is active, then restore it.
      initial.selection_option = "old"
      vim.o.selection = "inclusive"
    end
    -- The exclusive endpoint may be one cell beyond EOL. Keep this setting
    -- local to the scratch window, including for newline-only fragments.
    vim.wo[win].virtualedit = "onemore"
    local last = selected.last
    if vim.o.selection ~= "exclusive" then
      repeat
        last = last - 1
        local byte = text:byte(last + 1)
      until byte < 128 or byte >= 192
    end
    local first, final = point(initial.lines, selected.first), point(initial.lines, last)
    if selected.cursor == "start" then
      first, final = final, first
    end
    api.nvim_win_set_cursor(win, first)
    vim.cmd.normal({ args = { "v" }, bang = true })
    api.nvim_win_set_cursor(win, final)
    vim.cmd.normal({ args = { string.char(7) }, bang = true }) -- Visual -> Select.
    return false
  end
  -- Unlike startinsert!, startinsert inserts at an interior marker. At EOL
  -- the bang is needed because Normal mode otherwise clamps the cursor.
  local cursor = initial.cursor
  api.nvim_win_set_cursor(win, cursor)
  local entering = api.nvim_get_mode().mode:sub(1, 1) ~= "i"
  vim.cmd(cursor[2] == #initial.lines[cursor[1]] and "startinsert!" or "startinsert")
  return entering
end

function M.restore(initial)
  if initial.selection_option then
    if vim.o.selection == "inclusive" then
      vim.o.selection = initial.selection_option
    end
    initial.selection_option = nil
  end
end

return M
