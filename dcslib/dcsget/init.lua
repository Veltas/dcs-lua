local dcsget = {}

-- Creates table copied from entries of given tables
function dcsget.inherit(...)
  local childTable = {}
  for _, parentTable in ipairs{...} do
    for k, v in pairs(parentTable) do
      childTable[k] = v
    end
  end
  return childTable
end

return dcsget
