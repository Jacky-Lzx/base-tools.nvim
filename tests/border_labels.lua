local test = dofile("tests/support.lua")

test.run("base-tools.border_labels", function()
  local api = vim.api
  local float = require("base_tools.float")
  local eq = test.eq

  local function text(parts)
    if type(parts) == "string" or parts == nil then
      return parts or ""
    end
    return table.concat(vim.tbl_map(function(part)
      return part[1]
    end, parts))
  end

  local view = float.open({
    config = {
      relative = "editor",
      row = 1,
      col = 2,
      width = 20,
      height = 2,
      border = "single",
      title = "native",
      title_pos = "right",
      footer = "native footer",
    },
    border_labels = {
      top = { left = { { "文", "Title" }, { "A", "WarningMsg" } }, center = "MID", right = "R" },
      bottom = { left = "L", center = "OK", right = "42%" },
    },
  })
  local win = view.win
  local function config()
    return api.nvim_win_get_config(win)
  end
  eq("文A─────MID────────R", text(config().title))
  eq({ "文", "Title" }, config().title[1])
  eq({ "A", "WarningMsg" }, config().title[2])
  eq("L────────OK──────42%", text(config().footer))
  assert(view:set_border_labels({ bottom = { right = "90%" } }))
  eq("L────────OK──────90%", text(config().footer))
  eq("文A─────MID────────R", text(config().title))

  assert(view:update({ width = 8 }))
  eq("文AM…──R", text(config().title))
  eq("L──OK90%", text(config().footer))
  assert(view:update({ width = 3 }))
  eq("…─R", text(config().title))
  eq("L…%", text(config().footer))
  assert(view:update({ width = 20, border = "double" }))
  eq("文A═════MID════════R", text(config().title))

  assert(view:update({ title = "latest", title_pos = "center" }))
  assert(view:set_border_labels({ bottom = false }))
  eq("native footer", text(config().footer))
  eq("文A═════MID════════R", text(config().title))
  assert(view:set_border_labels({ top = false }))
  eq("latest", text(config().title))
  eq("center", config().title_pos)

  view:update({ width = 8 })
  view:set_border_labels({
    top = { left = { { "ab", "Title" }, { "cdef", "Special" } }, right = "RIGHT" },
  })
  eq("abc……GHT", text(config().title))
  eq({ "ab", "Title" }, config().title[1])
  eq({ "c", "Special" }, config().title[2])
  view:set_border_labels({ top = false })
  view:update({ width = 20 })

  local custom = { "╔", { "═", "Special" }, "╗", "║", "╝", { "═", "Comment" }, "╚", "║" }
  view:update({ border = custom })
  view:set_border_labels({ top = { center = "组" }, bottom = { right = "OK" } })
  eq({ string.rep("═", 9), "Special" }, config().title[1])
  eq({ "组", "FloatTitle" }, config().title[2])
  eq({ string.rep("═", 18), "Comment" }, config().footer[1])
  view:update({ border = "none" })
  eq("", text(config().title))
  eq("", text(config().footer))
  view:update({ border = "single" })
  eq("─────────组─────────", text(config().title))
  assert(view:set_border_labels({ top = { center = "" } }))
  eq("latest", text(config().title))
  view:close()
  eq(false, view:set_border_labels({ bottom = false }))

  local preview = require("base_tools.preview").open({
    config = { relative = "editor", row = 1, col = 2, width = 10, height = 3, border = "single" },
    lines = { "text" },
    border_labels = {
      top = { left = { kind = "filename", value = "lua/文.lua", highlight = "Title" } },
      bottom = { left = { kind = "path", value = "lua/文.lua", highlight = "Comment" } },
    },
  })
  local function preview_config()
    return api.nvim_win_get_config(preview.win)
  end
  eq("文.lua────", text(preview_config().title))
  eq({ "文.lua", "Title" }, preview_config().title[1])
  eq("lua/文.lua", text(preview_config().footer))
  assert(preview:set_border_labels({ bottom = { right = "42%" } }))
  eq("…文.lua42%", text(preview_config().footer))
  eq({ "…", "Comment" }, preview_config().footer[1])
  eq({ "文.lua", "Comment" }, preview_config().footer[2])
  assert(preview:set_border_labels({ top = { left = { kind = "filename", value = "src/a\nb" } } }))
  eq("a^@b──────", text(preview_config().title))
  assert(preview:set_border_labels({ top = { left = { kind = "filename", value = "" } } }))
  eq("", text(preview_config().title))
  preview:close()
end)
