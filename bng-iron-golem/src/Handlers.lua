--[[
Services an entity.
]]
local shared = require("shared")
local Globals = require("src.Globals")
local clog = require("src.log_console").log

local M = {}

M.max_player_stacks = 10

local function floating_text(entity, localizedtext)
  local pos = entity.position
  pos.y = entity.position.y - 2 + math.random()
  pos.x = entity.position.x - 1 + math.random()
  entity.surface.create_entity{name="flying-text", position=pos, text=localizedtext}
end

-- this connects two entites that are trading stuff for a short time
local function draw_beam(src_entity, dst_entity)
  src_entity.surface.create_entity {
    name = shared.transfer_beam_name,
    position = src_entity.position,
    force = src_entity.force,
    target = dst_entity,
    source = src_entity,
    duration = 30,
  }
end

--[[
  Transfer up to @count of @name from any player inventory to @inv.
]]
function M.transfer_player_to_inventory(entity, inv, name, count)
  for _, player in pairs(game.players) do
    -- We are done when count hits 0
    if count <= 0 then
      break
    end

    -- REVISIT: use different code if p_inv.is_filtered() is false?
    if player.force == entity.force and player.can_reach_entity(entity) then
      local p_inv = player.get_main_inventory()
      if p_inv ~= nil then
        for idx = 1, #p_inv do
          if count <= 0 then
            break
          end
          -- cannot take from a filtered slot
          if p_inv.get_filter(idx) == nil then
            local stack = p_inv[idx]
            if stack.valid_for_read and stack.name == name and stack.count > 0 then
              local n_added = inv.insert({ name=name, count=math.min(stack.count, count) })
              if n_added > 0 then
                count = count - n_added
                stack.count = stack.count - n_added
                -- notification
                local prot = game.item_prototypes[name]
                if prot ~= nil then
                  local ltext = { "flying-text.transfer_from_player", prot.localised_name, n_added, player.name, p_inv.get_item_count(name) }
                  floating_text(entity, ltext)
                  draw_beam(player.character, entity)
                end
              end
            end
          end
        end
      end
    end
  end

  if count > 0 then
    -- TODO: scan through storage chests looking for the item. If found, see if the chest is near a player that is also near
    -- the entity. If so, then transfer from the chest to the inv (skip the player).
  end
  return 0
end

--[[
  Transfers up to @count of @name from the inventory to @player.
  Returns the number transferred.
]]
function M.transfer_inventory_to_player(entity, inv, name, count, player)
  local prot = game.item_prototypes[name]
  local p_inv = player.get_main_inventory()
  if p_inv ~= nil and prot ~= nil and player.character ~= nil then
    -- we cannot exceed the specified number of stacks (5)
    local n_have = p_inv.get_item_count(name)
    local n_pmax = M.max_player_stacks * prot.stack_size
    local n_trans = math.max(0, math.min(n_pmax - n_have, count))
    if n_trans > 0 then
      local n_added = p_inv.insert({name=name, count=n_trans})
      if n_added > 0 then
        --floating_text(entity, { "flying-text.transfer_from_player", prot.localised_name, n_added, player.name, 0 })
        --floating_text(player.character, { "flying-text.transfer_to_player", prot.localised_name, n_added, player.name, p_inv.get_item_count(name) })
        floating_text(entity, { "flying-text.transfer_to_player", prot.localised_name, n_added, player.name, p_inv.get_item_count(name) })
        draw_beam(entity, player.character)
        return n_added
      end
    end
  end
  return 0
end

--[[
  Transfer up to @count of @name from the inventory to any player or storage chest.
  Returns the number it couldn't move.
]]
function M.transfer_inventory_away(entity, inv, name, count)
  -- FIXME: don't remove until it was accepted somewhere
  -- remove the items from the inventory
  local n_held = inv.remove({name=name, count=count})

  -- try to give then to a nearby player first
  for _, player in pairs(game.players) do
    if n_held <= 0 then
      break
    end
    if player.force == entity.force and player.can_reach_entity(entity) then
      local n_added = M.transfer_inventory_to_player(entity, inv, name, count, player)
      if n_added > 0 then
        n_held = n_held - n_added
      end
    end
  end

  -- try to give to a nearby golem

  -- put it back in the inventory
  if n_held > 0 then
    inv.insert({name=name, count=n_held})
  end
  return n_held
end

-- remove everything in @inv to a player or storage chest
function M.remove_all_inventory(entity, inv)
  if inv ~= nil then
    local contents = inv.get_contents()
    for name, count in pairs(contents) do
      M.transfer_inventory_away(entity, inv, name, count)
    end
  end
end

-- request everything in @recipe from a player or storage chest
function M.get_recipe_inv(entity, inv, recipe, factor)
  if recipe ~= nil and inv ~= nil then
    local contents = inv.get_contents()
    for _, ing in pairs(recipe.ingredients) do
      local prot = game.item_prototypes[ing.name]
      if prot ~= nil then
        local n_have = contents[ing.name] or 0
        local n_need = math.max(ing.amount * factor, math.ceil(prot.stack_size / 4))
        if n_have < n_need then
          M.transfer_player_to_inventory(entity, inv, ing.name, n_need - n_have)
        end
      end
    end
  end
end

-------------------------------------------------------------------------------

--[[
  Handle a furnace entity.
  We only do something when the state is not working.
]]
function M.handle_furnace(entity, info)
  -- don't do anything if the furnace is working
  if entity.status == defines.entity_status.working then
    return
  end

  -- refuel (take from player or golem)
  if entity.status == defines.entity_status.no_fuel then
    M.handle_refuel(entity)
  end

  -- add ingredients if empty (take from player or golem)
  if entity.status == defines.entity_status.no_ingredients then
    M.get_recipe_inv(entity, entity.get_inventory(defines.inventory.furnace_source), entity.previous_recipe, 5)
  end

  -- move all output to a player/golem
  if entity.status == defines.entity_status.full_output then
    M.remove_all_inventory(entity, entity.get_output_inventory())
  end
end

--[[
Handle a burner mining drill (coal circle)
The burner drill is special. If the fuel level gets too high, we remove some.
If the fuel level is too low, we add some.
]]
function M.handle_burner_mining_drill(entity, info)
  -- scan resources once to see if we are sitting on coal
  if info.resource == nil then
    info.resource = {}
    local ft = entity.surface.find_entities_filtered({ position=entity.position, radius=1, type="resource" })
    for _, tt in ipairs(ft) do
      info.resource[tt.name] = true
    end
  end

  -- if we are NOT on coal, then do the normal refuel
  if not info.resource.coal then
    M.handle_refuel(entity, info)
    return
  end

  -- We are on coal
  local fuel_name = "coal"
  local fuel_target = 5
  local prot = game.item_prototypes[fuel_name]
  local finv = entity.get_fuel_inventory()
  if finv ~= nil and prot ~= nil then
    local fuel_max = math.ceil(prot.stack_size / 2)
    local fuel_count = finv.get_item_count(fuel_name)
    if fuel_count == 0 then
      M.transfer_player_to_inventory(entity, finv, fuel_name, fuel_target)
    elseif fuel_count > fuel_max then
      M.transfer_inventory_away(entity, finv, fuel_name, fuel_count - (fuel_target + 1))
    end
  end
end

function M.handle_container(entity, info)
  -- TODO
  -- handle golem-chest-reqeuster
  --    try to pull from player or nearby provider or storage chest
end

function M.handle_container_provider(entity, info)
  local elapsed = game.tick - (info.tick or 0)
  if elapsed > 10 * 60 then
    M.remove_all_inventory(entity, entity.get_output_inventory())
    info.tick = game.tick
  end
end

-- request to fill each filtered slot
function M.handle_container_requester(entity, info)
  local inv = entity.get_output_inventory()
  if inv ~= nil then
    local contents = inv.get_contents()
    local wanted = {}

    for idx = 1, #inv do
      local name = inv.get_filter(idx)
      if name ~= nil then
        local prot = game.item_prototypes[name]
        if prot ~= nil then
          wanted[name] = (wanted[name] or 0) + prot.stack_size
        end
      end
    end

    for name, n_wanted in pairs(wanted) do
      local n_have = contents[name] or 0
      if n_have < n_wanted then
        M.transfer_player_to_inventory(entity, inv, name, n_wanted - n_have)
      end
    end
  end
end

function M.handle_assembler(entity, info)
  -- don't do anything if the assembler is working
  if entity.status == defines.entity_status.working then
    return
  end

  --[[ DO NOT REMOVE STUFF FROM ASSEMBLERS
  if entity.status == defines.entity_status.full_output then
    M.remove_all_inventory(entity, entity.get_output_inventory())
  end
  ]]

  if entity.status == defines.entity_status.item_ingredient_shortage then
    M.get_recipe_inv(entity, entity.get_inventory(defines.inventory.furnace_source), entity.get_recipe(), 1)
  end
end

-- try to top off an entity's fuel inv with @fuel_name
function M.refuel_inv(entity, inv, fuel_name)
  local prot = game.item_prototypes[fuel_name]
  if inv ~= nil and prot ~= nil then
    for idx = 1, #inv do
      local stack = inv[idx]
      if stack.valid_for_read then
        -- top off the fuel
        if stack.count < prot.stack_size / 2 then
          M.transfer_player_to_inventory(entity, inv, stack.name, prot.stack_size - stack.count)
        end
      else
        -- try to give the named fuel
        M.transfer_player_to_inventory(entity, inv, fuel_name, prot.stack_size)
      end
    end
  end
end

local fuel_list = {
  "solid-fueld",
  "coal",
  "wood"
}

--[[
Top off the fuel.
If a fuel stack is empty, try to find something that works.
coal, wood, solid fuel (coal for now)
]]
function M.handle_refuel(entity, info)
  local inv = entity.get_fuel_inventory()
  if inv == nil then
    return
  end

  -- Scan each stack. Match an existing fuel or add some.
  for idx = 1, #inv do
    local stack = inv[idx]
    if stack.valid_for_read then
      local prot = game.item_prototypes[stack.name]
      -- top off the fuel
      if prot ~= nil and stack.count < prot.stack_size / 2 then
        M.transfer_player_to_inventory(entity, inv, stack.name, prot.stack_size - stack.count)
      end
    else
      for _, fuel_name in ipairs(fuel_list) do
        local prot = game.item_prototypes[fuel_name]
        if prot ~= nil then
          M.transfer_player_to_inventory(entity, inv, fuel_name, prot.stack_size)
        end
      end
    end
  end
end

-------------------------------------------------------------------------------

Globals.register_handler("type", "furnace", M.handle_furnace)
Globals.register_handler("type", "assembling-machine", M.handle_assembler)
Globals.register_handler("name", shared.chest_names.requester, M.handle_container_requester)
Globals.register_handler("name", shared.chest_names.provider, M.handle_container_provider)
Globals.register_handler("name", shared.chest_names.storage, M.handle_container_storage)
Globals.register_handler("name", "burner-mining-drill", M.handle_burner_mining_drill)
Globals.register_handler("fuel", "", M.handle_refuel)

return M
