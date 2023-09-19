--[[
Class for a TransferTower.

REVISIT #27:
It might be a good idea to break the transer into two parts.
- pull items from provider chests
- pull items from storage to satisfy a request
- send items to satisfy a request

Breaking it up like that might make it worthwhile to put stuff in the tower for
distribution. At a cost of more processing time.
]]
local Globals = require('src.Globals')
local clog = require("src.log_console").log
local shared = require("shared")
local EntityHandlers = require 'src.EntityHandlers'
local Queue = require "src.Queue"

local M = {} -- module (create function)
local TransferTower = {} -- class functions
local TransferTower_Meta = { __index = TransferTower }

--[[ this is called to destory the class data.
The entity should have already been destroyed.
So, we just need to unhook from the list.
If there was something else to clean up, we'd do it now.
]]
function TransferTower:destroy()
  if self.nv.entity ~= nil then
    -- clear entity to mark destroy() as complete
    self.nv.entity = nil
  end
end

function TransferTower:IsValid()
  local entity = self.nv.entity
  return entity ~= nil and entity.valid
end

-- generic IsValid to see if the inst is a TransferTower: usage: TransferTower.IsValid(inst)
function M.IsValid(tower)
  return (tower ~= nil) and (getmetatable(tower) == TransferTower_Meta) and tower:IsValid()
end

-------------------------------------------------------------------------------

-- removes invalid items from self.nv.service_entities and self.nv.storage_entities
function TransferTower:purge_invalid()
  -- REVISIT: lua spec says setting a key to nil does not break table iteration. make sure that is true?
  for unum, _ in pairs(self.nv.service_entities) do
    if Globals.entity_get(unum) == nil then
      self.nv.service_entities[unum] = nil
    end
  end
  for unum, _ in pairs(self.nv.storage_entities) do
    if Globals.entity_get(unum) == nil then
      self.nv.storage_entities[unum] = nil
    end
  end
end

function TransferTower:scan()
  local entity = self.nv.entity
  local ents = entity.surface.find_entities_filtered({ area=self.nv.reach_box, name=Globals.get_entity_names() })
  for _, ent in ipairs(ents) do
    --clog("scan[%s]: %s @ (%s,%s)", ent.unit_number, ent.name, ent.position.x, ent.position.y)
    -- we handle ourself as a storage node
    if Globals.is_storage_name(ent.name) then
      self.nv.storage_entities[ent.unit_number] = true
    end
    if Globals.is_service_name(ent.name) then
      self.nv.service_entities[ent.unit_number] = true
    end
  end
  self.nv.need_scan = false
  self.tick_scan = game.tick
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
function TransferTower:find_job()
  local entity = self.nv.entity
  local handled_unums = self.nv.handled_unums

  local net = entity.logistic_network
  if net == nil then
    return nil
  end

  for unum, _ in pairs(self.nv.service_entities) do
    local inst = Globals.entity_get(unum)

    if inst ~= nil and (handled_unums[unum] ~= true) and (inst.nv.priority or 0) > 0 then
      for name, count in pairs(inst.nv.provide or {}) do
        local chest, n_free = EntityHandlers.find_chest_space2(inst.nv.entity, entity, net, name, count)
        if chest ~= nil then
          return { src=inst.nv.entity, src_inst=inst, dst=chest.nv.entity, dst_inst=chest, name=name, count=n_free }
        end
      end

      --[[
        A requester cannot request from another requester.
        A requester may request from a buffer if request_from_buffers is set.
        A buffer may NOT request from a requester or another buffer.
      ]]
      for name, count in pairs(inst.nv.request or {}) do
        local dst_ent = inst.nv.entity
        -- logistic chests generally cannot pull from requester
        local request_from_buffers = true
        if dst_ent.type == "logistic-container" then
          -- two types: 'buffer' and 'requester'. 'requester' can pull from 'buffer' if enabled, buffers can't.
          request_from_buffers = false
          if dst_ent.prototype.logistic_mode == "requester" and dst_ent.request_from_buffers then
            request_from_buffers = true
          end
        end

        local chest, n_avail = EntityHandlers.find_chest_items2(dst_ent, entity, net, name, count, request_from_buffers)
        if chest ~= nil then
          return { src=chest.nv.entity, src_inst=chest, dst=inst.nv.entity, dst_inst=inst, name=name, count=n_avail }
        end
      end

      handled_unums[unum] = true
    end
  end
  -- make the linter happy
  return nil
end

--[[
This is called periodically.
It transfers items within the logistic network.
]]
function TransferTower:service()
  -- don't process more than 1 Hz
  local elapsed = game.tick - (self.tick_service or 0)
  if elapsed < 60 then
    return
  end
  self.tick_service = game.tick

  --[[ Make sure we have enough energy.
    Energy starts around 10,000,000
      Full charge is about 100,000,000
    So, a mim of 20 Mj seems OK. Usage of 5 Mj might be a bit much, but we'll see.
  ]]
  local entity = self.nv.entity
  if entity.energy < shared.transfer_tower_power_min then
    --clog("[%s]TransferTower[%s]: energy=%s LOW POWER",
    --  game.tick, self.nv.unit_number, entity.energy)
    return
  end

  -- re-scan if storage was added/removed since last scan
  if (self.tick_scan or 0) <= Globals.storage_get_tick() then
    self.nv.need_scan = true
  end

  if self.nv.need_scan then
    self:scan()
  end
  self:purge_invalid()

  --local prot = entity.prototype
  --clog("[%s]TransferTower[%s]: energy=%s usage=%s max=%s",
  --  game.tick, self.nv.unit_number, entity.energy, prot.energy_usage, prot.max_energy_usage)

  local job = self:find_job()
  if job == nil then
    self.nv.handled_unums = {}
    return
  end

  EntityHandlers.transfer_items(job.src, self.nv.entity, job.dst, job.name, job.count)
  entity.energy = entity.energy - shared.transfer_tower_power_usage

  -- refresh the entity status
  local function call_service(inst)
    if inst ~= nil and type(inst.service) == "function" then
      inst:service(true)
    end
  end
  call_service(job.src_inst)
  call_service(job.dst_inst)
end

-------------------------------------------------------------------------------

--[[
  Create the instance for the entity.
]]
function M.create(nv)
  local entity = nv.entity

  -- create nv data
  if nv.reach_box == nil then
    nv.reach = shared.transfer_tower_reach
    nv.need_scan = true
    nv.reach_box = {
      { entity.position.x - nv.reach, entity.position.y - nv.reach },
      { entity.position.x + nv.reach, entity.position.y + nv.reach },
    }
    nv.service_queue = Queue.new()
    nv.service_entities = {}
    nv.storage_entities = {}
    nv.handled_unums = {}
  end

  local self = {
    __class = "TransferTower",
    nv = nv,

    localised_name = { shared.transfer_tower_name },
  }
  setmetatable(self, TransferTower_Meta)

  clog("TransferTower: Created %s [%s]", entity.name, self.nv.unit_number)

  return self
end
-------------------------------------------------------------------------------

Globals.register_handler("name", shared.transfer_tower_name, M.create)

return M
