-- SPDX-FileCopyrightText: 2026 Notify Ctrl <notify-ctrl@qq.com>
-- SPDX-License-Identifier: LGPL-2.1-or-later

local Effect = require "seer.core.effect"

---@class TriggerEffect: Effect
---@field event TriggerEvent @监听的时机类，例如 sr.DamageFinished；不是某次事件实例
---@field priority number @调度时的优先级，越大越先执行，默认 1
local TriggerEffect = Effect:subclass("TriggerEffect")

---@param skeleton TriggerEffectSkeleton
---@param can_triggervalue? table
---@param on_usevalue? table
---@param source? Skill|Buff
function TriggerEffect:initialize(skeleton, can_triggervalue, on_usevalue, source)
    Effect.initialize(self, skeleton, can_triggervalue, on_usevalue, source)
    assert(skeleton.type == Effect.Trigger, "TriggerEffect requires a trigger skeleton")
    self.event = skeleton.event
    self.priority = skeleton.priority
end

--- 委托骨架判断来源、目标、技能等条件。默认不发动，避免未实现的效果意外生效。
---@param event TriggerEvent 本次事件实例，可通过 event.ctx 访问战斗上下文
---@param target GameUnit? 引发时机的单位，不一定是效果拥有者
---@param owner GameUnit? 效果拥有者；场地等全局效果可以没有拥有者
---@param data any 本次事件的结算数据
---@return boolean
function TriggerEffect:triggerable(event, target, owner, data)
    -- 候选是快照；前面的效果可能已经移除/耗尽此 Buff，不能继续发动旧实例。
    local source = self.source
    if source and source.isExpired and (source.owner ~= owner or source:isExpired()) then return false end
    local callback = self.skeleton.can_trigger
    return callback ~= nil and callback(self, event, target, owner, data, self.can_triggervalue) == true
end

--- 骨架实现消耗或发动确认；流程根据返回值决定是否继续调用 use。
---@param event TriggerEvent
---@param target GameUnit?
---@param owner GameUnit?
---@param data any
---@return boolean @true 表示完成消耗或同意发动；默认无需消耗
function TriggerEffect:cost(event, target, owner, data)
    local callback = self.skeleton.on_cost
    if callback then return callback(self, event, target, owner, data, self.on_usevalue) end
    return true
end

--- 只执行效果，不检查时机、发动条件或消耗；调用顺序由流程负责。
---@param event TriggerEvent
---@param target GameUnit?
---@param owner GameUnit?
---@param data any
---@return boolean? @true 表示请求中断本次时机的后续结算，由流程处理
function TriggerEffect:use(event, target, owner, data)
    local callback = self.skeleton.on_use
    if not callback then return end
    local source, previous = self.source
    if source and source.isExpired and source.owner then
        previous = { turn = source.turn, count = source.count, stacks = source.stacks, value = source.value }
    end
    local result = callback(self, event, target, owner, data, self.on_usevalue)
    if previous then event.ctx.logic:finishBuffEffect(source, previous) end
    return result
end

return TriggerEffect
