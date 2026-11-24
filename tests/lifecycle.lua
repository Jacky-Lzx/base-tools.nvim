local test = dofile("tests/support.lua")

test.run("base-tools.lifecycle", function()
  local lifecycle = require("base_tools.lifecycle")
  local name = "base_tools.test_feature"
  local loads, starts, stops = 0, 0, 0
  local feature = {}
  package.preload[name] = function()
    loads = loads + 1
    return feature
  end

  local hooks = {
    setup = function(module, options)
      starts = starts + 1
      module.value = options and options.value
      if options and options.fail then
        error("setup failed")
      end
    end,
    dispose = function(module)
      stops = stops + 1
      module.value = nil
    end,
  }
  local owner, other = lifecycle.new(name, hooks), lifecycle.new(name, hooks)
  owner:dispose()
  owner:configure({ value = 1 })
  owner:configure({ value = 2 })
  test.eq({ 0, 0, 0 }, { loads, starts, stops })
  test.eq(nil, owner:peek())

  test.eq(feature, owner:ensure())
  test.eq(feature, owner:ensure())
  test.eq(feature, owner:peek())
  test.eq(nil, other:peek())
  test.eq({ 1, 1, 2 }, { loads, starts, feature.value })

  owner:configure({ value = 3 })
  test.eq({ 1, 2, 3 }, { loads, starts, feature.value })
  owner:dispose()
  owner:dispose()
  test.eq({ 1, 2, 1 }, { loads, starts, stops })
  test.eq(nil, owner:peek())
  test.eq(feature, package.loaded[name])

  other:configure({ fail = true })
  test.eq(
    false,
    pcall(function()
      other:ensure()
    end)
  )
  test.eq(nil, other:peek())
  other:dispose()
  test.eq(2, stops)
  other:ensure()
  test.eq(feature, other:peek())
  test.eq(nil, feature.value)
  other:dispose()

  local adopted = lifecycle.new(name, hooks)
  adopted:configure({ value = 4 }, package.loaded[name])
  test.eq(feature, adopted:peek())
  test.eq(4, feature.value)
  adopted:dispose()
  test.eq(4, stops)
  test.eq(1, loads)
  package.loaded[name], package.preload[name] = nil, nil
end)
