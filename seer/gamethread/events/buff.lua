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

local AddBuff = GameEvent:subclass("Seer.GameEvent.AddBuff")
function AddBuff:main()
    local logic, data = self.ctx.logic, self.data
    data.added = false
    local who, buff = data.who, data.buff
    if not self.ctx.gameFinished and who.alive and not buff.owner and not buff:isExpired()
        and not blocked(logic, sr.BeforeBuffAdded, who, data) then
        -- 前置效果可能在嵌套结算中添加相同状态、消耗轮数或击倒目标，提交前再检查。
        if who.alive and not buff.owner and not buff:isExpired() and not logic:getBuff(who, buff.id, true) then
            who.buffs[#who.buffs + 1] = buff
            buff.owner = who
            data.added = true
            self.ctx:broadcast("Seer.BuffAdded", { id = who.id, buffId = buff.id, name = buff.name,
                type = buff.type, turn = buff.turn, count = buff.count, stacks = buff.stacks, value = buff.value })
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
    if not self.ctx.gameFinished and not blocked(logic, sr.BeforeBuffRemoved, data.who, data) then
        -- 以实例身份移除，避免前置时机嵌套替换同编号 Buff 后误删新实例。
        for index, buff in ipairs(data.who.buffs) do
            if buff == data.buff then
                table.remove(data.who.buffs, index)
                buff.owner = nil
                data.removed = true
                self.ctx:broadcast("Seer.BuffRemoved", { id = data.who.id, buffId = buff.id, reason = data.reason })
                logic:trigger(sr.BuffRemoved, data.who, data)
                break
            end
        end
    end
    if not self.ctx.gameFinished then logic:trigger(sr.BuffRemoveFinished, data.who, data) end
    return data.removed
end

return { AddBuff = AddBuff, ApplyAbnormal = ApplyAbnormal, RemoveBuff = RemoveBuff }
