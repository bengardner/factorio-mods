--[[
Game plan:
duplicate logistic chests.
 - Active Provider : pushes all inv out to a player/golem/storage chest on each service
 - Storage : golem will use this to satisfy requests
   has a row of filters to prevent adding the wrong stuff
 - Requester (buffer): golem will read requests and fetch material to satisfy requests
]]

local shared = require "shared"

local M = {}

local function add_chest(variant, use_filter, inventory_size)
  local name = shared.chest_names[variant]
  local override_item_name = "iron-chest"
  local override_prototype = "container"

  local entity = table.deepcopy(data.raw[override_prototype][override_item_name])
  entity.name = name
  entity.minable.result = name
  --entity.picture.layers[1].filename = Paths.graphics .. "/entities/network-chest-steel.png"
  --entity.picture.layers[1].hr_version.filename = Paths.graphics .. "/entities/hr-network-chest-steel.png"
  --entity.picture.layers[1].hr_version.height = 80
  --entity.picture.layers[1].hr_version.width = 64
  --entity.icon = Paths.graphics .. "/icons/network-chest-steel.png"
  -- smaller than an iron chest
  entity.inventory_size = inventory_size
  if use_filter then
    entity.inventory_type = "with_filters_and_bar"
  end

  local item = table.deepcopy(data.raw["item"][override_item_name])
  item.name = name
  item.place_result = name
  item.order = 'g-' .. variant .. '-' .. item.order
  --item.subgroup = "golem-chest"

  local recipe = {
    name = name,
    type = "recipe",
    enabled = true,
    energy_required = 0.5,
    ingredients = {
      { "iron-chest", 1 },
      { "electronic-circuit", 2 }
    }, -- iron chest + 2x circuit board
    result = name,
    result_count = 1,
  }

  data:extend({ entity, item, recipe })
end

function M.main()
  -- filtered slots are poor-man's logistic request
  add_chest("requester", true, 19)

  add_chest("storage", true, 29)
  -- provider: filter does the normal filter thing
  add_chest("provider", true, 19)
end

M.main()
