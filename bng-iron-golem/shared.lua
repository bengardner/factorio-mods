--[[
  Data shared between the data, settings and control phases.
]]
local shared = {}

shared.mod_name = "bng-iron-golem"
shared.mod_path = "__bng-iron-golem__"

-- beam to illustrate that inventory has been transferred
shared.transfer_beam_name = "golem-transfer-beam"

-- tower that transfers items (1 Hz, one stack max)
shared.transfer_tower_name = "logistic-transfer-tower"
shared.transfer_tower_reach = 40
-- per transfer
shared.transfer_tower_power_usage =  5000000
shared.transfer_tower_power_min   = 20000000

function shared.get_gfx_path(path)
  return string.format("%s/data/%s", shared.mod_path, path)
end

function shared.get_icon_path(icon)
  return string.format("%s/data/icons/%s", shared.mod_path, icon)
end

return shared
