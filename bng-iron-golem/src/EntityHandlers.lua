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

--===========================================================================--

--[[
return if we can take items from this chest

Rules:
 - any non-logistic entity can take from a logicistic chest
 - only two logistic requesters: requester and buffer
 - anyone can take from storage
 -
]]
local function storage_can_take_from(inst, request_from_buffers, logistic_mode)
  -- if the requester is not logistic, then we are OK
  if logistic_mode == "none" then
    return true
  end

  local mode = inst.nv.logistic_mode

  if logistic_mode == "requester" then
    -- a requester cannot take from another requester
    if mode == "requester" then
      return false
    end
    -- a requester cannot take from a buffer unless enabled
    if mode == "buffer" and not request_from_buffers then
      return false
    end
    return true
  end

  -- buffers can take from anything except buffers and requesters
  return (mode ~= "buffer" and mode ~= "requester")
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

@logistic_mode is the logistic mode of the taker.
]]
function M.find_chest_items(dst_unum, storage_ents, name, count, request_from_buffers, logistic_mode)
  local best_chest
  local best_count = 0

  for unum, _ in pairs(storage_ents) do
    local inst = Globals.entity_get(unum)
    if inst ~= nil and inst.nv.unit_number ~= dst_unum and storage_can_take_from(inst, request_from_buffers, logistic_mode) then
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
            local chest, n_avail = M.find_chest_items(inst.nv.unit_number, storage_ents, name, count, request_from_buffers, inst.nv.logistic_mode or "none")
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

-------------------------------------------------------------------------------

--[[
Find space in the logistic network for the items.
@entity is either a "character" or "roboport" (tower).
]]
--@field entity LuaEntity @ character or tower
--@field name string @ Item name
--@field count number @ Item count
function M.find_chest_space2(src_entity, mid_entity, net, name, count)
  if net == nil then
    return
  end

  -- FIXME: does this do partial stacks? Do I need to check for count=1 if this fails?
  local pt = net.select_drop_point{ stack={ name=name, count=count } }
  if pt == nil then
    clog("%s[%s]: %s[%s] NOT drop for %s (%s)",
      mid_entity.name, mid_entity.unit_number,
      src_entity.name, src_entity.unit_number,
      name, count)
    return
  end
  if pt.owner.unit_number == src_entity.unit_number then
    --pt = net.select_drop_point{ stack={ name=name, count=count }, members="storage" }
    --if pt == nil then
      clog("%s[%s] self-drop for %s (%s)", src_entity.name, src_entity.unit_number, name, count)
      for si, se in ipairs(net.storages) do
        clog(" %s] %s [%s]", si, se.name, se.unit_number)
      end
      return
    --end
  end
--[[
  clog("%s[%s]: %s[%s] drop %s (%s) into %s[%s]",
    mid_entity.name, mid_entity.unit_number,
    src_entity.name, src_entity.unit_number,
    name, count,
    pt.owner.name, pt.owner.unit_number)
]]
  local sinv
  if pt.owner.type == "character" then
    sinv = pt.owner.get_main_inventory()
  else
    sinv = pt.owner.get_output_inventory()
  end
  if sinv ~= nil then
    -- get an accurate count
    count = math.min(count, sinv.get_insertable_count(name))
    if count > 0 then
      return Globals.entity_get(pt.owner.unit_number), count
    end
  end
end

--[[
Find items in the logistic network.
@entity is either a "character" or "roboport" (tower).
@logistic_mode is the logistic mode of the taker.
]]
function M.find_chest_items2(dst_entity, mid_entity, net, name, count, request_from_buffers)
  if net == nil then
    return
  end

  local pt = net.select_pickup_point{ name=name, position=mid_entity.position, include_buffers=request_from_buffers }
  if pt == nil or pt.owner == nil then
    --[[
    clog("%s[%s]: No pickup for %s (%s) for %s[%s]",
      mid_entity.name, mid_entity.unit_number,
      name, count,
      dst_entity.name, dst_entity.unit_number)
      ]]
    return
  end

  --[[
  clog("%s[%s]: %s[%s] pickup %s (%s) from %s [%s] rfb=%s",
    mid_entity.name, mid_entity.unit_number,
    dst_entity.name, dst_entity.unit_number,
    name, count,
    pt.owner.name, pt.owner.unit_number, request_from_buffers)
  ]]

  local sinv
  if pt.owner.type == "character" then
    sinv = pt.owner.get_main_inventory()
  else
    sinv = pt.owner.get_output_inventory()
  end
  if sinv ~= nil then
    -- get an accurate count
    count = math.min(count, sinv.get_item_count(name))
    return Globals.entity_get(pt.owner.unit_number), count
  end
end

function M.find_chest_space3(src_entity, mid_entity, net, name, count, storage_ents)
  if net == nil then
    return M.find_chest_space(storage_ents, name, count)
  end
  return M.find_chest_space2(src_entity, mid_entity, net, name, count)
end

function M.find_chest_items3(dst_entity, mid_entity, net, name, count, storage_ents, request_from_buffers)
  if net == nil then
    local logistic_mode = "none"
    local dst_inst = Globals.entity_get(dst_entity.unit_number)
    if dst_inst ~= nil then
      logistic_mode = dst_inst.nv.logistic_mode or "none"
    end
    return M.find_chest_items(dst_entity.unit_number, storage_ents, name, count, request_from_buffers, logistic_mode)
  end
  return M.find_chest_items2(dst_entity, mid_entity, net, name, count, request_from_buffers)
end

--[[
This finds a job that transfers between a storage chest and a service entity.
@entity is either a "character" or "roboport" (tower).
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
--@field entity LuaEntity @ Tower
--@field service_ents table @ Entities that need service, key=unit_number, val=true
--@field done_unums table @ Entities that have been serviced, key=unit_number, val=true
function M.tower_find_best_job(entity, service_ents, done_unums)
  local best_pri = 0
  local best_chest
  local best_inst
  local best_name
  local best_count

  local net = entity.logistic_network
  if net == nil then
    return nil
  end

  done_unums = done_unums or {}

  for unum, _ in pairs(service_ents) do
    local inst = Globals.entity_get(unum)
    local noskip = (done_unums[unum] ~= true)
    if inst ~= nil and noskip and (inst.nv.priority or 0) > best_pri then
      --clog(" -- check %s[%s] pri=%s req=%s pro=%s", inst.nv.entity_name, inst.nv.unit_number, inst.nv.priority,
      --  serpent.line(inst.nv.request), serpent.line(inst.nv.provide))
      local provide = inst.nv.provide
      if provide ~= nil and next(provide) ~= nil then
        for name, count in pairs(provide) do
          local chest, n_free = M.find_chest_space2(inst.nv.entity, entity, net, name, count)
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

      --[[
        A requester cannot request from another requester.
        A requester may request from a buffer if request_from_buffers is set.
        A buffer may NOT request from a requester or another buffer.
      ]]
      if inst.nv.priority > best_pri then
        local request = inst.nv.request
        if request ~= nil and next(request) ~= nil then
          for name, count in pairs(request) do
            local dst_ent = inst.nv.entity
            -- logistic chests generally cannot pull from requester
            local request_from_buffers = true
            if dst_ent.type == "logistic-container" then
              -- two type: 'buffer' and 'requester'. 'requester' can pull from 'buffer' if enabled
              request_from_buffers = false
              if dst_ent.prototype.logistic_mode == "requester" and dst_ent.request_from_buffers then
                request_from_buffers = true
              end
            end

            local chest, n_avail = M.find_chest_items2(dst_ent, entity, net, name, count, request_from_buffers)
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

-------------------------------------------------------------------------------

local function chest_get_insertable_count(entity, name)
  if entity.type == "logistic-storage" then
    return entity.get_output_inventory().get_insertable_count(name)
  end
  return 0
end

--[[
Find something that will take the items.
If net ~= nil, the check the network for requests.

  -- if service_ents ~= nil then try to satisfy a request
  -- if storage_ents ~= nil then try to find a chest that will take it

@return instance, count
]]
function M.find_item_takers(src_entity, mid_entity, net, name, count, service_ents, storage_ents)
  if net ~= nil then
    -- this is the usual path when in a logistic network
    local pt = net.select_drop_point{ stack={ name=name, count=count } }
    if pt ~= nil and pt.owner.unit_number ~= src_entity.unit_number then
      local sinv
      if pt.owner.type == "character" then
        sinv = pt.owner.get_main_inventory()
      else
        sinv = pt.owner.get_output_inventory()
      end
      if sinv ~= nil then
        -- get an accurate count
        count = math.min(count, sinv.get_insertable_count(name))
        if count > 0 then
          return Globals.entity_get(pt.owner.unit_number), count
        end
      end
    end
  end

  -- no logistic taker, see if there is a request outside the network
  if type(service_ents) == "table" then
    for unum, _ in pairs(service_ents) do
      local inst = Globals.entity_get(unum)
      if inst ~= nil then
        local request = inst.nv.request
        if request ~= nil then
          -- trusting that an entity won't request what it can't hold
          local n_trans = math.min(request[name] or 0, count)
          if n_trans > 0 then
            return inst, n_trans
          end
        end
      end
    end
  end

  -- OK. see if we can shove it in a chest
  if type(storage_ents) == "table" then
    return M.find_chest_space(storage_ents, name, count)
  end
end

-------------------------------------------------------------------------------

--[[
Transfers @count items from @src_entity in @src_inv via @mid_entity to @dst_entity in @dst_inv.
]]
function M.transfer_items(src_entity, mid_entity, dst_entity, name, count)
  local prot = game.item_prototypes[name]
  if prot == nil then
    return
  end

  -- try to grab from the trash first, if there is a trash inventory
  local n_trans = 0
  if src_entity.type == "character" then
    local tinv = src_entity.get_inventory(defines.inventory.character_trash)
    if tinv ~= nil then
      n_trans = tinv.remove( { name=name, count=count } )
    end
  elseif src_entity.type == "spider-vehicle" then
    local tinv = src_entity.get_inventory(defines.inventory.spider_trunk)
    if tinv ~= nil then
      n_trans = tinv.remove( { name=name, count=count } )
    end
  end
  -- auto-pull items from src_entity if there wasn't trash
  if n_trans == 0 then
    n_trans = src_entity.remove_item( { name=name, count=count } )
  end
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

  if false then
    clog("TRANSFER %s (%s) from %s[%s] to %s[%s] via %s[%s]",
      name, n_added,
      src_entity.name, src_entity.unit_number,
      dst_entity.name, dst_entity.unit_number,
      mid_entity.name, mid_entity.unit_number)
  end

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
