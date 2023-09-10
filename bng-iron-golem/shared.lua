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

data.transfer_beam_name = "golem-transfer-beam"

data.base_chest_name = "golem-chest-"

data.chest_names = {
  requester = data.base_chest_name .. "requester",
  provider = data.base_chest_name .. "provider",
  storage = data.base_chest_name .. "storage",
}

data.storage_chest_name = "golem-chest-storage"

data.surface_name = "bng-iron-golem"

function data.get_icon_path(icon)
  return string.format("%s/data/icons/%s", data.mod_path, icon)
end

return data
