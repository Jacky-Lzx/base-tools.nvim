require("base_tools")
local api = vim.api
local float = require("base_tools.float")
local layout = require("base_tools.input.layout")
local Context = require("base_tools.context")
local default_context = Context.new("base-tools")
local default_controller
local M = {}

---@class base_tools.InputStyle
---@field border? string
---@field width? number Cells or a fraction of editor width.
---@field min_width? integer
---@field max_width? integer
---@field max_height? integer
---@field row? integer|"center"|false Editor row, centered, or above the bottom margin.
---@field col? integer Offset from the centered column.
---@field bottom? integer
---@field title? string|false
---@field title_pos? "left"|"center"|"right"
---@field winblend? integer
---@field zindex? integer
---@field winhighlight? string
---@field prompt_group? string
---@field error_group? string
---@field hint_group? string

---@class base_tools.InputFragment
---@field text? string Editable text. Omit to mark a cursor boundary with cursor=true.
---@field selected? boolean Select this fragment initially.
---@field cursor? "start"|"end"|true

---@class base_tools.InputChange
---@field is_current fun(): boolean
---@field set_error fun(message?: string): boolean
---@field set_status fun(message?: string): boolean
---@field set_pending fun(pending: boolean): boolean

---@class base_tools.InputOptions
---@field context? base_tools.Context
---@field style? base_tools.InputStyle
---@field border_labels? base_tools.BorderLabels
---@field title? string|false
---@field title_pos? "left"|"center"|"right"
---@field width? number
---@field prompt? string
---@field position? "editor"|"cursor"
---@field default? string|(string|base_tools.InputFragment)[]
---@field validate? fun(value: string): boolean|string
---@field completion? string Neovim completion type.
---@field completion_cwd? string Base directory for file or directory completion.
---@field highlight? string|fun(value: string): [integer, integer, string][]
---@field multiline? boolean
---@field hints? boolean
---@field history? string
---@field change_delay? integer
---@field on_change? fun(value: string, change: base_tools.InputChange): function?

---@class base_tools.InputHandle
---@field cancel fun() Cancel the input. Also callable with colon syntax.
---@field get_layout fun(): table? Get a snapshot of the current layout.

---@class base_tools.InputAdapter
---@field filetype? string
---@field escape_to_normal? boolean Leave Insert/Select on Esc before cancelling in Normal mode.
---@field setup_highlights? fun(reset?: boolean)
---@field setup_buffer? fun(buf: integer, opts: base_tools.InputOptions)
---@field accept_completion? fun(buf: integer): boolean
---@field on_layout? fun(layout: table?)

---@class base_tools.InputController
---@field open fun(opts: base_tools.InputOptions?, on_done: fun(value: string?)): base_tools.InputHandle
---@field cancel fun()
---@field get_window fun(): integer?
---@field get_layout fun(): table?
---@field refresh fun()

---@class base_tools.InputFloatOptions
---@field height? integer
---@field title? string|false
---@field title_pos? "left"|"center"|"right"
---@field footer? string|[string, string?][] Bottom border label.
---@field footer_pos? "left"|"center"|"right"
---@field border_labels? base_tools.BorderLabels
---@field anchor? table
---@field focusable? boolean

--- Create an independent input controller with at most one active input.
--- Provider hooks are optional and belong to the caller's UI integration.
---@param adapter? base_tools.InputAdapter
---@return base_tools.InputController
function M.new(adapter)
  adapter = adapter or {}
  local M = {}
  -- A real scratch-buffer input for native Normal/Insert editing.
  local active, waiting, delivering
  local ns = api.nvim_create_namespace("")
  local refresh, finish, open_window, complete_close

  local function publish(a, layout)
    if adapter.on_layout then
      local ok, err = pcall(adapter.on_layout, layout and vim.deepcopy(layout))
      if not ok then
        vim.schedule(function()
          a.context:notify("layout callback: " .. tostring(err), vim.log.levels.ERROR)
        end)
      end
    end
  end

  local function value(a)
    return table.concat(api.nvim_buf_get_lines(a.buf, 0, -1, false), "\n")
  end

  local function validate(a, text, force)
    if not a.opts.validate then
      return true
    end
    if force or a.validated_text ~= text then
      a.validated_text = text
      local ok, result = pcall(a.opts.validate, text)
      a.validation_error = not ok and ("Validation failed: " .. tostring(result))
        or result ~= true and (type(result) == "string" and result ~= "" and result or "Invalid value")
        or nil
      refresh(a)
    end
    return a.validation_error == nil
  end

  function M.get_window()
    if
      active
      and not active.closed
      and active.win
      and api.nvim_win_is_valid(active.win)
      and api.nvim_buf_is_valid(active.buf)
      and api.nvim_win_get_buf(active.win) == active.buf
      and (not active.frame or active.frame:valid())
    then
      return active.win
    end
  end

  function M.get_layout()
    return M.get_window() and active.layout and vim.deepcopy(active.layout) or nil
  end

  local function signature(a)
    return {
      point = a.opts.position == "cursor" and require("base_tools.input.position").point(a.source) or nil,
      columns = vim.o.columns,
      rows = vim.o.lines - vim.o.cmdheight,
    }
  end

  local function geometry(a)
    return layout.editable(
      a.style,
      api.nvim_buf_line_count(a.buf),
      a.opts.position == "cursor" and a.source or nil,
      a.prompt
    )
  end

  local function draw_prompt(a, lines)
    local buf = a.frame.buf
    vim.bo[buf].modifiable = true
    api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    for row, line in ipairs(lines) do
      api.nvim_buf_set_extmark(buf, ns, row - 1, 0, { end_col = #line, hl_group = a.style.prompt_group })
    end
  end

  local function fit_horizontal_view(a)
    local win = a.win
    local width = api.nvim_win_get_width(win)
    api.nvim_win_call(win, function()
      local view = vim.fn.winsaveview()
      local cursor = vim.fn.virtcol(".")
      local last = math.max(cursor, vim.fn.virtcol("$") - 1)
      local right = last - width
      -- A jump off-screen can recenter the cursor and scroll past the line end.
      local leftcol = math.min(view.leftcol, right)
      local mode = api.nvim_get_mode().mode
      local selecting = a.initial.selection and mode == "s" and vim.fn.line("v") == vim.fn.line(".")
      local editing = a.initial.keep_suffix_visible and (mode == "n" or mode:sub(1, 1) == "i") and vim.fn.line("$") == 1
      if selecting or editing then
        local first = vim.fn.virtcol(".", true)[1]
        if selecting then
          first = math.min(first, vim.fn.virtcol("v", true)[1])
        end
        -- Keep the suffix in view when it fits beside the selection or cursor,
        -- reserving one cell for the left clipping marker.
        leftcol = math.max(leftcol, math.min(right, first - 2))
      end
      leftcol = math.max(0, cursor - width, leftcol)
      if leftcol ~= view.leftcol then
        vim.fn.winrestview({ leftcol = leftcol })
      end
    end)
  end

  local function update(a)
    if active ~= a or a.closed or not M.get_window() then
      return
    end
    if a.editing then
      a.editing.refresh(a.buf)
    end
    local box, edge, slot = geometry(a)
    local frame_changed = not vim.deep_equal(box, a.geometry)
    if frame_changed then
      local changed = vim.tbl_extend("force", {}, box)
      changed.noautocmd, changed.style, changed.title = nil, nil, box.title or ""
      local frame = a.frame or a.float
      frame:update(changed)
      a.geometry = box
    end
    if a.frame and (frame_changed or not vim.deep_equal(slot, a.prompt_slot)) then
      local editor = layout.editor(box, slot, a.frame.win)
      editor.noautocmd, editor.style = nil, nil
      a.float:update(editor)
      draw_prompt(a, slot.lines)
      a.prompt_slot = slot
    end
    local blend = a.style.winblend
    if a.winblend ~= blend then
      vim.wo[a.win].winblend = blend
      if a.frame then
        vim.wo[a.frame.win].winblend = blend
      end
      a.winblend = blend
    end
    if a.opts.validate or a.opts.on_change or a.opts.hints then
      require("base_tools.input.feedback").render(a, box)
    end
    a.signature = signature(a)
    fit_horizontal_view(a)
    -- Run only from scheduled work, never inside the decoration provider.
    local redraw = { valid = true, flush = true }
    if not a.frame then
      redraw.win = a.win
    end
    local ok = api.nvim__redraw and pcall(api.nvim__redraw, redraw)
    if not ok then
      vim.cmd.redraw()
    end
    if active ~= a or a.closed or not M.get_window() then
      return
    end
    local cursor = api.nvim_win_get_cursor(a.win)
    local screen = vim.fn.screenpos(a.win, cursor[1], cursor[2] + 1)
    local saved = api.nvim_win_call(a.win, vim.fn.winsaveview)
    a.layout = {
      win = a.win,
      frame_win = a.frame and a.frame.win or a.win,
      buf = a.buf,
      kind = "input",
      editable = true,
      vim_mode = true,
      row = box.row,
      col = box.col,
      width = box.width,
      height = box.height,
      outer_width = box.width + edge,
      outer_height = box.height + edge,
      border = { top = edge / 2, right = edge / 2, bottom = edge / 2, left = edge / 2 },
      text = {
        row = box.row + edge / 2 + slot.row,
        col = box.col + edge / 2 + slot.col - saved.leftcol,
      },
      cursor = { row = screen.row - 1, col = (screen.curscol or screen.col) - 1 },
    }
    publish(a, a.layout)
  end

  refresh = function(a)
    if active ~= a or a.closed or a.closing or a.refresh_pending then
      return
    end
    a.refresh_pending = true
    vim.schedule(function()
      a.refresh_pending = false
      if active ~= a or a.closed then
        return
      end
      local ok, err = pcall(update, a)
      if not ok then
        finish(a, nil)
        a.context:notify("input closed: " .. tostring(err), vim.log.levels.ERROR)
      end
    end)
  end

  function M.refresh()
    if active then
      refresh(active)
    end
  end

  local function dispatch(a, value)
    if a.delivered then
      return
    end
    a.delivered = true
    local previous = delivering
    delivering = true
    local ok, err = pcall(a.callback, value)
    delivering = previous
    if not ok then
      vim.schedule(function()
        a.context:notify("input callback: " .. tostring(err), vim.log.levels.ERROR)
      end)
    end
  end

  local function advance()
    local next_input = waiting
    if next_input and not active then
      vim.schedule(function()
        if waiting == next_input and not active and not next_input.closed then
          waiting = nil
          next_input.queued = false
          open_window(next_input)
        end
      end)
    end
  end

  complete_close = function(a, value)
    if a.closed then
      return
    end
    a.closed = true
    if value ~= nil then
      require("base_tools.input.history").add(a.opts.history, value)
    end
    require("base_tools.input.changes").stop(a)
    require("base_tools.input.content").restore(a.initial)
    require("base_tools.input.feedback").close(a)
    if a.editing then
      a.editing.detach(a.buf)
    end
    if active == a then
      active = nil
    end
    api.nvim_set_decoration_provider(ns, {})
    if a.group then
      pcall(api.nvim_del_augroup_by_id, a.group)
    end
    local focused = a.win and api.nvim_get_current_win() == a.win
    local externally_closed = a.win and not api.nvim_win_is_valid(a.win)
    if a.float then
      pcall(a.float.close, a.float)
    end
    if a.frame then
      pcall(a.frame.close, a.frame)
    end
    if a.buf and api.nvim_buf_is_valid(a.buf) then
      pcall(api.nvim_buf_delete, a.buf, { force = true })
    end
    if
      (focused or externally_closed)
      and api.nvim_win_is_valid(a.source.win)
      and api.nvim_win_get_buf(a.source.win) == a.source.buf
      and api.nvim_win_get_tabpage(a.source.win) == api.nvim_get_current_tabpage()
    then
      api.nvim_set_current_win(a.source.win)
    end
    publish(a, nil)
    dispatch(a, value)
    advance()
  end

  finish = function(a, value)
    if a.closed or a.closing then
      return
    end
    if a.queued then
      a.closed = true
      if waiting == a then
        waiting = nil
      end
      vim.schedule(function()
        dispatch(a, value)
        advance()
      end)
      return
    end
    a.closing = true
    -- Leave Insert while the input buffer still owns the cursor. Closing it first
    -- would let Neovim apply the Insert-exit cursor adjustment to the source file.
    local mode = api.nvim_get_mode().mode
    if
      a.win
      and (api.nvim_get_current_win() == a.win or not api.nvim_win_is_valid(a.win))
      and mode:sub(1, 1) == "i"
    then
      local returned = api.nvim_create_augroup("BaseToolsInputReturn" .. a.buf, { clear = true })
      api.nvim_create_autocmd("ModeChanged", {
        group = returned,
        pattern = "*:n",
        once = true,
        callback = function()
          pcall(api.nvim_del_augroup_by_id, returned)
          complete_close(a, value)
        end,
      })
      vim.cmd.stopinsert()
    else
      if a.win and api.nvim_get_current_win() == a.win and mode:match("^[sSvV\019\022]") then
        -- Clear the selection while its scratch buffer still owns both ends.
        vim.cmd.normal({
          args = { api.nvim_replace_termcodes("<Esc>", true, false, true) },
          bang = true,
        })
      end
      if a.entering_insert then
        vim.cmd.stopinsert()
      end
      complete_close(a, value)
    end
  end

  function M.cancel()
    if waiting then
      finish(waiting, nil)
    end
    if active then
      finish(active, nil)
    end
  end

  open_window = function(a)
    local opts = a.opts
    active = a
    local ok, err = pcall(function()
      if adapter.setup_highlights then
        adapter.setup_highlights()
      end
      a.buf = float.scratch({
        context = a.context,
        bufhidden = "wipe",
        swapfile = false,
        undofile = false,
        filetype = adapter.filetype or "base-tools-input",
      })
      vim.b[a.buf].completion = false -- Blink respects this buffer-local opt-out.
      api.nvim_buf_set_lines(a.buf, 0, -1, false, a.initial.lines)
      vim.bo[a.buf].modified = false
      if opts.completion or opts.highlight then
        a.editing = require("base_tools.input.buffer")
        a.editing.attach(a.buf, opts, a.context)
      end
      if adapter.setup_buffer then
        adapter.setup_buffer(a.buf, opts)
      end
      local w = a.style
      local prompt = opts.prompt or ""
      if (w.border == "none" or w.border == "") and prompt == "" and type(w.title) == "string" then
        prompt = w.title .. ": "
      end
      a.prompt = vim.fn.strtrans((prompt:gsub("[\r\n]", " ")))
      local box, _, slot = geometry(a)
      local editor = box
      if a.prompt ~= "" then
        local frame_options = layout.win_options(w)
        frame_options.wrap = false
        a.frame = float.open({
          context = a.context,
          config = box,
          win_options = frame_options,
          border_labels = opts.border_labels,
        })
        draw_prompt(a, slot.lines)
        editor = layout.editor(box, slot, a.frame.win)
      end

      local win_options = layout.win_options(w)
      win_options.wrap, win_options.scrolloff, win_options.sidescrolloff = false, 0, 0
      win_options.list = true
      local marker = vim.fn.strdisplaywidth("…") == 1 and "…" or "<"
      win_options.listchars = "tab:  ,precedes:" .. marker
      a.float = float.open({
        buf = a.buf,
        enter = true,
        context = a.context,
        config = editor,
        win_options = win_options,
        border_labels = not a.frame and opts.border_labels or nil,
      })
      a.win, a.geometry, a.winblend, a.prompt_slot = a.float.win, box, w.winblend, slot
      local function later(value)
        if active == a then
          finish(a, value)
        end
      end
      local function accept_completion()
        if adapter.accept_completion and adapter.accept_completion(a.buf) then
          return true
        end
        if vim.fn.pumvisible() == 1 then
          api.nvim_feedkeys(api.nvim_replace_termcodes("<C-y>", true, false, true), "ni", false)
          return true
        end
        return false
      end
      local function confirm()
        if accept_completion() then
          return
        end
        local text = value(a)
        require("base_tools.input.changes").flush(a)
        if validate(a, text, true) and not a.change_error and not a.change_pending then
          later(text)
        end
      end
      local function bind_confirm()
        vim.keymap.set(
          opts.multiline and "n" or { "n", "i", "s" },
          "<CR>",
          confirm,
          { buffer = a.buf, silent = true, desc = "Confirm input or accept completion" }
        )
        if opts.multiline then
          vim.keymap.set({ "n", "i", "s" }, "<C-s>", confirm, { buffer = a.buf, silent = true })
          for _, key in ipairs({ "<CR>", "<S-CR>" }) do
            vim.keymap.set({ "i", "s" }, key, function()
              if not accept_completion() then
                api.nvim_feedkeys(api.nvim_replace_termcodes("<CR>", true, false, true), "ni", false)
              end
            end, { buffer = a.buf, silent = true, desc = "Insert input newline" })
          end
        end
      end
      bind_confirm()
      require("base_tools.input.history").attach(a, refresh)
      vim.keymap.set({ "n", "i", "s" }, "<C-c>", function()
        later(nil)
      end, { buffer = a.buf, silent = true, desc = "Cancel input" })
      local modes = adapter.escape_to_normal and "n" or { "n", "i", "s" }
      vim.keymap.set(modes, "<Esc>", function()
        later(nil)
      end, { buffer = a.buf, silent = true, desc = "Cancel input" })
      if adapter.escape_to_normal then
        vim.keymap.set({ "i", "s" }, "<Esc>", "<Esc>", {
          buffer = a.buf,
          silent = true,
          desc = "Leave input Insert/Select mode",
        })
      end
      a.group = api.nvim_create_augroup("BaseToolsInput" .. a.buf, { clear = true })
      api.nvim_create_autocmd("InsertEnter", {
        group = a.group,
        buffer = a.buf,
        callback = function()
          -- Completion plugins install buffer mappings on InsertEnter. This
          -- input owns Enter; retain their other completion/navigation mappings.
          vim.schedule(function()
            if active == a and not a.closed and not a.closing and M.get_window() then
              bind_confirm()
            end
          end)
        end,
      })
      api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "CursorMoved", "CursorMovedI", "ModeChanged" }, {
        group = a.group,
        buffer = a.buf,
        callback = function()
          local mode = api.nvim_get_mode().mode
          if a.initial_started and not mode:match("^[sSvV\019\022]") then
            require("base_tools.input.content").restore(a.initial)
            a.initial.selection = nil
          end
          validate(a, value(a))
          if api.nvim_get_current_win() == a.win and api.nvim_get_mode().mode:sub(1, 1) == "i" then
            a.entering_insert = false
          end
          refresh(a)
        end,
      })
      api.nvim_create_autocmd({ "WinLeave", "BufWipeout" }, {
        group = a.group,
        buffer = a.buf,
        callback = function()
          later(nil)
        end,
      })
      local windows = { tostring(a.win) }
      if a.frame then
        windows[#windows + 1] = tostring(a.frame.win)
      end
      api.nvim_create_autocmd("WinClosed", {
        group = a.group,
        pattern = windows,
        callback = function()
          later(nil)
        end,
      })
      api.nvim_create_autocmd("WinScrolled", {
        group = a.group,
        pattern = tostring(a.win),
        callback = function()
          refresh(a)
        end,
      })
      api.nvim_create_autocmd({ "VimResized", "ColorScheme" }, {
        group = a.group,
        callback = function(e)
          if e.event == "ColorScheme" then
            if adapter.setup_highlights then
              adapter.setup_highlights(true)
            end
            if a.editing then
              a.editing.refresh(a.buf, true)
            end
          end
          refresh(a)
        end,
      })
      api.nvim_set_decoration_provider(ns, {
        on_end = function()
          if active == a and not a.closed and not a.closing and not vim.deep_equal(signature(a), a.signature) then
            refresh(a)
          end
        end,
      })
      refresh(a)
      a.entering_insert = require("base_tools.input.content").start(a.initial, a.win)
      a.initial_started = true
      validate(a, value(a))
      require("base_tools.input.changes").start(a, refresh)
    end)
    if not ok then
      finish(a, nil)
      error(err)
    end
  end

  function M.open(opts, callback)
    opts = opts or {}
    assert(type(opts) == "table", "input options must be a table")
    local check = Context.checker(opts.context, "input.open")
    check(type(callback) == "function", "input requires a completion callback")
    check(opts.style == nil or type(opts.style) == "table", "input style must be a table")
    check(opts.completion == nil or type(opts.completion) == "string", "completion must be a string")
    check(
      opts.completion_cwd == nil
        or type(opts.completion_cwd) == "string"
          and opts.completion_cwd ~= ""
          and (opts.completion == "file" or opts.completion == "dir"),
      "completion_cwd requires a nonempty directory and file or dir completion"
    )
    check(
      opts.highlight == nil or type(opts.highlight) == "string" or type(opts.highlight) == "function",
      "highlight must be a callback or function name"
    )
    check(opts.prompt == nil or type(opts.prompt) == "string", "prompt must be a string")
    check(opts.validate == nil or type(opts.validate) == "function", "validate must be a function")
    check(opts.hints == nil or type(opts.hints) == "boolean", "hints must be a boolean")
    check(opts.multiline == nil or type(opts.multiline) == "boolean", "multiline must be a boolean")
    check(
      opts.history == nil or type(opts.history) == "string" and opts.history ~= "",
      "history must be a nonempty string"
    )
    check(opts.on_change == nil or type(opts.on_change) == "function", "on_change must be a function")
    check(
      opts.change_delay == nil
        or type(opts.change_delay) == "number"
          and opts.change_delay >= 0
          and opts.change_delay < math.huge
          and opts.change_delay == math.floor(opts.change_delay),
      "change_delay must be a nonnegative integer"
    )
    local initial = require("base_tools.input.content").resolve(opts.default)
    if waiting then
      finish(waiting, nil)
    end
    local a = {
      opts = vim.deepcopy(opts),
      initial = initial,
      callback = callback,
      context = opts.context or default_context,
      source = active and active.source or require("base_tools.input.position").capture(),
      queued = active ~= nil or delivering == true,
    }
    local style = vim.tbl_extend("force", {}, opts.style or {})
    for _, key in ipairs({ "width", "title", "title_pos" }) do
      if opts[key] ~= nil then
        style[key] = opts[key]
      end
    end
    a.style = layout.resolve(style)
    if active or delivering then
      waiting = a
      if active then
        finish(active, nil)
      end
    else
      open_window(a)
    end
    return {
      cancel = function()
        finish(a, nil)
      end,
      get_layout = function()
        return active == a and M.get_layout() or nil
      end,
    }
  end

  return M
end

--- Open an editable input using the default controller.
--- The callback receives the confirmed text, or nil if cancelled.
---@param opts? base_tools.InputOptions
---@param on_done fun(value: string?)
---@return base_tools.InputHandle
function M.open(opts, on_done)
  default_controller = default_controller or M.new()
  return default_controller.open(opts, on_done)
end

--- Build options for base_tools.float.open without creating a window.
--- height is the number of content rows. A cursor anchor is optional.
--- Title and footer are omitted when the style has no border.
---@param style? base_tools.InputStyle
---@param opts? base_tools.InputFloatOptions
---@return base_tools.FloatOptions
function M.float_options(style, opts)
  opts = opts or {}
  style = layout.resolve(style)
  if opts.title ~= nil then
    style.title = opts.title
  end
  style.title_pos = opts.title_pos or style.title_pos
  local config, edge = layout.input(style, opts.height or 1, opts.anchor, opts.focusable ~= false)
  if edge > 0 and opts.footer ~= nil then
    config.footer, config.footer_pos = opts.footer, opts.footer_pos
  end
  return { config = config, win_options = layout.win_options(style), border_labels = opts.border_labels }
end

return M
