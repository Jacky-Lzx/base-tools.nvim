---Defer loading and initialization of Lua modules until a feature needs them.
local M = {}

---Callbacks supplied by the plugin that owns the feature.
---@class base_tools.LifecycleHooks
---@field setup fun(module: table, opts?: any) Initialize the module or apply new options. Receives nil if no options are saved.
---@field dispose fun(module: table) Release resources, including any created by a failed setup.

---Owns a module's configuration and initialization state independently of Lua's require cache.
---@class base_tools.Lifecycle
---@field name string Name passed to require.
---@field hooks base_tools.LifecycleHooks Feature initialization and cleanup callbacks.
---@field options any Latest options supplied by the caller.
---@field module table? Module retained for configuration or cleanup, including after a failed setup.
---@field ready boolean? True after setup completes successfully.
local Lifecycle = {}
Lifecycle.__index = Lifecycle

---Record the module before invoking setup so cleanup can recover from a setup error.
---@param self base_tools.Lifecycle
---@param module table
---@return table module
local function setup(self, module)
  self.module, self.ready = module, false
  self.hooks.setup(module, self.options)
  self.ready = true

  return module
end

---Inspect the lifecycle without loading or initializing the module.
---@return table? module The module after successful setup, or nil before setup, after failure, or after disposal.
function Lifecycle:peek()
  return self.ready and self.module or nil
end

---Save the options by reference. Apply them immediately if a module is already held.
---For a cold lifecycle, the options are used on the next call to ensure.
---@param opts? any Options to pass to setup, or nil to clear them.
---@param cached? table An already-loaded module that takes precedence over the held module.
function Lifecycle:configure(opts, cached)
  self.options = opts
  local module = cached or self.module
  if module then
    setup(self, module)
  end
end

---Return the initialized module, requiring it and running setup as needed.
---A setup error propagates and a later call can retry initialization.
---@return table module The successfully initialized module.
function Lifecycle:ensure()
  return self:peek() or setup(self, require(self.name))
end

---Run cleanup for an available module without loading it.
---On success, discard saved state and leave the require cache intact.
---@param cached? table An already-loaded module that takes precedence over the held module.
function Lifecycle:dispose(cached)
  local module = cached or self.module
  self.ready = false
  if module then
    self.hooks.dispose(module)
  end

  self.module, self.options = nil, nil
end

---Create an independent lifecycle. The named module is loaded by ensure.
---@param name string Module name accepted by require.
---@param hooks base_tools.LifecycleHooks Callbacks that initialize and clean up the module.
---@return base_tools.Lifecycle lifecycle
function M.new(name, hooks)
  return setmetatable({ name = name, hooks = hooks }, Lifecycle)
end

return M
