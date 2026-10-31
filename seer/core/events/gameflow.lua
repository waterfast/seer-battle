-- SPDX-License-Identifier: LGPL-2.1-or-later
-- 按新月杀的数据类、事件家族、具体时机三层格式定义。

--- 一轮包含双方选行动，以及按顺序进行的角色回合。
---@class RoundDataSpec
---@field number integer
---@field actions ActionData[]
---@field turn_table ServerPlayer[]
---@field from ServerPlayer?
---@field to ServerPlayer?
---@field skipped boolean?
---@class RoundData: RoundDataSpec, TriggerData
RoundData = TriggerData:subclass("RoundData")

---@class RoundEvent: TriggerEvent
---@field data RoundData
local RoundEvent = TriggerEvent:subclass("RoundEvent")

---@class sr.GameStart: RoundEvent
sr.GameStart = RoundEvent:subclass("sr.GameStart")
---@class sr.RoundStart: RoundEvent
sr.RoundStart = RoundEvent:subclass("sr.RoundStart")
---@class sr.RoundEnd: RoundEvent
sr.RoundEnd = RoundEvent:subclass("sr.RoundEnd")
---@class sr.EventTurnChanging: RoundEvent
sr.EventTurnChanging = RoundEvent:subclass("sr.EventTurnChanging")

--- 角色执行已选行动的回合，不在此重新选招。
---@class TurnDataSpec
---@field who ServerPlayer
---@field action ActionData
---@field reason string
---@field turn_end boolean?
---@class TurnData: TurnDataSpec, TriggerData
TurnData = TriggerData:subclass("TurnData")

function TurnData:initialize(who, action)
  TriggerData.initialize(self, {})
  self.who = who
  self.action = action
  self.reason = "game_rule"
  self.turn_end = false
end

---@class TurnEvent: TriggerEvent
---@field data TurnData
local TurnEvent = TriggerEvent:subclass("TurnEvent")
---@class sr.BeforeTurnStart: TurnEvent
sr.BeforeTurnStart = TurnEvent:subclass("sr.BeforeTurnStart")
---@class sr.TurnStart: TurnEvent
sr.TurnStart = TurnEvent:subclass("sr.TurnStart")
---@class sr.TurnEnd: TurnEvent
sr.TurnEnd = TurnEvent:subclass("sr.TurnEnd")

--- 统一行动意图；特殊行动仍各自拥有独立结算事件。
---@class ActionDataSpec
---@field who ServerPlayer
---@field from Pet
---@field type "skill"|"pass"|"switch"|"item"
---@field itemId integer?
---@field skill Skill?
---@field to Pet?
---@field prevented boolean?
---@class ActionData: ActionDataSpec, TriggerData
ActionData = TriggerData:subclass("ActionData")

---@class ActionChoiceEvent: TriggerEvent
---@field data ActionData
local ActionChoiceEvent = TriggerEvent:subclass("ActionChoiceEvent")
---@class sr.BeforeActionChoice: ActionChoiceEvent
sr.BeforeActionChoice = ActionChoiceEvent:subclass("sr.BeforeActionChoice")
---@class sr.AfterActionChoice: ActionChoiceEvent
sr.AfterActionChoice = ActionChoiceEvent:subclass("sr.AfterActionChoice")
