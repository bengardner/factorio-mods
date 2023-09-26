--[[
Attaches to the events to register and remove entities.
]]
local Event = require('__stdlib__/stdlib/event/event')
local Globals = require('src.Globals')
--local clog = require("src.log_console").log
local Player = require("src.Player")

local M = {}

--- handles all events that add an entity
function M.on_entity_add(event)
  local entity = event.created_entity or event.entity or event.destination
  if entity ~= nil and entity.valid then
    Globals.entity_add(entity)
  end
end

--- handles all events that remove an entity
function M.on_entity_remove(event)
  local entity = event.entity
  if entity ~= nil and entity.valid and entity.unit_number ~= nil then
    Globals.entity_remove(entity.unit_number)
  end
  local unit_number = event.unit_number
  if unit_number ~= nil then
    Globals.entity_remove(unit_number)
  end
end

-- service one entity per tick
function M.on_tick(event)
  -- setup Globals on the first tick.
  Globals.setup()

  -- service_queue_pop() checks entity.valid and removes invalid entities
  local inst = Globals.service_queue_pop()
  if inst ~= nil then
    -- wouldn't be on the service queue without 'service', but we check anyway.
    if type(inst.service) == "function" then
      inst:service()
      -- if the entity survived the handler, then we add it to the queue again
      if inst:IsValid() then
        Globals.service_queue_push(inst.nv.unit_number)
      end
    end
  end

  -- players/characters are serviced at 6 Hz
  if game.tick % 10 == 0 then
    for player_index, player in pairs(game.players) do
      if player.character ~= nil then
        local pi = Globals.get_player_info(player_index)
        if pi.service == nil then
          pi.service = {}
        end
        Player.service(player, pi.service)
      end
    end
  end
end

Event.on_event({
    defines.events.on_built_entity,
    defines.events.script_raised_built,
    defines.events.on_entity_cloned,
    defines.events.on_robot_built_entity,
    defines.events.script_raised_revive,
  },
  M.on_entity_add
)

Event.on_event({
    defines.events.on_pre_player_mined_item,
    defines.events.on_robot_mined_entity,
    defines.events.script_raised_destroy,
    defines.events.on_entity_died,
    defines.events.on_post_entity_died,
  },
  M.on_entity_remove
)

Event.on_nth_tick(1, M.on_tick)
Event.on_init(Globals.setup)
Event.on_load(Globals.restore_metatables)

return M
