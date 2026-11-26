---Restartable one-shot timers whose callbacks run on Neovim's main loop.
local Context = require("base_tools.context")
local M = {}

---@class base_tools.Timer
---@field private context? base_tools.Context
---@field private handle uv.uv_timer_t?
---@field private pending fun()?
---@field private closed boolean?
local Timer = {}
Timer.__index = Timer

---Replace any pending callback. A zero delay still schedules asynchronously.
---@param delay_ms number
---@param callback fun()
function Timer:start(delay_ms, callback)
  local check = Context.checker(self.context, "timer.start")
  local prefix = self.context and "" or "base-tools: "
  check(not self.closed, prefix .. "cannot start a closed timer")
  check(type(delay_ms) == "number" and delay_ms >= 0 and delay_ms < math.huge, prefix .. "invalid timer delay")
  check(type(callback) == "function", prefix .. "timer callback must be a function")
  self:cancel()

  local function run()
    -- The UV timer may have fired before cancel or restart.
    if self.pending == run then
      self.pending = nil
      callback()
    end
  end

  if delay_ms == 0 then
    vim.schedule(run)
  else
    if not self.handle then
      local handle, err = Context.call(self.context, "timer.start", vim.uv.new_timer)
      self.handle = check(handle, err or "unable to allocate a timer")
    end
    Context.call(self.context, "timer.start", self.handle.start, self.handle, delay_ms, 0, vim.schedule_wrap(run))
  end
  self.pending = run
end

---Cancel the pending callback and keep the timer available for reuse.
function Timer:cancel()
  self.pending = nil
  if self.handle then
    self.handle:stop()
  end
end

---Cancel the pending callback and release the timer. Safe to call again.
function Timer:close()
  self:cancel()
  if self.handle then
    self.handle:close()
    self.handle = nil
  end
  self.closed = true
end

---@param opts? { context?: base_tools.Context }
---@return base_tools.Timer timer
function M.new(opts)
  return setmetatable({ context = opts and opts.context }, Timer)
end

return M
