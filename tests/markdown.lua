local test = dofile("tests/support.lua")

test.run("base-tools.markdown conceals fences", function()
  local api = vim.api
  local eq = test.eq
  local markdown = require("base_tools.markdown")
  local buf = api.nvim_create_buf(false, true)
  local ns = api.nvim_create_namespace("base-tools-markdown-test")
  local function verify(lines, delimiters, fenced)
    api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    local hidden, code = markdown.conceal_fences(buf, ns)
    local hidden_rows, code_rows = vim.tbl_keys(hidden), vim.tbl_keys(code)
    table.sort(hidden_rows)
    table.sort(code_rows)
    eq(delimiters, hidden_rows)
    eq(fenced, code_rows)
    eq(lines, api.nvim_buf_get_lines(buf, 0, -1, false))
    local marks = api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
    eq(
      delimiters,
      vim.tbl_map(function(mark)
        eq("", mark[4].conceal_lines)
        return mark[2] + 1
      end, marks)
    )
  end

  verify({
    "# Heading",
    "",
    "> ```lua",
    "> return true",
    "> ```",
    "",
    "    ```literal in indented code",
    "",
    "~~~~lua",
    "# literal",
    "```",
    "~~~",
    "~~~~",
    "",
    "```sh",
    "echo trailing",
  }, { 3, 5, 9, 13, 15 }, { 3, 4, 5, 9, 10, 11, 12, 13, 15, 16 })

  local get_parser = vim.treesitter.get_parser
  vim.treesitter.get_parser = function()
    error("Markdown parser unavailable")
  end
  local ok, err = pcall(verify, {
    "    ```indented",
    " ```invalid`info",
    " ~~~~lua",
    " ```",
    " ~~~",
    " ~~~~~ ",
    "# prose",
  }, { 3, 6 }, { 3, 4, 5, 6 })
  vim.treesitter.get_parser = get_parser
  assert(ok, err)
  api.nvim_buf_delete(buf, { force = true })
end)

test.run("base-tools preview renders Markdown documents", function()
  local api = vim.api
  local eq = test.eq
  local preview = require("base_tools.preview")
  local config = { relative = "editor", row = 1, col = 2, width = 24, height = 12, border = "single" }
  local lines = { "```lua", "---", "```", "", "---", "", "# Details" }
  local rule_marks = api.nvim_create_namespace("base-tools-markdown-rules")
  local fence_marks = api.nvim_create_namespace("base-tools-markdown-fences")
  local view = preview.open({
    config = config,
    lines = lines,
    format = "markdown",
    markdown = { rule_highlight = "Title" },
    win_options = { conceallevel = 0, concealcursor = "" },
  })
  local win, buf = view.win, view.buf
  local function marks(ns)
    return api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
  end

  eq({ [1] = true, [3] = true }, view:markdown_rows())
  local _, fenced = view:markdown_rows()
  eq({ true, true, true }, fenced)
  eq(lines, api.nvim_buf_get_lines(buf, 0, -1, false))
  eq(5, view:content_height())
  eq(2, vim.wo[win].conceallevel)
  eq("markdown", vim.treesitter.highlighter.active[buf].tree:lang())
  eq(1, #marks(rule_marks))
  eq({ { string.rep("─", 24), "Title" } }, marks(rule_marks)[1][4].virt_text)
  assert(view:update({ width = 12 }))
  eq({ { string.rep("─", 12), "Title" } }, marks(rule_marks)[1][4].virt_text)
  assert(view:set_lines({ "***" }))
  eq({ { string.rep("─", 12), "Title" } }, marks(rule_marks)[1][4].virt_text)
  eq({}, marks(fence_marks))
  assert(view:set_content({ lines = lines, language = "markdown" }))
  eq({}, marks(rule_marks))
  eq({}, marks(fence_marks))
  eq(0, vim.wo[win].conceallevel)
  eq("", vim.wo[win].concealcursor)
  eq(7, view:content_height())
  view:close()

  buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  win = api.nvim_open_win(buf, false, config)
  vim.wo[win].conceallevel, vim.wo[win].concealcursor = 1, "n"
  view = preview.attach(win, { format = "markdown" })
  eq(2, vim.wo[win].conceallevel)
  eq(5, view:content_height())
  assert(view:detach())
  eq({}, marks(rule_marks))
  eq({}, marks(fence_marks))
  eq(1, vim.wo[win].conceallevel)
  eq("n", vim.wo[win].concealcursor)
  eq(lines, api.nvim_buf_get_lines(buf, 0, -1, false))
  api.nvim_win_close(win, true)
  api.nvim_buf_delete(buf, { force = true })
end)
