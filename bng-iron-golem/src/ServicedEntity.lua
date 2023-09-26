--[[
Class for a ServicedEntity.
Scans entities and sets the priority, request and provide fields.

`self.nv.priority` is a number that should reflect the priority of the request.
We currently don't use that for anything, but the idea was to use a different pool per priority
so that high priority requests are services faster.

`self.nv.request` is a table with key=item and val=count or { idx=inventory_index, count=count }
It indicates that is wants a certain number of items in a certain inventory.

`self.nv.provide` is a table with key=item and val=count or { idx=inventory_index, count=count }
It indicates that is wants to provide a certain number of items in a certain inventory.
]]
local Globals = require('src.Globals')
local shared = require("shared")
local clog = require("src.log_console").log

local M = {}
local ServicedEntity = {}
local ServicedEntity_Meta = { __index = ServicedEntity }

--[[ this is called to destory the class data.
The entity should have already been destroyed.
So, we just need to unhook from the list.
If there was something else to clean up, we'd do it now.
]]
function ServicedEntity:destroy()
  -- TODO: anything needed?
end

function ServicedEntity:IsValid()
  return self.nv ~= nil and self.nv.entity ~= nil and self.nv.entity.valid
end

function M.IsValid(inst)
  return (inst ~= nil) and (getmetatable(inst) == ServicedEntity_Meta) and inst:IsValid()
end

--[[
This is called periodically.
IsValid() is called right before this.
]]
function ServicedEntity:service(force)
  -- limit to 1 hz (for slower debug logs)
  local delta = game.tick - (self.service_tick or 0)
  if (delta < 60) and (force ~= true) then
    return
  end
  self.service_tick = game.tick

  -- reset the service info
  self.nv.priority = 0
  self.nv.request = {} -- key=name, val={ count=count, idx=invenroty.index }
  self.nv.provide = {} -- key=name, val={ count=count, idx=invenroty.index }

  -- collect the data
  self.my_service(self)

  if self.nv.priority > 0 and false then
    clog("service[%s][%s]: pri=%s req=%s pro=%s", self.nv.unit_number, self.nv.entity_name,
      self.nv.priority, serpent.line(self.nv.request), serpent.line(self.nv.provide))
  end
end

function ServicedEntity:get_priority()
  return self.nv.priority or 0
end

function ServicedEntity:up_priority(pri)
  if pri > self:get_priority() then
    self.nv.priority = pri
  end
end

-- Add an item request. We can only request an item for one inventory at a time
function ServicedEntity:add_request(inv, item, count, priority)
  self.nv.request[item] = { idx=inv.index, count=count }
  self:up_priority(priority)
end

-- Add an item provide. We can only provide an item for one inventory at a time
function ServicedEntity:add_provide(inv, item, count, priority)
  self.nv.provide[item] = { idx=inv.index, count=count }
  self:up_priority(priority)
end

-------------------------------------------------------------------------------
-- Service scanner routines to populate nv.priority, nv.request, nv.profide

--[[
Update self.nv.request to include items for the recipe.
]]
function ServicedEntity:update_recipe_inv(inv, recipe, factor)
  if recipe ~= nil and inv ~= nil then

    local contents = inv.get_contents()
    for _, ing in pairs(recipe.ingredients) do
      local prot = game.item_prototypes[ing.name]
      if prot ~= nil then
        local n_have = contents[ing.name] or 0
        local n_need = math.max(ing.amount, math.max(ing.amount * factor, prot.stack_size))
        if n_have < n_need then
          self:add_request(inv, ing.name, n_need - n_have, 2)
        end
      end
    end
  end
end

--[[
Update self.nv.provide to the current inventory.
REVISIT: could just do: self.nv.provide = inv.get_contents()
]]
function ServicedEntity:update_remove_all(inv)
  if inv ~= nil then
    local pri = 1
    if inv.is_full() then
      pri = 2
    end
    for name, count in pairs(inv.get_contents()) do
      self:add_provide(inv, name, count, pri)
    end
  end
end

--local fuel_list = { "solid-fuel", "coal", "wood" }

function ServicedEntity:update_refuel()
  -- we only do coal for now
  local fuel_name = "coal"
  local prot = game.item_prototypes[fuel_name]
  local pri = 1
  local hi_pri = 2

  -- We really don't want to lose power
  if self.nv.entity.type == "boiler" then
    hi_pri = 3
  end

  local inv = self.nv.entity.get_fuel_inventory()
  if inv ~= nil then
    -- if empty, request coal
    if inv.is_empty() then
      self:add_request(inv, fuel_name, #inv * prot.stack_size, hi_pri)
      return
    end

    -- try to top off the fuel(s)
    for fuel, _ in ipairs(inv.get_contents()) do
      local fuel_prot = game.item_prototypes[fuel]
      if fuel_prot ~= nil then
        local n_need = inv.get_insertable_count(fuel)
        -- start requesting when fuel is below 1/2 stack
        if n_need > fuel_prot.stack_size / 2 then
          if n_need > fuel_prot.stack_size - 3 then
            pri = hi_pri
          end
          self:add_request(inv, fuel, n_need, pri)
        end
      end
    end
  end
end

-------------------------------------------------------------------------------

--[[
Handle a furnace entity.
]]
function ServicedEntity:scan_furnace()
  local entity = self.nv.entity

  self:update_refuel()

  local inv_src = entity.get_inventory(defines.inventory.furnace_source)
  if inv_src ~= nil and inv_src.get_item_count() < 10 then
    self:update_recipe_inv(entity.get_inventory(defines.inventory.furnace_source), entity.previous_recipe, 50)
  end

  local inv_out = entity.get_output_inventory()
  -- can have full_output with 1 item if the recipe changed
  if inv_out ~= nil and (inv_out.get_item_count() > 10 or entity.status == defines.entity_status.full_output) then
    self:update_remove_all(inv_out)
  end
end

--[[
Handle a burner mining drill (coal circle)
The burner drill is special. If the fuel level gets too high, we remove some.
If the fuel level is too low, we add some.
]]
function ServicedEntity:scan_burner_mining_drill()
  local entity = self.nv.entity

  -- scan resources once to see if we are sitting on coal
  if self.nv.resource == nil then
    self.nv.resource = {}
    -- FIXME: use footprint of miner
    local ft = entity.surface.find_entities_filtered({ position=entity.position, radius=1, type="resource" })
    for _, tt in ipairs(ft) do
      self.nv.resource[tt.name] = true
    end
  end

  -- if we are NOT on coal, then do the normal refuel
  if not self.nv.resource.coal then
    self:update_refuel()
    return
  end

  -- We are on coal (special case mining circle)
  local fuel_name = "coal"
  local fuel_target = 5
  local prot = game.item_prototypes[fuel_name]

  local finv = entity.get_fuel_inventory()
  if finv ~= nil and prot ~= nil then
    local fuel_max = math.ceil(prot.stack_size / 2)
    local fuel_count = finv.get_item_count(fuel_name)
    if fuel_count == 0 then
      self:add_request(finv, fuel_name, fuel_target, 2)
    elseif fuel_count > fuel_max then
      self:add_provide(finv, fuel_name, fuel_count - (fuel_target + 1), 1)
    end
  end
end

--[[
Purge all inventory if it hasn't been empty for 10 seconds.
]]
function ServicedEntity:scan_container_active_provider()
  local entity = self.nv.entity

  -- We have to have inventory for 10 seconds
  local inv = entity.get_output_inventory()
  if inv == nil or inv.is_empty() then
    self.nv.tick_provider = game.tick
  end
  local elapsed = game.tick - (self.nv.tick_provider or 0)
  if elapsed > (10 * 60) then
      self:update_remove_all(entity.get_output_inventory())
  end
end

-- logistic requester/buffer, create a request for missing items
function ServicedEntity:scan_container_requester()
  local entity = self.nv.entity

  if entity.request_slot_count > 0 then
    local inv = entity.get_output_inventory()
    for idx = 1, entity.request_slot_count do
      local req = entity.get_request_slot(idx)
      if req ~= nil then
        local n_have = inv.get_item_count(req.name)
        local n_free = inv.get_insertable_count(req.name)
        local n_trans = math.min(n_free, req.count - n_have)
        if n_trans > 0 then
          --clog("%s[%s] has req for %s(%s), n_free=%s", entity.name, entity.unit_number, req.name, req.count, n_free)
          self:add_request(inv, req.name, n_trans, 1)
        end
      end
    end
  end
end

function ServicedEntity:scan_nothing()
  -- don't do anything
end

-------------------------------------------------------------------------------

function ServicedEntity:scan_assembler()
  local entity = self.nv.entity

  -- only scan if the assembler status is missing ingredients
  if entity.status == defines.entity_status.item_ingredient_shortage then
    self:update_recipe_inv(entity.get_inventory(defines.inventory.assembling_machine_input), entity.get_recipe(), 2)
  end
end

function ServicedEntity:scan_refuel()
  self:update_refuel()
end

-------------------------------------------------------------------------------
-- this is the ServicedEntity factory

--[[
  Create the instance for the entity. nv.entity is valid.
]]
function M.create(nv)
  local entity = nv.entity

  local self = {
    __class = "ServicedEntity",
    nv = nv,
    priority = 0,
    --request = {},
    --provide = {},
  }
  setmetatable(self, ServicedEntity_Meta)

  if entity.type == "logistic-container" then
    nv.logistic_mode = entity.prototype.logistic_mode
    Globals.storage_add(self)
  end

  --clog("ServicedEntity: Created %s [%s] @ %s mode=%s", entity.name, self.nv.unit_number, serpent.line(entity.position), nv.logistic_mode)

  return self
end

local function common_create(scan_fcn)
  return function (nv)
    local inst = M.create(nv)
    inst.my_service = scan_fcn
    return inst
  end
end

Globals.register_handler("type", "furnace", common_create(ServicedEntity.scan_furnace))
Globals.register_handler("type", "assembling-machine", common_create(ServicedEntity.scan_assembler))
Globals.register_handler("name", "burner-mining-drill", common_create(ServicedEntity.scan_burner_mining_drill))
Globals.register_handler("fuel", "", common_create(ServicedEntity.scan_refuel))

Globals.register_handler("logistic-mode", "requester", common_create(ServicedEntity.scan_container_requester))
Globals.register_handler("logistic-mode", "buffer", common_create(ServicedEntity.scan_container_requester))
Globals.register_handler("logistic-mode", "active-provider", common_create(ServicedEntity.scan_container_active_provider))
Globals.register_handler("logistic-mode", "passive-provider", common_create(ServicedEntity.scan_nothing))
Globals.register_handler("logistic-mode", "storage", common_create(ServicedEntity.scan_nothing))

return M
