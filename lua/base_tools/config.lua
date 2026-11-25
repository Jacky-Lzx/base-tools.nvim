require("base_tools")

local M = {}

---@class base_tools.ConfigMergeRules
---@field replace? (string|integer)[][] Paths whose supplied values replace their defaults.

--- Merge overrides into defaults and return a detached configuration.
---@param defaults table
---@param opts? table
---@param rules? base_tools.ConfigMergeRules
---@return table
function M.merge(defaults, opts, rules)
  assert(type(defaults) == "table", "Config defaults must be a table")
  assert(opts == nil or type(opts) == "table", "Config options must be a table")
  assert(rules == nil or type(rules) == "table", "Config merge rules must be a table")

  local overrides = vim.deepcopy(opts or {})
  local merged = vim.tbl_deep_extend("force", vim.deepcopy(defaults), overrides)

  local replace = rules and rules.replace
  assert(replace == nil or vim.islist(replace), "Config replacement paths must be a list")

  for _, path in ipairs(replace or {}) do
    assert(vim.islist(path) and #path > 0, "Config replacement paths must be nonempty lists")
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

--- Read a copy of the full configuration or a value at the given path.
---@param config table
---@param ... string|integer
---@return any
function M.get(config, ...)
  if select("#", ...) == 0 then
    return vim.deepcopy(config)
  end

  return vim.deepcopy(vim.tbl_get(config, ...))
end

---@class base_tools.Config
---@field private _defaults table
---@field private _current table
---@field private _options? base_tools.ConfigOptions
---@field private _committing? boolean
local Config = {}
Config.__index = Config

---@class base_tools.ConfigOptions : base_tools.ConfigMergeRules
---@field validate? fun(candidate: table) Raise an error if the candidate is invalid.
---@field schema? base_tools.ConfigSchema Nested rules, compiled when the instance is created.
---@field fields? base_tools.ConfigField[] Additional rules, run after the schema in list order.

---@alias base_tools.ConfigFieldValidator fun(value: any, get: fun(...: string|integer): any): boolean, string?
---@alias base_tools.ConfigSectionAllow fun(value: any): boolean, string?
---@alias base_tools.ConfigSchema table<string|integer, base_tools.ConfigFieldValidator|base_tools.ConfigSchema|base_tools.ConfigSection>

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

---@class base_tools.ConfigSectionOptions
---@field allow? base_tools.ConfigSectionAllow Accept a non-table value and skip child rules.

---@class base_tools.ConfigSection
---@field private schema base_tools.ConfigSchema
---@field private allow? base_tools.ConfigSectionAllow
local Section = {}

---@class base_tools.ConfigField
---@field path (string|integer)[]
---@field validate base_tools.ConfigFieldValidator Return true or false with a message describing the required value.

---Declare a group of schema rules with an optional non-table alternative.
---@param schema base_tools.ConfigSchema
---@param options? base_tools.ConfigSectionOptions
---@return base_tools.ConfigSection
function M.section(schema, options)
  assert(type(schema) == "table" and getmetatable(schema) ~= Section, "Config section rules must be a schema table")
  assert(options == nil or type(options) == "table", "Config section options must be a table")
  local allow = options and options.allow
  assert(allow == nil or type(allow) == "function", "Config section allow must be a function")
  return setmetatable({ schema = schema, allow = allow }, Section)
end

local function check_key(key)
  assert(
    type(key) == "string" or (type(key) == "number" and key % 1 == 0),
    "Config path keys must be strings or integers"
  )
end

local function check_path(path)
  assert(vim.islist(path) and #path > 0, "Config path must be a nonempty list")
  for _, key in ipairs(path) do
    check_key(key)
  end
end

local function section_validator(allow)
  return function(value)
    if type(value) == "table" then
      return true
    end
    if allow then
      local valid, message = allow(value)
      return valid, message or "must be a table or an allowed value"
    end
    return false, "must be table"
  end
end

local function sorted_keys(values)
  local keys = vim.tbl_keys(values)
  for _, key in ipairs(keys) do
    check_key(key)
  end
  table.sort(keys, function(a, b)
    if type(a) == type(b) then
      return a < b
    end
    return type(a) == "number"
  end)
  return keys
end

local function add_schema_fields(fields, schema, prefix, visited)
  assert(not visited[schema], "Config schema cannot contain cycles")
  visited[schema] = true
  for _, key in ipairs(sorted_keys(schema)) do
    local rule = schema[key]
    local path = vim.list_extend(vim.list_slice(prefix), { key })
    if type(rule) == "function" then
      fields[#fields + 1] = { path = path, validate = rule }
    elseif type(rule) == "table" then
      local children, allow = rule, nil
      if getmetatable(rule) == Section then
        children, allow = rule.schema, rule.allow
      end
      fields[#fields + 1] = { path = path, validate = section_validator(allow), skip_children = allow ~= nil }
      add_schema_fields(fields, children, path, visited)
    else
      error(table.concat(path, ".") .. " must define a validator or section", 0)
    end
  end
  visited[schema] = nil
end

local compile_definition

local function compile_section(entry, path, options, visited)
  local defaults, schema = compile_definition(entry.fields, path, options, visited)
  local validate = entry.validate
  assert(validate == nil or type(validate) == "function", "Config definition validate must be a function")
  if validate then
    options.fields[#options.fields + 1] = {
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
  return defaults, schema
end

local function compile_choices(entry, path, options, visited)
  local choices = entry.choices
  assert(type(choices) == "table", "Config choices must be a table")
  local selected = choices[entry.default_choice]
  assert(type(selected) == "table", "Config default_choice must name an existing choice")

  local literals, labels, section = {}, {}, nil
  for _, name in ipairs(sorted_keys(choices)) do
    local choice = choices[name]
    assert(type(choice) == "table", "Config choices must be tables")
    if choice.fields ~= nil then
      assert(choice.value == nil, "A config choice must declare fields or a literal value")
      assert(choice.default == nil or type(choice.default) == "table", "A section choice default must be a table")
      assert(not section, "Config choices may contain at most one section")
      section = choice
    else
      local value = choice.value
      local kind = type(value)
      assert(choice.default == nil and choice.validate == nil, "A literal config choice is defined by its value")
      assert(
        kind == "boolean" or kind == "string" or (kind == "number" and value == value),
        "A literal config choice must be a boolean, string or number"
      )
      assert(not vim.tbl_contains(literals, value), "Literal config choices must be distinct")
      literals[#literals + 1] = value
      labels[#labels + 1] = vim.inspect(value)
    end
  end

  if section then
    table.insert(labels, 1, "a table")
  end
  local message = "must be " .. table.concat(labels, " or ")
  local function match_literal(value)
    return vim.tbl_contains(literals, value), message
  end

  if not section then
    return selected.value, match_literal
  end
  local defaults, schema = compile_section(section, path, options, visited)
  if selected ~= section then
    defaults = selected.value
  end
  return defaults, M.section(schema, { allow = match_literal })
end

compile_definition = function(definition, prefix, options, visited)
  assert(type(definition) == "table", "Config definition must be a table of options")
  assert(not visited[definition], "Config definition cannot contain cycles")
  visited[definition] = true

  local defaults, schema = {}, {}
  for _, key in ipairs(sorted_keys(definition)) do
    local entry = definition[key]
    assert(type(entry) == "table", "Config definition entries must be tables")
    local path = vim.list_extend(vim.list_slice(prefix), { key })
    local validate = entry.validate
    assert(validate == nil or type(validate) == "function", "Config definition validate must be a function")
    assert(entry.replace == nil or type(entry.replace) == "boolean", "Config definition replace must be boolean")
    assert(entry.allow == nil, "Config definitions use choices for alternate values")
    if entry.replace then
      options.replace[#options.replace + 1] = path
    end

    if entry.choices ~= nil then
      assert(entry.fields == nil and entry.default == nil, "Config choices define their own fields and default")
      defaults[key], schema[key] = compile_choices(entry, path, options, visited)
      if validate then
        options.fields[#options.fields + 1] = { path = path, validate = validate }
      end
    elseif entry.fields ~= nil then
      assert(entry.default_choice == nil, "Config default_choice requires choices")
      defaults[key], schema[key] = compile_section(entry, path, options, visited)
    else
      assert(entry.default_choice == nil, "Config default_choice requires choices")
      schema[key] = validate
      defaults[key] = vim.deepcopy(entry.default)
    end
  end

  visited[definition] = nil
  return defaults, schema
end

---Compile plain option definitions into defaults and rules for new().
---@param definition table<string|integer, base_tools.ConfigDefinitionEntry>
---@return table defaults
---@return base_tools.ConfigOptions options
function M.compile_definition(definition)
  local options = { replace = {}, fields = {} }
  local defaults, schema = compile_definition(definition, {}, options, {})
  options.schema = schema
  return defaults, options
end

local function resolve_fields(options)
  local compiled = {}
  local schema = options.schema
  if schema ~= nil then
    assert(type(schema) == "table" and getmetatable(schema) ~= Section, "Config schema must be a table of rules")
    add_schema_fields(compiled, schema, {}, {})
  end

  local fields = options.fields
  assert(fields == nil or vim.islist(fields), "Config fields must be a list")
  for _, field in ipairs(fields or {}) do
    assert(type(field) == "table" and type(field.validate) == "function", "Config fields must define a validator")
    check_path(field.path)
    compiled[#compiled + 1] = { path = vim.deepcopy(field.path), validate = field.validate }
  end
  return #compiled > 0 and compiled or nil
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

local function validate_and_apply(self, snapshot, path, apply)
  assert(not self._committing, "Cannot write config from a validation or apply callback")
  local options = self._options or {}
  if not options.fields and not options.validate and not apply then
    return
  end

  self._committing = true
  local ok, err = pcall(function()
    local function get(...)
      return M.get(snapshot, ...)
    end

    local skipped
    for _, field in ipairs(options.fields or {}) do
      if
        (not path or intersects(path, field.path)) and (not skipped or not below_skipped_section(field.path, skipped))
      then
        local value = get(unpack(field.path))
        local valid, message = field.validate(value, get)
        if valid ~= true then
          error(table.concat(field.path, ".") .. " " .. (message or "is invalid"), 0)
        end
        if field.skip_children and type(value) ~= "table" then
          skipped = skipped or {}
          skipped[#skipped + 1] = field.path
        end
      end
    end

    if options.validate then
      options.validate(get())
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

---Read the current configuration or a value at the given path as a copy.
---@param ... string|integer
---@return any
function Config:get(...)
  return M.get(self._current, ...)
end

---Build a candidate from defaults without changing the current configuration.
---@param opts? table
---@return table
function Config:resolve(opts)
  return M.merge(self._defaults, opts, self._options)
end

---Validate a full candidate without applying or publishing it.
---@param candidate table
function Config:check(candidate)
  assert(type(candidate) == "table", "Config candidate must be a table")
  validate_and_apply(self, vim.deepcopy(candidate))
end

---Validate and optionally apply a candidate before publishing it.
---@param candidate table
---@param apply? fun(candidate: table) Apply the validated configuration, raising on failure.
function Config:commit(candidate, apply)
  assert(type(candidate) == "table", "Config candidate must be a table")
  assert(apply == nil or type(apply) == "function", "Config apply must be a function")
  local snapshot = vim.deepcopy(candidate)
  validate_and_apply(self, snapshot, nil, apply)
  self._current = snapshot
end

---Restore the original defaults.
function Config:reset()
  self:commit(self._defaults)
end

local function with_change(self, path, value)
  check_path(path)
  assert(value ~= nil, "Config value must not be nil")

  local candidate = self:get()
  local parent = candidate
  if #path > 1 then
    parent = vim.tbl_get(parent, unpack(path, 1, #path - 1))
  end

  local key = path[#path]
  assert(type(parent) == "table" and rawget(parent, key) ~= nil, "Config path does not exist: " .. vim.inspect(path))

  parent[key] = vim.deepcopy(value)
  return candidate
end

---Check a proposed replacement using the same rules as change(), without applying it.
---@param path (string|integer)[]
---@param value any
function Config:validate(path, value)
  validate_and_apply(self, with_change(self, path, value), vim.deepcopy(path))
end

---Replace an existing value and validate the affected paths before publishing.
---@param path (string|integer)[]
---@param value any
---@param apply? fun(candidate: table) Apply the validated configuration, raising on failure.
function Config:change(path, value, apply)
  assert(apply == nil or type(apply) == "function", "Config apply must be a function")
  local candidate = with_change(self, path, value)
  validate_and_apply(self, candidate, vim.deepcopy(path), apply)
  self._current = candidate
end

---Set or invert an existing boolean option through the normal write flow.
---@param path (string|integer)[]
---@param value? boolean Invert the current value when omitted.
---@param apply? fun(candidate: table) Apply the validated configuration, raising on failure.
---@return boolean value The new value.
function Config:toggle(path, value, apply)
  check_path(path)
  local current = vim.tbl_get(self._current, unpack(path))
  if type(current) ~= "boolean" then
    error(table.concat(path, ".") .. " must be boolean to toggle", 0)
  end
  if value == nil then
    value = not current
  elseif type(value) ~= "boolean" then
    error(table.concat(path, ".") .. " must be boolean", 0)
  end

  self:change(path, value, apply)
  return value
end

---Create an independent configuration initialized with a copy of its defaults.
---@param defaults table
---@param options? base_tools.ConfigOptions
---@return base_tools.Config
function M.new(defaults, options)
  local initial = M.merge(defaults, nil, options)
  options = options or {}
  local validate = options.validate
  assert(validate == nil or type(validate) == "function", "Config validate must be a function")

  local config = setmetatable({
    _defaults = initial,
    _current = initial,
    _options = { replace = vim.deepcopy(options.replace), fields = resolve_fields(options), validate = validate },
  }, Config)
  config:reset()
  return config
end

return M
