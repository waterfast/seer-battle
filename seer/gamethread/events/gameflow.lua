-- SPDX-License-Identifier: LGPL-2.1-or-later
-- 参考新月杀 server/events/gameflow.lua 的 Round/Turn 组织，按赛尔号行动流程实现。
local GameEvent = require "gamethread.gameevent"
require "seer.core.events"

---@class Seer.GameEvent.Turn: GameEvent
---@field data TurnData
local Turn = GameEvent:subclass("Seer.GameEvent.Turn") -- 玩家行动流程

function Turn:main()
  local ctx = self.ctx
  local logic = ctx.logic
  local data = self.data
  self.previous = ctx.current
  ctx.current = data.who

  if logic:trigger(sr.BeforeTurnStart, data.who.pet, data) then data.turn_end = true end
  if data.turn_end or ctx.gameFinished then return end
  if logic:trigger(sr.TurnStart, data.who.pet, data) then data.turn_end = true end
  if data.turn_end or ctx.gameFinished then return end
  logic:playTurn(data)
end

function Turn:clear()
  if not self.ctx.gameFinished then
    self.ctx.logic:trigger(sr.TurnEnd, self.data.who.pet, self.data)
  end
  self.ctx.current = self.previous
end

---@class Seer.GameEvent.Round: GameEvent
---@field data RoundData
local Round = GameEvent:subclass("Seer.GameEvent.Round")

function Round:main()
  local ctx = self.ctx
  local logic = ctx.logic
  local data = self.data
  ctx:broadcast("Seer.RoundStart", { number = data.number })
  if logic:trigger(sr.RoundStart, nil, data) then return end
  if ctx.gameFinished then return end

  -- 先收齐双方的行动，再排序；这里之前不会执行任何一方的技能。
  logic:replaceFaintedPets()
  data.actions = logic:chooseActions()
  if ctx.gameFinished then return end
  logic:sortActions(data.actions)

  data.turn_table = {}
  for _, action in ipairs(data.actions) do
    data.turn_table[#data.turn_table + 1] = action.who
    data.to = action.who
    data.skipped = false
    if logic:trigger(sr.EventTurnChanging, action.from, data) then data.skipped = true end
    if ctx.gameFinished then return end
    if not data.skipped and logic:canAct(action.who) then
      logic:executeEvent(Turn, TurnData:new(action.who, action))
    end
    data.from = action.who
    if logic:checkGameOver() then return end
  end
  logic:finishRound(data)
  logic:checkGameOver()
end

return { Round = Round, Turn = Turn }
