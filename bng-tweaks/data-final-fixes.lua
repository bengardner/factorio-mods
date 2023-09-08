-- make spidertron grid huge
-- want grid width to be 10, but another mod set it to 20 and I don't want to break the save game
data.raw["equipment-grid"]['spidertron-equipment-grid'].width = 20
data.raw["equipment-grid"]['spidertron-equipment-grid'].height = 60

data.raw["spider-vehicle"]['spidertron'].inventory_size = 160
data.raw["spider-vehicle"]['spidertron'].max_health = 300000

--[[
data.raw["spider-vehicle"]['spidertron'].guns = {
        "spidertron-rocket-launcher-1",
        "spidertron-rocket-launcher-2",
        "spidertron-rocket-launcher-3",
        "spidertron-rocket-launcher-4",
		"tank-cannon",
        "tank-machine-gun",
      }
]]

-- original data
-- max_shield_value = 150
-- energy_per_shield = "30kJ"
data.raw["energy-shield-equipment"]["energy-shield-mk2-equipment"].max_shield_value = 1500
data.raw["energy-shield-equipment"]["energy-shield-mk2-equipment"].energy_per_shield = "3kJ"

-- insane ranges
--data.raw["gun"]["tank-cannon"].attack_parameters.range = 180

data.raw["ammo"]["cannon-shell"].ammo_type.action.action_delivery.max_range = 60


data.raw["gun"]["spidertron-rocket-launcher-1"].attack_parameters.range = 90
data.raw["gun"]["spidertron-rocket-launcher-2"].attack_parameters.range = 90
data.raw["gun"]["spidertron-rocket-launcher-3"].attack_parameters.range = 90
data.raw["gun"]["spidertron-rocket-launcher-4"].attack_parameters.range = 90
data.raw["gun"]["artillery-wagon-cannon"].attack_parameters.range = 500

data.raw["electric-turret"]["laser-turret"].attack_parameters.range = 42

data.raw["ammo-turret"]["gun-turret"].attack_parameters.range = 36

do
  local lr = data.raw["logistic-robot"]["logistic-robot"]
  lr.energy_per_move = "0.05kJ"
  lr.max_payload_size = 100
  lr.speed = 0.1
end
