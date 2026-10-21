-- SPDX-License-Identifier: LGPL-2.1-or-later
---
--[[
精灵的原始面板与当前体力，不保存能力等级带来的倍率。
--]]
local class = kt.class

---@class Stat: Object
---@field atk number @攻击，未应用能力等级
---@field def number @防御，未应用能力等级
---@field spatk number @特攻，未应用能力等级
---@field spdef number @特防，未应用能力等级
---@field speed number @速度，未应用能力等级
---@field hp number @当前体力
---@field maxHp number @体力上限
local Stat = class("Stat")
local names = { "atk", "def", "spatk", "spdef", "speed", "hp", "maxHp" }
local valid = {}
for _, name in ipairs(names) do
    valid[name] = true
end

--- 构造面板，未提供的属性默认为 0。
---@param data? table<string, number> 初始面板，允许包含其他精灵数据字段
function Stat:initialize(data)
    data = data or {}
    for _, name in ipairs(names) do
        self[name] = 0
    end

    local values = {}
    for _, name in ipairs(names) do
        values[name] = data[name] or 0
    end
    self:setMany(values)
end

--- 读取指定面板属性。
---@param name string 属性名称
---@return number @当前值
function Stat:get(name)
    assert(valid[name], "unknown stat: " .. tostring(name))
    return self[name]
end

--- 先校验整批数据，避免输入错误时只修改一部分。
---@param values table<string, number> 待更新的面板属性，必须为有限非负数
function Stat:setMany(values)
    for name, value in pairs(values) do
        assert(valid[name], "unknown stat: " .. tostring(name))
        assert(type(value) == "number" and value >= 0 and value < math.huge,
            "stat must be a finite non-negative number")
    end
    for name, value in pairs(values) do
        self[name] = value
    end
end

--- 导出独立副本，修改结果不会影响当前对象。
---@return table<string, number> @属性快照
function Stat:toTable()
    local result = {}
    for _, name in ipairs(names) do
        result[name] = self[name]
    end

    return result
end

return Stat
