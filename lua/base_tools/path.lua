require("base_tools")

local fs, uv = vim.fs, vim.uv
local windows = vim.fn.has("win32") == 1
local M = {}

local function check_path(value)
  assert(type(value) == "string" and value ~= "" and not value:find("\0", 1, true), "expected a non-empty path")
end

local function join(base, tail)
  if tail == "" then
    return base
  end
  return base .. (vim.endswith(base, "/") and "" or "/") .. tail
end

local function is_relative(value)
  local path = windows and value:gsub("\\", "/") or value
  return not (vim.startswith(path, "/") or (windows and path:match("^%a:")))
end

local function normalize(value)
  local path = fs.normalize(value, { expand_env = false })
  if windows and vim.startswith(path, "//") and #path > 2 then
    return (path:gsub("/$", ""))
  end
  return path
end

local function lexical(value, cwd)
  check_path(value)
  if cwd ~= nil then
    check_path(cwd)
  end
  if vim.startswith(value, "~") then
    local expanded = vim.fn.fnamemodify(value, ":p")
    if not vim.startswith(expanded, "~") then
      return normalize(expanded)
    end
  end
  if is_relative(value) then
    value = join(cwd and lexical(cwd) or vim.fn.getcwd(), value)
  else
    value = vim.fn.fnamemodify(value, ":p")
  end
  return normalize(value)
end

local function root_of(path)
  if windows then
    local root = path:match("^//[?.]/[Uu][Nn][Cc]/[^/]+/[^/]+")
      or path:match("^//[?.]/[^/]+")
      or path:match("^//[^/]+/[^/]+")
      or path:match("^%a:/")
    if root then
      return root
    end
  end
  return vim.startswith(path, "//") and "//" or "/"
end

local function parent(path, root)
  if path == root or path == root .. "/" then
    return nil
  end
  local directory = fs.dirname(path)
  if not directory or directory == path then
    return nil
  end
  if #directory < #root then
    return root
  end
  return directory
end

local function resolve_ancestors(value, mode)
  local root = root_of(value)
  local tails = {}
  local head = value
  if mode == "parent" then
    head = parent(value, root)
    if not head then
      return value
    end
    tails[1] = fs.basename(value)
  end

  while head do
    local resolved = uv.fs_realpath(head)
    if resolved then
      resolved = normalize(resolved)
      for index = #tails, 1, -1 do
        resolved = join(resolved, tails[index])
      end
      return resolved
    end
    tails[#tails + 1] = fs.basename(head)
    head = parent(head, root)
  end
  return value
end

---@class base_tools.PathAbsoluteOptions
---@field cwd? string Base directory for an ordinary relative path. Defaults to the current window's directory.
---@field symlinks? "none"|"parent"|"all" Which existing components to resolve. Defaults to "none".

--- Make a local pathname absolute and normalize its lexical components.
--- Resolve links afterward if requested, leaving any nonexistent suffix in place.
--- Use "parent" to preserve the final component, including a final symlink.
---@param value string
---@param opts? base_tools.PathAbsoluteOptions
---@return string
function M.absolute(value, opts)
  assert(opts == nil or type(opts) == "table", "expected path options to be a table")
  opts = opts or {}
  local mode = opts.symlinks == nil and "none" or opts.symlinks
  assert(mode == "none" or mode == "parent" or mode == "all", "expected symlinks to be none, parent, or all")
  local absolute = lexical(value, opts.cwd)
  return mode == "none" and absolute or resolve_ancestors(absolute, mode)
end

local function descendant_suffix(base, target)
  if base == target then
    return ""
  end
  local prefix = vim.endswith(base, "/") and base or base .. "/"
  if vim.startswith(target, prefix) then
    return target:sub(#prefix + 1)
  end
end

--- Check lexical containment, including equality.
---@param root string
---@param target string
---@return boolean
function M.contains(root, target)
  return descendant_suffix(lexical(root), lexical(target)) ~= nil
end

--- Replace the containing directory of a path, preserving the relative suffix.
--- A target outside the source directory is returned unchanged.
---@param target string
---@param from string
---@param to string
---@return string
function M.remap(target, from, to)
  local suffix = descendant_suffix(lexical(from), lexical(target))
  if suffix == nil then
    return target
  end
  return join(lexical(to), suffix)
end

--- Return the lexical path from base to target. Both are relative to the current
--- directory if needed. Siblings can use ".." and an identical path returns ".".
---@param base string
---@param target string
---@return string? relative
---@return string? error
function M.relative(base, target)
  base, target = lexical(base), lexical(target)
  local root = root_of(base)
  if root ~= root_of(target) then
    return nil, "paths have different roots"
  end

  local levels = 0
  while base do
    local suffix = descendant_suffix(base, target)
    if suffix then
      local relative = string.rep("../", levels) .. suffix
      return relative == "" and "." or relative:gsub("/$", "")
    end
    base = parent(base, root)
    levels = levels + 1
  end

  return nil, "paths have no common directory"
end

return M
