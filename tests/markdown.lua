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
