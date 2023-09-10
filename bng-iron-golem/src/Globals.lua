--[[
Global data, some of which is persistent..
We own all of "global", but mostly restrict our data to "global.mod"
]]
local Queue = require "src.Queue"
local shared = require('shared')
local clog = require("src.log_console").log

local M = {}

local setup_has_run = false

function M.setup()
  if setup_has_run then
    return
  end
  setup_has_run = true

  M.inner_setup()
end

function M.inner_setup()
  -- player info, indexed by player_index
  if global.player_info == nil then
    global.player_info = {}
  end

  -- other module data
  if global.mod == nil then
    global.mod = {
      entities = {}, -- key=unit_number, val={ entity=entity, handler=fcn }
      scan_queue = Queue.new(),
    }
  end

  if global.mod.golems == nil then
    -- key=unit_number, val={ entity=entity, inv=inventory, other data? } See "Golem" class.
    global.mod.golems = {}
  end

  --M.surface_get()
  M.restore_metatables()

  -- FIXME: during testing I reset the queues at startup
  M.entity_scan()
  M.reset_queues()
end

-------------------------------------------------------------------------------

-- get or create the extra surface where we put the chests for the golems
function M.surface_get()
  local surface = game.get_surface(shared.surface_name)
  if surface ~= nil then
    clog("surface: found")
  else
    surface = game.create_surface(shared.surface_name, { width=100, height=100 })
  end
  return surface
end

-------------------------------------------------------------------------------

-- DEBUG: re-scan the surfaces for entities that we track
function M.entity_scan()
  global.mod.entities = {}
  for _, surface in pairs(game.surfaces) do
    local entities = surface.find_entities()
    for _, entity in ipairs(entities) do
      local handler = M.get_entity_handler(entity)
      if handler ~= nil then
        M.entity_add(entity, handler)
      end
    end
  end
end

function M.reset_queues()
  global.mod.scan_queue = Queue.new()
  for unum, _ in pairs(global.mod.entities) do
    M.queue_push(unum)
  end

  global.mod.golem_queue = Queue.new()
  for unum, _ in pairs(global.mod.golems) do
    M.golem_queue_push(unum)
  end
end

-------------------------------------------------------------------------------

-- list of handlers:
-- { check=func, arg=value, handler=handler }
M.handlers = { }

local function fcn_type(entity, arg)
  return entity.type == arg
end

local function fcn_name(entity, arg)
  return entity.name == arg
end

local function fcn_fuel(entity, arg)
  return entity.get_fuel_inventory() ~= nil
end

local function fcn_ammo(entity, arg)
  return entity.get_ammo_inventory() ~= nil
end

function M.register_handler(ftype, farg, handler)
  if ftype == "type" then
    table.insert(M.handlers, { check=fcn_type, arg=farg, handler=handler })
  elseif ftype == "name" then
    table.insert(M.handlers, { check=fcn_name, arg=farg, handler=handler })
  elseif ftype == "fuel" then
    table.insert(M.handlers, { check=fcn_fuel, handler=handler })
  elseif ftype == "ammo" then
    table.insert(M.handlers, { check=fcn_ammo, handler=handler })
  end
end

-- Get the handler function for an entity
function M.get_entity_handler(entity)
  if entity ~= nil and entity.valid then
    for _, ent in ipairs(M.handlers) do
      if ent.check(entity, ent.arg) == true then
        return ent.handler
      end
    end
  end
end

-- Check to see if an entity is tracked
function M.is_tracked_entity(entity)
  return M.get_entity_handler(entity) ~= nil
end

function M.entity_add(entity, handler)
  if handler == nil then
    handler = M.get_entity_handler(entity)
  end
  if entity ~= nil and entity.valid and entity.unit_number ~= nil and handler ~= nil then
    local unum = entity.unit_number
    clog("entity_add[%s]: %s @ (%s,%s) handler=%s", unum, entity.name, entity.position.x, entity.position.y, handler)
    if global.mod.entities[unum] == nil then
      M.queue_push(unum)
    end
    global.mod.entities[unum] = { entity=entity, handler=handler }
  end
end

function M.entity_del(unit_number)
  global.mod.entities[unit_number] = nil
  -- it will be elimintaed from the queue on the next pass
end

function M.entity_get(unit_number)
  local info = global.mod.entities[unit_number]
  if info ~= nil then
    if not info.entity.valid then
      M.entity_del(unit_number)
      info = nil
    end
  end
  return info
end

-- remove the first unit_number from the queue and return the entity info table
function M.queue_pop()
  while true do
    local unum = Queue.pop(global.mod.scan_queue)
    if unum == nil then
      -- queue is empty
      return nil
    end

    local info = M.entity_get(unum)
    if info ~= nil and info.entity ~= nil and info.entity.valid then
      return info
    else
      clog("queue_pop: lost item")
    end
  end
end

-- Add a unit number to the end of the queue
function M.queue_push(unit_number)
  if unit_number ~= nil then
    Queue.push(global.mod.scan_queue, unit_number)
  end
end

-------------------------------------------------------------------------------
-- Golem data

local function golem_valid(golem)
  return golem ~= nil and type(golem.IsValid) == "function" and golem:IsValid()
end

-- get a golem instance, validate it and destroy if bad. return if good.
function M.golem_get(unit_number)
  if unit_number ~= nil then
    local golem = global.mod.golems[unit_number]
    if golem ~= nil then
      if golem_valid(golem) then
        return golem
      end
      clog("golem not valid: %s meta=%s", serpent.block(golem), serpent.block(getmetatable(golem)))
      golem:destroy()
      global.mod.golems[unit_number] = nil
    end
  end
end

function M.golem_del(unit_number)
  local golem = global.mod.golems[unit_number]
  if golem_valid(golem) then
    golem:destroy()
  end
  global.mod.golems[unit_number] = nil
end

function M.golem_add(golem)
  if golem_valid(golem) then
    global.mod.golems[golem.entity.unit_number] = golem
    M.golem_queue_push(golem.entity.unit_number)
  end
end

function M.golem_get_map()
  return global.mod.golems
end

-- Add a unit number to the end of the queue
function M.golem_queue_push(unit_number)
  if unit_number ~= nil then
    Queue.push(global.mod.golem_queue, unit_number)
  end
end

-- remove the first unit_number from the queue and return the entity info table
function M.golem_queue_pop()
  while true do
    local unum = Queue.pop(global.mod.golem_queue)
    if unum == nil then
      -- queue is empty
      return nil
    end

    local golem = M.golem_get(unum)
    if golem ~= nil and golem:IsValid() then
      return golem
    end
  end
end

-------------------------------------------------------------------------------

-- return a list of storage chest entities in range
function M.find_storage_chests(surface, position, radius)
-- be lazy for now and use the surface scan
local ents = surface.find_entities_filtered{
    position = position,
    radius = radius,
    name = shared.storage_chest_name,
  }
  return ents
end

-- returns all in-range storage chests in a table with key=unit_number, val=entity
function M.find_storage_chests2(surface, position, radius)
  local chests = {}
  for _, st_ent in ipairs(M.find_storage_chests(surface, position, radius)) do
    chests[st_ent.unit_number] = st_ent
  end
  return chests
end

-------------------------------------------------------------------------------
-- Player data

-- Grabs a persistent table for a player. Never returns nil.
function M.get_player_info(player_index)
  local info = global.player_info[player_index]
  if info == nil then
    info = {}
    global.player_info[player_index] = info
  end
  return info
end

-- grab the whole player info map for iteration
function M.get_player_info_map()
  return global.player_info
end

function M.get_player_guis(tag)
  local items = {}
  for player_index, info in pairs(global.player_info) do
    if info.ui ~= nil and info.ui[tag] ~= nil then
      items[player_index] = info.ui[tag]
    end
  end
  return items
end

-- grab the UI table for a player
function M.get_ui_state(player_index)
  local info = M.get_player_info(player_index)
  if info.ui == nil then
    info.ui = {}
  end
  return info.ui
end

local metatabs = {} -- key=string, val=table

function M.restore_metatables()
  clog("restoring metatables")
  local function restore_meta(inst)
    if inst ~= nil and inst.__class ~= nil then
      local mt = metatabs[inst.__class]
      if mt ~= nil then
        if inst.entity and inst.entity.valid then
          clog(" metatable: %s for %s [%s]", inst.__class, inst.entity.name, inst.entity.unit_number)
        else
          clog(" metatable: %s", inst.__class)
        end
        setmetatable(inst, mt)
      end
    end
  end

  -- restore UI metatables
  -- global.player_info[player_index][tags] = table/class
  for _, info in pairs(global.player_info) do
    if info.ui ~= nil then
      for _, inst in pairs(info.ui) do
        restore_meta(inst)
      end
    end
  end

  for _, inst in pairs(global.mod.golems) do
    restore_meta(inst)
  end
  for _, inst in pairs(global.mod.entities) do
    restore_meta(inst)
  end
end

function M.register_metaclass(name, metatab)
  metatabs[name] = metatab
end

return M
