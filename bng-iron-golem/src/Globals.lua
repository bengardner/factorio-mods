--[[
Global data, some of which is persistent..
We own all of "global", but mostly restrict our data to "global.mod"

Design note:

All entities that are serviced regularly (except players) are put in
the service_entities table and added to service_queue.
The service queue is processed one item per tick.
Most items will rate-limit how ofter then are processed.

Entities that need servicing will add themselves to the job queue.

Each TransferTower will take one job per service (1 Hz).
It will move up to 1 stack of 1 item.

A TransferTower keeps a list of the unit_number of all entities within range.
When a new entity is added, it is passed to all existing Towers.
Whan an entity is remove, notification is also sent.

Each entity can be part of zero or more transfer tower networks.

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
    global.mod = {}
  end

  if global.entity_nv == nil then
    global.entity_nv = {}
  end

  -- entities to be processed in a round-robin manner
  if global.mod.service_queue == nil then
    global.mod.service_queue = Queue.new()
  end
  if global.mod.towers == nil then
    -- key=unit_number, val=TransferTower class
    global.mod.towers = {}
  end

  if global.mod.storage_chests == nil then
    -- key=unit_number, val=TransferTower class
    global.mod.storage_chests = {}
  end

  M.scan_prototypes()
  M.restore_metatables()

  -- FIXME: during testing I reset the queues at startup
  clog("TEST: rescanning entities")
  M.debug_entity_scan()
  M.debug_reset_queues()
end

M.entity_inst_table = {}

-------------------------------------------------------------------------------

-- get or create the extra surface where we put the chests for the golems
-- NO LONGER USED
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

local function IsValid(item)
  return item ~= nil and type(item.IsValid) == "function" and item:IsValid()
end

local replace_chests = {
  [shared.chest_names.requester] = shared.chest_name_requester,
  [shared.chest_names.provider] = shared.chest_name_provider,
  [shared.chest_names.storage] = shared.chest_name_storage,
}

-- DEBUG: re-scan the surfaces for entities that we track
function M.debug_entity_scan()
  -- scan for storage chests
  -- don't clear for now, we should discard invalid upon service
  --global.mod.storage_chests = {}
  --global.mod.service_entities = {}
  for _, surface in pairs(game.surfaces) do
    local entities = surface.find_entities_filtered( { name=M.get_entity_names() } )
    for _, entity in ipairs(entities) do
      clog("%s[%s] @ (%s,%s)", entity.name, entity.unit_number, entity.position.x, entity.position.y)
      if shared.chest_names[entity.name] ~= nil then

      end
      --if entity.name == shared.chest_names.requester then
      --  local ent = entity.surface.create{ name=shared.chest_name_requester, position=entity.position, fast_replace=true }
      --end
      M.entity_add(entity)
    end
  end
end

function M.debug_reset_queues()
  -- entities are processed one per tick
  global.mod.service_queue = Queue.new()
  for unum, _ in pairs(M.entity_inst_table) do
    M.service_queue_push(unum)
  end
end

--[[
This is the list of names of everything we care about.
Find all type = "furnace" and energy_source.type = "burner".
Find all type = "assembling-machine"
Find all with entity.energy_source.fuel_category="chemical" and fuel_inventory_size > 0.
Or with entity.burner.fuel_category="chemical" and fuel_inventory_size > 0.
  boiler
  burner-inserter

  What is burner-generator?

key=entity name, val=whether it can move after creation
]]
local entity_name_type = {}
local entity_name_list = {}
local entity_storage_map = {}

function M.add_entity_name_type(name, can_move, is_storage)
  if entity_name_type[name] == nil then
    table.insert(entity_name_list, name)
    if is_storage then
      entity_storage_map[name] = true
    end
  end
  entity_name_type[name] = can_move
end

-- get all the entity names that we care about as a list
function M.get_entity_names()
  return entity_name_list
end

function M.is_storage_name(name)
  return entity_storage_map[name] ~= nil
end

function M.is_service_name(name)
  -- everything except for "storage", but that won't hurt
  return entity_name_type[name] ~= nil
end

-------------------------------------------------------------------------------

local function entity_nv_get(unit_number)
  return global.entity_nv[unit_number]
end

local function entity_nv_del(unit_number)
  global.entity_nv[unit_number] = nil
end

local function entity_nv_create(entity)
  local unum = entity.unit_number
  local nv = {
    entity = entity,
    entity_name = entity.name,
    unit_number = entity.unit_number,
  }
  global.entity_nv[unum] = nv
  return nv
end

-------------------------------------------------------------------------------

-- list of handlers:
-- { check=func, arg=value, handler=handler }
M.handler_match_table = { }

local named_match_fcns = {
  ["name"] = function (entity, arg)
    return entity.name == arg
  end,

  ["type"] = function (entity, arg)
    return entity.type == arg
  end,

  ["fuel"] = function (entity, arg)
    return entity.get_fuel_inventory() ~= nil
  end,

  ["ammo"] = function (entity, arg)
    return entity.get_ammo_inventory() ~= nil
  end,

  ["logistic-mode"] = function (entity, arg)
    if entity.type == "logistic-container" then
      return entity.prototype.logistic_mode == arg
    end
  end,
}

--[[
The handler function takes a matching entity.
  function handler(entity)

It must return a table that contains at least:
    - entity (value passed to handler())
    - service (function) called  periodically, passed the returned table
It may contain :
    - destroy (function) function called when the entity is invalid
    - isValid (function) function the returns whether the instance is valid
Functions are passed the table as the first and only parameter.
]]

function M.register_handler(ftype, farg, handler)
  local match_fcn
  if type(ftype) == "string" then
    match_fcn = named_match_fcns[ftype]
  elseif type(ftype) == "function" then
    match_fcn = ftype
  end
  if match_fcn ~= nil then
    table.insert(M.handler_match_table, { check=match_fcn, arg=farg, handler=handler })
  end
end

-- Get the handler function for an entity
function M.get_entity_handler(entity)
  if entity ~= nil and entity.valid then
    for _, ent in ipairs(M.handler_match_table) do
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

-------------------------------------------------------------------------------

local function entity_add_finish(unit_number, inst)
  if inst ~= nil then
    M.entity_inst_table[unit_number] = inst

    -- add to the service queue if it has a service function
    if type(inst.service) == "function" then
      M.service_queue_push(unit_number)
      --clog("added to queue %s %s", unit_number, serpent.block(inst))
    end

    -- HACK: tell all towers to re-scan -- should check tower areas
    global.mod.storage_tick = game.tick
  end
  -- pass-through
  return inst
end

-- Add a new entity. Might be called multiple times.
function M.entity_add(entity)
  local unit_number = entity.unit_number
  local inst = M.entity_inst_table[unit_number]
  if inst == nil then
    local handler = M.get_entity_handler(entity)
    if handler ~= nil then
      return entity_add_finish(unit_number, handler(entity_nv_create(entity)))
    end
  end
end

-- get or create the class for this entity.
function M.entity_get(unit_number)
  -- See if we have the instance cached
  local inst = M.entity_inst_table[unit_number]
  if inst ~= nil then
    -- Check if valid
    if inst:IsValid() then
      return inst
    end
    -- drop it and return nil
    M.entity_remove(unit_number)
    return
  end

  -- See if we have data for the entity
  local nv = entity_nv_get(unit_number)
  if nv == nil then
    return
  end

  -- get the handler
  local handler = M.get_entity_handler(nv.entity)
  if handler == nil then
    -- config must have changed, entity no longer tracked
    -- drop nv data just in case we have some
    entity_nv_del(unit_number)
    return
  end

  return entity_add_finish(unit_number, handler(nv))
end

function M.entity_remove(unit_number)
  -- break link to NV data
  entity_nv_del(unit_number)

  -- see if we have an instance
  local inst = M.entity_inst_table[unit_number]
  if inst ~= nil then
    M.entity_inst_table[unit_number] = inst
    if type(inst.destroy) == "function" then
      inst:destroy()
    end
  end
end

-------------------------------------------------------------------------------

-- Called from the storage chest class to link to all
function M.storage_add(inst)
  -- record that we added storage
  global.mod.storage_tick = game.tick
end

function M.storage_del(inst)
  global.mod.storage_tick = game.tick
end

function M.storage_get_tick()
  return global.mod.storage_tick
end

-------------------------------------------------------------------------------

-- remove the first unit_number from the queue and return the entity info table
function M.service_queue_pop()
  while true do
    local unum = Queue.pop(global.mod.service_queue)
    if unum == nil then
      -- queue is empty
      return nil
    end

    local inst = M.entity_get(unum)
    if inst ~= nil then
      if inst:IsValid() then
        return inst
      end
      --clog("service_queue_pop[%s] not IsValid", unum)
    --else
    --  clog("service_queue_pop[%s] nil inst=%s nv=%s", unum, serpent.block(M.entity_inst_table), serpent.block(global.entity_nv))
    end
  end
end

-- Add a unit number to the end of the queue
function M.service_queue_push(unit_number)
  if unit_number ~= nil then
    --clog("service_queue_push[%s]", unit_number)

    Queue.push(global.mod.service_queue, unit_number)
  end
end

-------------------------------------------------------------------------------
-- TrnasferTower data

-- get a TransferTower instance, validate it and destroy if bad. return if good.
function M.tower_get(unit_number)
  if unit_number ~= nil then
    return global.mod.towers[unit_number]
  end
end

function M.tower_del(unit_number)
  if unit_number ~= nil then
    global.mod.towers[unit_number] = nil
  end
end

-- called only from TransferTower
function M.tower_add(tower)
  if IsValid(tower) then
    global.mod.towers[tower.nv.unit_number] = tower
  end
end

function M.tower_get_map()
  return global.mod.towers
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

-------------------------------------------------------------------------------
-- Metatable restoration stuff (set __class=name to get restored)

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

  --if global.mod.service_entities ~= nil then
  --  for _, inst in pairs(global.mod.service_entities) do
  --    restore_meta(inst)
  --  end
  --end
end

function M.register_metaclass(name, metatab)
  metatabs[name] = metatab
end

-------------------------------------------------------------------------------

function M.scan_prototypes()
  -- add our stuff
  --M.add_entity_name_type(shared.chest_names.provider, false, false)
  --M.add_entity_name_type(shared.chest_names.requester, false, false)
  --M.add_entity_name_type(shared.chest_names.storage, false, true)

  --M.add_entity_name_type(shared.chest_name_provider, false, false)
  --M.add_entity_name_type(shared.chest_name_requester, false, false)
  --M.add_entity_name_type(shared.chest_name_storage, false, true)

  M.add_entity_name_type(shared.transfer_tower_name, false, true)

  -- add refuel targets (coal/chemical only) and assemblers
  for _, prot in pairs(game.entity_prototypes) do
    if prot.has_flag("player-creation") then
        -- check for stuff that burns coal
      if prot.burner_prototype ~= nil and prot.burner_prototype.fuel_categories.chemical == true then
        M.add_entity_name_type(prot.name, not prot.is_building, false)
      elseif prot.is_building then
        if prot.type == "assembling-machine" then
          M.add_entity_name_type(prot.name, false, false)
        elseif prot.type == "logistic-container" then
          M.add_entity_name_type(prot.name, false, true)
        end
      end
    end
  end

  -- debug: show entities that we track
  clog("%s: entity_name_list: %s", shared.mod_name, serpent.block(entity_name_list))
end

return M
