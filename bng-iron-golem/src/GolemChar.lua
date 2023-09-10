--[[
Class for a Golem.
]]
local Globals = require('src.Globals')
local clog = require("src.log_console").log
local shared = require("shared")
local Event = require('__stdlib__/stdlib/event/event')

-- this is a Golem class
local GolemChar = {}

--[[ this is called to destory the class data.
The entity should have already been destroyed.
]]
function GolemChar:destroy()
  clog("GolemChar[%s] destroyed", self.unit_number)
  if self.entity ~= nil and self.entity.valid then
    self.entity.die(nil, nil)
    self.entity = nil
  end
end

function GolemChar:IsValid()
  return self.entity ~= nil and self.entity.valid
end

-------------------------------------------------------------------------------
-- AI stuff

--[[
This is called periodically (evert 30 ticks?)
It should drive the AI.

  - find a job
  - do the job
  - wander between Golem Poles
]]
function GolemChar:tick()

end

-------------------------------------------------------------------------------
-- inventory stuff

function GolemChar:get_output_inventory()
  return self.entity.get_output_inventory()
end

function GolemChar:insert(itemstack)
  return self.entity.insert(itemstack)
end

function GolemChar:remove_items(items)
  return self.entity.remove(items)
end

function GolemChar:get_item_count(item)
  return self.entity.get_item_count(item)
end

-------------------------------------------------------------------------------
-- this is the golem factory
local M = {}

--[[
  Create the Golem instance for the entity.
]]
function M.create(entity)
  if entity ~= nil and entity.valid and entity.name == shared.golem_player_name then
    local self = {
      __class = "GolemChar",
      entity = entity,
      unit_number = entity.unit_number,
      localised_name = { shared.golem_name },
      -- other fields???
    }
    setmetatable(self, { __index = GolemChar })

    -- give it some ammo and a gun
    entity.get_inventory(defines.inventory.character_guns).insert({name="submachine-gun", count=1})
    entity.get_inventory(defines.inventory.character_ammo).insert({name="uranium-rounds-magazine", count=200})

    clog("Created %s", entity.name)

    Globals.golem_add(self)
    return self
  end
end

-- get the instance associated with this unit_number
function M.get(unit_number)
  return Globals.golem_get(unit_number)
end

Globals.register_metaclass("GolemChar", { __index = GolemChar })

return M
