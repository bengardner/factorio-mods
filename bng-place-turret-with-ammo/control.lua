
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

local function on_built_entity(event)
  local player = game.players[event.player_index]
  if player == nil then
    return
  end
  local player_inv = player.get_main_inventory()
  if player_inv == nil then
    return
  end

  local entity = event.created_entity
  if entity == nil or not entity.valid then
    return
  end

  -- TODO: detect other turret types? Embedded turrets? (car, tank, heli)
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

script.on_event(
  defines.events.on_built_entity,
  on_built_entity,
  {{ filter = "turret" }}
)
