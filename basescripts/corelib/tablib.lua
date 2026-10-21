-- SPDX-FileCopyrightText: 2026 Notify Ctrl <notify-ctrl@qq.com>
-- SPDX-License-Identifier: LGPL-2.1-or-later

-- Goodies for manipulate tables

local tablib = {}

-- 1. Array-like tables
---------------------------

-- Very useful functions borrowed from JavaScript
-- The only difference is Lua array index starts from 1.
-- I will mention this in index-related methods
-- TODO: please complete annotations for the functions from reference site
-- ref: https://developer.mozilla.org/docs/Web/JavaScript/Reference/Global_Objects/Array


---@generic T
---@param self T[]
---@param func fun(element: T, index: integer, array: T[]): boolean?
---@return boolean
function tablib.every(self, func)
  for i, v in ipairs(self) do
    if not func(v, i, self) then
      return false
    end
  end
  return true
end


---@generic T
---@param self T[]
---@param func fun(element: T, index: integer, array: T[]): boolean?
---@return T?
function tablib.find(self, func)
  for i, v in ipairs(self) do
    if func(v, i, self) then
      return v
    end
  end
  return nil
end


---@generic T
---@param self T[]
---@param func fun(element: T, index: integer, array: T[]): boolean?
---@return integer
function tablib.findIndex(self, func)
  for i, v in ipairs(self) do
    if func(v, i, self) then
      return i
    end
  end
  return -1
end


---@generic T
---@param self T[]
---@param func fun(element: T, index: integer, array: T[]): boolean?
---@return T[]
function tablib.filter(self, func)
  local ret = {}
  for i, v in ipairs(self) do
    if func(v, i, self) then
      ret[#ret + 1] = v
    end
  end
  return ret
end


---@generic T
---@param self T[]
---@param value T
---@param from? integer
---@return integer
function tablib.indexOf(self, value, from)
  from = from or 1
  for i = from, #self do
    if self[i] == value then return i end
  end
  return -1
end


---@generic T, T2
---@param self T[]
---@param func fun(element: T, index: integer, array: T[]): T2
---@return T2[]
function tablib.map(self, func)
  local ret = {}
  for i, v in ipairs(self) do
    ret[#ret + 1] = func(v, i, self)
  end
  return ret
end


---@generic T
---@param self T[]
---@param ... T
---@return integer
function tablib.push(self, ...)
  local args = {...}
  local len = #self
  for i = 1, #args do
    self[len + i] = args[i]
  end
  return #self
end


-- And these are borrowed from QList<T> methods


---@generic T
---@param self T[]
---@return boolean
function tablib.contains(self, element)
  for _, e in ipairs(self) do
    if e == element then return true end
  end
  return false
end


---@generic T
---@param self T[]
---@param element T
---@return boolean
function tablib.removeOne(self, element)
  for i = 1, #self do
    if self[i] == element then
      table.remove(self, i)
      return true
    end
  end
  return false
end



-- 2. Object-like tables (k-v pairs)
--------------------------------------

---@generic T, T2
---@param self table<T, T2>
---@param source table<T, T2>
---@return table<T, T2>
function tablib.assign(self, source)
  for key, value in pairs(source) do
    self[key] = value
  end
  return self
end


---@generic T, T2
---@param self table<T, T2>
---@return [T, T2][]
function tablib.entries(self)
  local ret = {}
  for k, v in pairs(self) do
    if type(k) == "string" then
      ret[#ret + 1] = { k, v }
    end
  end
  return ret
end


---@generic T, T2
---@param self table<T, T2>
---@return string[]
function tablib.keys(self)
  local ret = {}
  for k in pairs(self) do
    if type(k) == "string" then
      ret[#ret + 1] = k
    end
  end
  return ret
end


function tablib.isEmpty(self)
  return next(self) == nil
end


-- Clone a table. Shallow by default; pass `deep = true` to clone nested tables
-- recursively. Metatables are not preserved.
---@generic T
---@param self T
---@param deep? boolean
---@return T
function tablib.clone(self, deep)
  local ret = {}
  for k, v in pairs(self) do
    if deep and type(v) == "table" then
      ret[k] = tablib.clone(v, deep)
    else
      ret[k] = v
    end
  end
  return ret
end

return tablib
