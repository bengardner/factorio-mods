--[[
Constant values that are shared between the stages.
]]
local M = {}

M.MODULE_NAME = "magic-science-pack-chest"
M.MODULE_PATH = "__" .. M.MODULE_NAME .. "__"

M.CHEST_NAME = "magic-science-pack-chest"

M.SCIENCE_PACKS = {
    ["automation-science-pack"] = 100,
    ["logistic-science-pack"] = 100,
    ["military-science-pack"] = 100,
    ["chemical-science-pack"] = 100,
    ["production-science-pack"] = 100,
    ["utility-science-pack"] = 100,
    ["space-science-pack"] = 100,
}

M.PATH_GRAPHICS = M.MODULE_PATH .. "/graphics"

function M.path_graphics(bn)
    return string.format("%s/%s", M.PATH_GRAPHICS, bn)
end

return M
