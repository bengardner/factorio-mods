--[[
Attaches to the events to register and remove entities.
]]
local Event = require('__stdlib__/stdlib/event/event')
local Globals = require('src.Globals')
local clog = require("src.log_console").log
local shared = require("shared")
local Golem = require("src.Golem")
local GolemUI = require("src.GolemUI")
local GolemChar = require("src.GolemChar")
local Player = require("src.Player")

local M = {}

--- handles all events that add an entity
function M.on_entity_add(event)
  local entity = event.created_entity or event.entity or event.destination
  if entity == nil or not entity.valid then
    return
  end

  clog("Adding %s @ (%s,%s) ninv=%s", entity.name, entity.position.x, entity.position.y, entity.get_max_inventory_index())

  if entity.name == shared.golem_name then
    Golem.create(entity)

  elseif entity.name == shared.golem_player_name then
    GolemChar.create(entity)
    --clog("Not handling golem right now")

  elseif Globals.is_tracked_entity(entity) then
    Globals.entity_add(entity)

  end
end

--- handles all events that remove an entity
function M.on_entity_remove(event)
  local entity = event.created_entity or event.entity or event.destination
  if entity == nil or not entity.valid or entity.unit_number == nil then
    return
  end

  if entity.name == shared.golem_name or entity.name == shared.golem_player_name then
    Globals.golem_del(entity.unit_number)

  else
    -- just clears the entry. Safe if we don't track entity.
    Globals.entity_del(entity.unit_number)
  end
end

-- service one entity per tick
function M.on_tick(event)
  -- setup Globals on the first tick.
  Globals.setup()

  -- queue_pop() checks entity.valid and removes invalid entities
  local info = Globals.queue_pop()
  if info ~= nil then
    local entity = info.entity
    if entity ~= nil and info.handler ~= nil then
      --clog("calling handler for %s @ (%s,%s)", entity.name, entity.position.x, entity.position.y)
      info.handler(entity, info)
      -- if the entity survived the handler, then we add it to the queue again
      if entity.valid then
        Globals.queue_push(entity.unit_number)
      end
    end
  end

  -- calling the Golem tick every two seconds (FIXME)
  if game.tick % 10 == 0 then
    local golem = Globals.golem_queue_pop()
    if golem ~= nil then
      golem:tick()
      if golem:IsValid() then
        Globals.golem_queue_push(golem.unit_number)
      end
    end
  end

  if game.tick % 10 == 5 then
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

function M.open_golem_gui(event)
  local player = game.players[event.player_index]
  if player ~= nil and player.selected ~= nil then
    local entity = player.selected
    if entity.name == shared.golem_name then
      local golem = Golem.get(entity.unit_number)
      if golem ~= nil then
        GolemUI.create(event.player_index, golem)
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
    defines.events.on_marked_for_deconstruction,
    defines.events.on_post_entity_died,
  },
  M.on_entity_remove
)

Event.on_nth_tick(1, M.on_tick)

Event.on_init(Globals.setup)

Event.on_event("golem-open-gui", M.open_golem_gui)

Event.on_load(Globals.restore_metatables)

return M
