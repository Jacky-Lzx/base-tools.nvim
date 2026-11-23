vim.opt.runtimepath:prepend(vim.uv.cwd())

local M = {}

local function report(stream, fd, label, color, name)
  if (vim.env.NO_COLOR or "") == "" and vim.env.TERM ~= "dumb" and vim.uv.guess_handle(fd) == "tty" then
    label = ("\27[%dm%s\27[0m"):format(color, label)
  end
  stream:write(label, " ", name, "\n")
  stream:flush()
end

function M.eq(expected, actual)
  assert(vim.deep_equal(expected, actual), vim.inspect({ expected = expected, actual = actual }))
end

function M.run(name, test)
  local ok, err = xpcall(test, debug.traceback)
  if ok then
    report(io.stdout, 1, "PASS", 32, name)
    return
  end

  report(io.stderr, 2, "FAIL", 31, name)
  io.stderr:write(err, "\n")
  io.stderr:flush()
  vim.cmd.cquit()
end

return M
