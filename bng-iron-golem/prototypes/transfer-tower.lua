local shared = require("shared")


local name = shared.transfer_tower_name

local substation = data.raw["electric-pole"]["substation"]

local override_item_name = "steel-chest"
local override_prototype = "container"

-- for now, I'm going with a
local entity = table.deepcopy(data.raw[override_prototype][override_item_name])
entity.name = name
entity.minable.result = name
entity.inventory_size = 39
entity.corpse = substation.corpse
entity.collision_box = substation.collision_box
entity.drawing_box = substation.drawing_box
entity.selection_box = substation.selection_box
entity.water_reflection = substation.water_reflection

entity.icon = shared.get_icon_path("transfer-tower.png")
entity.icon_mipmaps = substation.icon_mipmaps
entity.icon_size = substation.icon_size

-- draw a square
entity.radius_visualisation_specification = {
  sprite = {
    filename = "__base__/graphics/entity/small-electric-pole/electric-pole-radius-visualization.png",
    size = 12,
  },
  distance = shared.transfer_tower_reach,
  draw_in_cursor = true,
  draw_on_selection  = true,
}

entity.dying_explosion = "substation-explosion"

-- base picture
entity.picture.layers[1].filename = shared.get_gfx_path("transfer-tower/transfer-tower.png")
entity.picture.layers[1].height = 136
entity.picture.layers[1].width = 70
entity.picture.layers[1].shift = { 0, -0.96875 }
entity.picture.layers[1].hr_version.filename = shared.get_gfx_path("transfer-tower/hr-transfer-tower.png")
entity.picture.layers[1].hr_version.height = 270
entity.picture.layers[1].hr_version.width = 138
entity.picture.layers[1].hr_version.shift = { 0, -0.96875 }

-- shadow
entity.picture.layers[2].filename = shared.get_gfx_path("transfer-tower/transfer-tower-shadow.png")
entity.picture.layers[2].height = 52
entity.picture.layers[2].width = 186
entity.picture.layers[2].shift = { 1.9375, 0.3125 }
entity.picture.layers[2].hr_version.filename = shared.get_gfx_path("transfer-tower/hr-transfer-tower-shadow.png")
entity.picture.layers[2].hr_version.height = 104
entity.picture.layers[2].hr_version.width = 370
entity.picture.layers[2].hr_version.shift = { 1.9375, 0.3125 }

-- hit the top-center post
entity.hit_visualization_box = { { -0.1, -2.3 }, { 0.1, -2.2 } }

-- steel-chest in line 37239
-- substation on line 63290
--

local item = {
  type = "item",
  name = name,
  localised_name = {name},
  icon = shared.get_icon_path("transfer-tower.png"),
  icon_size = 64,
  flags = {},
  subgroup = "extraction-machine", -- FIXME: should be in logistics or something
  order = "zb"..name,
  stack_size = 10,
  place_result = name
}

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
