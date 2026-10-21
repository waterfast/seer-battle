-- SPDX-License-Identifier: LGPL-2.1-or-later
---
--[[
战斗中的能力变化等级，与原始面板分开保存，范围为 -6～+6。
--]]
local class = kt.class

---@class StatStages: Object
---@field atk integer @攻击等级，-6～+6
---@field def integer @防御等级，-6～+6
---@field spatk integer @特攻等级，-6～+6
---@field spdef integer @特防等级，-6～+6
---@field speed integer @速度等级，-6～+6
---@field accuracy integer @命中等级，-6～+6
local StatStages = class("StatStages")
local names = { "atk", "def", "spatk", "spdef", "speed", "accuracy" }
local valid = {}
for _, name in ipairs(names) do
    valid[name] = true
end
-- 赛尔号命中弱化使用独立表，不使用宝可梦的命中倍率。
local accuracyDebuffs = { 0.85, 0.70, 0.55, 0.45, 0.35, 0.25 }

local function check(name, value)
    assert(valid[name], "unknown stat stage: " .. tostring(name))
    assert(math.type(value) == "integer", "stat stage must be an integer")
end

--- 供参数化能力效果复用同一份能力名称集合。
function StatStages.isValidName(name)
    return valid[name] == true
end

--- 返回按固定顺序排列的能力名称副本，供筛选规则复用，避免维护多份全集。
---@return string[]
function StatStages.getNames()
    local result = {}
    for index, name in ipairs(names) do
        result[index] = name
    end
    return result
end

--- 构造能力等级，所有能力从 0 级开始。
function StatStages:initialize()
    self:reset()
end

--- 读取指定能力的当前等级。
---@param name string 属性名称
---@return integer @当前值
function StatStages:get(name)
    assert(valid[name], "unknown stat stage: " .. tostring(name))
    return self[name]
end

--- 返回实际变化量，封顶后可能小于请求值。
---@param name string 能力名称
---@param value integer 目标等级，超出范围时截断至 -6～+6
---@return integer @实际变化量
function StatStages:set(name, value)
    check(name, value)
    local old = self[name]
    self[name] = math.max(-6, math.min(6, value))
    return self[name] - old
end

--- 在当前等级上增减，遵循与 set 相同的上下限。
---@param name string 能力名称
---@param delta integer 请求变化量，正数强化、负数弱化
---@return integer @实际变化量
function StatStages:change(name, delta)
    check(name, delta)
    return self:set(name, self[name] + delta)
end

--- 支持一次升降多项；所有参数通过校验后才执行。
---@param deltas table<string, integer> 各项能力的请求变化量
---@return table<string, integer> @各项能力的实际变化量
function StatStages:changeMany(deltas)
    for name, delta in pairs(deltas) do
        check(name, delta)
    end

    local changed = {}
    for name, delta in pairs(deltas) do
        changed[name] = self:change(name, delta)
    end

    return changed
end

--- 清空全部能力等级，恢复到未强化、未弱化的状态。
function StatStages:reset()
    for _, name in ipairs(names) do
        self[name] = 0
    end
end

--- 将等级换算为倍率，不修改原始面板；命中弱化单独查表。
---@param name string 能力名称
---@return number @用于战斗结算的倍率
function StatStages:getMultiplier(name)
    local stage = self:get(name)
    if stage >= 0 then
        return (2 + stage) / 2
    end
    if name == "accuracy" then
        return accuracyDebuffs[-stage]
    end
    return 2 / (2 - stage)
end

--- 导出独立副本，修改结果不会影响当前对象。
---@return table<string, integer> @属性快照
function StatStages:toTable()
    local result = {}
    for _, name in ipairs(names) do
        result[name] = self[name]
    end

    return result
end

return StatStages
