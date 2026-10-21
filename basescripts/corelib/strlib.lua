-- Goodies for manipulate strings

local strlib = {}

--- usage: for part in strlib.splitSeq(str, delim) do ...
---@param self string
---@param delimiter string
---@return fun(): string|nil
function strlib.splitSeq(self, delimiter)
  if #self == 0 then
    return function() return nil end
  end

  local from = 1
  return function()
    if from > #self then
      return nil
    end

    local delim_from, delim_to = self:find(delimiter, from, true)
    local part

    if delim_from then
      part = self:sub(from, delim_from - 1)
      from = delim_to + 1
    else
      part = self:sub(from)
      from = #self + 1
    end

    return part
  end
end

---@param self string
---@param delimiter string
---@return string[]
function strlib.split(self, delimiter)
  if #self == 0 then return {} end
  local result = {}
  local from = 1
  local delim_from, delim_to = self:find(delimiter, from)
  while delim_from do
    table.insert(result, self:sub(from, delim_from - 1))
    from  = delim_to + 1
    delim_from, delim_to = self:find(delimiter, from)
  end
  table.insert(result, self:sub(from))
  return result
end

---@param self string
function strlib.startsWith(self, start)
  return self:sub(1, #start) == start
end

---@param self string
function strlib.endsWith(self, e)
  return e == "" or self:sub(-#e) == e
end

return strlib
