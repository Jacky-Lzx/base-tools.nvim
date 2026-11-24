local M = {}

local function rgb(value)
  if type(value) == "string" then
    value = tonumber(value:match("^#(%x%x%x%x%x%x)$") or "", 16)
  end
  assert(type(value) == "number" and value >= 0 and value <= 0xffffff and value % 1 == 0, "Expected an RGB color")

  return value
end

--- Mix two RGB colors, rounding each channel to the nearest integer.
---@param foreground integer|string RGB integer or #rrggbb.
---@param background integer|string RGB integer or #rrggbb.
---@param amount number Foreground weight in [0, 1].
---@return integer
function M.mix(foreground, background, amount)
  local fg, bg = rgb(foreground), rgb(background)
  assert(type(amount) == "number" and amount >= 0 and amount <= 1, "Expected a foreground weight in [0, 1]")

  local result = 0
  for _, scale in ipairs({ 0x10000, 0x100, 1 }) do
    local foreground_channel = math.floor(fg / scale) % 256
    local background_channel = math.floor(bg / scale) % 256
    local blended = math.floor(foreground_channel * amount + background_channel * (1 - amount) + 0.5)
    result = result + blended * scale
  end

  return result
end

--- Format an RGB color as lowercase #rrggbb.
---@param value integer|string RGB integer or #rrggbb.
---@return string
function M.hex(value)
  return ("#%06x"):format(rgb(value))
end

return M
