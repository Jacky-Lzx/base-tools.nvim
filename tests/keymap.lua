local test = dofile("tests/support.lua")
local keymap = require("base_tools.keymap")
local api = vim.api

test.run("base-tools.keymap resolves action chains without changing their input", function()
  local function callback() end
  local input = { a = "open", b = callback, c = { callback, "open", desc = "Actions" }, d = false, e = {} }
  local bindings = keymap.resolve(input, { actions = { open = true } })
  test.eq({
    { lhs = "a", actions = { "open" } },
    { lhs = "b", actions = { callback } },
    { lhs = "c", actions = { callback, "open" }, desc = "Actions" },
    { lhs = "e", actions = {} },
  }, bindings)
  bindings[3].actions[1] = "open"
  test.eq(callback, input.c[1])
  test.eq(false, pcall(keymap.resolve, { a = "missing" }, { actions = {} }))
  test.eq(false, pcall(keymap.resolve, { a = { [2] = "open" } }))
  test.eq(false, pcall(keymap.resolve, { ["<M-z>"] = "open", ["<A-z>"] = "open" }, { check_aliases = true }))
end)

test.run("base-tools.keymap overlays defaults by key and inherits action descriptions", function()
  local defaults = { r = { "open", "close", desc = "Default chain" }, q = "close", x = "open" }
  local overrides = { r = false, x = { "close", desc = "Override" }, ["<F2>"] = "open" }
  local opts = {
    defaults = defaults,
    actions = { close = { desc = "Close" }, open = { desc = "Open" } },
    check_aliases = true,
  }
  local bindings = keymap.resolve(overrides, opts)
  test.eq({
    { lhs = "<F2>", actions = { "open" }, desc = "Open", desc_inherited = true },
    { lhs = "q", actions = { "close" }, desc = "Close", desc_inherited = true },
    { lhs = "x", actions = { "close" }, desc = "Override" },
  }, bindings)

  overrides.r = { "close", desc = "New chain" }
  bindings = keymap.resolve(overrides, opts)
  test.eq({ lhs = "r", actions = { "close" }, desc = "New chain" }, bindings[3])
  test.eq({ "open", "close", desc = "Default chain" }, defaults.r)
  test.eq(keymap.resolve(defaults, { actions = opts.actions }), keymap.resolve(nil, opts))
  test.eq(false, pcall(keymap.resolve, false, opts))
  test.eq(
    false,
    pcall(keymap.resolve, { ["<M-z>"] = "open" }, {
      defaults = { ["<A-z>"] = "close" },
      check_aliases = true,
    })
  )
end)

test.run("base-tools.keymap restores only the captured mode and scope", function()
  local function original()
    return "original"
  end
  local function local_action() end
  local function replacement() end
  local function later() end
  local lhs = "<F22>"
  local buf = api.nvim_get_current_buf()
  vim.keymap.set("!", lhs, original, { expr = true, replace_keycodes = false, silent = true })
  vim.keymap.set("i", lhs, local_action, { buffer = buf })
  local close_insert, previous = keymap.install("i", lhs, replacement)
  test.eq(original, previous.callback)
  test.eq(local_action, vim.fn.maparg(lhs, "i", false, true).callback)

  vim.keymap.set("c", lhs, later)
  close_insert()
  test.eq(later, vim.fn.maparg(lhs, "c", false, true).callback)
  vim.keymap.del("i", lhs, { buffer = buf })
  local restored = vim.fn.maparg(lhs, "i", false, true)
  test.eq({ original, 1, 0, 1 }, { restored.callback, restored.expr, restored.replace_keycodes, restored.silent })

  local close_local, prior_local = keymap.install("i", lhs, replacement, { buffer = buf })
  test.eq(nil, prior_local)
  close_local()
  test.eq(original, vim.fn.maparg(lhs, "i", false, true).callback)

  local close_replaced = keymap.install("i", lhs, replacement)
  vim.keymap.set("i", lhs, later)
  close_replaced()
  test.eq(later, vim.fn.maparg(lhs, "i", false, true).callback)
  vim.keymap.del("i", lhs)
  vim.keymap.del("c", lhs)
end)

test.run("base-tools.keymap handles overlapping owners and captures the installed key", function()
  local function original() end
  local function replacement() end
  local leader = vim.g.mapleader
  vim.g.mapleader = ","
  local lhs = "<Leader><F23>"
  local buf = api.nvim_create_buf(false, true)
  vim.keymap.set("n", lhs, original, { buffer = buf })
  local first = keymap.install("n", lhs, replacement, { buffer = buf })
  local second = keymap.install("n", lhs, replacement, { buffer = buf })
  vim.g.mapleader = ";"
  first()
  second()
  second()
  api.nvim_buf_call(buf, function()
    test.eq(original, vim.fn.maparg(",<F23>", "n", false, true).callback)
  end)
  local wiped = keymap.install("n", lhs, replacement, { buffer = buf })
  api.nvim_buf_delete(buf, { force = true })
  wiped()
  vim.g.mapleader = leader
end)

test.run("base-tools.keymap keeps distinct terminal key spellings", function()
  local function tab() end
  local function ctrl_i() end
  local function replacement() end
  local buf = api.nvim_create_buf(false, true)
  vim.keymap.set("n", "<Tab>", tab, { buffer = buf })
  vim.keymap.set("n", "<C-I>", ctrl_i, { buffer = buf })
  local close, previous = keymap.install("n", "<C-I>", replacement, { buffer = buf })
  test.eq(ctrl_i, previous.callback)
  close()
  api.nvim_buf_call(buf, function()
    test.eq(tab, vim.fn.maparg("<Tab>", "n", false, true).callback)
    test.eq(ctrl_i, vim.fn.maparg("<C-I>", "n", false, true).callback)
  end)
  api.nvim_buf_delete(buf, { force = true })
end)
