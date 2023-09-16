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
function M.service_entity(job, actor, inv, storage)
  local unit_number = job.entity.unit_number

  -- grab the global handler info (also verifies entity and inst)
  local inst = Globals.entity_get(unit_number)
  if inst == nil then
    clog("service_entity[%s]: not found", unit_number)
    return
  end
  local target = job.entity

  -- Service again to make sure the job is 100% accurate
  inst.service(inst)

  -- grab job again as it may have been replaced
  job = Jobs.get_job(unit_number)
  if job == nil then
    -- looks like it taken care of
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

  -- Service again to cancel job if now complete so next player/tower doesn't dup
  inst.service(inst)
end

-- return if we can take items from this chest
local function storage_can_take_from(inst, request_from_buffers)
  local mode = inst.nv.logistic_mode
  if mode == "requester" then
    return false
  end
  if mode == "buffer" and not request_from_buffers then
    return false
  end
  -- covers active-provider, passive-provider, storage, and buffer+request_from_buffers, transfer tower
  return true
end

-- return if we can add unrequested items to this storage entity (storage+tower only)
local function storage_can_add_to(inst)
  local mode = inst.nv.logistic_mode
  return mode == "storage" or mode == nil
end

function M.find_chest_space(storage_ents, name, count)
  local best_chest
  local best_score = 0
  local best_count = 0

  for unum, _ in pairs(storage_ents) do
    local inst = Globals.entity_get(unum)
    if inst ~= nil and storage_can_add_to(inst) then
      local ent = inst.nv.entity
      local inv = ent.get_output_inventory()
      local n_trans = 0
      local score = -1

      if inst.nv.logistic_mode == "storage" and ent.storage_filter ~= nil then
        if name == ent.storage_filter.name then
          n_trans = math.min(inv.get_insertable_count(name), count)
          if n_trans > 0 then
            score = n_trans + 3
          end
        end
      else
        -- not filtered
        n_trans = math.min(count, inv.get_insertable_count(name))
        if n_trans > 0 then
          score = n_trans
          if inv.is_empty() then
            score = score + 1
          elseif inv.get_item_count(name) > 0 then
            score = score + 2
          end
        end
      end
      if score > best_score then
        best_chest = inst
        best_score = score
        best_count = n_trans
      end
    end
  end
  if best_chest ~= nil then
    return best_chest, best_count
  end
end

--[[
Find the best storage chest that has the items.
score is based on the number of items available.
returns chest, count
]]
function M.find_chest_items(storage_ents, name, count, request_from_buffers)
  local best_chest
  local best_count = 0

  for unum, _ in pairs(storage_ents) do
    local inst = Globals.entity_get(unum)
    if inst ~= nil and storage_can_take_from(inst, request_from_buffers) then
      local inv = inst.nv.entity.get_output_inventory()
      local n_avail = inv.get_item_count(name)
      if n_avail > 0 then
        local n_trans = math.min(n_avail, count)
        if n_trans > best_count then
          best_chest = inst
          best_count = n_trans
        end
        if n_trans == count then
          break
        end
      end
    end
  end
  if best_chest ~= nil then
    return best_chest, best_count
  end
end

--[[
This finds a job that transfers between a storage chest and a service entity.
@service_ents and @storage_ents are tables with key=unit_number and val=(dont't care)
@service_ents contains the in-range entities that could be serviced.
@storage_ents contains the in-range storage chest entities.

returns a table with the following:
  - src : source entity
  - dst : destination entity
  - name : name of item
  - count : count to transfer
  - chest : the chest involved
  - inst : the instance involved (to re-run inst:service(true) after the transfer)
]]
function M.find_best_job(service_ents, storage_ents, skip_service)
  local best_pri = 0
  local best_chest
  local best_inst
  local best_name
  local best_count

  skip_service = skip_service or {}

  for unum, _ in pairs(service_ents) do
    local inst = Globals.entity_get(unum)
    local noskip = (skip_service[unum] ~= true)
    if inst ~= nil and noskip and (inst.nv.priority or 0) > best_pri then
      --clog(" -- check %s[%s] pri=%s req=%s pro=%s", inst.nv.entity_name, inst.nv.unit_number, inst.nv.priority,
      --  serpent.line(inst.nv.request), serpent.line(inst.nv.provide))
      local request_from_buffers = true
      if inst.nv.logistic_mode == "requester" then
        request_from_buffers = inst.nv.entity.request_from_buffers
      end

      local provide = inst.nv.provide
      if provide ~= nil and next(provide) ~= nil then
        for name, count in pairs(provide) do
          local chest, n_free = M.find_chest_space(storage_ents, name, count)
          if chest ~= nil then
            best_pri = inst.nv.priority
            best_inst = inst
            best_chest = chest
            best_name = name
            best_count = -n_free
            break
          end
        end
      end

      if inst.nv.priority > best_pri then
        local request = inst.nv.request
        if request ~= nil and next(request) ~= nil then
          for name, count in pairs(request) do
            local chest, n_avail = M.find_chest_items(storage_ents, name, count, request_from_buffers)
            if chest ~= nil then
              best_pri = inst.nv.priority
              best_inst = inst
              best_chest = chest
              best_name = name
              best_count = n_avail
            end
          end
        end
      end
    end
  end

  if best_chest ~= nil then
    if best_count < 0 then
      -- moving from the entity to the chest
      return { pri=best_pri, dst=best_chest.nv.entity, src=best_inst.nv.entity, inst=best_inst, chest=best_chest, name=best_name, count=-best_count }
    else
      -- moving from the chest to the entity
      return { pri=best_pri, src=best_chest.nv.entity, dst=best_inst.nv.entity, inst=best_inst, chest=best_chest, name=best_name, count=best_count }
    end
  end
  -- make the linter happy
  return nil
end

--[[
PLAN: (not implemented)
  There are 6 possible item movements:
   - move items from job.chest to job.inst (count > 0)  : src=job.chest.nv.entity, dst=job.inst.nv.entity
   - move items from job.instl to job.chest (count < 0) : src=job.inst.nv.entity, dst=job.chest.nv.entity
   - move items from mid_entity to job.inst (job.chest = nil, count > 0) : src=mid_entity, dst=job.inst.nv.entity
   - move items from job.inst to mid_entity (job.chest = nil, count < 0) : src=job.inst.nv.entity, dst=mid_entity
   - move items from mid_entity to job.chest (job.inst = nil, count > 0) : src=mid_entity, dst=job.chest.nv.entity
   - move items from job.chest to mid_entity (job.inst = nil, count < 0) : src=job.chest.nv.entity, dst=mid_entity

returns
  { src_entity=LuaEntity, dst_entity=LuaEntity, name=string, count=integer }
]]
function M.find_best_job2(service_ents, storage_ents, mid_entity, mid_inv, mid_limits)
  local best_pri = 0
  local best_inst
  local best_name
  local best_count
  local best_chest

  --[[
  Check each serive entity.
  If we can move items to/from a storage chest to satisfy a request, then do that.
  ]]

  for unum, _ in pairs(service_ents) do
    local inst = Globals.entity_get(unum)
    if inst ~= nil and (inst.nv.priority or 0) > best_pri then
      clog(" -- check %s[%s] pri=%s req=%s pro=%s", inst.nv.entity_name, inst.nv.unit_number, inst.nv.priority,
        serpent.line(inst.nv.request), serpent.line(inst.nv.provide))

      local provide = inst.nv.provide
      if provide ~= nil and next(provide) ~= nil then
        for name, count in pairs(provide) do
          local chest, n_free = M.find_chest_space(storage_ents, name, count)
          if chest ~= nil then
            best_pri = inst.nv.priority
            best_inst = inst
            best_chest = chest
            best_name = name
            best_count = -n_free
            break
          end
        end
      end

      if inst.nv.priority > best_pri then
        local request = inst.nv.request
        if request ~= nil and next(request) ~= nil then
          for name, count in pairs(request) do
            local chest, n_avail = M.find_chest_items(storage_ents, name, count)
            if chest ~= nil then
              best_pri = inst.nv.priority
              best_inst = inst
              best_chest = chest
              best_name = name
              best_count = n_avail
            end
          end
        end
      end
    end
  end

  if best_chest ~= nil then
    return { pri=best_pri, inst=best_inst, chest=best_chest, name=best_name, count=best_count }
  end
end

--[[
Transfers @count items from @src_entity in @src_inv via @mid_entity to @dst_entity in @dst_inv.
]]
function M.transfer_items(src_entity, mid_entity, dst_entity, name, count)
  local prot = game.item_prototypes[name]
  if prot == nil then
    return
  end

  --local n_can_add = dst_entity.

  -- pull items from src_entity
  local n_trans = src_entity.remove_item( { name=name, count=count } )
  if n_trans == 0 then
    clog("!! transfer: failed to remove %s %s from %s[%s]", name, count, src_entity.name, src_entity.unit_number)
    return
  end

  -- push items to dst_inv
  local n_added = dst_entity.insert( { name=name, count=n_trans })

  -- return excess to src_inv
  if n_added < n_trans then
    src_entity.insert( { name=name, count=n_trans - n_added })
  end
  if n_added == 0 then
    local inv = dst_entity.get_output_inventory()
    if inv ~= nil then
      clog("!! transfer: failed to insert %s %s to %s[%s] inv[%s]=%s", name, n_trans, dst_entity.name, dst_entity.unit_number,
        #inv, serpent.block(inv.get_contents()))
    else
      clog("!! transfer: failed to insert %s %s to %s[%s]", name, n_trans, dst_entity.name, dst_entity.unit_number)
    end
    return
  end

--[[
  clog("TRANSFER %s (%s) from %s[%s] to %s[%s] via %s[%s]",
    name, n_added,
    src_entity.name, src_entity.unit_number,
    dst_entity.name, dst_entity.unit_number,
    mid_entity.name, mid_entity.unit_number)
]]

  -- show beam from src_entity to mid_entity if not the same.
  if src_entity.unit_number ~= mid_entity.unit_number then
    draw_beam(src_entity, mid_entity)
  end

  -- show beam from dst_entity to mid_entity if not the same.
  if dst_entity.unit_number ~= mid_entity.unit_number then
    draw_beam(dst_entity, mid_entity)
  end

  -- show text over src_entity
  floating_text(src_entity, { "flying-text.item_transfer",
    prot.localised_name, string.format("%+d", -math.floor(n_added)) })

  -- show text over dst_entity
  floating_text(dst_entity, { "flying-text.item_transfer",
    prot.localised_name, string.format("%+d", math.floor(n_added)) })
end

-- FIXME: this isn't done
function M.do_transfer_stuff(service_ents, storage_ents, mid_entity, mid_inv, mid_limits)

  local job = M.find_best_job2(service_ents, storage_ents, mid_entity, mid_inv, mid_limits)
  if job == nil then
    return
  end

  --[[
    job should have: src_entity, dst_entity, name, count, service_inst
  ]]
  M.transfer_items2(job.src_entity, job.dst_entity, job.name, job.count)

  -- refresh the entity status that was just serviced
  if job.service_inst ~= nil then
    job.service_inst:service(true)
  end
end

return M
