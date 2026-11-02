-- SPDX-License-Identifier: LGPL-2.1-or-later
local GameEvent = require "gamethread.gameevent"
local BuffType = require "seer.core.buff.type"
require "seer.core.events"

-- 前置时机返回 true 与显式 preventBuff 都表示阻止；结束时机的返回值不撤销结果。
local function blocked(logic, timing, target, data)
    if data.prevented or logic.ctx.gameFinished then return true end
    if logic:trigger(timing, target, data) then data:preventBuff() end
    return data.prevented or logic.ctx.gameFinished
end

local function canAttach(logic, who, buff)
    if logic.ctx.gameFinished or not logic:isBuffTargetAlive(who) then return false end
    if buff.owner or buff:isExpired() then return false end
    return buff.keepOnSwitch or not logic.leavingPets[who]
end

local AddBuff = GameEvent:subclass("Seer.GameEvent.AddBuff")
function AddBuff:main()
    local logic, data = self.ctx.logic, self.data
    data.added = false
    local who, buff = data.who, data.buff
    if not self.ctx.gameFinished then logic:removeExpiredBuffs(who) end
    if canAttach(logic, who, buff) and not blocked(logic, sr.BeforeBuffAdded, who, data) then
        -- 前置效果可能在嵌套结算中添加状态、耗尽旧状态或击倒目标，提交前再检查。
        logic:removeExpiredBuffs(who)
        if canAttach(logic, who, buff) and not logic:getBuff(who, buff.id, true)
            and (not buff.abnormalKind or not logic:getAbnormal(who, buff.abnormalKind)) then
            who.buffs[#who.buffs + 1] = buff
            buff.owner = who
            buff.firstTickRound = logic.roundEndNumber and (logic.roundEndNumber + 1) or logic.roundNumber
            data.added = true
            self.ctx:broadcast("Seer.BuffAdded", { id = who.id, buffId = buff.id, name = buff.name,
                type = buff.type, scope = buff.scope, keepOnSwitch = buff.keepOnSwitch,
                abnormalKind = buff.abnormalKind, abnormalCategory = buff.abnormalCategory,
                turn = buff.turn, count = buff.count, stacks = buff.stacks, value = buff.value })
            logic:trigger(sr.BuffAdded, who, data)
        end
    end
    if not self.ctx.gameFinished then logic:trigger(sr.BuffAddFinished, who, data) end
    return data.added
end

local ApplyAbnormal = GameEvent:subclass("Seer.GameEvent.ApplyAbnormal")
function ApplyAbnormal:main()
    local logic, data = self.ctx.logic, self.data
    data.added = false
    assert(data.buff.type == BuffType.Abnormal, "applyAbnormal requires an abnormal buff")
    if not self.ctx.gameFinished and data.who.alive then
        local timings = { { sr.PreAbnormal, data.who },
            { sr.AbnormalCaused, data.from }, { sr.AbnormalInflicted, data.who } }
        local prevented = false
        for _, timing in ipairs(timings) do
            if blocked(logic, timing[1], timing[2], data) then prevented = true; break end
        end
        if not prevented then
            -- 直接执行子事件，不能回到 addBuff 入口，否则异常会被再次分派到本流程。
            logic:executeEvent(AddBuff, data)
            if data.added and not self.ctx.gameFinished then logic:trigger(sr.AbnormalApplied, data.who, data) end
        end
    end
    if not self.ctx.gameFinished then logic:trigger(sr.AbnormalFinished, data.who, data) end
    return data.added
end

local RemoveBuff = GameEvent:subclass("Seer.GameEvent.RemoveBuff")
function RemoveBuff:main()
    local logic, data = self.ctx.logic, self.data
    data.removed = false
    -- 自然耗尽与规则离场是强制清理；普通移除仍可取消，驱散另受 dispellable 约束。
    local forced = data.reason == "switch" or (data.reason == "expired" and data.buff:isExpired())
    data.forced = forced
    local prevented = true
    if not self.ctx.gameFinished then
        prevented = blocked(logic, sr.BeforeBuffRemoved, data.who, data)
        data.forced = forced
        if forced then data.prevented = false end
    end
    if not self.ctx.gameFinished and (forced or not prevented)
        and (forced or data.reason ~= "dispel" or data.buff.dispellable) then
        -- 以实例身份移除，避免前置时机嵌套替换同编号 Buff 后误删新实例。
        for index, buff in ipairs(data.who.buffs) do
            if buff == data.buff then
                table.remove(data.who.buffs, index)
                buff.owner = nil
                data.removed = true
                self.ctx:broadcast("Seer.BuffRemoved", { id = data.who.id, buffId = buff.id, scope = buff.scope, reason = data.reason })
                logic:trigger(sr.BuffRemoved, data.who, data)
                break
            end
        end
    end
    if not self.ctx.gameFinished then logic:trigger(sr.BuffRemoveFinished, data.who, data) end
    return data.removed
end

local ResolveRoundEnd = GameEvent:subclass("Seer.GameEvent.ResolveRoundEnd")
function ResolveRoundEnd:main()
    local logic, data = self.ctx.logic, self.data
    assert(math.type(data.number) == "integer" and data.number > 0, "round number must be positive")
    if self.ctx.gameFinished or data.number <= logic.lastBuffRound then return end
    assert(not logic.roundEndNumber, "cannot nest round-end settlement")
    logic.lastBuffRound = data.number
    logic.roundEndNumber = data.number
    self.scoped = true
    local snapshot = logic:snapshotBuffs()
    logic:trigger(sr.RoundEnd, nil, data)
    for _, entry in ipairs(snapshot) do
        if self.ctx.gameFinished then break end
        local who, buff = entry.who, entry.buff
        if buff.owner == who and logic:getBuff(who, buff.id, true) == buff then
            if buff.turn ~= nil and data.number >= (buff.firstTickRound or data.number) then
                buff:advanceRound()
                if not buff:isExpired() then
                    logic:notifyBuffUpdated(who, buff)
                end
            end
            if buff:isExpired() then logic:removeBuff { who = who, buff = buff, reason = "expired" } end
        end
    end
end
function ResolveRoundEnd:clear()
    if self.scoped then self.ctx.logic.roundEndNumber = nil end
end

return { AddBuff = AddBuff, ApplyAbnormal = ApplyAbnormal, RemoveBuff = RemoveBuff,
    ResolveRoundEnd = ResolveRoundEnd }
