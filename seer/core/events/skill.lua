-- SPDX-License-Identifier: LGPL-2.1-or-later

---@class SkillUseDataSpec
---@field from Pet
---@field to Pet
---@field skill Skill
---@field prevented boolean?
---@field hit boolean?
---@field damage integer?
---@field actualDamage integer?
---@class SkillUseData: SkillUseDataSpec, TriggerData
SkillUseData = TriggerData:subclass("SkillUseData")

---@class SkillUseEvent: TriggerEvent
---@field data SkillUseData
local SkillUseEvent = TriggerEvent:subclass("SkillUseEvent")

---@class sr.BeforeSkillUse: SkillUseEvent
sr.BeforeSkillUse = SkillUseEvent:subclass("sr.BeforeSkillUse")
---@class sr.SkillUsing: SkillUseEvent
sr.SkillUsing = SkillUseEvent:subclass("sr.SkillUsing")
---@class sr.BeforeSkillHit: SkillUseEvent
sr.BeforeSkillHit = SkillUseEvent:subclass("sr.BeforeSkillHit")
---@class sr.SkillHit: SkillUseEvent
sr.SkillHit = SkillUseEvent:subclass("sr.SkillHit")
---@class sr.SkillMissed: SkillUseEvent
sr.SkillMissed = SkillUseEvent:subclass("sr.SkillMissed")
---@class sr.BeforeSkillDamage: SkillUseEvent
sr.BeforeSkillDamage = SkillUseEvent:subclass("sr.BeforeSkillDamage")
---@class sr.SkillUseFinished: SkillUseEvent
sr.SkillUseFinished = SkillUseEvent:subclass("sr.SkillUseFinished")

--- 命中后的整段效果处理完毕（含属性技或被防止的伤害），未命中不触发。
---@class sr.SkillEffectFinished: SkillUseEvent
sr.SkillEffectFinished = SkillUseEvent:subclass("sr.SkillEffectFinished")
--- 伤害事件返回后触发，actualDamage 是实际扣除量，伤害被防止时为 0。
---@class sr.AfterSkillDamage: SkillUseEvent
sr.AfterSkillDamage = SkillUseEvent:subclass("sr.AfterSkillDamage")
