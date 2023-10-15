
local function on_player_events(event)
  local player = game.get_player(event.player_index)
  if player ~= nil and player.character ~= nil then
    player.character_mining_speed_modifier = 3
    player.character_crafting_speed_modifier = 3
  end
end

script.on_event(
  {
    defines.events.on_player_created,
    defines.events.on_cutscene_cancelled,
    defines.events.on_cutscene_finished,
  },
  on_player_events
)
