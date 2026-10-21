-- SPDX-License-Identifier: LGPL-2.1-or-later

---@class Bag: Object
---@field owner ServerPlayer @背包所属角色
---@field pets Pet[] @携带的精灵，通常模式最多六只
---@field items table<integer, integer> @道具编号对应数量
local Bag = kt.class("Bag")

---@param owner ServerPlayer
---@param pets? Pet[]
---@param items? table<integer, integer>
function Bag:initialize(owner, pets, items)
    self.owner = owner
    self.pets = { table.unpack(pets or {}) }
    self.items = {}
    for id, count in pairs(items or {}) do
        self.items[id] = count
    end
end

---@return ServerPlayer
function Bag:getOwner()
    return self.owner
end

---@return Pet[]
function Bag:getPets()
    return { table.unpack(self.pets) }
end

--- 按本局单位编号查询，不按精灵种类或背包位置查询。
---@param id integer
---@return Pet?
function Bag:getPet(id)
    for _, pet in ipairs(self.pets) do
        if pet.id == id then return pet end
    end
end

---@return Pet[]
function Bag:getAlivePets()
    local pets = {}
    for _, pet in ipairs(self.pets) do
        if pet.alive then pets[#pets + 1] = pet end
    end
    return pets
end

---@return table<integer, integer>
function Bag:getItems()
    local items = {}
    for id, count in pairs(self.items) do items[id] = count end
    return items
end

---@param id integer
---@return integer
function Bag:getItemCount(id)
    return self.items[id] or 0
end

---@param id integer
---@param count? integer 默认查询是否至少有一个
---@return boolean
function Bag:hasItem(id, count)
    return self:getItemCount(id) >= (count or 1)
end

return Bag
