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
    self.nv.entity = nil
    -- remove myself from the tower list (is that used?)
    Globals.tower_del(self.nv.unit_number)
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
This is called periodically (evert 30 ticks?)
It should drive the AI.

  - find a job
  - do the job
  - wander between Golem Poles
]]
function TransferTower:service()
  -- don't process more than 1 Hz
  local elapsed = game.tick - (self.tick_service or 0)
  if elapsed < 60 then
    return
  end
  self.tick_service = game.tick

  -- re-scan if storage was added/removed since last scan
  if (self.tick_scan or 0) <= Globals.storage_get_tick() then
    self.nv.need_scan = true
  end

  if self.nv.need_scan then
    self:scan()
  end
  self:purge_invalid()
--[[
  clog("[%s]TransferTower[%s]: storage=%s ents=%s", game.tick, self.nv.unit_number,
    serpent.line(self.nv.storage_entities),
    serpent.line(self.nv.service_entities))
]]
  local job = EntityHandlers.find_best_job(self.nv.service_entities, self.nv.storage_entities, self.nv.handled_unums)
  if job == nil then
    self.nv.handled_unums = {}
    return
  end

  EntityHandlers.transfer_items(job.src, self.nv.entity, job.dst, job.name, job.count)

  -- refresh the entity status
  if job.inst ~= nil then
    self.nv.handled_unums[job.inst.nv.unit_number] = true
    job.inst:service(true)
  end
end

-------------------------------------------------------------------------------
-- this is the TransferTower factory

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

  -- register myself
  Globals.tower_add(self)
  return self
end

-- get the instance associated with this unit_number
function M.get(unit_number)
  return Globals.tower_get(unit_number)
end

Globals.register_handler("name", shared.transfer_tower_name, M.create)

return M
