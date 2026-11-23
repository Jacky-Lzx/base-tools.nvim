local test = dofile("tests/support.lua")

test.run("base-tools.text", function()
  local text = require("base_tools.text")

  local eq = test.eq

  eq({ "短", 0, #"短", 0 }, { text.clip("短", 2) })
  eq({ "中文…", 0, #"中文", 0 }, { text.clip("中文路径", 5) })
  eq({ "…src.lua", 5, 12, #"…" }, { text.clip("some/src.lua", 8, { side = "start" }) })
  eq({ "lua", 4, 7, 0 }, { text.clip("vim.lua", 3, { side = "start", ellipsis = false }) })
  eq({ "", 0, 0, 0 }, { text.clip("text", 0) })

  for _, grapheme in ipairs({ "é", "👩‍💻", "🇨🇳", "✊🏽", "1️⃣" }) do
    local cells = vim.fn.strdisplaywidth(grapheme) + 1
    eq({ grapheme .. "…", 0, #grapheme, 0 }, { text.clip(grapheme .. "xxx", cells) })
    eq({ "…" .. grapheme, 3, 3 + #grapheme, #"…" }, { text.clip("xxx" .. grapheme, cells, { side = "start" }) })
  end
  vim.o.ambiwidth = "double"
  eq({ ".", 0, 0, 0 }, { text.clip("abcd", 1) })
  vim.o.ambiwidth = "single"
end)
