local M = {}

function M.setup()
  if global.entities == nil then
    if global.mod ~= nil and global.mod.entities ~= nil then
      global.entities = global.mod.entities
      global.mod = nil
    else
      global.entities = {}
    end
  end
end

function M.entity_register(entity)
  M.setup()
  if global.entities[entity.unit_number] == nil then
    global.entities[entity.unit_number] = entity
  end
end

function M.entity_unregister(unit_number)
  M.setup()
  global.entities[unit_number] = nil
end

function M.entity_table()
  M.setup()
  return global.entities
end

function M.get_science_packs(force_scan)
  local pp = global.science_packs or {}
  if next(pp) == nil or force_scan then
    -- scans prototypes and updates the list of science packs
    for k, v in pairs(game.item_prototypes) do
      if v.type == 'tool' and string.find(k, 'science%-pack') ~= nil then
        print('Science Pack:', k)
        pp[k] = 50 -- TODO: configurable?
      end
    end
    global.science_packs = pp
  end
  return global.science_packs
end

return M
