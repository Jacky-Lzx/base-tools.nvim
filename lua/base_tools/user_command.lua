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
