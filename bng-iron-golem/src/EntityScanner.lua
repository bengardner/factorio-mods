--[[
Scans one entity per tick.
Adds the entity to a job queue or removes it altogether.
]]
local shared = require("shared")
local Globals = require("src.Globals")
local Jobs = require("src.Jobs")
local clog = require("src.log_console").log

local M = {}

-- add a job to request everything in @recipe from a player or storage chest
function M.update_recipe_inv(entity, inv, recipe, factor)
  if recipe ~= nil and inv ~= nil then
    local priority = 0
    local request = {}
    local contents = inv.get_contents()
    for _, ing in pairs(recipe.ingredients) do
      local prot = game.item_prototypes[ing.name]
      if prot ~= nil then
        local n_have = contents[ing.name] or 0
        local n_need = math.max(ing.amount * factor, math.ceil(prot.stack_size / 4))
        if n_have < n_need then
          request[ing.name] = (request[ing.name] or 0) + n_need - n_have
          priority = 2
        end
      end
    end
    Jobs.update_job(entity, priority, request, nil)
  end
end

-- adds a job to remove all (output) inventory
function M.update_remove_all(entity, inv)
  if inv ~= nil then
    local contents = inv.get_contents()
    if next(contents) ~= nil then
      Jobs.update_job(entity, 1, nil, contents)
    end
  end
end

local fuel_list = {
  "solid-fuel",
  "coal",
  "wood"
}

function M.update_refuel(entity)
  local priority = 0 -- don't add
  local request = {}

  -- Scan each stack. Match an existing fuel or add some.
  local inv = entity.get_fuel_inventory()
  if inv ~= nil then
    -- any empty stacks mean priority 2 service
    local n_empty = inv.count_empty_stacks(true, false)
    if n_empty > 0 then
      priority = 2
      request = {}
      for _, name in pairs(fuel_list) do
        local prot = game.item_prototypes[name]
        if prot ~= nil then
          request[name] = prot.stack_size
        end
      end
    else
      for idx = 1, #inv do
        local stack = inv[idx]
        if stack.valid_for_read then
          local prot = game.item_prototypes[stack.name]
          -- top off the fuel
          if prot ~= nil and stack.count < prot.stack_size / 2 then
            priority = 1
            request[stack.name] = (request[stack.name] or 0) + (prot.stack_size - stack.count)
          end
        end
      end
    end
  end

  Jobs.update_job(entity, priority, request, nil)
end

-------------------------------------------------------------------------------

--[[
  Handle a furnace entity.
  We only do something when the state is not working.
]]
function M.scan_furnace(entity, info)
  local inv_src = entity.get_inventory(defines.inventory.furnace_source)
  local inv_out = entity.get_output_inventory()
  local inv_fuel = entity.get_fuel_inventory()

  if inv_fuel ~= nil and inv_fuel.get_item_count() < 10 then
    M.update_refuel(entity)
  end

  if inv_src ~= nil and inv_src.get_item_count() < 10 then
    M.update_recipe_inv(entity, entity.get_inventory(defines.inventory.furnace_source), entity.previous_recipe, 50)
  end

  if inv_out ~= nil and inv_out.get_item_count() > 10 then
    M.update_remove_all(entity, entity.get_output_inventory())
  end

  Jobs.cancel_old_job(entity.unit_number)
end

--[[
Handle a burner mining drill (coal circle)
The burner drill is special. If the fuel level gets too high, we remove some.
If the fuel level is too low, we add some.
]]
function M.scan_burner_mining_drill(entity, info)
  -- scan resources once to see if we are sitting on coal
  if info.resource == nil then
    info.resource = {}
    local ft = entity.surface.find_entities_filtered({ position=entity.position, radius=1, type="resource" })
    for _, tt in ipairs(ft) do
      info.resource[tt.name] = true
    end
  end

  -- if we are NOT on coal, then do the normal refuel
  if not info.resource.coal then
    M.scan_refuel(entity, info)
    return
  end

  local provide
  local request
  local priority = 0

  -- We are on coal
  local fuel_name = "coal"
  local fuel_target = 5
  local prot = game.item_prototypes[fuel_name]
  local finv = entity.get_fuel_inventory()
  if finv ~= nil and prot ~= nil then
    local fuel_max = math.ceil(prot.stack_size / 2)
    local fuel_count = finv.get_item_count(fuel_name)
    if fuel_count == 0 then
      request = { coal = fuel_target }
      priority = 2
    elseif fuel_count > fuel_max then
      provide = { coal = fuel_count - (fuel_target + 1) }
      priority = 1
    end
  end

  Jobs.set_job(entity, priority, request, provide)
end

-- add or clear a job every 10 seconds
function M.scan_container_provider(entity, info)
  -- we have to have inventory for 10 seconds
  local inv = entity.get_output_inventory()
  if inv == nil or inv.is_empty() then
    info.tick_provider = game.tick
  end
  local elapsed = game.tick - (info.tick_provider or 0)
  if elapsed > (10 * 60) then
      M.update_remove_all(entity, entity.get_output_inventory())
  end
  Jobs.cancel_old_job(entity.unit_number)
end

-- request to fill each filtered slot
function M.scan_container_requester(entity, info)
  local request = {}
  local priority = 0

  local inv = entity.get_output_inventory()
  if inv ~= nil then
    local contents = inv.get_contents()
    local wanted = {}

    for idx = 1, #inv do
      local name = inv.get_filter(idx)
      if name ~= nil then
        local prot = game.item_prototypes[name]
        if prot ~= nil then
          wanted[name] = (wanted[name] or 0) + prot.stack_size
        end
      end
    end

    for name, n_wanted in pairs(wanted) do
      local n_have = contents[name] or 0
      if n_have < n_wanted then
        request[name] = (request[name] or 0) + (n_wanted - n_have)
        priority = 2
      end
    end
  end

  Jobs.set_job(entity, priority, request, nil)
end

-- refresh the contents, which is used when evaluating jobs for golems
function M.scan_container_storage(entity, info)
  local inv = entity.get_output_inventory()
  if inv ~= nil then
    info.contents = inv.get_contents()
  end
end

-------------------------------------------------------------------------------

function M.scan_assembler(entity, info)
  -- only scan if the assembler status is missing ingredients
  if entity.status == defines.entity_status.item_ingredient_shortage then
    M.update_recipe_inv(entity, entity.get_inventory(defines.inventory.assembling_machine_input), entity.get_recipe(), 2)
  end

  Jobs.cancel_old_job(entity.unit_number)
end

--[[
Top off the fuel.
If a fuel stack is empty, try to find something that works.
coal, wood, solid fuel (coal for now)
]]
function M.scan_refuel(entity, info)
  M.update_refuel(entity)

  Jobs.cancel_old_job(entity.unit_number)
end

-------------------------------------------------------------------------------

local function simple_handler(scan_fcn)
  return function (entity)
    if entity.name == shared.chest_names.storage then
      Globals.storage_add(entity)
    end
    return {
      entity = entity,
      service = function (inst)
        scan_fcn(entity, inst)
      end,
      destroy = function (inst)
        Globals.storage_del(entity)
      end,
    }
  end
end

Globals.register_handler("type", "furnace", simple_handler(M.scan_furnace))
Globals.register_handler("type", "assembling-machine", simple_handler(M.scan_assembler))
Globals.register_handler("name", shared.chest_names.requester, simple_handler(M.scan_container_requester))
Globals.register_handler("name", shared.chest_names.provider, simple_handler(M.scan_container_provider))
Globals.register_handler("name", shared.chest_names.storage, simple_handler(M.scan_container_storage))
Globals.register_handler("name", "burner-mining-drill", simple_handler(M.scan_burner_mining_drill))
Globals.register_handler("fuel", "", simple_handler(M.scan_refuel))

return M
