# base-tools.nvim

Shared utilities for Neovim plugins.

## Requirements

Neovim **0.12+**.

## Installation

Put this repository on `runtimepath` and require the module you need.
Plugins that use these modules can declare `Jacky-Lzx/base-tools.nvim` as a dependency.

## Module lifecycle

Create one lifecycle per feature and call it from the plugin's own activation points.

```lua
local view = require("base_tools.lifecycle").new("my_plugin.view", {
  setup = function(module, opts)
    module.setup(opts)
  end,
  dispose = function(module)
    module.close()
  end,
})

view:configure({ width = 24 })
-- Later, in a command or autocmd:
view:ensure().open()
-- When disabling the feature:
view:dispose()
```

`configure(opts)` saves options and applies them immediately when the module is already managed.
`ensure()` loads the module and runs setup as needed.
`peek()` returns the module only after setup succeeds.
`dispose()` releases owned resources and forgets options.
Neither configuration, inspection nor cleanup requires a cold module.
Lua's module cache is left intact.

A caller that already holds a cached module can supply it as `configure(opts, cached)` or `dispose(cached)`.
This also covers modules used through another entry point.
A setup error is propagated and the module remains eligible for another setup attempt or cleanup.
This utility uses only Lua and can be required by plugins supporting older Neovim versions.

## Timers

```lua
local timer = require("base_tools.timer").new()

timer:start(100, function()
  vim.notify("Ready")
end)
timer:cancel()
timer:close()
```

`start(delay_ms, callback)` replaces any pending callback on that timer.
The callback runs on Neovim's main loop, including when the delay is zero.
`cancel()` also invalidates callbacks already waiting in the main-loop queue.
`close()` cancels the callback and releases the timer.
Create a new timer to schedule work after closing it.

## Process groups

```lua
local group = require("base_tools.process").new()
group:run({ "git", "status", "--short" }, { cwd = vim.fn.getcwd() }, function(result, launch_error)
  if launch_error then
    vim.notify(launch_error, vim.log.levels.ERROR)
  elseif result.code == 0 then
    vim.notify(result.stdout or "")
  end
end)
-- When the caller no longer needs the result:
group:close()
```

`run(argv, opts, callback)` takes `vim.system()` arguments and schedules its completion callback on Neovim's main loop.
The callback receives the system result, including nonzero exit codes, or `nil, launch_error` if the process could not start.
`close()` marks the group cancelled, sends SIGTERM to its running processes, and skips pending completion callbacks.
It is safe to close a group more than once. Calls to `run()` on a closed group are ignored.

## Keys

```lua
local keys = require("base_tools.keys")
local sequence = keys.encode("<Left>")
vim.api.nvim_feedkeys(sequence, "n", false)
```

`encode(notation, do_lt?)` converts textual key notation to Neovim's internal key sequence.
Set `do_lt` to `true` to translate `<lt>` into a literal `<`.
Pass already encoded sequences directly to APIs that accept internal key sequences.

## Keymaps

```lua
local keymap = require("base_tools.keymap")
local bindings = keymap.resolve({
  ["<CR>"] = { "open", desc = "Open selection" },
  q = false,
}, { actions = { open = true } })

local binding = bindings[1]
local cleanup, previous = keymap.install("n", binding.lhs, function()
  vim.notify("Open selection")
end, { buffer = 0, desc = binding.desc })
-- When the caller releases the buffer:
cleanup()
```

`resolve(spec, opts)` returns `{ lhs, actions, desc }` records in key order.
Each entry accepts an action name, Lua function, action list with optional `desc`, or `false` to skip the binding.
The caller executes the action list.
Pass an action registry to validate action names, or leave it out for dynamic dispatch.
Set `check_aliases = true` to reject keys that encode to the same typed sequence.

`install(mode, lhs, callback, opts)` installs one Lua mapping in a single mode, using the options accepted by
`vim.keymap.set()`.
It returns an idempotent cleanup function and the prior mapping in the same scope, if present.
Cleanup restores that definition while the installed callback still owns the key.
With overlapping managed mappings it skips owners that have already released their mapping.

## Configuration

```lua
local validators = require("base_tools.config.validators")
local config = require("base_tools.config").new(defaults, {
  replace = { { "compare", "keymap", "panel" } },
  fields = {
    { path = { "buffer", "signs" }, validate = validators.type("boolean") },
    { path = { "buffer", "debounce" }, validate = validators.range(0, 1000) },
  },
})
local options = config:resolve(user_options)
config:commit(options, apply_options)
local signs = config:get("buffer", "signs")
config:validate({ "buffer", "debounce" }, 250)
config:change({ "buffer", "signs" }, true, apply_options)
```

Each instance owns its defaults and current configuration.
`resolve(opts?)` builds a detached candidate from defaults.
`check(candidate)` validates a full candidate without applying it or changing the current configuration.
`commit(candidate, apply?)` runs the optional validator and then the optional apply callback before publishing the
candidate.
`change(path, value, apply?)` replaces an existing value and uses the same commit flow.
Paths with missing keys and `nil` values raise an error.
`reset()` restores the original defaults.

Each entry in `fields` defines a path and a `validate(value, get)` callback.
Return `true` if the value is valid or `false, message` for an error prefixed with the option path.
The callback receives a copy of the field value.
Use `get(...)` to read a copy from the candidate, for example to check whether the field's parent section is disabled.
Full writes validate all field rules. `change()` and the read-only `validate(path, value)` validate the changed path,
its ancestor rules and any rules below a replaced section.
Use the `validate(candidate)` option for cross-field constraints such as a minimum that must not exceed another option's
maximum.
That callback sees the full candidate on every write and raises an error for invalid values.

`base_tools.config.validators` provides `type(name)`, `range(min?, max?)`, `integer(min?, max?)`, `one_of(values)`,
`optional(rule)` and `any_of(...)`.
Ranges use inclusive bounds and finite numbers. Omit either bound with `nil` to leave that side open.
`one_of` accepts a list of scalar values, and `optional` also accepts `nil`.
`any_of` tries the supplied validators in order and accepts the first successful alternative.

The optional `apply(candidate)` callback runs only after validation succeeds and raises if application fails.
The whole-config validator and apply callback receive detached copies.
If a validator or the apply callback fails, the instance keeps the previous configuration.
Writes to the same instance from inside these callbacks raise an error.

`get(...)` reads the current configuration using the same path semantics as the standalone getter below.

`merge(defaults, opts?, rules?)` merges dictionaries recursively and replaces lists.
Fields listed in `rules.replace` use the supplied value as a whole, including an empty table.
Supplied `false` values override defaults.
The returned table is detached from both inputs.

`get(config, ...)` reads a path and copies the result.
With no keys it returns a copy of the whole configuration.
Missing paths return `nil`.

## User commands

```lua
local commands = require("base_tools.user_command").new()
local cleanup = commands.create("ExampleInfo", function()
  vim.notify("Example info")
end, { desc = "Show example info" })
cleanup()
```

Keep one registry per plugin.
`create(name, callback, opts?, buffer?)` registers a command and returns a cleanup function for that registration.
`delete(name, buffer?)` removes the current command owned by that registry.
Pass a buffer number for a buffer-local command or `0` for the current buffer.
Omit the buffer to register a global command.
Registration rejects commands owned elsewhere.
Cleanup checks ownership again so a later replacement keeps its command.

Use `create_many(definitions, buffer?)` for several commands in the same scope.
Each definition is `{ name, callback, opts? }`.
The returned cleanup functions follow the definition order.
Duplicate names and ownership conflicts are checked before registration.
If Neovim rejects a later definition, earlier successes remain owned by the registry and can be removed with `delete()`.

Use `create_group(name, spec, opts?, buffer?)` when an Ex command selects an action with its first argument.

```lua
commands.create_group("Example", {
  default = "info",
  actions = {
    { name = "info", run = show_info },
    { name = "export", run = export_file, complete = { "file" } },
  },
}, { bang = true })
```

Each handler receives Neovim's original command arguments, including the action in `fargs[1]`.
Pass options such as `bang`, `range`, and `bar` directly to Neovim.
Groups default to `nargs = "*"`. Use `nargs = "+"` to require an action.
An optional `on_unknown(args)` handles unknown actions.

`complete` supplies a provider for each argument after the action.
A string delegates to a native completion type such as `"file"`.
A list or a function returning a list supplies literal candidates, matched according to `wildoptions`.
Function providers receive `lead`, `line`, `cursor`, the already completed `args` after the action, and
the one-based argument `index`.
The module's `group(name, spec, opts?)` returns a definition tuple for `create_many()`.

Set `menu = true` to add a `menu` subcommand. It uses `vim.ui.select()` to list
the actions in declaration order. Choosing a generated item fills the command
line with the action and leaves it ready for arguments or confirmation.
Set `default = "menu"` to open it when no action is supplied.

A menu table can set `prompt` and `items(defaults)`. The callback gets a fresh
copy of the generated items each time the menu opens and returns the list to
display. Each item has an `id`, a `label` and a `run()` callback. The callback
can reorder, filter, or rename items, replace their handlers, or return a
custom list.

## Colors and highlights

```lua
local color = require("base_tools.color")
local highlight = require("base_tools.highlight")

local normal = highlight.resolve("Normal")
local background = normal.bg or 0x202020
local tinted = color.mix("#89b4fa", background, 0.15)
vim.api.nvim_set_hl(0, "ExampleTint", { bg = tinted })
```

`color.mix(foreground, background, amount)` accepts RGB integers or `#rrggbb` strings and returns an RGB integer.
`amount` is the foreground weight from 0 to 1.
Use `color.hex(value)` to format an RGB value as a lowercase color string.

`highlight.resolve(name)` follows links in the global highlight namespace.
It returns the resolved definition, or an empty table for missing groups and link cycles.
Reading a group leaves its definition and the active window untouched.

## Text

```lua
local text = require("base_tools.text")

local clipped, first, last, offset = text.clip("src/main.lua", 9, { side = "start" })
```

`clip(value, cells, opts?)` clips a single line to a terminal cell budget, keeping whole display characters.
The default `side = "end"` retains the prefix, and `side = "start"` retains the suffix.
The default ellipsis is `"…"`.
Set `ellipsis = false` to omit it or supply a custom string.
A marker that exceeds the budget falls back to a dot if it fits.

The returned zero-based byte range `[first, last)` identifies the retained
source text. `offset` is the byte column where that text starts in the output.
For an unchanged string the range is `[0, #value)` and the offset is zero.

## Scratch buffers

```lua
local buffer = require("base_tools.buffer")
local buf = buffer.scratch({ bufhidden = "wipe", name = function(id)
  return "example://output/" .. id
end })

vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "Temporary output" })
vim.api.nvim_open_win(buf, false, { win = 0, split = "right" })
```

`buffer.scratch(options?)` creates an unlisted scratch buffer and applies the supplied buffer-local options.
By default, `bufhidden = "hide"` keeps the buffer available for reuse.
Use `bufhidden = "wipe"` to delete it when its last window stops displaying it.
An optional `name` sets the buffer name before applying the supplied options.
Pass a string or a function that receives the new buffer ID and returns the name.
If naming or setting options fails, the function deletes the new buffer.

## Window footers

```lua
local footer = require("base_tools.footer").attach(win, {
  left = "Enter: open  q: close",
  right = "5 files",
})
footer:update({ right = "7 files" })
footer:close()
```

A footer uses the local statusline for the buffer displayed in `win`.
Neovim's `laststatus` option controls where the statusline is visible.
Labels are plain text. When the window is narrow, the right label is hidden
before trimming the left label to the available display width.

`update(opts)` replaces only the supplied labels. An empty string clears a
label. `close()` restores the previous local statusline if the footer still
owns it. A window can display another buffer with its own statusline, and the
footer becomes visible again when its buffer returns. Attaching a new footer
to the same window and buffer replaces the earlier one.

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

`open({ config, buf?, enter?, buf_options?, win_options? })` forwards `config` to Neovim.
It opens without entering the window by default.
Set `config.focusable` to control whether the window can subsequently receive focus.

The returned handle has `win` and `buf` IDs.
`view:valid()` checks the window, `view:update(config)` applies changes to the same window,
and `view:close()` closes it.
Update returns false if the window has closed.
When `open` allocates the buffer, the handle owns it and releases it on close.
A supplied buffer remains under the caller's ownership and follows its own `bufhidden` option.
`float.scratch(buf_options?)` is an alias for `buffer.scratch(buf_options?)`.

### Border labels

Set any of the left, center, and right positions on the top and bottom
borders of a float:

```lua
local float = require("base_tools.float")
local label = require("base_tools.label")
local view = float.open({
  config = {
    relative = "editor", row = 2, col = 2, width = 48, height = 8, border = "rounded",
  },
  border_labels = {
    top = {
      left = label.filename("lua/base_tools/float.lua"),
      center = " Lua ",
      right = " LuaLS ",
    },
    bottom = {
      left = label.path("lua/base_tools/float.lua", { highlight = "Comment" }),
      right = { { " 42% ", "DiagnosticInfo" } },
    },
  },
})

view:set_border_labels({ bottom = { right = " 100% " } })
view:set_border_labels({ top = { center = false } })
```

A slot accepts a single-line string, Neovim-style `{text, highlight}` chunks, or a file label with `kind`, `value`,
and an optional `highlight`.
Use `kind = "path"` to display the supplied path, or `kind = "filename"` to display its last component.
Path labels shorten from the start to keep the filename visible on narrow windows.
Both kinds show control characters in printable form and work with `view:set_border_labels()`.
The `label.path(path, opts?)` and `label.filename(path, opts?)` constructors return these tables and accept
an optional `opts.highlight`.

Omitted slots retain their values.
Pass `false`, an empty string, an empty list, or a file label with an empty `value` to clear a slot.
Pass `top = false` or `bottom = false` to clear a whole edge.
Clearing the last slot restores that edge's native title or footer, if configured.

Labels track window width in display cells.
Left and right take precedence when space is tight.
The center stays centered and may be shortened or hidden.
An edge needs a visible horizontal border to display its labels.

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

`preview.open(opts)` accepts the same window and buffer options as `float.open`, optional initial `lines`,
and `scrollbar = true` or a table of scrollbar highlight options.
The float's `border_labels` option and `view:set_border_labels()` are also available on previews.
Previews use wrapping and smooth scrolling by default.
`view:set_lines(lines)` replaces the contents, `view:update(config)` changes the window geometry,
and `view:scroll(rows)` moves the viewport without scrolling beyond its last full page.
Positive rows scroll down.

`view:fit_height({ max_height = 12 })` fits the height at the current width, accounting for wrapping and concealed lines.
It returns the resulting window height, or `nil` if the preview is closed.
The height is at least one row.
Call it again after changing the width or contents when you want to refit.
Use `view:content_height({ max_height = 12 })` to measure the same height without resizing, then include that height
in an update alongside the window position.

Use `view:set_content({ lines = lines, border_labels = labels })` to replace the contents and update selected border
slots in one call.
For example, when switching to another file:

```lua
local label = require("base_tools.label")
view:set_content({
  lines = new_lines,
  border_labels = { top = { left = label.filename(new_path) } },
})
```

Omitted border slots retain their values.
The scrollbar and any scroll percentage labels use the new contents immediately.
All three refresh an enabled scrollbar.
External window and buffer changes also refresh it during redraw.
Use `view:set_scrollbar(opts)` to configure or disable the scrollbar on an existing preview.

Set `scroll = "top"` on `view:set_content()` to reset the cursor and viewport when switching items.
Use `scroll = "keep"` to keep the current row and wrapped row offset where possible.
If the replacement is shorter, the viewport adjusts to the new content.
Omitting `scroll` leaves placement to Neovim.

Pass `language = "lua"` to `preview.open()` or `view:set_content()` to enable Tree-sitter highlighting.
Omit `language` to keep the current highlighter, or use `language = false` to clear highlighting started by the preview.
A missing parser leaves the contents readable as plain text.
An existing external Tree-sitter highlighter stays under the caller's control.

`view:position()` returns the current scroll position when the content overflows.
`view:refresh()` also refreshes the scrollbar and returns that position.
Use the progress value to display a custom label.
Closing the preview releases its auxiliary window and any buffer it owns.

A preview label can also use `label.scroll_percent(opts?)`, which returns
a `{ kind = "scroll_percent", highlight = ... }` table:

```lua
local label = require("base_tools.label")
local border_labels = {
  bottom = { right = label.scroll_percent({ highlight = "Comment" }) },
}
```

The percentage updates when the preview scrolls, changes size, or receives new content.
It is visible on overflow and works independently of the `scrollbar` option.

For `bottom.right`, set `label.scroll_percent({ fallback = "below" })` to show the percentage just below the right edge
when the window has no horizontal bottom border.
It follows external scrolling and resize events and appears only when the content overflows and there is room below.

Use `preview.attach(win, opts?)` when another API creates the float.
The options accept `scrollbar` and `border_labels`.
For example:

```lua
local label = require("base_tools.label")
local view = require("base_tools.preview").attach(win, {
  scrollbar = true,
  border_labels = { bottom = { right = label.scroll_percent({ arrows = true }) } },
})
view:detach()
```

The original caller owns the window, buffer, and local options.
Repeated calls return the current attachment.
Use its setters to update the options.
`view:detach()` removes the preview decorations and restores the original title and footer.
Closing the window also releases the attachment.
`arrows = true` adds indicators for directions with content remaining.

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

`scrollbar.position(win)` returns `total`, `visible`, `offset`, and `progress` for a window with content below or above
the viewport.
Sizes and offsets are measured in screen rows, including wrapping and concealment.
`progress` runs from 0 at the top to 1 at the bottom.

`bar:update(win)` returns the same position and draws a one-column scrollbar over the right border or in the gutter
beside a borderless window.
Call it after scrolling, changing the content, or resizing the window.
The scrollbar closes automatically when the target window closes.
A call when the content fits or `bar:close()` also releases the scrollbar window and its buffer.
Position labels and key mappings are handled by the caller.

## Markdown

Use `format = "markdown"` in `preview.open()`, `preview.attach()`, or `view:set_content()` to render documentation.
The preview starts Tree-sitter highlighting, hides code fence rows, and draws thematic breaks at the window width.
The buffer retains the original Markdown.

```lua
view:set_content({
  lines = lines,
  format = "markdown",
  markdown = { rule_highlight = "FloatBorder" },
})
```

Use `language = "markdown"` for syntax highlighting in a source preview. `view:set_format("markdown", opts?)` changes
the presentation of existing contents, and `view:set_format(false)` restores the window's conceal options and clears
the document decorations.
`view:markdown_rows()` returns the hidden delimiter rows and all fenced rows as 1-based sets for custom navigation.

Call `require("base_tools.markdown").conceal_fences(buf, ns)` to hide whole Markdown fence rows using extmarks in
a caller-owned namespace.
The original text remains available to parsers and for copying.
The helper returns two 1-based sets of rows, one for hidden delimiters and one for all lines in fenced blocks.
When the Markdown parser is unavailable, it recognizes simple backtick and tilde fences.

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
nvim --headless -u NONE -i NONE -n -l tests/border_labels.lua
```
