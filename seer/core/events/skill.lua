-- SPDX-License-Identifier: LGPL-2.1-or-later

---@class SkillUseDataSpec
---@field from Pet
---@field to Pet
---@field skill Skill
---@field prevented boolean?
---@field preventReason? string @技能被阻止的业务原因
---@field power? number @本次计算的威力，不修改共享技能配置
---@field hit boolean?
---@field isCritical? boolean @计算前可显式指定，计算后保存实际结果
---@field critChance? number @本次基础暴击率覆盖
---@field critChanceBonus? number @本次暴击概率加值覆盖
---@field critResistance? number @本次目标暴击抗性覆盖
---@field randomRoll? integer @本次浮动覆盖，217～255
---@field calculation? DamageCalculation @独立计算服务返回的本段数值记录
---@field damage integer?
---@field actualDamage integer?
---@field damageEvent? DamageData @ 本次普通攻击对应的伤害结算对象；未进入 Damage 时为空
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

--- 命中效果之后、数值计算之前，可修改本次 power。
sr.BeforeSkillDamageCalculation = SkillUseEvent:subclass("sr.BeforeSkillDamageCalculation")
