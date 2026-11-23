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

## Previews

```lua
local preview = require("base_tools.preview")
local view = preview.open({
  config = { relative = "editor", row = 2, col = 2, width = 24, height = 5 },
  lines = { "A document" },
  scrollbar = true,
})
view:set_lines({ "New content" })
local _, position = view:scroll(4)
view:close()
```

`preview.open(opts)` accepts the same window and buffer options as
`float.open`, optional initial `lines`, and `scrollbar = true` or a table of
scrollbar highlight options. Previews use wrapping and smooth scrolling by
default. `view:set_lines(lines)` replaces the contents, `view:update(config)`
changes the window geometry, and `view:scroll(rows)` moves the viewport
without scrolling beyond its last full page. Positive rows scroll down.
All three refresh an enabled scrollbar. External window and buffer changes
also refresh it during redraw. Use `view:set_scrollbar(opts)` to configure
or disable the scrollbar on an existing preview.

`view:position()` returns the current scroll position when the content
overflows. `view:refresh()` also refreshes the scrollbar and returns that
position. Use the progress value to display a custom label. Closing the
preview releases its auxiliary window and any buffer it owns.

## Scrollbars

```lua
local scrollbar = require("base_tools.scrollbar")
local bar = scrollbar.new({ track_highlight = "FloatBorder", thumb_highlight = "Title" })
local position = bar:update(win)
if position then
  local percent = math.floor(position.progress * 100)
end
bar:close()
```

`scrollbar.position(win)` returns `total`, `visible`, `offset`, and `progress`
for a window with content below or above the viewport. Sizes and offsets are
measured in screen rows, including wrapping and concealment. `progress` runs
from 0 at the top to 1 at the bottom.

`bar:update(win)` returns the same position and draws a one-column scrollbar
over the right border or in the gutter beside a borderless window. Call it
after scrolling, changing the content, or resizing the window. The scrollbar
closes automatically when the target window closes. A call when the content
fits or `bar:close()` also releases the scrollbar window and its buffer.
Position labels and key mappings are handled by the caller.

## Development

Run from the repository root:

```sh
nvim --headless -u NONE -i NONE -n -l tests/test.lua
```

Run each module on its own with the corresponding test file.

```sh
nvim --headless -u NONE -i NONE -n -l tests/text.lua
nvim --headless -u NONE -i NONE -n -l tests/float.lua
nvim --headless -u NONE -i NONE -n -l tests/scrollbar.lua
nvim --headless -u NONE -i NONE -n -l tests/preview.lua
```
