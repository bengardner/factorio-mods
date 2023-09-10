--[[
Helper functions for players.
This does the job service stuff.
]]
local Globals = require('src.Globals')
local Jobs = require 'src.Jobs'
local EntityHandlers = require 'src.EntityHandlers'
local clog = require("src.log_console").log

local M = {}

--[[
This is called periodically to service surrounding entities
]]
function M.service(player, info)
  -- don't service more than 2 Hz
  local tick_delta = game.tick - (info.tick_service or 0)
  if tick_delta < 120 then
    return
  end
  info.tick_service = game.tick

  --clog("[%s] Player.service: %s", game.tick, player.name)

  -- try to find something to do
  local p_entity = player.character
  local reach = 10 -- player.reach_distance
  local p_inv = p_entity.get_main_inventory()

  -- calculate empty_stacks and avail (player first)
  local empty_stacks = p_inv.count_empty_stacks()
  local avail = p_inv.get_contents()

  -- add in storage
  local storage = Globals.find_storage_chests2(p_entity.surface, p_entity.position, reach)
  for _, st_ent in pairs(storage) do
    local inv = st_ent.get_output_inventory()
    empty_stacks = empty_stacks + inv.count_empty_stacks()
    for name, count in pairs(inv.get_contents()) do
      avail[name] = (avail[name] or 0) + count
    end
  end

  --clog("empty=%s avail=%s storage=%s", empty_stacks, serpent.line(avail), serpent.line(storage))

  local job = Jobs.request_a_job(p_entity.position, reach, empty_stacks, avail)
  if job ~= nil then
    EntityHandlers.service_entity(job.entity.unit_number, p_entity, p_inv, storage)
    info.tick_action = game.tick
  end
end

return M
