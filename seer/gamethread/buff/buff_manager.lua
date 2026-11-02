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
---@param who Pet|ServerPlayer
---@param id integer
---@param includeExpired? boolean
---@return Buff?
function BuffManager:getBuff(who, id, includeExpired)
    for _, buff in ipairs(who.buffs) do
        if buff.id == id and (includeExpired or not buff:isExpired()) then return buff end
    end
end

--- 异常查询返回同一 buffs 容器中的实例，不维护第二套可变状态。
function BuffManager:getAbnormals(who, category)
    local result = {}
    for _, buff in ipairs(who.buffs) do
        if buff.type == BuffType.Abnormal and not buff:isExpired()
            and (category == nil or buff.abnormalCategory == category) then
            result[#result + 1] = buff
        end
    end
    return result
end

function BuffManager:getAbnormal(who, kind)
    for _, buff in ipairs(self:getAbnormals(who)) do
        if buff.abnormalKind == kind then return buff end
    end
end

function BuffManager:hasAbnormal(who, kind)
    return self:getAbnormal(who, kind) ~= nil
end

--- 玩家方与精灵使用同一套状态操作，归属必须明确属于本局。
function BuffManager:isBuffTargetAlive(who)
    if who.player then return who.alive end
    return #who.bag:getAlivePets() > 0
end

local function checkTarget(self, who)
    assert(who and who.ctx == self.ctx and type(who.buffs) == "table",
        "buff target must belong to this battle")
    if not who.player then
        assert(self.ctx:getPlayer(who.id) == who, "side buff target must be a battle player")
    end
end

function BuffManager:notifyBuffUpdated(who, buff)
    self.ctx:broadcast("Seer.BuffUpdated", { id = who.id, buffId = buff.id, scope = buff.scope,
        turn = buff.turn, count = buff.count, stacks = buff.stacks, value = buff.value })
end

--- 效果成功执行后，框架收尾已耗尽状态，脚本只需表达实际消耗。
function BuffManager:finishBuffEffect(buff, previous)
    local who = buff.owner
    if not who or self.ctx.gameFinished then return end
    if buff:isExpired() then
        self:removeBuff { who = who, buff = buff, reason = "expired" }
    else
        for _, field in ipairs({ "turn", "count", "stacks", "value" }) do
            if buff[field] ~= previous[field] then self:notifyBuffUpdated(who, buff); break end
        end
    end
end

--- 对精灵、后备和玩家方统一取实例快照，计时不依赖当前出战位置。
function BuffManager:snapshotBuffs()
    local result = {}
    local function append(who)
        for _, buff in ipairs(who.buffs) do result[#result + 1] = { who = who, buff = buff } end
    end
    for _, player in ipairs(self.ctx.players) do
        append(player)
        for _, pet in ipairs(player.bag.pets) do append(pet) end
    end
    return result
end

--- 到期清理不能被驱散免疫阻止；防止清理回调嵌套添加时递归清理同一列表。
function BuffManager:removeExpiredBuffs(who)
    if self.expiredCleanup[who] then return end
    self.expiredCleanup[who] = true
    local ok, err = xpcall(function()
        for _, buff in ipairs({ table.unpack(who.buffs) }) do
            if self.ctx.gameFinished then break end
            if buff:isExpired() then self:removeBuff { who = who, buff = buff, reason = "expired" } end
        end
    end, debug.traceback)
    self.expiredCleanup[who] = nil
    if not ok then error(err, 0) end
end

function BuffManager:clearSwitchBuffs(who)
    local previous = self.leavingPets[who]
    self.leavingPets[who] = true
    local ok, err = xpcall(function()
        for _, buff in ipairs({ table.unpack(who.buffs) }) do
            if self.ctx.gameFinished then break end
            if not buff.keepOnSwitch then self:removeBuff { who = who, buff = buff, reason = "switch" } end
        end
    end, debug.traceback)
    self.leavingPets[who] = previous
    if not ok then error(err, 0) end
end

--- 轮末业务效果、统一扣轮与过期清理组成一个完整结算。
function BuffManager:finishRound(data)
    return self:executeEvent(Events.ResolveRoundEnd, data)
end

--- 输入允许注册编号或局内 Buff 实例，触发时机中统一使用实例。
local function prepare(self, spec)
    checkTarget(self, spec.who)
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
    assert(data.buff.scope == (data.who.player and "pet" or "side"), "buff scope does not match its target")
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
    checkTarget(self, spec.who)
    local data = {}
    for key, value in pairs(spec) do data[key] = value end
    if type(data.buff) == "number" then data.buff = self:getBuff(data.who, data.buff, true) end
    if not data.buff then return false end
    return self:executeEvent(Events.RemoveBuff, BuffChangeData:new(data))
end

return BuffManager
