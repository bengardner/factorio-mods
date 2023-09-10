--[[
Game plan:
duplicate logistic chests.
 - Active Provider : pushes all inv out to a player/golem/storage chest on each service
 - Storage : golem will use this to satisfy requests
   has a row of filters to prevent adding the wrong stuff
 - Requester (buffer): golem will read requests and fetch material to satisfy requests
]]

local shared = require("shared")

local name = shared.golem_inv_chest_name
local override_item_name = "iron-chest"
local override_prototype = "container"

local entity = table.deepcopy(data.raw[override_prototype][override_item_name])
entity.name = name
entity.minable = nil -- .minable = false
entity.collision_mask = {}

  --entity.picture.layers[1].filename = Paths.graphics .. "/entities/network-chest-steel.png"
  --entity.picture.layers[1].hr_version.filename = Paths.graphics .. "/entities/hr-network-chest-steel.png"
  --entity.picture.layers[1].hr_version.height = 80
  --entity.picture.layers[1].hr_version.width = 64
  --entity.icon = Paths.graphics .. "/icons/network-chest-steel.png"
  -- smaller than an iron chest
entity.inventory_size = 29
entity.inventory_type = "with_filters_and_bar"

data:extend({ entity })
