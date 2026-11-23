# base-tools.nvim

Shared utilities for Neovim plugins.

## Requirements

Neovim **0.12+**.

## Installation

Put this repository on `runtimepath` and require the module you need. Plugins
that use these modules can declare `Jacky-Lzx/base-tools.nvim` as a dependency.
For example, a lazy.nvim library specification can use `lazy = true`.

## Text

```lua
local text = require("base_tools.text")

local clipped, first, last, offset = text.clip("src/main.lua", 9, { side = "start" })
```

`clip(value, cells, opts?)` clips a single line to a terminal cell budget,
keeping whole display characters. The default `side = "end"` retains the
prefix, and `side = "start"` retains the suffix. The default ellipsis is
`"…"`. Set `ellipsis = false` to omit it or supply a custom string. A marker
that exceeds the budget falls back to a dot if it fits.

The returned zero-based byte range `[first, last)` identifies the retained
source text. `offset` is the byte column where that text starts in the output.
For an unchanged string the range is `[0, #value)` and the offset is zero.

## Floats

```lua
local float = require("base_tools.float")
local view = float.open({
  config = { relative = "editor", row = 2, col = 2, width = 20, height = 1, style = "minimal" },
  win_options = { wrap = false },
})
vim.api.nvim_buf_set_lines(view.buf, 0, -1, false, { "Floating text" })
view:update({ width = 28 })
view:close()
```

`open({ config, buf?, enter?, buf_options?, win_options? })` forwards `config`
to Neovim. It opens without entering the window by default. Set
`config.focusable` to control whether the window can subsequently receive focus.

The returned handle has `win` and `buf` IDs. `view:valid()` checks the window,
`view:update(config)` applies changes to the same window, and
`view:close()` closes it. Update returns false if the window has closed.
When `open` allocates the buffer, the handle owns it and releases it on close.
A supplied buffer remains under the caller's ownership and follows its own
`bufhidden` option. `float.scratch(buf_options?)` creates an unlisted scratch
buffer with `bufhidden = "hide"` by default for callers that reuse buffers.

## Development

Run from the repository root:

```sh
nvim --headless -u NONE -i NONE -n -l tests/test.lua
```

Run either module on its own with the corresponding test file.

```sh
nvim --headless -u NONE -i NONE -n -l tests/text.lua
nvim --headless -u NONE -i NONE -n -l tests/float.lua
```
