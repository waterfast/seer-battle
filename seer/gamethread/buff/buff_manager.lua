-- SPDX-License-Identifier: LGPL-2.1-or-later
local Buff = require "seer.core.buff"
local BuffType = require "seer.core.buff.type"
local Events = require "seer.gamethread.events.buff"

--- Buff 查询与流程入口，作为 mixin 加入 Seer.GameLogic。
--- 不在这里实现具体异常伤害、免疫或重复刷新规则。
---@class BuffChangeRequest: BuffChangeDataSpec
---@field buff integer|Buff @传配置编号时创建局内实例
---@field state? table @本次施加的 turn/count/stacks/maxStacks/value；只用于编号入口
local BuffManager = {}

--- 查询目标身上的第一个同编号 Buff，默认排除耗尽状态。
---@param who Pet
---@param id integer
---@param includeExpired? boolean
---@return Buff?
function BuffManager:getBuff(who, id, includeExpired)
    for _, buff in ipairs(who.buffs) do
        if buff.id == id and (includeExpired or not buff:isExpired()) then return buff end
    end
end

--- 输入允许注册编号或局内 Buff 实例，触发时机中统一使用实例。
local function prepare(self, spec)
    assert(spec.who and spec.who.ctx == self.ctx, "buff target must belong to this battle")
    local data = {}
    for key, value in pairs(spec) do data[key] = value end
    if type(data.buff) == "number" then
        data.buff = sr:createBuff(data.buff, data.state)
    else
        assert(data.state == nil, "state must be passed when creating a buff by id")
    end
    assert(type(data.buff) == "table" and data.buff.isInstanceOf and data.buff:isInstanceOf(Buff),
        "buff must be an id or Buff instance")
    assert(math.type(data.buff.id) == "integer", "buff must have an installed id")
    assert(sr:getBuff(data.buff.id) ~= data.buff, "shared buff definitions cannot be attached")
    return BuffChangeData:new(data)
end

--- 添加 Buff。异常类型自动经过异常流程，避免绕开免疫时机。
---@param spec BuffChangeRequest
---@return boolean added
function BuffManager:addBuff(spec)
    local data = prepare(self, spec)
    local event = data.buff.type == BuffType.Abnormal and Events.ApplyAbnormal or Events.AddBuff
    return self:executeEvent(event, data)
end

--- 显式施加异常，供技能调用；非异常 Buff 不接受此入口。
---@param spec BuffChangeRequest
---@return boolean added
function BuffManager:applyAbnormal(spec)
    return self:executeEvent(Events.ApplyAbnormal, prepare(self, spec))
end

--- 移除一个明确的 Buff 实例；也可用编号定位，包含已耗尽状态。
---@param spec BuffChangeRequest
---@return boolean removed
function BuffManager:removeBuff(spec)
    assert(spec.who and spec.who.ctx == self.ctx, "buff target must belong to this battle")
    local data = {}
    for key, value in pairs(spec) do data[key] = value end
    if type(data.buff) == "number" then data.buff = self:getBuff(data.who, data.buff, true) end
    if not data.buff then return false end
    return self:executeEvent(Events.RemoveBuff, BuffChangeData:new(data))
end

return BuffManager
