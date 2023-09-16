local shared = require("shared")


local name = shared.transfer_roboport_name

local override_item_name = "roboport"
local override_prototype = "roboport"

local entity = table.deepcopy(data.raw[override_prototype][override_item_name])
entity.name = name
entity.minable.result = name
entity.construction_radius = 0
entity.draw_construction_radius_visualization = false
entity.logistics_radius = shared.transfer_tower_reach
entity.material_slots_count = 0
entity.robot_slots_count = 0



local item = table.deepcopy(data.raw["item"][override_item_name])
item.name = name
item.localised_name = {name}
item.order = "zb"..name
item.place_result = name



local recipe = {
  type = "recipe",
  name = name,
  localised_name = { name },
  enabled = true,
  ingredients =
  {
    --{ "iron-stick", 10 },
    --{ "iron-gear-wheel", 5 },
    --{ "iron-chest", 1 },
    --{ "electronic-circuit", 2 },
  },
  energy_required = 2,
  result = name
}


data:extend{ entity, item, recipe }
