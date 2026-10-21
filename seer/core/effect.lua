-- SPDX-FileCopyrightText: 2026 Notify Ctrl <notify-ctrl@qq.com>
-- SPDX-License-Identifier: LGPL-2.1-or-later
---
--[[
局内实际效果：共享静态骨架，独立持有触发参数、执行参数和来源。
--]]
local class = kt.class
local EffectSkeleton = require "seer.core.effect_skeleton"

---@class Effect: Object
---@field id? integer @效果编号，来自显式固定的配置编号
---@field type? EffectType @效果类型
---@field name string @效果名称
---@field description? string @骨架的描述翻译 key
---@field skeleton EffectSkeleton @共享静态行为骨架
---@field source? Skill|Buff @承载此效果的运行时对象
---@field owner? GameUnit @效果拥有者；场地等全局效果可以没有拥有者
---@field can_triggervalue table @触发条件参数，例如 {hpBelow = 0.5}
---@field on_usevalue table @执行参数，例如 {amount = 50} 或 {stat, stages}
---@field target? GameUnit @效果目标；某些效果可能需要指定目标
local Effect = class("Effect")

---@alias EffectType 1
Effect.Trigger = 1 -- 当前只实现触发效果骨架及对应实例

---@param skeleton EffectSkeleton
---@param can_triggervalue? table
---@param on_usevalue? table
---@param source? Skill|Buff
function Effect:initialize(skeleton, can_triggervalue, on_usevalue, source)
    assert(skeleton and skeleton.isInstanceOf and skeleton:isInstanceOf(EffectSkeleton),
        "effect requires an EffectSkeleton")
    skeleton:validateParameters(can_triggervalue, on_usevalue)
    self.skeleton = skeleton
    self.id, self.name, self.type = skeleton.id, skeleton.name, skeleton.type
    self.description = skeleton.description
    self.can_triggervalue = EffectSkeleton.copyParameters(can_triggervalue)
    self.on_usevalue = EffectSkeleton.copyParameters(on_usevalue)
    self.source = source
end

return Effect
