--- Assorted tools.
--@module tools
local M = {}

--- Generates a string representation of a table.
--@param table the table
--@return the string
function M:table_to_string(table)
  local out = "{"
  for key,value in pairs(table) do
    
    local val_string = ''
    
    if type(value) == 'table' then
      val_string = self:table_to_string(value)
    else
      val_string = tostring(value) 
    end
    
    out = out .. tostring(key) .. ":" .. val_string .. ", "
  end

  out = out .. "}"
  return out
end

--- An arbitrarily large number used for clamping regrets.
--@return the number
function M:max_number()
  return 999999
end

return M