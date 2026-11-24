local test = dofile("tests/support.lua")
local timer = require("base_tools.timer")

test.run("base-tools.timer restart and cancel", function()
  local task = timer.new()
  local calls = {}
  local function record(value)
    return function()
      test.eq(false, vim.in_fast_event())
      calls[#calls + 1] = value
    end
  end

  task:start(10, record("superseded delay"))
  task:start(1, record("delayed"))
  assert(vim.wait(1000, function()
    return #calls > 0
  end, 1))
  test.eq({ "delayed" }, calls)

  task:start(0, record("superseded callback"))
  task:start(0, record("cancelled callback"))
  task:cancel()
  task:cancel()
  task:start(0, record("immediate"))
  test.eq({ "delayed" }, calls)
  assert(vim.wait(1000, function()
    return #calls >= 2
  end, 1))
  test.eq({ "delayed", "immediate" }, calls)
  task:close()
end)

test.run("base-tools.timer close after the UV deadline", function()
  local task = timer.new()
  local called, expired, drained = false, false, false
  task:start(1, function()
    called = true
  end)

  local barrier = assert(vim.uv.new_timer())
  barrier:start(10, 0, function()
    expired = true
    barrier:close()
  end)
  -- Let the UV timers fire while scheduled Lua callbacks are still queued.
  assert(vim.wait(1000, function()
    return expired
  end, 1, true))
  test.eq(false, called)

  task:close()
  task:close()
  vim.schedule(function()
    drained = true
  end)
  assert(vim.wait(1000, function()
    return drained
  end, 1))
  test.eq(false, called)
  test.eq(false, pcall(task.start, task, 0, function() end))
end)
