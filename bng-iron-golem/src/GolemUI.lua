--[[
Handles the GUI for the IronGolem.
A player may only have one Golem Gui open at a time.
]]
local Event = require('__stdlib__/stdlib/event/event')
local Gui = require('__stdlib__/stdlib/event/gui')
local Globals = require('src.Globals')
local clog = require("src.log_console").log
local shared = require("shared")
local UiCharacterInventory = require("src.UiCharacterInventory")
local UiInventory = require("src.UiInventory")
local UiConstants = require "src.UiConstants"

-- this table only contains the create method and event handlers
local M = {}

M.MAX_HEIGHT = 600

-- this is a GUI instance
local GolemUI = {}

-- get the golem table (which may be nil) and the ui structure
function M.gui_get(player_index)
  return Globals.get_ui_state(player_index).golem
end

-- sets the golem UI table (create or destroy)
function M.gui_set(player_index, value)
  Globals.get_ui_state(player_index).golem = value
end
function M.destroy_by_unit_number(unit_number)
  for _, inst in pairs(Globals.get_player_guis("golem")) do
    if inst.golem.unit_number == unit_number then
      inst:destroy()
    end
  end
end

function M.destroy_by_player_index(player_index)
  local self = M.gui_get(player_index)
  if self ~= nil then
    self:destroy()
  end
end

--[[
  Create the GUI for the player/entity combo.
]]
function M.create(player_index, golem)
  -- close the gui if one is present
  local self = M.gui_get(player_index)
  if self ~= nil then
    self:destroy()
  end

  local player = game.get_player(player_index)
  if player == nil then
    return
  end

  -- create the main window
  local frame = player.gui.screen.add({
    type = "frame",
    name = UiConstants.UIGOLEM_FRAME,
    style = "inset_frame_container_frame",
  })
  frame.style.horizontally_stretchable = true
  frame.style.vertically_stretchable = true
  frame.style.maximal_height = M.MAX_HEIGHT
  frame.auto_center = true

  -- create a new "class"
  self = {
    __class = "GolemUI",
    player = player,
    frame = frame,
    golem = golem,
    elems = {},
    children = {},
    IsValid = GolemUI.IsValid,
  }
  setmetatable(self, { __index = GolemUI })

  -- shorter ref (needed?)
  local elems = self.elems

  -- need a vertical flow to wrap (header, body)
  local main_flow = frame.add({
    type = "flow",
    direction = "vertical",
  })
  main_flow.style.horizontally_stretchable = true
  main_flow.style.vertically_stretchable = true

  -- create the flow for the header/title bar
  local header_flow = main_flow.add({
    type = "flow",
    direction = "horizontal",
  })
  header_flow.drag_target = frame
  header_flow.style.height = 24

  header_flow.add {
    type = "label",
    caption = "Iron Golem",
    style = "frame_title",
    ignored_by_interaction = true,
  }

  local header_drag = header_flow.add {
    type = "empty-widget",
    style = "draggable_space_header",
    ignored_by_interaction = true,
  }
  header_drag.style.horizontally_stretchable = true
  header_drag.style.vertically_stretchable = true
  --header_drag.style.height = 20

  header_flow.add {
    name = UiConstants.UIGOLEM_REFRESH_BTN,
    type = "sprite-button",
    sprite = "utility/refresh",
    style = "frame_action_button",
    tooltip = { "gui.refresh" },
  }

  elems.close_button = header_flow.add {
    name = UiConstants.UIGOLEM_CLOSE_BTN,
    type = "sprite-button",
    sprite = "utility/close_white",
    hovered_sprite = "utility/close_black",
    clicked_sprite = "utility/close_black",
    style = "close_button",
  }

  -- add shared body area
  local body_flow = main_flow.add({
    type = "flow",
    direction = "horizontal",
  })

  -- dummy flow to be the parent of the character inventory
  local left_pane = body_flow.add({
    type = "flow",
  })

  local right_pane = body_flow.add({
    type = "flow",
  })

  self.children.char_inv = UiCharacterInventory.create(left_pane, player)
  self.children.golem_inv = UiInventory.create(right_pane, player, golem)

  -- connect the two windows to transfer inventory with shortcuts
  self.children.char_inv.peer = self.children.golem_inv
  self.children.golem_inv.peer = self.children.char_inv

  local scroll_pane = self.children.golem_inv.elems.scroll_pane
  local storage_frame = scroll_pane.add{
    type = "flow",
    direction = "horizontal",
  }

  self.elems.storage_frame = storage_frame

  storage_frame.add({
    type = "label",
    style = "frame_title",
    caption = "TODO: put something here. target? task? state?",
    ignored_by_interaction = true,
  })
  self:update_storage_chest_info()

  -- make this the foreground player GUI
  player.opened = frame

  -- save the GUI data for this player
  M.gui_set(player_index, self)

  -- refresh the page
  self:refresh()
end

-------------------------------------------------------------------------------
-- Instance methods

function GolemUI:destroy()
  if self.player ~= nil then
    -- break the link to prevent future events
    M.gui_set(self.player.index, nil)

    -- close the GUI
    local player = self.player
    if player.opened == self.elems.main_window then
      player.opened = nil
    end
    self.player = nil

    -- call destructor on any child classes
    for _, ch in pairs(self.children) do
      if type(ch.destroy) == "function" then
        ch.destroy(ch)
      end
    end

    -- destroy the UI
    self.frame.destroy()
  end
end

function GolemUI:refresh()
  for _, ch in pairs(self.children) do
    if type(ch.refresh) == "function" then
      ch.refresh(ch)
    end
  end
  self:update_storage_chest_info()
end

function GolemUI:update_storage_chest_info()
  local gent = self.golem.entity
  if gent ~= nil and gent.valid then
    local pp = self.elems.storage_frame
    pp.clear()

    for _, ent in ipairs(Globals.find_storage_chests(gent.surface, gent.position, 20)) do
      clog("near: %s @ (%s,%s)", ent.name, ent.position.x, ent.position.y)
    end
  end
end

-------------------------------------------------------------------------------
-- Events

function M.on_click_refresh_button(event)
  -- needed to refresh the network item list, which can change rapidly
  local self = M.gui_get(event.player_index)
  if self ~= nil then
    self:refresh()
  end
end

function M.on_click_close_button(event)
  local self = M.gui_get(event.player_index)
  if self ~= nil then
    self:destroy()
  end
end

-- triggered if the GUI is removed from self.player.opened
function M.on_gui_closed(event)
  local self = M.gui_get(event.player_index)
  if self ~= nil then
    self:destroy()
  end
end

Gui.on_click(UiConstants.UIGOLEM_CLOSE_BTN, M.on_click_close_button)
Gui.on_click(UiConstants.UIGOLEM_REFRESH_BTN, M.on_click_refresh_button)
-- Gui doesn't have on_gui_closed, so add it manually
Event.register(defines.events.on_gui_closed, M.on_gui_closed, Event.Filters.gui, UiConstants.UIGOLEM_FRAME)

Globals.register_metaclass("GolemUI", { __index = GolemUI})

return M
