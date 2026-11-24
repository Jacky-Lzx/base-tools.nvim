local test = dofile("tests/support.lua")
local process = require("base_tools.process")

test.run("base-tools.process delivers results and launch errors on the main loop", function()
  local group = process.new()
  local completed, launch_error
  group:run({ "sh", "-c", "printf result; printf warning >&2; exit 7" }, nil, function(result, err)
    test.eq(false, vim.in_fast_event())
    test.eq(nil, err)
    completed = result
  end)
  group:run({ vim.fn.tempname() }, nil, function(result, err)
    test.eq(false, vim.in_fast_event())
    test.eq(nil, result)
    launch_error = err
  end)
  test.eq(nil, launch_error)
  assert(vim.wait(1000, function()
    return completed ~= nil and launch_error ~= nil
  end, 1))
  test.eq({ code = 7, signal = 0, stdout = "result", stderr = "warning" }, completed)
  test.eq("string", type(launch_error))
  group:close()
end)

test.run("base-tools.process closes running and queued work", function()
  local group = process.new()
  local jobs, signals = {}, {}
  local called, drained = false, false
  local system = vim.system
  local ok, err = pcall(function()
    vim.system = function(_, _, on_exit)
      local job = { done = false, on_exit = on_exit }
      function job:is_closing()
        return self.done
      end
      function job:kill(signal)
        signals[#signals + 1] = { self, signal }
      end
      jobs[#jobs + 1] = job
      return job
    end

    local function callback()
      called = true
    end
    group:run({ "finished" }, nil, callback)
    group:run({ "running" }, nil, callback)
    jobs[1].done = true
    jobs[1].on_exit({ code = 0, signal = 0 })
    group:close()
    group:close()
    group:run({ "after close" }, nil, callback)
    jobs[2].done = true
    jobs[2].on_exit({ code = 0, signal = 15 })
  end)
  vim.system = system
  assert(ok, err)

  test.eq(true, group.cancelled)
  test.eq(2, #jobs)
  test.eq({ { jobs[2], 15 } }, signals)
  vim.schedule(function()
    drained = true
  end)
  assert(vim.wait(1000, function()
    return drained
  end, 1))
  test.eq(false, called)
end)
