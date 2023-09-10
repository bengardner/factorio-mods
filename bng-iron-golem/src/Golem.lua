--[[
Class for a Golem.
]]
local Globals = require('src.Globals')
local clog = require("src.log_console").log
local shared = require("shared")
local Event = require('__stdlib__/stdlib/event/event')
local Jobs = require 'src.Jobs'
local EntityHandlers = require 'src.EntityHandlers'

-- this is a Golem class
local Golem = {}

--[[ this is called to destory the class data.
The entity should have already been destroyed.
]]
function Golem:destroy()
  clog("Golem[%s] destroyed", self.unit_number)
  if self.chest_entity ~= nil then
    -- NOTE: we are not dropping the inventory on the ground
    self.chest_entity.destroy()
    self.chest_entity = nil
  end
  if self.entity ~= nil and self.entity.valid then
    clog("die=%s", self.entity.die)
    self.entity.destroy()
    self.entity = nil
  end
end

function Golem:IsValid()
  return self.entity ~= nil and self.entity.valid and self.chest_entity ~= nil and self.chest_entity.valid
end

-------------------------------------------------------------------------------
-- AI stuff

function Golem:say(text)
  if not (self.entity and self.entity.valid) then return end
  clog("%s[%s]: %s", self.name, self.unit_number, text)
  self.entity.surface.create_entity{name="flying-text", position=self.entity.position, text=text}
end

function Golem:ai_wait(ticks)
  self.entity.set_command {
    type = defines.command.stop,
    ticks_to_wait = ticks,
    distraction = defines.distraction.none,
  }
  self:say("waiting")
end

function Golem:get_waypoint()
  if self.visited_waypoints == nil then
    self.visited_waypoints = {}
  end
  for _ = 1,2 do
    local wp = Globals.find_storage_chests(self.entity.surface, self.entity.position, 40)
    for _, ent in ipairs(wp) do
      if ent.valid and self.visited_waypoints[ent.unit_number] == nil then
        self.visited_waypoints[ent.unit_number] = game.tick
        return  ent
      end
    end
    self.visited_waypoints = {}
  end
end

function Golem:visit_next_waypoint()
  local ent = self.entity

  local wp = self:get_waypoint()
  if wp ~= nil then
    local commands = {
      {
        type = defines.command.go_to_location,
        destination = wp.position,
        radius = 3,
      },
      {
        type = defines.command.stop,
        ticks_to_wait = 10*60,
      }
    }

    ent.set_command {
      type = defines.command.compound,
      structure_type = defines.compound_command.return_last,
      distraction = defines.distraction.none,
      commands = commands
    }
    self:say(string.format("going to (%s,%s)", wp.position.x, wp.position.y))
    return
  end
  -- no waypoints, so we should stay stopped for a while
  self:ai_wait(120)
end

--[[
  Do something is called whenever there is nothing to do.
]]
function Golem:do_something()
  self:visit_next_waypoint()
end

--[[
This is called periodically (evert 30 ticks?)
It should drive the AI.

  - find a job
  - do the job
  - wander between Golem Poles
]]
function Golem:tick()
  -- don't service more than once per second
  local tick_delta = game.tick - (self.tick_check or 0)
  if tick_delta < 60 then
    return
  end
  self.tick_check = game.tick

  -- try to find something to do
  local g_entity = self.entity
  local g_inv = self:get_output_inventory()
  local reach = 40 -- self.range
  local empty_stacks = g_inv.count_empty_stacks()
  local avail = g_inv.get_contents()

  local storage = Globals.find_storage_chests2(g_entity.surface, g_entity.position, reach)
  for _, st_ent in pairs(storage) do
    local inv = st_ent.get_output_inventory()
    empty_stacks = empty_stacks + inv.count_empty_stacks()
    for name, count in pairs(inv.get_contents()) do
      avail[name] = (avail[name] or 0) + count
    end
  end

  --clog("golem job e=%s a=%s", empty_stacks, serpent.line(avail))

  local job = Jobs.request_a_job(
    g_entity.position,
    reach,
    empty_stacks,
    avail)

  if job ~= nil then
    clog("golem found job %s", serpent.line(job))

    EntityHandlers.service_entity(job.entity.unit_number, g_entity, g_inv, storage)
    self.tick_action = game.tick
    -- stop sill if working
    self:ai_wait(60)
    return
  else
    -- nothing to do here
    tick_delta = game.tick - (self.tick_action or 0)
    if tick_delta > 10*60 then
      self:visit_next_waypoint()
      self.tick_action = game.tick
    end
  end
end

function Golem:CommandComplete(event)
  clog("%s[%s] command complete result=%s distracted=%s", self.name, self.unit_number, event.result, event.was_distracted)
  -- add a stop/wait until the next service period
  self:ai_wait(120)
end

-------------------------------------------------------------------------------
-- inventory stuff

function Golem:get_output_inventory()
  if self:IsValid() then
    return self.chest_entity.get_output_inventory()
  end
end

function Golem:insert(itemstack)
  if self:IsValid() then
    return self.chest_entity.insert(itemstack)
  end
end

function Golem:remove_items(items)
  if self:IsValid() then
    return self.chest_entity.remove(items)
  end
end

function Golem:get_item_count(item)
  if self:IsValid() then
    return self.chest_entity.get_item_count(item)
  end
end

-------------------------------------------------------------------------------
-- this is the golem factory
local M = {}

local function create_inv_chest(entity)
  local surface = Globals.surface_get()
  local chest = surface.create_entity {
    name = shared.golem_inv_chest_name,
    position = entity.position,
    force = entity.force,
    raise_built = false,
  }
  chest.minable = false
  chest.destructible = false
  -- want it to be hidden and non-selectable
  return chest
end

--[[
  Create the Golem instance for the entity.
]]
function M.create(entity)
  if entity ~= nil and entity.valid and entity.name == shared.golem_name then
    local self = {
      __class = "Golem",
      entity = entity,
      name = entity.name,
      unit_number = entity.unit_number,
      chest_entity = create_inv_chest(entity),
      localised_name = { shared.golem_name },
      IsValid = Golem.IsValid,
      visited_waypoints = {},
      range = 40,
      -- other fields???
    }
    setmetatable(self, { __index = Golem })
    clog("Created %s", entity.name)
    Globals.golem_add(self)
    return self
  end
end

function M.destroy_unit_number(unit_number)
  local self = Globals.golem_get(unit_number)
  if self ~= nil then
    self:destroy()
  end
end

-- get the instance associated with this unit_number
function M.get(unit_number)
  return Globals.golem_get(unit_number)
end

local function on_ai_command_completed(event)
  local golem = M.get(event.unit_number)
  if golem ~= nil and golem:IsValid() then
    golem:CommandComplete(event)
  end
end

Event.register(defines.events.on_ai_command_completed, on_ai_command_completed)

Globals.register_metaclass("Golem", { __index = Golem })

return M
