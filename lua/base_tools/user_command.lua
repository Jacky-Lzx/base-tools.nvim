require("base_tools")

local M = {}
local api = vim.api

--- Ex command text or a Lua handler receiving Neovim's command arguments.
---@alias base_tools.UserCommandCallback string|fun(args: vim.api.keyset.create_user_command.command_args)

--- Tuple of command name, handler and optional Neovim command options.
---@alias base_tools.UserCommandDefinition [string, base_tools.UserCommandCallback, vim.api.keyset.user_command?]

--- Removes the corresponding registration while it still belongs to the registry.
---@alias base_tools.UserCommandCleanup fun()

local owners = setmetatable({}, { __mode = "k" })
local wipeout

local function snapshot(buffer)
  return buffer and api.nvim_buf_get_commands(buffer, {}) or api.nvim_get_commands({})
end

local function check_owner(name, existing, previous)
  if existing and not (previous and vim.deep_equal(existing, previous)) then
    error("Command already exists: " .. name)
  end
end

local function install(name, callback, opts, buffer, replace)
  opts = vim.tbl_extend("force", {}, opts or {}, { force = replace })
  local action = callback

  -- Give each registration its own Lua callback identity.
  if type(callback) == "function" then
    action = function(args)
      return callback(args)
    end
  end

  if buffer then
    api.nvim_buf_create_user_command(buffer, name, action, opts)
  else
    api.nvim_create_user_command(name, action, opts)
  end
end

local function remove_if_current(name, buffer, installed)
  if not installed or (buffer and not api.nvim_buf_is_valid(buffer)) then
    return false
  end

  if not vim.deep_equal(snapshot(buffer)[name], installed) then
    return false
  end

  if buffer then
    api.nvim_buf_del_user_command(buffer, name)
  else
    api.nvim_del_user_command(name)
  end
  return true
end

---@class base_tools.UserCommandContext
---@field lead string Current argument prefix from Neovim.
---@field line string Full command line.
---@field cursor integer Byte position of the cursor.
---@field args string[] Completed arguments after the action name.
---@field index integer Position of the argument being completed, starting at 1.

---@alias base_tools.UserCommandProvider string|string[]|fun(ctx: base_tools.UserCommandContext): string[]

---@class base_tools.UserCommandAction
---@field name string
---@field run fun(args: vim.api.keyset.create_user_command.command_args)
---@field complete? table<integer, base_tools.UserCommandProvider> Providers by argument position.

---@class base_tools.UserCommandGroup
---@field actions base_tools.UserCommandAction[] Actions in completion order.
---@field default? string Action to run when the command has no arguments.
---@field on_unknown? fun(args: vim.api.keyset.create_user_command.command_args)

local function match(candidates, lead)
  if lead == "" then
    return candidates
  end
  if vim.tbl_contains(vim.opt.wildoptions:get(), "fuzzy") then
    return vim.fn.matchfuzzy(candidates, lead)
  end
  return vim.tbl_filter(function(value)
    return vim.startswith(value, lead)
  end, candidates)
end

--- Build a command definition for use with a registry's create_many().
---@param name string
---@param spec base_tools.UserCommandGroup
---@param opts? vim.api.keyset.user_command
---@return base_tools.UserCommandDefinition
function M.group(name, spec, opts)
  assert(
    type(spec) == "table" and type(spec.actions) == "table" and vim.islist(spec.actions),
    "Command group actions must be a list"
  )

  spec = vim.deepcopy(spec)
  local options = vim.tbl_extend("force", { nargs = "*" }, opts or {})
  assert(options.nargs == "*" or options.nargs == "+", "Command groups require nargs=* or nargs=+")

  local escapes = options.bar and '[ \t\\|"]' or "[ \t\\]"
  local function escape_candidate(value)
    -- User command fargs unescapes separators and backslashes.
    return (value:gsub(escapes, "\\%0"))
  end

  local actions, names = {}, {}
  for _, action in ipairs(spec.actions) do
    assert(
      type(action) == "table" and type(action.name) == "string" and action.name:match("^%S+$"),
      "Expected a subcommand name"
    )
    assert(type(action.run) == "function", "Expected a handler for " .. action.name)
    assert(action.complete == nil or type(action.complete) == "table", "Expected completion providers by position")
    assert(not actions[action.name], "Duplicate action: " .. action.name)

    actions[action.name] = action
    names[#names + 1] = escape_candidate(action.name)
  end

  assert(spec.default == nil or actions[spec.default], "Unknown default action: " .. tostring(spec.default))
  assert(spec.on_unknown == nil or type(spec.on_unknown) == "function", "Expected an unknown action handler")

  options.complete = function(lead, line, cursor)
    -- Leave only completed words before the cursor for Neovim's Ex parser.
    local ok, parsed = pcall(api.nvim_parse_cmd, line:sub(1, cursor - #lead), {})
    while ok and parsed.nextcmd ~= "" do
      ok, parsed = pcall(api.nvim_parse_cmd, parsed.nextcmd, {})
    end

    if not ok or parsed.cmd ~= name then
      return {}
    end

    local args = parsed.args
    local index = #args
    if index == 0 then
      return match(names, lead)
    end

    local action = actions[args[1]]
    local provider = action and action.complete and action.complete[index]
    if not provider then
      return {}
    end

    local native = type(provider) == "string"
    local candidates = provider
    if native then
      candidates = vim.fn.getcompletion(lead, provider, true)
    elseif type(provider) == "function" then
      candidates =
        provider({ lead = lead, line = line, cursor = cursor, args = vim.list_slice(args, 2), index = index })
    end

    local values = vim.tbl_map(escape_candidate, candidates)

    return native and values or match(values, lead)
  end

  local function run(args)
    local action_name = args.fargs[1] or spec.default
    local action = actions[action_name]
    if action then
      return action.run(args)
    end

    if spec.on_unknown then
      return spec.on_unknown(args)
    end

    error("Unknown " .. name .. " action: " .. (action_name or ""), 0)
  end

  return { name, run, options }
end

--- Create an isolated registry for a consumer's global and buffer-local commands.
---@return base_tools.UserCommandRegistry
function M.new()
  ---@class base_tools.UserCommandRegistry
  local registry = {}
  local owned = {}
  owners[owned] = true
  if not wipeout then
    wipeout = api.nvim_create_autocmd("BufWipeout", {
      callback = function(event)
        for commands in pairs(owners) do
          commands[event.buf] = nil
        end
      end,
    })
  end

  local function remember(name, buffer, installed)
    local scope = buffer or 0
    owned[scope][name] = installed

    return function()
      local commands = owned[scope]
      if commands and commands[name] == installed and remove_if_current(name, buffer, installed) then
        commands[name] = nil
      end
    end
  end

  --- Register a command or replace the registry's existing definition.
  ---@param name string User command name starting with an uppercase letter.
  ---@param callback base_tools.UserCommandCallback
  ---@param opts? vim.api.keyset.user_command Neovim command options. Ownership controls `force`.
  ---@param buffer? integer Buffer number, `0` for the current buffer, or omitted for global scope.
  ---@return base_tools.UserCommandCleanup cleanup
  function registry.create(name, callback, opts, buffer)
    if buffer == 0 then
      buffer = api.nvim_get_current_buf()
    end

    local scope = buffer or 0
    owned[scope] = owned[scope] or {}
    local existing = snapshot(buffer)[name]
    check_owner(name, existing, owned[scope][name])
    install(name, callback, opts, buffer, existing ~= nil)
    return remember(name, buffer, snapshot(buffer)[name])
  end

  --- Register an ordered group of subcommands with positional completion.
  ---@param name string
  ---@param spec base_tools.UserCommandGroup
  ---@param opts? vim.api.keyset.user_command
  ---@param buffer? integer
  ---@return base_tools.UserCommandCleanup
  function registry.create_group(name, spec, opts, buffer)
    local definition = M.group(name, spec, opts)
    return registry.create(definition[1], definition[2], definition[3], buffer)
  end

  --- Register a batch in one scope using shared command snapshots.
  --- Checks duplicate names and ownership conflicts before installing any command.
  --- Successful registrations keep their ownership if a later registration fails.
  ---@param definitions base_tools.UserCommandDefinition[] Ordered command definitions.
  ---@param buffer? integer Buffer number, `0` for the current buffer, or omitted for global scope.
  ---@return base_tools.UserCommandCleanup[] cleanups Cleanup functions in definition order.
  function registry.create_many(definitions, buffer)
    if #definitions == 0 then
      return {}
    end

    if buffer == 0 then
      buffer = api.nvim_get_current_buf()
    end

    local scope = buffer or 0
    owned[scope] = owned[scope] or {}
    local before, seen = snapshot(buffer), {}
    for _, definition in ipairs(definitions) do
      local name = definition[1]
      assert(not seen[name], "Duplicate command in batch: " .. name)
      seen[name] = true
      check_owner(name, before[name], owned[scope][name])
    end

    local count = 0
    local ok, err = pcall(function()
      for i, definition in ipairs(definitions) do
        local name, callback, opts = definition[1], definition[2], definition[3]
        install(name, callback, opts, buffer, before[name] ~= nil)
        count = i
      end
    end)

    local cleanups = {}
    if count > 0 then
      -- Keep ownership of commands created before a later registration failed.
      local after = snapshot(buffer)
      for i = 1, count do
        local name = definitions[i][1]
        cleanups[i] = remember(name, buffer, after[name])
      end
    end

    if not ok then
      error(err, 0)
    end

    return cleanups
  end

  --- Delete a command whose current definition is owned by this registry.
  ---@param name string
  ---@param buffer? integer Buffer number, `0` for the current buffer, or omitted for global scope.
  function registry.delete(name, buffer)
    if buffer == 0 then
      buffer = api.nvim_get_current_buf()
    end

    local commands = owned[buffer or 0]
    if commands then
      remove_if_current(name, buffer, commands[name])
      commands[name] = nil
    end
  end

  return registry
end

return M
