local shared = require("shared")
local name = shared.golem_player_name


local character = table.deepcopy(data.raw["character"]["character"])
character.name = name
character.collision_mask = {"ghost-layer"}
character.type = "unit"

character.flags = {
  "placeable-off-grid",
  "not-on-map",
  "not-flammable"
}
character.healing_per_tick = 0
character.max_health = 750



local item = {
  type = "item",
  name = name,
  localised_name = {name},
  icon = shared.get_icon_path("iron_golem.png"),
  icon_size = 64,
  flags = {},
  subgroup = "extraction-machine", -- TODO:
  order = "zb"..name,
  stack_size = 1,
  place_result = name
}



local recipe = {
  type = "recipe",
  name = name,
  localised_name = {name},
  --category = ,
  enabled = true,
  ingredients =
  {
    -- Final ingredients are set in customizer.lua
    {"iron-plate", 10},
    {"iron-gear-wheel", 5},
    {"iron-stick", 10}
  },
  energy_required = 2,
  result = name}


data:extend({ item, recipe, character })
