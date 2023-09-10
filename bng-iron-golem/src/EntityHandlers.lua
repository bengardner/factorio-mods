--[[
Services an entity.
]]
local shared = require("shared")
local Globals = require("src.Globals")
local Jobs = require("src.Jobs")
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

local function display_transfer(src_entity, dst_entity, name, src_count, dst_count)
  local prot = game.item_prototypes[name]
  if prot ~= nil then
    if src_count ~= 0 then
      local ltext = { "flying-text.item_transfer", prot.localised_name, string.format("%+d", math.floor(src_count)) }
      floating_text(src_entity, ltext)
    end
    if dst_count ~= 0 then
      local ltext = { "flying-text.item_transfer", prot.localised_name, string.format("%+d", math.floor(dst_count)) }
      floating_text(dst_entity, ltext)
    end

    draw_beam(src_entity, dst_entity)
  end
end

--[[
Adds items to inv (owned by entity) or a storage entity to PROVIDE items.
returns the count that was not added. (0=all added)

Overall, the action is to move items from @src_entity to either @entity or a
storage chest.
]]
function M.add_items_to_something(name, count, entity, inv, storage, src_entity)
  -- try to put them in the actor's inventory
  if count > 0 then
    local n_added = inv.insert( { name=name, count=count })
    if n_added > 0 then
      count = count - n_added
      -- single beam, numbers on each side
      display_transfer(src_entity, entity, name, -n_added, n_added)
    end
  end

  -- try to put them in a storage chest
  for _, st_ent in pairs(storage or {}) do
    if count <= 0 then
      break
    end
    local n_added = st_ent.insert( { name=name, count=count })
    if n_added > 0 then
      count = count - n_added
      -- dual beams, numbers at the end points
      display_transfer(src_entity, entity, name, -n_added, 0)
      display_transfer(entity, st_ent, name, 0, n_added)
    end
  end

  return count
end

--[[
Takes items from @inv (owned by @entity) or a storage entity.
returns the count that was taken.

Overall, the action is to take items from either @entity or a storage chest and
insert then into @dst_entity.
]]
function M.take_items_from_something(name, count, entity, inv, storage, dst_entity)
  local n_have = 0

  -- try taking from actor first
  local n_taken = inv.remove( { name=name, count=count })
  if n_taken > 0 then
    count = count - n_taken
    n_have = n_have + n_taken
      -- single beam, numbers on each side
      display_transfer(entity, dst_entity, name, -n_taken, n_taken)
  end

  -- try to take from a storage chest
  for _, st_ent in pairs(storage or {}) do
    if count <= 0 then
      break
    end
    n_taken = st_ent.remove_item( { name=name, count=count })
    if n_taken > 0 then
      count = count - n_taken
      n_have = n_have + n_taken
      display_transfer(st_ent, entity, name, -n_taken, 0)
      display_transfer(entity, dst_entity, name, 0, n_taken)
    end
  end

  return n_have
end

--[[
Services an entity.
The scanner has just been executed to get up-to-date request and provide tables.

@actor is a player's character entity or a golem entity.
@inv is the actor's inventory (player.get_main_inventory() or golem:get_output_inventory())
@target is the entity to service
@request is the items that should be added
@provide is the items that should be removed.
@storage is a table of storage chest key=unit_numbers, val=entity
]]
function M.service_entity(unit_number, actor, inv, storage)
  -- grab the global handler info
  local info = Globals.entity_get(unit_number)
  if info == nil then
    return
  end

  local target = info.entity
  if target == nil or not target.valid or info.handler == nil then
    return
  end

  -- Service again to make sure the job is 100% accurate
  info.handler(target, info)
  local job = Jobs.get_job(unit_number)
  if job == nil then
    return
  end

  -- handle removing items from @target
  for name, count in pairs(job.provide or {}) do
    -- remove items from the target
    local n_remain = target.remove_item( { name=name, count=count } )

    if n_remain > 0 then
      n_remain = M.add_items_to_something(name, n_remain, actor, inv, storage, target)
    end

    -- put the remaining items back in target
    if n_remain > 0 then
      target.insert( { name=name, count=n_remain } )
    end
  end

  -- handle adding items to @target
  for name, count in pairs(job.request or {}) do
    local n_have = M.take_items_from_something(name, count, actor, inv, storage, target)

    if n_have > 0 then
      local n_added = target.insert( { name=name, count=n_have })
      if n_added > 0 then
        n_have = n_have - n_added
      end
      if n_have > 0 then
        n_have = M.add_items_to_something(name, n_have, actor, inv, storage, target)
        if n_have > 0 then
          clog("LOST %s (%s)", name, n_have)
        end
      end
    --else
    --  clog("Didn't get any %s for %s", name, target.name)
    end
  end

  -- Service again to cancel job if now complete
  info.handler(target, info)
end

return M
