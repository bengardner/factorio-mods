--[[
This is a cheap, invisible, dummy roboport that has the purpose of making the small logistic containers happy.
It has the same logistic range as the transfer tower.

I'm keeping the charging ports because why not.

]]
local shared = require("shared")


local name = shared.transfer_tower_name

local override_item_name = "roboport"
local override_prototype = "roboport"

local substation = data.raw["electric-pole"]["substation"]

local entity = table.deepcopy(data.raw[override_prototype][override_item_name])
entity.name = name
entity.minable.result = name

-- roboport overrides
entity.draw_construction_radius_visualization = false
entity.construction_radius = shared.transfer_tower_reach
entity.logistics_radius = shared.transfer_tower_reach
entity.logistics_connection_distance = shared.transfer_tower_reach
entity.material_slots_count = 0
entity.robot_slots_count = 0

-- generic stuff - copy appearance from substation
entity.drawing_box = substation.drawing_box
entity.collision_box = substation.collision_box
entity.selection_box = substation.selection_box
entity.corpse = substation.corpse
entity.damaged_trigger_effect = substation.damaged_trigger_effect
entity.dying_explosion = substation.dying_explosion
entity.icon = shared.get_icon_path("transfer-tower.png")
entity.icon_mipmaps = substation.icon_mipmaps
entity.icon_size = substation.icon_size

entity.icon = shared.get_icon_path("transfer-tower.png")
entity.icon_mipmaps = substation.icon_mipmaps
entity.icon_size = substation.icon_size

-- hit the top-center post
entity.hit_visualization_box = { { -0.1, -2.3 }, { 0.1, -2.2 } }

-- remove animations and replace all images with empty
local blank_anim = {
  direction_count = 1,
  filename = "__core__/graphics/empty.png",
  frame_count = 1,
  height = 1,
  priority = "extra-high",
  width = 1
}

entity.base = {
  layers = {
    {
      filename = shared.get_icon_path("transfer-tower.png"),
      height = 64,
      width = 64,
    },
  }
}
-- base picture
entity.base = {
  layers = {
    {
      filename = shared.get_gfx_path("transfer-tower/transfer-tower-shadow.png"),
      draw_as_shadow = true,
      height = 52,
      width = 186,
      shift = { 1.9375, 0.3125 },
      hr_version = {
        filename = shared.get_gfx_path("transfer-tower/hr-transfer-tower-shadow.png"),
        draw_as_shadow = true,
        force_hr_shadow = true,
        height = 104,
        width = 370,
        shift = { 1.9375, 0.3125 },
        scale = 0.5,
      },
    },
    {
      filename = shared.get_gfx_path("transfer-tower/transfer-tower.png"),
      height = 136,
      width = 70,
      hr_version = {
        filename = shared.get_gfx_path("transfer-tower/hr-transfer-tower.png"),
        height = 270,
        width = 138,
        shift = { 0, -0.96875 },
        scale = 0.5,
      },
    },
  },
}

entity.base_animation = blank_anim
entity.base_patch = entity.base
entity.door_animation_up = blank_anim
entity.door_animation_down = blank_anim
entity.recharging_animation = blank_anim

entity.open_door_trigger_effect = nil
entity.close_door_trigger_effect = nil
entity.circuit_wire_connection_point = nil
entity.draw_copper_wires = false
entity.draw_circuit_wires = false



local item = {
  type = "item",
  name = name,
  --localised_name = {name},
  icon = shared.get_icon_path("transfer-tower.png"),
  icon_size = 64,
  flags = {},
  subgroup = "logistic-network",
  order = "zb"..name,
  stack_size = 10,
  place_result = name
}



local recipe = {
  type = "recipe",
  name = name,
  --localised_name = { name },
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
