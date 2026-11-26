require("base_tools")

local Context = require("base_tools.context")

local M = {}

---@class base_tools.ConfigChoiceDefaults
---@field path (string|integer)[] Path to the choice.
---@field defaults table Defaults for its table branch.

---@class base_tools.ConfigMergeRules
---@field replace (string|integer)[][] Paths whose supplied values replace their defaults.
---@field choice_defaults base_tools.ConfigChoiceDefaults[] Table branch defaults, with ancestors first.

---@class base_tools.ConfigRules: base_tools.ConfigMergeRules
---@field fields base_tools.ConfigField[] Validators in application order.

local function check_key(key, check)
  check(
    type(key) == "string" or (type(key) == "number" and key % 1 == 0),
    "Config path keys must be strings or integers"
  )
end

local function check_path(path, check)
  check(vim.islist(path) and #path > 0, "Config path must be a nonempty list")
  for _, key in ipairs(path) do
    check_key(key, check)
  end
end

local function apply_choice_defaults(defaults, overrides, choices)
  for _, choice in ipairs(choices) do
    local path = choice.path

    if
      type(vim.tbl_get(overrides, unpack(path))) == "table" and type(vim.tbl_get(defaults, unpack(path))) ~= "table"
    then
      local parent = defaults
      for i = 1, #path - 1 do
        local key = path[i]
        if type(parent[key]) ~= "table" then
          parent[key] = {}
        end

        parent = parent[key]
      end

      parent[path[#path]] = vim.deepcopy(choice.defaults)
    end
  end
end

local function merge(defaults, opts, rules, check)
  check(opts == nil or type(opts) == "table", "Config options must be a table")

  local overrides = vim.deepcopy(opts or {})
  local base = vim.deepcopy(defaults)
  apply_choice_defaults(base, overrides, rules.choice_defaults)

  local merged = vim.tbl_deep_extend("force", base, overrides)

  for _, path in ipairs(rules.replace) do
    local value = vim.tbl_get(overrides, unpack(path))
    if value ~= nil then
      local parent = merged
      for i = 1, #path - 1 do
        parent = parent[path[i]]
      end

      parent[path[#path]] = value
    end
  end

  return merged
end

local function get_value(config, ...)
  if select("#", ...) == 0 then
    return vim.deepcopy(config)
  end

  return vim.deepcopy(vim.tbl_get(config, ...))
end

---@class base_tools.Config
---@field private _defaults table
---@field private _current table
---@field private _context? base_tools.Context
---@field private _rules base_tools.ConfigRules
---@field private _committing? boolean
local Config = {}
Config.__index = Config

---@class base_tools.ConfigSection
---@field private _config base_tools.Config
---@field private _path (string|integer)[]
---@field private _rules base_tools.ConfigMergeRules
local Section = {}
Section.__index = Section

---@alias base_tools.ConfigFieldValidator fun(value: any, get: fun(...: string|integer): any): boolean, string?

---@class base_tools.ConfigDefinitionEntry
---@field default? any Default value. Sections otherwise derive their default from their fields.
---@field validate? base_tools.ConfigFieldValidator Validate the value or the enabled section.
---@field replace? boolean Replace the default when a value is supplied, including an empty table.
---@field fields? table<string|integer, base_tools.ConfigDefinitionEntry> Child definitions for a section.
---@field choices? table<string|integer, base_tools.ConfigDefinitionChoice> Named literal and section alternatives.
---@field default_choice? string|integer Name of the default alternative.

---@class base_tools.ConfigDefinitionChoice
---@field value? string|number|boolean Literal alternative.
---@field fields? table<string|integer, base_tools.ConfigDefinitionEntry> Section alternative.
---@field default? table Override the defaults derived for a section alternative.
---@field validate? base_tools.ConfigFieldValidator Validate an active section alternative.

---@class base_tools.ConfigField
---@field path (string|integer)[]
---@field validate base_tools.ConfigFieldValidator Return true or false with a message describing the required value.
---@field skip_children? boolean Skip descendant rules for a valid non-table choice.

local function validate_section(value)
  return type(value) == "table", "must be table"
end

local function sorted_keys(values, check)
  local keys = vim.tbl_keys(values)
  for _, key in ipairs(keys) do
    check_key(key, check)
  end
  table.sort(keys, function(a, b)
    if type(a) == type(b) then
      return a < b
    end
    return type(a) == "number"
  end)
  return keys
end

local compile_definition

local function compile_section(entry, path, rules, visited, check)
  local defaults = compile_definition(entry.fields, path, rules, visited, check)
  local validate = entry.validate
  check(validate == nil or type(validate) == "function", "Config definition validate must be a function")
  if validate then
    rules.section_checks[#rules.section_checks + 1] = {
      path = path,
      validate = function(value, get)
        if type(value) == "table" then
          return validate(value, get)
        end
        return true
      end,
    }
  end
  if entry.default ~= nil then
    defaults = vim.deepcopy(entry.default)
  end
  return defaults
end

local function compile_choices(entry, path, rules, visited, check)
  local choices = entry.choices
  check(type(choices) == "table", "Config choices must be a table")
  local selected = choices[entry.default_choice]
  check(type(selected) == "table", "Config default_choice must name an existing choice")

  local literals, labels, section = {}, {}, nil
  for _, name in ipairs(sorted_keys(choices, check)) do
    local choice = choices[name]
    check(type(choice) == "table", "Config choices must be tables")
    if choice.fields ~= nil then
      check(choice.value == nil, "A config choice must declare fields or a literal value")
      check(choice.default == nil or type(choice.default) == "table", "A section choice default must be a table")
      check(not section, "Config choices may contain at most one section")
      section = choice
    else
      local value = choice.value
      local kind = type(value)
      check(choice.default == nil and choice.validate == nil, "A literal config choice is defined by its value")
      check(
        kind == "boolean" or kind == "string" or (kind == "number" and value == value),
        "A literal config choice must be a boolean, string or number"
      )
      check(not vim.tbl_contains(literals, value), "Literal config choices must be distinct")
      literals[#literals + 1] = value
      labels[#labels + 1] = vim.inspect(value)
    end
  end

  local has_section = section ~= nil
  if has_section then
    table.insert(labels, 1, "a table")
  end
  local message = "must be " .. table.concat(labels, " or ")
  rules.fields[#rules.fields + 1] = {
    path = path,
    validate = function(value)
      return (has_section and type(value) == "table") or vim.tbl_contains(literals, value), message
    end,
    skip_children = has_section,
  }

  if not section then
    return selected.value
  end
  local choice = { path = path }
  rules.choice_defaults[#rules.choice_defaults + 1] = choice
  choice.defaults = compile_section(section, path, rules, visited, check)
  if selected == section then
    return choice.defaults
  end
  return selected.value
end

compile_definition = function(definition, prefix, rules, visited, check)
  check(type(definition) == "table", "Config definition must be a table of options")
  check(not visited[definition], "Config definition cannot contain cycles")
  visited[definition] = true

  local defaults = {}
  for _, key in ipairs(sorted_keys(definition, check)) do
    local entry = definition[key]
    check(type(entry) == "table", "Config definition entries must be tables")
    local path = vim.list_extend(vim.list_slice(prefix), { key })
    local validate = entry.validate
    check(validate == nil or type(validate) == "function", "Config definition validate must be a function")
    check(entry.replace == nil or type(entry.replace) == "boolean", "Config definition replace must be boolean")
    check(entry.allow == nil, "Config definitions use choices for alternate values")
    check(entry.choices ~= nil or entry.default_choice == nil, "Config default_choice requires choices")
    if entry.replace then
      rules.replace[#rules.replace + 1] = path
    end

    if entry.choices ~= nil then
      check(entry.fields == nil and entry.default == nil, "Config choices define their own fields and default")
      defaults[key] = compile_choices(entry, path, rules, visited, check)
      if validate then
        rules.section_checks[#rules.section_checks + 1] = { path = path, validate = validate }
      end
    elseif entry.fields ~= nil then
      rules.fields[#rules.fields + 1] = { path = path, validate = validate_section }
      defaults[key] = compile_section(entry, path, rules, visited, check)
    else
      if validate then
        rules.fields[#rules.fields + 1] = { path = path, validate = validate }
      end
      defaults[key] = vim.deepcopy(entry.default)
    end
  end

  visited[definition] = nil
  return defaults
end

local function intersects(left, right)
  for i = 1, math.min(#left, #right) do
    if left[i] ~= right[i] then
      return false
    end
  end
  return true
end

local function below_skipped_section(path, skipped)
  for _, section in ipairs(skipped) do
    if #section < #path and intersects(section, path) then
      return true
    end
  end
  return false
end

local function validate_and_apply(self, snapshot, path, apply, check)
  check(not self._committing, "Cannot validate or write config from a validation or apply callback")

  local fields = self._rules.fields
  if #fields == 0 and not apply then
    return
  end

  self._committing = true
  local ok, err = pcall(function()
    local function get(...)
      return get_value(snapshot, ...)
    end

    local skipped
    for _, field in ipairs(fields) do
      if
        (not path or intersects(path, field.path)) and (not skipped or not below_skipped_section(field.path, skipped))
      then
        local value = get(unpack(field.path))
        local valid, message = field.validate(value, get)
        if valid ~= true then
          check(false, table.concat(field.path, ".") .. " " .. (message or "is invalid"), 0)
        end
        if field.skip_children and type(value) ~= "table" then
          skipped = skipped or {}
          skipped[#skipped + 1] = field.path
        end
      end
    end

    if apply then
      apply(get())
    end
  end)

  self._committing = false
  if not ok then
    error(err, 0)
  end
end

local function commit(self, candidate, path, apply, check)
  check(apply == nil or type(apply) == "function", "Config apply must be a function")
  validate_and_apply(self, candidate, path, apply, check)
  self._current = candidate
end

---Read the current configuration or a value at the given path as a copy.
---@param ... string|integer
---@return any
function Config:get(...)
  return get_value(self._current, ...)
end

---Build and validate a candidate from defaults without changing the current configuration.
---@param opts? table
---@return table
function Config:resolve(opts)
  local check = Context.checker(self._context, "config.resolve")
  local candidate = merge(self._defaults, opts, self._rules, check)
  validate_and_apply(self, candidate, nil, nil, check)
  return candidate
end

---Resolve, validate and apply options using the original defaults as the starting point.
---@param opts? table
---@param apply? fun(candidate: table) Apply the validated configuration, raising on failure.
function Config:configure(opts, apply)
  local check = Context.checker(self._context, "config.configure")
  commit(self, merge(self._defaults, opts, self._rules, check), nil, apply, check)
end

---Restore the original defaults.
function Config:reset()
  local check = Context.checker(self._context, "config.reset")
  commit(self, vim.deepcopy(self._defaults), nil, nil, check)
end

local function has_field(self, path)
  for _, field in ipairs(self._rules.fields) do
    if #field.path == #path and intersects(field.path, path) then
      return true
    end
  end
  return false
end

local function with_change(self, path, value, check)
  check_path(path, check)

  local candidate = self:get()
  local parent = candidate
  if #path > 1 then
    parent = vim.tbl_get(parent, unpack(path, 1, #path - 1))
  end

  local key = path[#path]
  if type(parent) ~= "table" then
    check(false, "Config path does not exist: " .. vim.inspect(path), 0)
  end
  local present = rawget(parent, key) ~= nil
  local declared = (not present or value == nil) and has_field(self, path)
  if not present and not declared then
    check(false, "Config path does not exist: " .. vim.inspect(path), 0)
  end
  check(value ~= nil or declared, "Config value must not be nil without a field rule")

  parent[key] = vim.deepcopy(value)
  return candidate
end

local function validate_change(config, path, value, check)
  validate_and_apply(config, with_change(config, path, value, check), vim.deepcopy(path), nil, check)
end

---Check a proposed replacement using the same rules as change(), without applying it.
---@param path (string|integer)[]
---@param value any
function Config:validate(path, value)
  validate_change(self, path, value, Context.checker(self._context, "config.validate"))
end

---Get a live view of a path in this configuration.
---@param ... string|integer
---@return base_tools.ConfigSection
function Config:section(...)
  local check = Context.checker(self._context, "config.section")
  local path = { ... }
  check(#path == select("#", ...), "Config path keys must be strings or integers")
  check_path(path, check)

  -- Keep the final section key so rules for the section itself also apply.
  local function relative(rule_path)
    if #rule_path >= #path and intersects(path, rule_path) then
      return vim.list_slice(rule_path, #path)
    end
  end

  local rules = { replace = {}, choice_defaults = {} }
  for _, rule_path in ipairs(self._rules.replace) do
    local scoped = relative(rule_path)
    if scoped then
      rules.replace[#rules.replace + 1] = scoped
    end
  end
  for _, choice in ipairs(self._rules.choice_defaults) do
    local scoped = relative(choice.path)
    if scoped then
      rules.choice_defaults[#rules.choice_defaults + 1] = { path = scoped, defaults = choice.defaults }
    end
  end

  return setmetatable({ _config = self, _path = path, _rules = rules }, Section)
end

---Read a detached value at a path relative to this section.
---@param ... string|integer
---@return any
function Section:get(...)
  local path = vim.list_extend(vim.list_slice(self._path), { ... })
  return self._config:get(unpack(path))
end

---Merge and validate a temporary section from its current value.
---Omit overrides to read a copy of the current section.
---@param opts? table
---@return any
function Section:merge(opts)
  if opts == nil then
    return self:get()
  end
  local config, path = self._config, self._path
  local check = Context.checker(config._context, "config.section.merge")
  check(type(opts) == "table", "Config options must be a table")
  local key = path[#path]
  local current = vim.tbl_get(config._current, unpack(path))
  local candidate = merge({ [key] = current }, { [key] = opts }, self._rules, check)[key]
  validate_change(config, path, candidate, check)
  return candidate
end

---Replace a value or set/clear a declared field and validate before publishing.
---@param path (string|integer)[]
---@param value any
---@param apply? fun(candidate: table) Apply the validated configuration, raising on failure.
function Config:change(path, value, apply)
  local check = Context.checker(self._context, "config.change")
  commit(self, with_change(self, path, value, check), vim.deepcopy(path), apply, check)
end

---Set or invert an existing boolean option through the normal write flow.
---@param path (string|integer)[]
---@param value? boolean Invert the current value when omitted.
---@param apply? fun(candidate: table) Apply the validated configuration, raising on failure.
---@return boolean value The new value.
function Config:toggle(path, value, apply)
  local check = Context.checker(self._context, "config.toggle")
  check_path(path, check)
  local current = vim.tbl_get(self._current, unpack(path))
  if type(current) ~= "boolean" then
    check(false, table.concat(path, ".") .. " must be boolean to toggle", 0)
  end
  if value == nil then
    value = not current
  elseif type(value) ~= "boolean" then
    check(false, table.concat(path, ".") .. " must be boolean", 0)
  end

  commit(self, with_change(self, path, value, check), vim.deepcopy(path), apply, check)
  return value
end

---Create an independent configuration from an option definition.
---@param definition table<string|integer, base_tools.ConfigDefinitionEntry>
---@param opts? { context?: base_tools.Context }
---@return base_tools.Config
function M.new(definition, opts)
  local context = opts and opts.context
  local check = Context.checker(context, "config.new")
  local rules = { replace = {}, choice_defaults = {}, fields = {}, section_checks = {} }
  local initial = compile_definition(definition, {}, rules, {}, check)
  vim.list_extend(rules.fields, rules.section_checks)
  rules.section_checks = nil

  local config = setmetatable({
    _defaults = initial,
    _context = context,
    _rules = rules,
  }, Config)
  commit(config, vim.deepcopy(initial), nil, nil, check)

  return config
end

return M
