--[[
Class for a StorageChest.
]]
local Globals = require('src.Globals')
local shared = require("shared")
local clog = require("src.log_console").log

local StorageChest = {}
local StorageChest_Meta = { __index = StorageChest }

--[[ this is called to destory the class data.
The entity should have already been destroyed.
So, we just need to unhook from the list.
If there was something else to clean up, we'd do it now.
]]
function StorageChest:destroy()
  -- TODO: do we really need to do anything? everyone will eventual drop invalid handles
  Globals.storage_del(self)
end

function StorageChest:IsValid()
  return self.nv ~= nil and self.nv.entity ~= nil and self.nv.entity.valid
end

--[[
This is called periodically.
IsValid() is called right before this.
]]
function StorageChest:service()
  -- limit to 1 hz (for slower debug logs)
  local delta = game.tick - (self.service_tick or 0)
  if delta < 60 then
    return
  end
  self.service_tick = game.tick

  local ent = self.nv.entity

 -- clog("storage: %s[%s] type=%s fi=%s log=%s", ent.name, ent.unit_number, ent.type, ent.filter_slot_count, self.nv.is_logistic)

  local inv = ent.get_output_inventory()

  -- i'm not really sure caching this is a win.. but it helps debug.
  self.nv.is_empty = inv.is_empty()
  --self.nv.is_full = inv.is_full()
  --self.nv.contents = inv.get_contents()

  --clog("service[%s]: is_empty=%s is_full=%s contents=%s", self.nv.unit_number, self.nv.is_empty, self.nv.is_full, serpent.line(self.nv.contents))
end

-------------------------------------------------------------------------------
-- this is the StorageChest factory
local M = {}

--[[
  Create the instance for the entity. nv.entity is valid.
]]
function M.create(nv)
  local entity = nv.entity

  local self = {
    __class = "StorageChest",
    nv = nv,
    localised_name = { shared.chest_names.storage },
  }
  nv.is_logistic = (entity.type == "logistic-container")
  setmetatable(self, StorageChest_Meta)

  clog("StorageChest: Created %s [%s] @ %s", entity.name, self.nv.unit_number, serpent.line(entity.position))

  -- register myself
  Globals.storage_add(self)
  return self
end

function M.IsValid(inst)
  return (inst ~= nil) and (getmetatable(inst) == StorageChest_Meta) and inst:IsValid()
end

Globals.register_handler("name", shared.chest_names.storage, M.create)
--Globals.register_handler("name", shared.chest_name_storage, M.create)
Globals.register_handler("logistic-mode", "storage", M.create)

return M
