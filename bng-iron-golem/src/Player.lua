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
  local reach = entity.reach_distance

  reach = 10

  local ents = entity.surface.find_entities_filtered({
    position=entity.position,

    radius=reach,
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

  -- scan player inv to determine min and max values for each item
  local pinv = entity.get_main_inventory()
  if pinv == nil then
    return
  end
  local contents = pinv.get_contents()

  -- FIXME: this next bit should be done elsewhere
  -- if the force doesn't have character logistics, then enabled it (should be done elsewhere?)
  if not entity.force.character_logistic_requests then
    entity.force.character_logistic_requests = true
  end
  if entity.force.character_trash_slot_count < 10 then
    entity.force.character_trash_slot_count = 10
  end

  -- find building-based logsitic network (can't use my own!)
  local net = entity.surface.find_logistic_network_by_position(entity.position, entity.force)

  -- handle trash first (char => storage)
  local trash_inv = entity.get_inventory(defines.inventory.character_trash)
  if trash_inv ~= nil and not trash_inv.is_empty() then
    --clog("player_find_job: net=%s trash=%s", net, serpent.block(trash_inv.get_contents()))
    for name, count in pairs(trash_inv.get_contents()) do
      local inst, n_trans = EntityHandlers.find_item_takers(entity, entity, net, name, count, service_ents, storage_ents)
      if inst ~= nil then
        return { src=entity, dst=inst.nv.entity, dst_inst=inst, name=name, count=n_trans }
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

    -- check logistic maximums (char => trash)
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

    -- check logistic minimums (storage => char)
    for name, n_want in pairs(item_min) do
      local n_have = contents[name] or 0
      if n_want > n_have then
        local n_trans = math.min(n_want - n_have, pinv.get_insertable_count(name))
        if n_trans > 0 then
          --clog("player_find_job: log want %s (%s)", name, n_trans)
          local inst, n_avail = EntityHandlers.find_chest_items3(entity, entity, net, name, n_trans, storage_ents, true)
          if inst ~= nil then
            return { dst=entity, src=inst.nv.entity, src_inst=inst, name=name, count=n_avail }
          end
        end
      end
    end
  end
  pinfo.allow_resupply = true

  -- scan entities using player inventory and storage
  for unum, _ in pairs(service_ents) do
    local inst = Globals.entity_get(unum)
    local noskip = (pinfo.handled_unums[unum] ~= true)

    if inst ~= nil and noskip and (inst.nv.priority or 0) > 0 then
      --clog("player_find_job: %s[%s] pri=%s provides=%s request=%s", inst.nv.entity_name, inst.nv.unit_number,
      --  inst.nv.priority, serpent.line(inst.nv.provide), serpent.line(inst.nv.request))

      -- check provides (entity => char)
      for name, count in pairs(inst.nv.provide or {}) do
        -- get min of physical limits and available items
        local n_trans = math.min(count, pinv.get_insertable_count(name))
        -- cap at the max space available
        local n_max = item_max[name]
        if n_max ~= nil then
          n_trans = math.min(n_max - (contents[name] or 0), n_trans)
        end
        if n_trans > 0 then
          return { src=inst.nv.entity, src_inst=inst, dst=entity, name=name, count=n_trans }
        end

        -- see if someone else can take the item
        local dst_inst, dst_count = EntityHandlers.find_item_takers(inst.nv.entity, entity, net, name, count, service_ents, storage_ents)
        if dst_inst ~= nil then
          return { src=inst.nv.entity, src_inst=inst, dst=dst_inst.nv.entity, dst_inst=dst_inst, name=name, count=dst_count }
        end
      end

      -- check requests (char => entity)
      local request = inst.nv.request
      if request ~= nil and next(request) ~= nil then
        for name, count in pairs(request) do
          --clog("See request for %s (%s) from %s [%s] - i have %s", name, count, inst.nv.entity_name, inst.nv.unit_number, contents[name])
          -- cap the count based on the number available
          local n_trans = math.min(count, (contents[name] or 0) - (item_min[name] or 0))
          if n_trans > 0 then
            -- move items from char to entity
            return { src=entity, dst=inst.nv.entity, dst_inst=inst, name=name, count=n_trans }
          end


          -- try to grab from somewhere else (entity to entity, skip me)
          local chest, n_avail = EntityHandlers.find_chest_items3(entity, entity, net, name, count, storage_ents, false)
          --clog("player_find_job: %s[%s] request %s (%s) => %s %s", inst.nv.entity_name, inst.nv.unit_number, name, count, serpent.line(chest), n_avail)
          if chest ~= nil and inst.nv.unit_number ~= chest.nv.unit_number then
            return { src=chest.nv.entity, src_inst=chest, dst=inst.nv.entity, dst_inst=inst, name=name, count=n_avail }
          end
        end
      end

      -- checked it an could do nothing, so punt
      pinfo.handled_unums[unum] = true
    end
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
  local job = M.player_find_job(entity, info, service_ents, storage_ents)
  if job == nil then
    -- clear the list of handled entities
    info.handled_unums = {}
    return
  end

  EntityHandlers.transfer_items(job.src, entity, job.dst, job.name, job.count)

  -- refresh the entity status
  local function call_service(inst)
    if inst ~= nil and type(inst.service) == "function" then
      inst:service(true)
    end
  end
  call_service(job.src_inst)
  call_service(job.dst_inst)
end

return M
