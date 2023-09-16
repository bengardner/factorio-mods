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

return M
