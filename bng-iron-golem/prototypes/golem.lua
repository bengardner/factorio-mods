local shared = require("shared")
local name = shared.golem_name

data:extend
{
  {
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
  },
  {
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
    result = name
  }
}
