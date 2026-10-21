-- SPDX-License-Identifier: LGPL-2.1-or-later

--- 描述一次 Buff 添加、异常施加或移除。buff 是局内实例，不能传入共享定义。
---@class BuffChangeDataSpec
---@field from? Pet @来源，可为空（例如场地效果）
---@field who Pet @目标
---@field buff Buff @本次操作的局内 Buff 实例
---@field skill? Skill @来源技能
---@field reason? string @移除等操作的原因，例如 expired
---@field prevented? boolean @是否阻止本次操作
---@field added? boolean @是否实际添加
---@field removed? boolean @是否实际移除
---@class BuffChangeData: BuffChangeDataSpec, TriggerData
BuffChangeData = TriggerData:subclass("BuffChangeData")

--- 防止本次添加、异常施加或移除。
function BuffChangeData:preventBuff()
    self.prevented = true
end

---@class BuffChangeEvent: TriggerEvent
---@field data BuffChangeData
local BuffChangeEvent = TriggerEvent:subclass("BuffChangeEvent")

--- 添加 Buff 前，可以修改实例参数或防止添加。
---@class sr.BeforeBuffAdded: BuffChangeEvent
sr.BeforeBuffAdded = BuffChangeEvent:subclass("sr.BeforeBuffAdded")
--- Buff 已进入目标的列表后。
---@class sr.BuffAdded: BuffChangeEvent
sr.BuffAdded = BuffChangeEvent:subclass("sr.BuffAdded")
--- 添加流程结束，即使未添加也触发；通过 data.added 判断结果。
---@class sr.BuffAddFinished: BuffChangeEvent
sr.BuffAddFinished = BuffChangeEvent:subclass("sr.BuffAddFinished")

--- 移除前，可以防止移除；此时该 Buff 仍在列表中。
---@class sr.BeforeBuffRemoved: BuffChangeEvent
sr.BeforeBuffRemoved = BuffChangeEvent:subclass("sr.BeforeBuffRemoved")
---@class sr.BuffRemoved: BuffChangeEvent
sr.BuffRemoved = BuffChangeEvent:subclass("sr.BuffRemoved")
---@class sr.BuffRemoveFinished: BuffChangeEvent
sr.BuffRemoveFinished = BuffChangeEvent:subclass("sr.BuffRemoveFinished")

--- 异常施加开始前。
---@class sr.PreAbnormal: BuffChangeEvent
sr.PreAbnormal = BuffChangeEvent:subclass("sr.PreAbnormal")
--- 来源施加异常时，target 为来源，可以阻止或调整异常。
---@class sr.AbnormalCaused: BuffChangeEvent
sr.AbnormalCaused = BuffChangeEvent:subclass("sr.AbnormalCaused")
--- 目标承受异常时，target 为目标；异常免疫在这里防止施加。
---@class sr.AbnormalInflicted: BuffChangeEvent
sr.AbnormalInflicted = BuffChangeEvent:subclass("sr.AbnormalInflicted")
--- 异常成功添加后。
---@class sr.AbnormalApplied: BuffChangeEvent
sr.AbnormalApplied = BuffChangeEvent:subclass("sr.AbnormalApplied")
--- 异常施加流程结束，包含免疫、重复等未添加的情况。
---@class sr.AbnormalFinished: BuffChangeEvent
sr.AbnormalFinished = BuffChangeEvent:subclass("sr.AbnormalFinished")
