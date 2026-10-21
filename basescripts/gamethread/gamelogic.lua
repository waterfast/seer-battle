-- SPDX-FileCopyrightText: 2026 Notify Ctrl <notify-ctrl@qq.com>
-- SPDX-License-Identifier: LGPL-2.1-or-later

local async = require "corelib.async"
local class = kt.class
local GameEvent = require "gamethread.gameevent"
local TriggerEvent = require "core.trigger_event"

---@class GameLogic: Object
---@field ctx ServerGameContext
---@field root GameEvent
---@field gameEventStack GameEvent[]
---@field allGameEvents table<integer, any>
---@field eventRecorder table<any, GameEvent[]>
---@field currentEventId integer
local GameLogic = class("GameLogic")

function GameLogic:initialize(ctx)
  self.ctx = ctx

  self.gameEventStack = {}
  self.allGameEvents = {}
  self.eventRecorder = {}
  self.currentEventId = 0
  self.current_trigger_event_id = 0
  self.triggerEffects = {}
  self.triggerStack = {}
  self.taskScope = async.newscope()
end

---@param event GameEvent
function GameLogic:pushEvent(event)
  self.gameEventStack[#self.gameEventStack + 1] = event

  self.currentEventId = self.currentEventId + 1
  event.id = self.currentEventId
  self.allGameEvents[event.id] = event

  local key = event.class
  self.eventRecorder[key] = self.eventRecorder[key] or {}
  self.eventRecorder[key][#self.eventRecorder[key] + 1] = event
end

---@return GameEvent?
function GameLogic:popEvent()
  return table.remove(self.gameEventStack)
end

---@return GameEvent?
function GameLogic:getCurrentEvent()
  return self.gameEventStack[#self.gameEventStack]
end

---@return integer
function GameLogic:getCurrentEventDepth()
  return #self.gameEventStack
end

---@param eventType any
---@param includeSelf? boolean
---@return GameEvent?
function GameLogic:getMostRecentEvent(eventType, includeSelf)
  local current = self:getCurrentEvent()
  if not current then return nil end
  return current:findParent(eventType, includeSelf == nil and true or includeSelf)
end

---@return string
function GameLogic:dumpEventStack()
  local top = self:getCurrentEvent()

  local ret = "===== Start of event stack dump =====\n"
  while top do
    ret = ret .. tostring(top) .. "\n"
    top = top.parent
  end
  ret = ret .. "===== End of event stack dump =====\n"
  return ret
end

--- root event of game
local Game = GameEvent:subclass("GameEvent.Game")
function Game:main()
  self.ctx.logic:run()
end

function GameLogic:start()
  self.taskScope:spawn(function()
    local ctx = self.ctx
    kt.c.luaEvent("gameStart", { roomId = ctx.id, threadId = kt.gamethread.id })
    local _ <close> = setmetatable({}, { __close = function()
      kt.c.luaEvent("gameOver", { roomId = ctx.id })
    end })

    local root = Game:new(ctx)
    self.root = root
    ctx:broadcast("Room::StartGame", { gameType = ctx.bg.id })

    local ok, errmsg = pcall(root.exec, root)
    if not ctx.gameFinished then
      -- root event may be killed by error?
      if not ok then
        kt.log.critical(errmsg)
      else
        kt.log.info("Game is over now because root event finished.")
      end
      ctx:gameOver()
    end
  end)
end

--- 显式注册持续效果；返回条目，用于之后准确移除。
function GameLogic:addEffect(effect, owner)
  local entry = { effect = effect, owner = owner }
  self.triggerEffects[#self.triggerEffects + 1] = entry
  return entry
end

function GameLogic:removeEffect(entry)
  for i, value in ipairs(self.triggerEffects) do
    if value == entry then table.remove(self.triggerEffects, i); return end
  end
end

--- 结算失败时停止父流程，不能继续执行后续回合。
function GameLogic:executeEvent(eventType, data)
  local ok, result = eventType:new(self.ctx, data):exec()
  if not ok then error(result or "game event interrupted", 0) end
  return result
end

function GameLogic:collectEffects()
  return { table.unpack(self.triggerEffects) }
end

--- 逐个效果执行一次；快照保证嵌套触发和新增效果不改变当前遍历。
function GameLogic:dispatchTrigger(event)
  local candidates = {}
  for index, entry in ipairs(self:collectEffects()) do
    if rawequal(entry.effect.event, event.class) then
      candidates[#candidates + 1] = {
        effect = entry.effect, owner = entry.owner, index = index,
        priority = entry.effect.priority or 1,
      }
    end
  end
  table.sort(candidates, function(a, b)
    if a.priority == b.priority then return a.index < b.index end
    return a.priority > b.priority
  end)
  for _, entry in ipairs(candidates) do
    if self.ctx.gameFinished or event:breakCheck() then break end
    local effect, owner = entry.effect, entry.owner
    if effect:triggerable(event, event.target, owner, event.data)
        and effect:cost(event, event.target, owner, event.data) then
      if self.ctx.gameFinished then break end
      if effect:use(event, event.target, owner, event.data) == true then
        event.broken = true
        event.break_reason = effect.name
        break
      end
    end
  end
  return event.broken
end

---@param eventType TriggerEvent
---@return boolean, TriggerEvent
function GameLogic:trigger(eventType, target, data)
  assert(type(eventType) == "table" and eventType:isSubclassOf(TriggerEvent),
    "trigger requires a TriggerEvent class")
  local event = eventType:new(self.ctx, target, data)
  self.triggerStack[#self.triggerStack + 1] = event
  -- 即使效果报错也恢复时机栈；错误继续交给外层 GameEvent 处理。
  local ok, result = xpcall(event.exec, debug.traceback, event)
  table.remove(self.triggerStack)
  if not ok then error(result, 0) end
  return result, event
end

function GameLogic:run()
  kt.log.info("Hello, world!")
end

return GameLogic
