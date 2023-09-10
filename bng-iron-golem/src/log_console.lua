--[[
  I got tired of writing game.print(string.format(...)).

  Prints formatted text to the console for debug.
]]
local M = {}

function M.log(...)
  if game ~= nil then
    local text = string.format(...)
    game.print(text)
    print(text)
  end
end

return M
