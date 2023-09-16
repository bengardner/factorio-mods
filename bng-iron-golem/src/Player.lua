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
  local n_stacks = 5
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

  -- TODO: if character logistic reqeusts are acitve, then use that, ignore filters.

  -- get the player filtered counts
  local filtered = {}
  if pinv.is_filtered() then
    for idx = 1, #pinv do
      local filt = pinv.get_filter(idx)
      if filt ~= nil then
        local prot = game.item_prototypes[filt]
        if prot ~= nil then
          filtered[filt] = (filtered[filt] or 0) + prot.stack_size
        end
      end
    end
  end

  -- allow a resupply request every other service
  if pinfo.allow_resupply == true then
    pinfo.allow_resupply = false
    --clog("+ doing resupply check")
    -- grab the first item we are short on
    for name, count in pairs(contents) do
      local prot = game.item_prototypes[name]
      if prot == nil then
        return
      end

      local n_wanted = filtered[name] or 0
      local n_max = n_wanted + n_stacks * prot.stack_size
      --clog(" * check %s  have=%s want=%s max=%s", name, count, n_wanted, n_max)
      if n_wanted > count then
        local chest, n_avail = EntityHandlers.find_chest_items(storage_ents, name, n_wanted - count)
        if chest ~= nil then
          --clog(" -> request %s %s", name, n_avail)
          return { pri=3, dst=entity, src=chest.nv.entity, chest=chest, name=name, count=n_avail }
        end
      end
      if count > n_max then
        local chest, n_free = EntityHandlers.find_chest_space(storage_ents, name, count - n_max)
        if chest ~= nil then
          --clog(" -> provide %s %s to %s[%s]", name, n_free, chest.nv.entity.name, chest.nv.entity.unit_number)
          return { pri=3, src=entity, dst=chest.nv.entity, chest=chest, name=name, count=n_free }
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
          local prot = game.item_prototypes[name]
          if prot == nil then
            return
          end
          -- get min of physical limits and rule-based limits
          local n_max_accept = math.min(pinv.get_insertable_count(name), ((filtered[name] or 0) + n_stacks * prot.stack_size) - (contents[name] or 0))
          count = math.min(count, n_max_accept)
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
            local prot = game.item_prototypes[name]
            if prot == nil then
              return
            end
            -- cap the count based on the number available
            count = math.min(count, (contents[0] or 0) - (filtered[name] or 0))
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
