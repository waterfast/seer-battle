-- SPDX-License-Identifier: LGPL-2.1-or-later

--- 能力变化原因。由调用方传入，manager 便捷方法提供相应默认值；不据此推断增减算法。
---@alias StageChangeReason 1|2|3|4|5
sr.ReasonStageChange = 1 -- 通用变化，可同时升降不同能力
sr.ReasonStrengthen = 2 -- 强化
sr.ReasonWeaken = 3 -- 弱化
sr.ReasonClearBoosts = 4 -- 消强
sr.ReasonCriticalBreak = 5 -- 暴击后对应防御等级归零

---@class StageChangeDataSpec
---@field from? Pet @变化来源
---@field who Pet @能力等级变化的目标
---@field changes table<string, integer> @有符号的变化量，正数增加、负数减少
---@field operation? "add"|"clearBoosts"|"reset" @实际操作，独立于 reason；由 manager 设置
---@field stats? string[] @消强所选能力，前置时机可修改；提交时根据最新等级解析
---@field reason StageChangeReason @变化类别，供技能与监听效果区分
---@field skill? Skill @来源技能
---@field prevented? boolean
---@field actualChanges? table<string, integer> @实际变化量，受 -6～+6 上下限限制
---@field oldStages? table<string, integer> @实际提交前的快照
---@field newStages? table<string, integer> @本次提交后的快照
---@class StageChangeData: StageChangeDataSpec, TriggerData
StageChangeData = TriggerData:subclass("StageChangeData")

function StageChangeData:preventStageChange()
    self.prevented = true
end

---@class StageChangeEvent: TriggerEvent
---@field data StageChangeData
local StageChangeEvent = TriggerEvent:subclass("StageChangeEvent")

--- 统一变化前；允许修改 changes 或防止变化，所有 manager 便捷方法也经过此时机。
---@class sr.BeforeStageChange: StageChangeEvent
sr.BeforeStageChange = StageChangeEvent:subclass("sr.BeforeStageChange")
--- 至少一项实际发生变化后。
---@class sr.StagesChanged: StageChangeEvent
sr.StagesChanged = StageChangeEvent:subclass("sr.StagesChanged")
--- 统一变化流程结束，包括被阻止或已达上限的情况。
---@class sr.StageChangeFinished: StageChangeEvent
sr.StageChangeFinished = StageChangeEvent:subclass("sr.StageChangeFinished")
