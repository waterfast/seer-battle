-- SPDX-FileCopyrightText: 2026 Notify Ctrl <notify-ctrl@qq.com>
-- SPDX-License-Identifier: LGPL-2.1-or-later
---
--[[
技能，精灵可以携带并使用的基本能力。
--]]
local class = kt.class

---@class Skill: Object
---@field id? integer @技能编号，来自显式固定的配置编号
---@field name string @技能名称
---@field power integer @技能威力
---@field priority integer @行动先制，与效果的触发优先级不同，999先制属于必先
---@field type "physical"|"special"|"status"|"passive" @技能类型，物理/特殊/属性/被动
---@field element ElementType[] @技能属性，空为属性技能
---@field accuracy integer @技能命中率，百分比
---@field hits integer @技能连击次数
---@field critChance number @技能暴击率，0~1；默认 0，当前尚未接入暴击结算
---@field pp integer @技能剩余PP
---@field maxPp integer @技能最大PP
---@field effects TriggerEffect[]
local Skill = class("Skill")

--- 构造函数，不可随意调用。
---@param id integer 技能id
---@param name string 技能名称
function Skill:initialize(id, name)
    self.id = id
    self.name = name or ""
    self.power = 0
    self.priority = 0
    self.type = "physical"
    self.element = {}
    self.accuracy = 100
    self.hits = 1
    self.critChance = 0
    self.pp = 0
    self.maxPp = 0
    self.effects = {}
end

return Skill
