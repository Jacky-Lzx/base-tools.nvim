---Restartable one-shot timers whose callbacks run on Neovim's main loop.
local M = {}

---@class base_tools.Timer
---@field private handle uv.uv_timer_t?
---@field private pending fun()?
---@field private closed boolean?
local Timer = {}
Timer.__index = Timer

---Replace any pending callback. A zero delay still schedules asynchronously.
---@param delay_ms number
---@param callback fun()
function Timer:start(delay_ms, callback)
  assert(not self.closed, "base-tools: cannot start a closed timer")
  assert(type(delay_ms) == "number" and delay_ms >= 0 and delay_ms < math.huge, "base-tools: invalid timer delay")
  assert(type(callback) == "function", "base-tools: timer callback must be a function")
  self:cancel()

  local function run()
    -- The UV timer may have fired before cancel or restart.
    if self.pending == run then
      self.pending = nil
      callback()
    end
  end

  self.pending = run
  if delay_ms == 0 then
    vim.schedule(run)
  else
    self.handle = self.handle or assert(vim.uv.new_timer())
    self.handle:start(delay_ms, 0, vim.schedule_wrap(run))
  end
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

---@return base_tools.Timer timer
function M.new()
  return setmetatable({}, Timer)
end

return M
