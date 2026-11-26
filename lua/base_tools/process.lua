---Run asynchronous subprocesses with a shared cancellation lifetime.
local Context = require("base_tools.context")
local M = {}

---@class base_tools.ProcessGroup
---@field cancelled boolean Whether the group has been closed.
---@field private context? base_tools.Context
---@field private processes table<vim.SystemObj, true>
local Group = {}
Group.__index = Group

---Run a subprocess and deliver its result on Neovim's main loop.
---A launch error is delivered as the second callback argument.
---@param argv string[]
---@param opts vim.SystemOpts?
---@param callback fun(result: vim.SystemCompleted?, launch_error?: string)
function Group:run(argv, opts, callback)
  if self.cancelled then
    return
  end

  local process
  local function complete(result, launch_error)
    vim.schedule(function()
      if process then
        self.processes[process] = nil
      end
      if not self.cancelled then
        callback(result, launch_error)
      end
    end)
  end

  local ok, value = pcall(vim.system, argv, opts, complete)
  if ok then
    process = value
    self.processes[process] = true
  else
    complete(nil, Context.format(self.context, "process.run", tostring(value)))
  end
end

---Terminate running subprocesses and invalidate queued completion callbacks.
function Group:close()
  self.cancelled = true
  for process in pairs(self.processes) do
    if not process:is_closing() then
      process:kill(15)
    end
  end
  self.processes = {}
end

---@param opts? { context?: base_tools.Context }
---@return base_tools.ProcessGroup group
function M.new(opts)
  return setmetatable({ cancelled = false, processes = {}, context = opts and opts.context }, Group)
end

return M
