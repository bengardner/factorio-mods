--[[
Create "small" versions of the logistic chests that require "electronic-circuit" instead of :
duplicate logistic chests.
 - Active Provider : pushes all inv out to a player/golem/storage chest on each service
 - Storage : golem will use this to satisfy requests
   has a row of filters to prevent adding the wrong stuff
 - Requester (buffer): golem will read requests and fetch material to satisfy requests
]]

local shared = require "shared"

local M = {}

local function add_chest(logistic_name, inventory_size)
  local override_item_name = 'logistic-chest-' .. logistic_name
  local override_prototype = "logistic-container"
  local name = override_item_name .. '-small'

  local entity = table.deepcopy(data.raw[override_prototype][override_item_name])
  entity.name = name
  entity.minable.result = name
  entity.next_upgrade = override_item_name
  --entity.picture.layers[1].filename = Paths.graphics .. "/entities/network-chest-steel.png"
  --entity.picture.layers[1].hr_version.filename = Paths.graphics .. "/entities/hr-network-chest-steel.png"
  --entity.picture.layers[1].hr_version.height = 80
  --entity.picture.layers[1].hr_version.width = 64
  --entity.icon = Paths.graphics .. "/icons/network-chest-steel.png"
  -- smaller than an iron chest
  entity.inventory_size = inventory_size
  --entity.render_not_in_network_icon = false

  -- TODO: replace graphics with 'iron-chest' w/ colors

  local item = table.deepcopy(data.raw["item"][override_item_name])
  item.name = name
  item.place_result = name
  item.order = 'g-' .. name

  local recipe = {
    name = name,
    type = "recipe",
    enabled = true,
    energy_required = 0.5,
    ingredients = {
      { "iron-chest", 1 },
      { "electronic-circuit", 3 }
    },
    result = name,
    result_count = 1,
  }

  data:extend({ entity, item, recipe })
end

function M.main()
  add_chest("active-provider", 19)
  add_chest("passive-provider", 19)
  add_chest("requester", 19)
  add_chest("buffer", 19)
  add_chest("storage", 19)
end

M.main()
