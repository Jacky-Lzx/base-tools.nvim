local t = dofile("tests/support.lua")
local path = require("base_tools.path")
local uv = vim.uv

t.run("absolute paths use a caller-provided directory and preserve literal names", function()
  local root = path.absolute(vim.fn.tempname())
  local options = { cwd = root .. "/src" }
  t.eq(root .. "/docs/a b.md", path.absolute("../docs/./a b.md", options))
  t.eq(root .. "/src/$PATH:2.lua", path.absolute("$PATH:2.lua", options))
  t.eq(root .. "/src/~draft/a.lua", path.absolute("~draft/a.lua", options))
  t.eq(path.absolute(vim.fn.getcwd()) .. "/~draft", path.absolute("~draft"))
  t.eq(path.absolute(vim.uv.os_homedir()) .. "/docs/a.md", path.absolute("~/docs/a.md", options))
  if vim.fn.has("unix") == 1 then
    local root_home = vim.fn.fnamemodify("~root", ":p")
    if not vim.startswith(root_home, "~") then
      t.eq(path.absolute(root_home) .. "/docs/a.md", path.absolute("~root/docs/a.md", options))
    end
  end
  t.eq(root, path.absolute(root, options))
  assert(not pcall(path.absolute, ""))
  assert(not pcall(path.absolute, "invalid\0path"))
  assert(not pcall(path.absolute, root, { symlinks = false }))
end)

t.run("containment and remapping recognize path components and filesystem roots", function()
  local root = path.absolute(vim.fn.tempname())
  local source = root .. "/src"
  local target = root .. "/lib"
  local volume = root:match("^%a:/") or "/"
  t.eq(true, path.contains(source, source))
  t.eq(true, path.contains(source .. "/", source .. "/pkg/../a.lua"))
  t.eq(false, path.contains(source, source .. "-old/a.lua"))
  t.eq(false, path.contains(source, source .. "/../a.lua"))
  t.eq(target .. "/a.lua", path.remap(source .. "/a.lua", source, target))
  t.eq(target, path.remap(source, source, target))
  t.eq(source .. "-old/a.lua", path.remap(source .. "-old/a.lua", source, target))
  t.eq(target .. "/a.lua", path.remap(volume .. "a.lua", volume, target))
  t.eq(volume .. "a.lua", path.remap(source .. "/a.lua", source, volume))
end)

t.run("relative paths support siblings, ancestors, and identical paths", function()
  local base = path.absolute(vim.fn.tempname())
  t.eq("folder/a.lua", path.relative(base, base .. "/folder/a.lua"))
  t.eq("../docs/a.md", path.relative(base .. "/src", base .. "/docs/a.md"))
  t.eq("../../..", path.relative(base .. "/one/two/three", base))
  t.eq(".", path.relative(base .. "/one/..", base))
  t.eq("../sibling", path.relative("base", "sibling"))
  if vim.fn.has("win32") == 1 then
    local relative, err = path.relative("C:/project", "D:/docs")
    t.eq(nil, relative)
    t.eq("paths have different roots", err)
  end
end)

t.run("symlink resolution keeps missing suffixes and can preserve the final link", function()
  if vim.fn.has("win32") == 1 then
    return -- Creating symlinks can require additional permissions on Windows.
  end
  local temp = vim.fn.tempname()
  vim.fn.mkdir(temp, "p")
  local root = assert(uv.fs_realpath(temp))
  local actual, link = root .. "/actual", root .. "/link"
  vim.fn.mkdir(actual)
  local ok, err = pcall(function()
    assert(uv.fs_symlink(actual, link))
    t.eq(link, path.absolute(link))
    t.eq(link, path.absolute(link, { symlinks = "parent" }))
    t.eq(actual, path.absolute(link, { symlinks = "all" }))
    t.eq(actual .. "/missing/a.lua", path.absolute(link .. "/missing/a.lua", { symlinks = "parent" }))
    t.eq(actual .. "/missing/a.lua", path.absolute(link .. "/missing/a.lua", { symlinks = "all" }))
  end)
  vim.fn.delete(root, "rf")
  assert(ok, err)
end)
