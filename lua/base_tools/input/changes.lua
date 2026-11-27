-- Revision-scoped draft notifications; late work cannot publish into a new draft.
local M = {}
local api = vim.api

local function report(a, err)
  vim.schedule(function()
    a.context:notify("change cancellation: " .. tostring(err), vim.log.levels.WARN)
  end)
end

local function cancel(a)
  local fn = a.change_cancel
  a.change_cancel = nil
  if fn then
    local ok, err = pcall(fn)
    if not ok then
      report(a, err)
    end
  end
end

function M.stop(a)
  a.change_generation = (a.change_generation or 0) + 1
  if a.change_timer then
    a.change_timer:stop()
    a.change_timer:close()
    a.change_timer = nil
  end
  cancel(a)
end

function M.flush(a)
  if not a.opts.on_change or a.closed or a.closing then
    return
  end
  local generation = a.change_generation
  if a.change_delivered == generation then
    return
  end
  if a.change_timer then
    a.change_timer:stop()
  end
  cancel(a)
  a.change_delivered = generation
  local function current()
    return not a.closed and not a.closing and a.change_generation == generation
  end
  local function publish(field, text)
    assert(text == nil or type(text) == "string", "feedback must be a string or nil")
    if not current() then
      return false
    end
    a[field] = text ~= "" and text or nil
    a.change_refresh(a)
    return true
  end
  local context = {
    is_current = current,
    set_error = function(text)
      return publish("change_error", text)
    end,
    set_status = function(text)
      return publish("change_status", text)
    end,
    set_pending = function(pending)
      assert(type(pending) == "boolean", "pending must be a boolean")
      if not current() then
        return false
      end
      a.change_pending = pending
      a.change_refresh(a)
      return true
    end,
  }
  local ok, result = pcall(a.opts.on_change, a.change_text, context)
  if not ok then
    context.set_error("Change handler failed: " .. tostring(result))
    context.set_pending(false)
  elseif type(result) == "function" then
    if current() then
      a.change_cancel = result
    else
      -- A reentrant handler may already have replaced or cancelled its input.
      pcall(result)
    end
  end
end

function M.start(a, refresh)
  if not a.opts.on_change then
    return
  end
  a.change_refresh = refresh
  local function changed()
    local text = table.concat(api.nvim_buf_get_lines(a.buf, 0, -1, false), "\n")
    if text == a.change_text then
      return
    end
    a.change_text = text
    a.change_generation = (a.change_generation or 0) + 1
    a.change_error, a.change_status, a.change_pending = nil, nil, false
    local generation = a.change_generation
    -- Buffer attach callbacks run under textlock; user cancellation runs later.
    local previous = a.change_cancel
    a.change_cancel = nil
    vim.schedule(function()
      if previous then
        local ok, err = pcall(previous)
        if not ok then
          report(a, err)
        end
      end
      if a.closed or a.closing or a.change_generation ~= generation then
        return
      end
      refresh(a)
      local delay = a.opts.change_delay or 0
      if delay == 0 then
        M.flush(a)
      else
        a.change_timer = a.change_timer or vim.uv.new_timer()
        a.change_timer:start(
          delay,
          0,
          vim.schedule_wrap(function()
            if a.change_generation == generation then
              M.flush(a)
            end
          end)
        )
      end
    end)
  end
  api.nvim_buf_attach(a.buf, false, {
    on_lines = function()
      if a.closed or a.closing then
        return true
      end
      changed()
    end,
  })
  changed()
end

return M
