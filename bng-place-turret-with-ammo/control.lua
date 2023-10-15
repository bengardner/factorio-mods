
-- the ammo to use, best first
local gun_ammo_types = {
  "uranium-rounds-magazine",
  "piercing-rounds-magazine",
  "firearm-magazine",
}

local MIN_AMMO_COUNT = 10
local MAX_AMMO_COUNT = 50

local function take_player_inventory(inv, min_count, max_count)
  for _, name in ipairs(gun_ammo_types) do
    if inv.get_item_count(name) >= min_count then
      local n_taken = inv.remove({ name = name, count = max_count })
      if n_taken > 0 then
        return { name = name, count = n_taken }
      end
    end
  end
  return nil
end

local function handle_turret(player, entity)
  if player == nil or player.object_name ~= "LuaPlayer" then
    return
  end
  if entity == nil or not entity.valid then
    return
  end
  local player_inv = player.get_main_inventory()
  if player_inv == nil then
    return
  end

  if entity.name == "gun-turret" then
    local inv = entity.get_inventory(defines.inventory.turret_ammo)
    if inv ~= nil then
      local items = take_player_inventory(player_inv, MIN_AMMO_COUNT, MAX_AMMO_COUNT)
      if items ~= nil then
        inv.insert(items)
      end
    end
  end
end

-- pull ammo from the player that placed the turret
local function on_built_entity(event)
  handle_turret(game.players[event.player_index], event.created_entity)
end

-- pull ammo from the logistic network (if any)
local function on_robot_built_entity(event)
  local entity = event.created_entity
  if entity == nil or not entity.valid then
    return
  end
  handle_turret(entity.last_user, entity)
end

script.on_event(
  defines.events.on_built_entity,
  on_built_entity,
  {{ filter = "turret" }}
)

script.on_event(
    defines.events.on_robot_built_entity,
  on_robot_built_entity,
  {{ filter = "turret" }}
)
