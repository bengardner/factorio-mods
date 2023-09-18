--[[
Helper functions for players.
This does the job service stuff.
]]
local Globals = require('src.Globals')
local shared = require("shared")
local EntityHandlers = require 'src.EntityHandlers'
local clog = require("src.log_console").log

local M = {}

local function is_same_pos(p1, p2)
  return p1 ~= nil and p2 ~= nil and math.abs(p1.x - p2.x) < 0.1 and math.abs(p1.y - p2.y) < 0.1
end

function M.player_scan(entity)
  local storage_ents = {}
  local service_ents = {}

  local ents = entity.surface.find_entities_filtered({
    position=entity.position,
    radius=entity.reach_distance,
    name=Globals.get_entity_names()
  })

  for _, ent in ipairs(ents) do
    if Globals.is_storage_name(ent.name) then
      storage_ents[ent.unit_number] = true
    end
    if Globals.is_service_name(ent.name) then
      service_ents[ent.unit_number] = true
    end
  end
  return storage_ents, service_ents
end

--[[
We already failed to find a storage-to-entity job.
Now try player-to-entity jobs.
Things we can do:
  - move items from entity to player inventory
  - move items from player inventory to entity
  - move items from player inventory to storage (??)
  - move items from storage to player inventory (??)

Restrictions:
  - will not remove items from player inventory if filtered (each filter is worth one stack)
  - will not add more than filtered + 5 stacks of any one item to player inventory
  - a filter represents a request, so grab from storage
  - ammo inventories are ignored

  returns a table with the following:
    - src : source entity
    - dst : destination entity
    - name : name of item
    - count : count to transfer
    - chest : (optional) the chest to grab from
    - inst : (optional) the instance involved (to re-run service afterwards)
]]
function M.player_find_job(entity, pinfo, service_ents, storage_ents)
  local best_pri = 0
  local best_inst
  local best_name
  local best_count

  -- scan player inv to determine min and max values for each item
  local pinv = entity.get_main_inventory()
  if pinv == nil then
    return
  end
  local contents = pinv.get_contents()

  -- if the force doesn't have character logistics, then enabled it (should be done elsewhere?)
  if not entity.force.character_logistic_requests then
    entity.force.character_logistic_requests = true
  end
  if entity.force.character_trash_slot_count < 10 then
    entity.force.character_trash_slot_count = 10
  end

  -- handle trash first
  local trash_inv = entity.get_inventory(defines.inventory.character_trash)
  if trash_inv ~= nil then
    for name, count in pairs(trash_inv.get_contents()) do
      local chest, n_free = EntityHandlers.find_chest_space(storage_ents, name, count)
      if chest ~= nil then
        return { pri=3, src=entity, dst=chest.nv.entity, chest=chest, name=name, count=n_free }
      end
    end
  end

  -- remap min and max values to be easier to check
  local item_max = {}
  local item_min = {}
  for idx = 1, entity.request_slot_count do
    local pls = entity.get_personal_logistic_slot(idx)
    if pls ~= nil then
      if pls.min ~= nil and pls.min > 0 then
        item_min[pls.name] = pls.min
      end
      if pls.max ~= nil and pls.max < 1000000 then
        item_max[pls.name] = pls.max
      end
    end
  end

  -- allow a resupply request every other service so entities are not neglected
  if pinfo.allow_resupply == true then
    pinfo.allow_resupply = false

    -- check logistic maximums
    if trash_inv ~= nil then
      for name, n_max in pairs(item_max) do
        local n_have = contents[name] or 0
        if n_have > n_max then
          -- we have too many, so move excess to the trash inventory, if possible (add then remove)
          local n_trans = trash_inv.insert( {name=name, count=n_have - n_max} )
          if n_trans > 0 then
            pinv.remove( {name=name, count=n_trans} )
          end
        end
      end
    end

    -- check logistic minimums
    for name, n_want in pairs(item_min) do
      local n_have = contents[name] or 0
      if n_want > n_have then
        local n_trans = math.min(n_want - n_have, pinv.get_insertable_count(name))
        if n_trans > 0 then
          local chest, n_avail = EntityHandlers.find_chest_items(entity.unit_number, storage_ents, name, n_trans, "none")
          if chest ~= nil then
            return { pri=3, dst=entity, src=chest.nv.entity, chest=chest, name=name, count=n_avail }
          end
        end
      end
    end
  end
  pinfo.allow_resupply = true

  -- do a more-or-less regular scan, with limits
  for unum, _ in pairs(service_ents) do
    local inst = Globals.entity_get(unum)
    local noskip = (pinfo.handled_unums[unum] ~= true)

    if inst ~= nil and noskip and (inst.nv.priority or 0) > best_pri then

      local provide = inst.nv.provide
      if provide ~= nil and next(provide) ~= nil then
        for name, count in pairs(provide) do
          -- get min of physical limits and available items
          count = math.min(count, pinv.get_insertable_count(name))
          -- cap at the max space available
          local n_max = item_max[name]
          if n_max ~= nil then
            count = math.min(n_max - (contents[name] or 0), count)
          end
          --clog(" - max_accept %s %s, count=%s ss=%s", name, n_max_accept, count, prot.stack_size)
          if count > 0 then
            best_pri = inst.nv.priority
            best_inst = inst
            best_name = name
            best_count = -count
            break
          end
        end
      end

      if inst.nv.priority > best_pri then
        local request = inst.nv.request
        if request ~= nil and next(request) ~= nil then
          for name, count in pairs(request) do
            --clog("See request for %s (%s) from %s [%s] - i have %s", name, count, inst.nv.entity_name, inst.nv.unit_number, contents[name])
            -- cap the count based on the number available
            count = math.min(count, (contents[name] or 0) - (item_min[name] or 0))
            if count > 0 then
              best_pri = inst.nv.priority
              best_inst = inst
              best_name = name
              best_count = count
            end
          end
        end
      end
    end
  end

  if best_inst ~= nil then
    if best_count < 0 then
      -- player providing items
      return { pri=best_pri, dst=entity, src=best_inst.nv.entity, inst=best_inst, name=best_name, count=-best_count }
    end
    -- player taking items
    return { pri=best_pri, src=entity, dst=best_inst.nv.entity, inst=best_inst, name=best_name, count=best_count }
  end
end

--[[
This is called periodically to service surrounding entities.
player.character has already been validated.
]]
function M.service(player, info)
  -- don't service more than 2 Hz
  local tick_delta = game.tick - (info.tick_service or 0)
  if tick_delta < 30 then
    return
  end

  local entity = player.character

  if info.last_pos == nil then
    info.last_pos = entity.position
    info.tick_moved = 0
    return
  end

  -- need to be in the same position for 30 ticks
  if not is_same_pos(info.last_pos, entity.position) then
    info.tick_moved = game.tick
    info.last_pos = entity.position
    return
  end
  tick_delta = game.tick - info.tick_moved
  if tick_delta < 30 then
    return
  end

  --clog("Player doing service %s", serpent.line(info))

  -- we have been holding still long enough, so we will do a service
  info.tick_service = game.tick
  if info.handled_unums == nil then
    info.handled_unums = {}
  end

  -- scan for anything nearby that needs to be handled
  local storage_ents, service_ents = M.player_scan(entity)

  -- toggle whether we check personal or entity services first
  local job
  if info.swap_order == true then
    job = EntityHandlers.find_best_job(service_ents, storage_ents, info.handled_unums)
    if job == nil then
      job = M.player_find_job(entity, info, service_ents, storage_ents)
    end
    info.swap_order = false
  else
    job = M.player_find_job(entity, info, service_ents, storage_ents)
    if job == nil then
      job = EntityHandlers.find_best_job(service_ents, storage_ents, info.handled_unums)
    end
    info.swap_order = true
  end

  if job == nil then
    -- clear the list of handled entities
    info.handled_unums = {}
    return
  end

  EntityHandlers.transfer_items(job.src, entity, job.dst, job.name, job.count)

  -- refresh the entity status
  if job.inst ~= nil then
    info.handled_unums[job.inst.nv.unit_number] = true
    job.inst:service(true)
  end
end

return M
