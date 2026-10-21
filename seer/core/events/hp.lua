-- SPDX-License-Identifier: GPL-3.0-or-later
-- Adapted from FreeKill ltk/core/events/hp.lua; retains the original data/event layout.

--- HpChangedData 描述和一次体力变化有关的数据
---@class HpChangedDataSpec
---@field public who GameUnit @ 体力变化的角色
---@field public num integer @ 体力变化量，可能是正数或者负数
---@field public shield_lost? integer @ 护甲变化量
---@field public reason string @ 体力变化原因
---@field public skillName string @ 引起体力变化的技能名
---@field public damageEvent? DamageData @ 引起这次体力变化的伤害数据
---@field public hpLostEvent? DamageData @ 引起这次体力变化的体力流失数据
---@field public preventDying? boolean @ 是否阻止本次体力变更流程引发濒死流程
---@field public prevented boolean? @ 体力变化是否被防止

--- 描述和一次体力变化有关的数据
---@class HpChangedData: HpChangedDataSpec, TriggerData
HpChangedData = TriggerData:subclass("HpChangedData")

--- HpLostData 描述跟失去体力有关的数据
---@class HpLostDataSpec
---@field public who GameUnit @ 失去体力的角色
---@field public num integer @ 失去体力的数值
---@field public skillName string @ 导致这次失去的技能名
---@field public proposer GameUnit @ 体力流失来源
---@field public prevented boolean? @ 失去体力是否被防止

--- 描述跟失去体力有关的数据
---@class HpLostData: HpLostDataSpec, TriggerData
HpLostData = TriggerData:subclass("HpLostData")

--- 防止失去体力
function HpLostData:preventHpLost()
  self.num = 0
  self.prevented = true
end

--- ShieldChangedData 描述和一次护甲变化有关的数据
---@class ShieldChangedDataSpec
---@field public who GameUnit @ 护甲变化的角色
---@field public num integer @ 护甲变化量，可能是正数或者负数
---@field public prevented boolean? @ 护甲变化是否被防止

--- 描述和一次护甲变化有关的数据
---@class ShieldChangedData: ShieldChangedDataSpec, TriggerData
ShieldChangedData = TriggerData:subclass("ShieldChangedData")

--- 防止护甲变化
function ShieldChangedData:preventShieldChange()
  self.num = 0
  self.prevented = true
end

--- MaxHpChangedData 描述跟体力上限变化有关的数据
---@class MaxHpChangedDataSpec
---@field public who GameUnit @ 改变体力上限的角色
---@field public num integer @ 体力上限变化量，可能是正数或者负数
---@field public prevented boolean? @ 改变体力上限是否被防止

--- 描述跟体力上限变化有关的数据
---@class MaxHpChangedData: MaxHpChangedDataSpec, TriggerData
MaxHpChangedData = TriggerData:subclass("MaxHpChangedData")

--- 防止改变体力上限
function MaxHpChangedData:preventMaxHpChange()
  self.num = 0
  self.prevented = true
end

---@alias DamageType integer
sr.NormalDamage = 1 --一般攻击伤害
sr.FixedDamage = 2 --固定伤害
sr.PercentDamage = 3 --百分比伤害
sr.TrueDamage = 4 --真实伤害

--- DamageData 描述和伤害事件有关的数据
---@class DamageDataSpec
---@field public from? GameUnit @ 伤害来源
---@field public to GameUnit @ 伤害目标
---@field public damage integer @ 伤害值
---@field public actualDamage? integer @ 实际扣除体力，防止伤害时为 0
---@field public skill? Skill @ 本次伤害来源技能
---@field public card? Card @ 造成伤害的牌
---@field public chain? boolean @ 伤害是否是铁索传导的伤害
---@field public damageType? DamageType @ 伤害属性
---@field public skillName? string @ 造成本次伤害的技能名
---@field public beginnerOfTheDamage? boolean @ 是否是本次铁索传导的起点
---@field public by_user? boolean @ 是否由卡牌直接生效造成的伤害
---@field public chain_table? GameUnit[] @ 处于连环状态的角色表
---@field public isVirtualDMG? boolean @ 是否是虚拟伤害
---@field public dealtRecorderId integer? @ “实际造成的伤害”中对应的事件ID
---@field public prevented boolean? @ 伤害是否被防止
---@field public parent DamageData? @ 传导的来源伤害数据

--- 描述和伤害事件有关的数据
---@class DamageData: DamageDataSpec, TriggerData
DamageData = TriggerData:subclass("DamageData")

--- 改变伤害事件的伤害值
---@param num integer 伤害值改变量
function DamageData:changeDamage(num)
  self.last_damage = self.damage
  self.damage = self.damage + num
  if self.damage < 1 then
    self:preventDamage()
  end
end

--- 防止伤害
function DamageData:preventDamage()
  if self.damage > 0 then
    self.last_damage = self.damage
  end
  self.damage = 0
  self.prevented = true
end

--- RecoverData 描述和回复体力有关的数据
---@class RecoverDataSpec
---@field public who GameUnit @ 回复体力的角色
---@field public num integer @ 回复值
---@field public recoverBy? GameUnit @ 此次回复的回复来源
---@field public skillName? string @ 因何种技能而回复
---@field public card? Card @ 造成此次回复的卡牌
---@field public prevented boolean? @ 回复体力是否被防止

--- 描述和回复体力有关的数据
---@class RecoverData: RecoverDataSpec, TriggerData
RecoverData = TriggerData:subclass("RecoverData")

--- 改变回复事件的回复值
---@param num integer 回复值改变量
function RecoverData:changeRecover(num)
  self.num = self.num + num
  if self.num < 1 then
    self:preventRecover()
  end
end

--- 防止回复
function RecoverData:preventRecover()
  self.num = 0
  self.prevented = true
end

---@class HpChangedEvent: TriggerEvent
---@field data HpChangedData
local HpChangedEvent = TriggerEvent:subclass("HpChangedEvent")

--- 改变体力值前
---@class sr.BeforeHpChanged: HpChangedEvent
sr.BeforeHpChanged = HpChangedEvent:subclass("sr.BeforeHpChanged")
--- 改变体力值后
---@class sr.HpChanged: HpChangedEvent
sr.HpChanged = HpChangedEvent:subclass("sr.HpChanged")

---@class DamageEvent: TriggerEvent
---@field data DamageData
local DamageEvent = TriggerEvent:subclass("DamageEvent")

--- 伤害结算开始前
---@class sr.PreDamage: DamageEvent
sr.PreDamage = DamageEvent:subclass("sr.PreDamage")
--- 造成伤害时
---@class sr.DamageCaused: DamageEvent
sr.DamageCaused = DamageEvent:subclass("sr.DamageCaused")
--- 造成伤害时②（用于确定伤害值，如改为固定伤害值或防止伤害）
---@class sr.DetermineDamageCaused: DamageEvent
sr.DetermineDamageCaused = DamageEvent:subclass("sr.DetermineDamageCaused")
--- 受到伤害时
---@class sr.DamageInflicted: DamageEvent
sr.DamageInflicted = DamageEvent:subclass("sr.DamageInflicted")
--- 受到伤害时②（用于确定伤害值，如改为固定伤害值或防止伤害）
---@class sr.DetermineDamageInflicted: DamageEvent
sr.DetermineDamageInflicted = DamageEvent:subclass("sr.DetermineDamageInflicted")
--- 造成伤害后
---@class sr.Damage: DamageEvent
sr.Damage = DamageEvent:subclass("sr.Damage")
--- 受到伤害后
---@class sr.Damaged: DamageEvent
sr.Damaged = DamageEvent:subclass("sr.Damaged")
--- 伤害结算结束后
---@class sr.DamageFinished: DamageEvent
sr.DamageFinished = DamageEvent:subclass("sr.DamageFinished")

---@class HpLostEvent: TriggerEvent
---@field public data HpLostData
local HpLostEvent = TriggerEvent:subclass("HpLostEvent")

--- 失去体力结算开始前
---@class sr.PreHpLost: HpLostEvent
sr.PreHpLost = HpLostEvent:subclass("sr.PreHpLost")
--- 失去体力后
---@class sr.HpLost: HpLostEvent
sr.HpLost = HpLostEvent:subclass("sr.HpLost")

---@class RecoverEvent: TriggerEvent
---@field public data RecoverData
local RecoverEvent = TriggerEvent:subclass("RecoverEvent")

--- 回复体力结算开始前
---@class sr.PreHpRecover: RecoverEvent
sr.PreHpRecover = RecoverEvent:subclass("sr.PreHpRecover")
--- 回复体力后
---@class sr.HpRecover: RecoverEvent
sr.HpRecover = RecoverEvent:subclass("sr.HpRecover")

---@class MaxHpChangedEvent: TriggerEvent
---@field public data MaxHpChangedData
local MaxHpChangedEvent = TriggerEvent:subclass("MaxHpChangedEvent")

--- 改变体力上限前
---@class sr.BeforeMaxHpChanged: MaxHpChangedEvent
sr.BeforeMaxHpChanged = MaxHpChangedEvent:subclass("sr.BeforeMaxHpChanged")
--- 改变体力上限后
---@class sr.MaxHpChanged: MaxHpChangedEvent
sr.MaxHpChanged = MaxHpChangedEvent:subclass("sr.MaxHpChanged")

---@class ShieldChangedEvent: TriggerEvent
---@field data ShieldChangedData
local ShieldChangedEvent = TriggerEvent:subclass("ShieldChangedEvent")

--- 改变护甲值前，受到伤害减少护甲不要用此时机
---@class sr.BeforeShieldChanged: ShieldChangedEvent
sr.BeforeShieldChanged = ShieldChangedEvent:subclass("sr.BeforeShieldChanged")
--- 改变护甲值后，受到伤害减少护甲不要用此时机
---@class sr.ShieldChanged: ShieldChangedEvent
sr.ShieldChanged = ShieldChangedEvent:subclass("sr.ShieldChanged")

-- 注释环节

---@alias HpChangedTrigFunc fun(self: TriggerSkill, event: HpChangedEvent,
---  target: GameUnit, player: GameUnit, data: HpChangedData): any
---@alias HpLostTrigFunc fun(self: TriggerSkill, event: HpLostEvent,
---  target: GameUnit, player: GameUnit, data: HpLostData): any
---@alias DamageTrigFunc fun(self: TriggerSkill, event: DamageEvent,
---  target: GameUnit, player: GameUnit, data: DamageData): any
---@alias RecoverTrigFunc fun(self: TriggerSkill, event: RecoverEvent,
---  target: GameUnit, player: GameUnit, data: RecoverData): any
---@alias MaxHpChangedTrigFunc fun(self: TriggerSkill, event: MaxHpChangedEvent,
---  target: GameUnit, player: GameUnit, data: MaxHpChangedData): any
---@alias ShieldChangedTrigFunc fun(self: TriggerSkill, event: ShieldChangedEvent,
---  target: GameUnit, player: GameUnit, data: ShieldChangedData): any

---@class DamageSkelAttr: TrigSkelAttribute

---@class SkillSkeleton
---@field public addEffect fun(self: SkillSkeleton, key: HpChangedEvent,
---  data: TrigSkelSpec<HpChangedTrigFunc>, attr: TrigSkelAttribute?): SkillSkeleton
---@field public addEffect fun(self: SkillSkeleton, key: HpLostEvent,
---  data: TrigSkelSpec<HpLostTrigFunc>, attr: DamageSkelAttr?): SkillSkeleton
---@field public addEffect fun(self: SkillSkeleton, key: DamageEvent,
---  data: TrigSkelSpec<DamageTrigFunc>, attr: DamageSkelAttr?): SkillSkeleton
---@field public addEffect fun(self: SkillSkeleton, key: RecoverEvent,
---  data: TrigSkelSpec<RecoverTrigFunc>, attr: DamageSkelAttr?): SkillSkeleton
---@field public addEffect fun(self: SkillSkeleton, key: MaxHpChangedEvent,
---  data: TrigSkelSpec<MaxHpChangedTrigFunc>, attr: TrigSkelAttribute?): SkillSkeleton
---@field public addEffect fun(self: SkillSkeleton, key: ShieldChangedEvent,
---  data: TrigSkelSpec<ShieldChangedTrigFunc>, attr: TrigSkelAttribute?): SkillSkeleton

function DamageEvent:breakCheck()
  return not self:isInstanceOf(sr.DamageFinished) and (self.data.damage < 1 or self.data.prevented)
end

--- 精灵体力归零后
---@class sr.PetFainted: HpChangedEvent
sr.PetFainted = HpChangedEvent:subclass("sr.PetFainted")
