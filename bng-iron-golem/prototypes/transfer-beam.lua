--[[
  An eletric beam with no damage to show that some inventory moved.
]]

local shared = require("shared")

local name = shared.transfer_beam_name
local override_item_name = "electric-beam"
local override_prototype = "beam"

local entity = table.deepcopy(data.raw[override_prototype][override_item_name])
entity.name = name
entity.action.action_delivery.target_effects[1].damage.amount = 0

data:extend({ entity })
