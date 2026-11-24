local test = dofile("tests/support.lua")
local highlight = require("base_tools.highlight")
local api = vim.api

test.run("Highlights follow global links and ignore window remapping", function()
  api.nvim_set_hl(0, "BaseToolsTestHighlight", { fg = "#001122", bold = true })
  api.nvim_set_hl(0, "BaseToolsTestLink", { link = "BaseToolsTestHighlight" })
  api.nvim_set_hl(0, "BaseToolsTestAlias", { link = "BaseToolsTestLink" })
  local previous = vim.wo.winhighlight
  vim.wo.winhighlight = "BaseToolsTestHighlight:Error"
  local resolved = highlight.resolve("BaseToolsTestAlias")
  test.eq(0x001122, resolved.fg)
  test.eq(true, resolved.bold)
  vim.wo.winhighlight = previous
end)

test.run("Highlights skip missing groups and handle link cycles", function()
  local missing = "BaseToolsTestMissing"
  test.eq(0, vim.fn.hlexists(missing))
  test.eq({}, highlight.resolve(missing))
  test.eq(0, vim.fn.hlexists(missing))

  api.nvim_set_hl(0, "BaseToolsTestCycleOne", { link = "BaseToolsTestCycleTwo" })
  api.nvim_set_hl(0, "BaseToolsTestCycleTwo", { link = "BaseToolsTestCycleOne" })
  test.eq({}, highlight.resolve("BaseToolsTestCycleOne"))
end)
