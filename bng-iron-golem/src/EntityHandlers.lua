--[[
Services an entity.
]]
local shared = require("shared")
local Globals = require("src.Globals")
local clog = require("src.log_console").log

local M = {}

M.max_player_stacks = 10
M.debug_trans = false

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

-- return if we can add unrequested items to this storage entity (containers/chests only)
local function storage_can_add_to(inst)
  return not inst.nv.entity.to_be_deconstructed and (inst.nv.logistic_mode == "storage")
end

--[[
Scans the list of storage entities looking for storage space.
Used only by a player when outside a logistic network or nothing was found in the net.
@return inst, count, inv.index
]]
function M.find_chest_space(storage_ents, name, count)
  local best_chest
  local best_score = 0
  local best_count = 0
  local best_invidx = 0

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
        best_invidx = inv.index
      end
    end
  end
  if best_chest ~= nil then
    return best_chest, best_count, best_invidx
  end
end

--[[
Find the best storage chest that has the items.
score is based on the number of items available.
returns chest, count, inv_idx

@logistic_mode is the logistic mode of the taker.
]]
function M.chest_find_items(dst_unum, storage_ents, name, count, request_from_buffers, logistic_mode)
  local best_chest
  local best_count = 0
  local best_inv_idx

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
          best_inv_idx = inv.index
        end
        if n_trans == count then
          break
        end
      end
    end
  end
  if best_chest ~= nil then
    return best_chest, best_count, best_inv_idx
  end
end

-------------------------------------------------------------------------------

--[[
Find space in the logistic network for the items.
@entity is either a "character" or "roboport" (tower).
]]
--@field entity LuaEntity @ character or tower
--@field name string @ Item name
--@field count number @ Item count
function M.logistic_find_space(src_entity, mid_entity, net, name, count)
  if net == nil then
    return
  end

  local pt = net.select_drop_point{ stack={ name=name, count=count } }
  if pt == nil then
    return
  end

  if pt.owner.unit_number == src_entity.unit_number then
    return
  end

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
      return Globals.entity_get(pt.owner.unit_number), count, sinv.index
    end
  end
end

--[[
Find items in the logistic network.
@entity is either a "character" or "roboport" (tower).
@logistic_mode is the logistic mode of the taker.
]]
function M.logistic_find_items(dst_entity, mid_entity, net, name, count, request_from_buffers)
  if net == nil then
    return
  end

  local pt = net.select_pickup_point{ name=name, position=mid_entity.position, include_buffers=request_from_buffers }
  if pt == nil or pt.owner == nil then
    -- nothing in the network
    return
  end
  local src_entity = pt.owner

  --[[
  We have the entity that can supply stuff, but not the inventory.
  It can be a character, spidertron or chest.
  We want to grab from trash first, if possible.
  REVISIT: I'm not sure that a character or spidertron could show up here.
  ]]
  local sinva = {}
  if pt.owner.type == "character" then
    table.insert(sinva, defines.inventory.character_trash)
    table.insert(sinva, defines.inventory.character_main)
  elseif pt.owner.type == "spider-vehicle" then
    table.insert(sinva, defines.inventory.spider_trash)
    table.insert(sinva, defines.inventory.spider_trunk)
  else
    table.insert(sinva, defines.inventory.chest)
  end
  for _, inv_idx in ipairs(sinva) do
    local inv = src_entity.get_inventory(inv_idx)
    if inv ~= nil then
      -- get an accurate count
      count = math.min(count, inv.get_item_count(name))
      if count > 0 then
        return Globals.entity_get(pt.owner.unit_number), count, inv.index
      end
    end
  end
end

--[[
function M.find_chest_space3(src_entity, mid_entity, net, name, count, storage_ents)
  if net == nil then
    return M.find_chest_space(storage_ents, name, count)
  end
  return M.logistic_find_space(src_entity, mid_entity, net, name, count)
end
]]

function M.find_items(dst_entity, mid_entity, net, name, count, storage_ents, request_from_buffers)
  if net == nil then
    local logistic_mode = "none"
    local dst_inst = Globals.entity_get(dst_entity.unit_number)
    if dst_inst ~= nil then
      logistic_mode = dst_inst.nv.logistic_mode or "none"
    end
    return M.chest_find_items(dst_entity.unit_number, storage_ents, name, count, request_from_buffers, logistic_mode)
  end
  return M.logistic_find_items(dst_entity, mid_entity, net, name, count, request_from_buffers)
end

-------------------------------------------------------------------------------

--[[
Find something that will take the items.
If net ~= nil, the check the network for requests.

  -- if service_ents ~= nil then try to satisfy a request
  -- if storage_ents ~= nil then try to find a chest that will take it

@return instance, count, inventory.index
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
          return Globals.entity_get(pt.owner.unit_number), count, sinv.index
        end
      end
    end
  end

  -- no logistic taker, see if there is a request outside the network
  if type(service_ents) == "table" then
    for unum, _ in pairs(service_ents) do
      local inst = Globals.entity_get(unum)
      if inst ~= nil and inst.nv.request ~= nil then
        local req = inst.nv.request[name]
        if req ~= nil then
          -- trusting that an entity won't request what it can't hold (too complicated to check)
          local n_trans = math.min(req.count, count)
          if n_trans > 0 then
            return inst, n_trans, req.idx
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
function M.transfer_items(mid_entity, job)
  local src_entity = job.src
  local dst_entity = job.dst
  local name = job.name
  local count = job.count
  --src_entity, src_inv_idx, mid_entity, dst_entity, dst_inv_idx, name, count)
  local prot = game.item_prototypes[name]
  if prot == nil then
    return
  end

  -- this would be an error, even if the inventories are different
  if src_entity.unit_number == dst_entity.unit_number then
    return
  end

  local src_inv = src_entity.get_inventory(job.src_inv)
  local dst_inv = dst_entity.get_inventory(job.dst_inv)
  if src_inv == nil or dst_inv == nil then
    return
  end

  -- remove items from the source
  local n_trans = src_inv.remove({ name=name, count=count })
  if n_trans == 0 then
    return
  end

  -- add items to the dest
  local n_added = dst_inv.insert({ name=name, count=n_trans })

  -- return any that didn't fit
  if n_added < n_trans then
    src_inv.insert({ name=name, count=n_trans - n_added })
  end

  if M.debug_trans then
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

return M
