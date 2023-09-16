--[[
  Data shared between the data, settings and control phases.
]]
local data = {}

data.mod_name = "bng-iron-golem"
data.mod_path = "__bng-iron-golem__"

data.golem_name = "iron-golem"
data.golem_inv_chest_name = "iron-golem-inv-chest"
data.golem_player_name = "iron-golem-proxy-player"
data.golem_reach = 20
data.golem_collision_mask = {"item-layer", "object-layer", "player-layer", "water-tile"}
data.mining_damage = 10

-- beam to illustrate that inventory has been transferred
data.transfer_beam_name = "golem-transfer-beam"

-- tower that transfers items (1 Hz, one stack max)
data.transfer_tower_name = "golem-transfer-tower"
data.transfer_tower_reach = 40
data.transfer_roboport_name = "golem-transfer-roboport"

data.base_chest_name = "golem-chest-"

data.chest_names = {
  requester = data.base_chest_name .. "requester",
  provider = data.base_chest_name .. "provider",
  storage = data.base_chest_name .. "storage",
}

data.chest_name_provider = "bng-chest-provider"
data.chest_name_requester = "bng-chest-requester"
data.chest_name_storage = "bng-chest-storage"

-- this gets referenced a lot
data.storage_chest_name = data.chest_names.storage

data.surface_name = "bng-iron-golem"

function data.get_gfx_path(path)
  return string.format("%s/data/%s", data.mod_path, path)
end

function data.get_icon_path(icon)
  return string.format("%s/data/icons/%s", data.mod_path, icon)
end

return data
