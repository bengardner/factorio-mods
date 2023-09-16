--[[
This maintains the job list.
]]
--local Globals = require('src.Globals')
--local Shared = require('src.Shared')
local clog = require("src.log_console").log

local M = {}

--[[
  entry structure:
    entity = entity
    priority = priority (1..3)
    tick = game.tick when added
    request = { item=count } of items that are wanted by the entity
    provide = { item=count } of items to be removed from the entity
]]

M.job_list = {
  {}, -- low priority (1), key=unit_number, value=entity
  {}, -- med priority (2), key=unit_number, value=entity
  {}, -- high priority (3), key=unit_number, value=entity
}
-- map: key=unit_number, val=entry
M.entities = {}
-- map: key=unit_number, val=game.tick
M.claims = {}

global.job_list = M.job_list
global.job_entities = M.job_entities

local function priority_bound(priority)
  return math.min(#M.job_list, math.max(1, priority))
end

local function same_tables(t1, t2)
  -- same address (identity) or both nil
  if t1 == t2 then
    return true
  end
  -- one is nil and the other is not
  if t1 == nil or t2 == nil then
    return false
  end
  for k1, v1 in pairs(t1) do
    if t2[k1] ~= v1 then
      return false
    end
  end
  for k2, v2 in pairs(t2) do
    if t1[k2] ~= v2 then
      return false
    end
  end
  return true
end

--[[
  See if the two jobs are the same.
  We only compare the priority, request and provide fields.
]]
local function same_job(j1, j2)
  if j1.priority ~= j2.priority then
    return false
  end
  if not same_tables(j1.request, j2.request) then
    return false
  end
  if not same_tables(j1.provide, j2.provide) then
    return false
  end
  return true
end

--[[
  Adds a job for an entity if one does not exist.
  @entity the entity that needs service
  @to_insert table (key=name, val=count) of items that are needed
  @to_remove table (key=name, val=count) of items that need to be removed
]]
function M.update_job(entity, priority, request, provide)
  local unum = entity.unit_number

  -- priority 0 does nothing
  if priority < 1 then
    return
  end

  -- make sure the priority is in range
  priority = priority_bound(priority)

  -- create the new job entry
  local entry = {
    entity=entity,
    position=entity.position,
    request=request,
    provide=provide,
    tick=game.tick,
    priority=priority
  }

  local function merge_tables(t1, t2)
    local r
    if t1 ~= nil or t2 ~= nil then
      r = {}
      local function add_tab(xx)
        if xx ~= nil then
          for k, v in pairs(xx) do
            r[k] = (r[k] or 0) + v
          end
        end
      end
      add_tab(t1)
      add_tab(t2)
    end
    return r
  end

  -- merge or remove an old entry if from a different tick
  local old_ent = M.entities[unum]
  if old_ent ~= nil then
    -- 99% of the time, the job will be the same as the prior job
    if same_job(old_ent, entry) then
      old_ent.tick = game.tick
      return
    end

    -- combine requests if from the same tick
    if entry.tick == old_ent.tick then
      entry.priority = math.max(entry.priority, old_ent.priority)
      entry.reqeust = merge_tables(entry.request, request)
      entry.provide = merge_tables(entry.provide, provide)
    end
    -- remove the entry if the priority changed
    if entry.priority ~= old_ent.priority then
      M.job_list[old_ent.priority][unum] = nil
    end
  end

  --clog("Added job: %s", serpent.block(entry))
  M.job_list[priority][unum] = entry
  M.entities[unum] = entry
end

function M.set_job(entity, priority, request, provide)
  M.cancel_job(entity.unit_number)
  M.update_job(entity, priority, request, provide)
end

function M.get_job(unit_number)
  return M.entities[unit_number]
end

-- this is called from the scanner when the entity no longer needs to be serviced.
function M.cancel_job(unit_number)
  local ent = M.entities[unit_number]
  if ent ~= nil then
    M.job_list[ent.priority][unit_number] = nil
    M.entities[unit_number] = nil
  end
end

-- this is called from the scanner when the entity may not need to be serviced.
function M.cancel_old_job(unit_number)
  local ent = M.entities[unit_number]
  if ent ~= nil and ent.tick < game.tick then
    M.job_list[ent.priority][unit_number] = nil
    M.entities[unit_number] = nil
  end
end

-- this is called when a job is claimed by a player or golem
-- A "claim" is used if the job cannot be immediately satisfied.
function M.claim_job(unit_number)
  M.claims[unit_number] = game.tick
end

local function dist2(p1, p2)
  return (p1.x - p2.x) ^2 + (p1.y - p2.y) ^2
end

--[[
Grab the first job that we can do within the given range.
  inv_free_slots is the number of free slots in the golem AND any nearby storage chests
  inv_contens is the golem inventory + the inventory of nearby storage chests
]]
function M.request_a_job(position, range, inv_free_slots, inv_contents)
  local range2 = range * range

  --clog("request_a_job: pos=(%s,%s) r=%s empty=%s inv=%s",
  --  position.x, position.y, range, inv_free_slots, serpent.block(inv_contents))

  for pri = #M.job_list, 1, -1 do
    -- check all jobs at the priority
    for _, entry in pairs(M.job_list[pri]) do
      --clog("Look at job for %s at (%s,%s) r=%s p=%s", entry.entity.name, entry.position.x, entry.position.y,
      --  serpent.block(entry.request), serpent.block(entry.provide))
      if true then -- (game.tick - (M.claims[unum] or 0)) > 120 then
        local d2 = dist2(entry.position, position)
        if d2 <= range2 then
          --clog("found job for %s in range r=%s p=%s", entry.entity.name, serpent.block(entry.request), serpent.block(entry.provide))
          -- if we have any of the requested items, then we can help
          for item, _ in pairs(entry.request or {}) do
            if inv_contents[item] ~= nil then
              --clog(" -picked R job for %s", entry.entity.name)
              return entry
            end
          end
          -- if we have any free slots, then we can do something
          if entry.provide ~= nil and next(entry.provide) ~= nil and inv_free_slots > 0 then
            --clog(" -picked P job for %s", entry.entity.name)
            return entry
          end
        end
      end
    end
  end
end

function M.print()
  clog("M.job_list=%s", serpent.block(M.job_list))
end

return M
