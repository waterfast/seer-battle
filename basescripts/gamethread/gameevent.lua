-- SPDX-FileCopyrightText: 2026 Notify Ctrl <notify-ctrl@qq.com>
-- SPDX-License-Identifier: LGPL-2.1-or-later

local async = require "corelib.async"
local class = kt.class

---@class GameEvent: Object
---@field ctx ServerGameContext
---@field data any
---@field id integer
---@field endId integer
---@field parent GameEvent?
---@field extraClear fun(self: GameEvent)[]
---@field extraExit fun(self: GameEvent)[]
---@field status "ready"|"running"|"exiting"|"dead"
---@field interrupted boolean
---@field cancelParent boolean
---@field execRet any
---@field mainFunc AsyncFunction?
local GameEvent = class("GameEvent")

function GameEvent:initialize(ctx, ...)
  self.ctx = ctx
  self.data = table.pack(...)
  if self.data.n == 1 then self.data = self.data[1] end

  self.id = -1
  self.endId = -1
  self.parent = nil
  self.extraClear = {}
  self.extraExit = {}
  self.status = "ready"
  self.interrupted = false
  self.cancelParent = false
  self.execRet = nil
end

function GameEvent:__tostring()
  return string.format("<%s #%d>", self.class.name, self.id)
end

---@return boolean?
function GameEvent:prepare() return false end

function GameEvent:main() end

function GameEvent:clear() end

function GameEvent:exit() end

---@param f fun(self: GameEvent)
function GameEvent:addCleaner(f)
  self.extraClear[#self.extraClear + 1] = f
end

---@param f fun(self: GameEvent)
function GameEvent:addExitFunc(f)
  self.extraExit[#self.extraExit + 1] = f
end

---@param f fun(self: GameEvent)
function GameEvent:prependExitFunc(f)
  table.insert(self.extraExit, 1, f)
end

local function classMatches(cls, eventType)
  return cls == eventType
    or (type(cls) == "table" and type(cls.isSubclassOf) == "function" and cls:isSubclassOf(eventType))
end

local function traceMsg(err)
  return tostring(err) .. "\n" .. debug.traceback(nil, 2)
end

---@param eventType any
---@param includeSelf boolean?
---@param depth integer?
---@return GameEvent?
function GameEvent:findParent(eventType, includeSelf, depth)
  if includeSelf and classMatches(self.class, eventType) then return self end
  if depth == 0 then return nil end
  local e = self.parent
  local l = 1
  while e do
    if classMatches(e.class, eventType) then return e end
    if depth and l >= depth then break end
    e = e.parent
    l = l + 1
  end
  return nil
end

---@return boolean?, any
function GameEvent:exec()
  if self.status ~= "ready" then return end
  local logic = self.ctx.logic
  self.parent = logic:getCurrentEvent()
  if self:prepare() then return end

  logic:pushEvent(self)
  self.status = "running"

  self.mainFunc = async.async(self.main)(self)
  kt.gamethread:bindCoroutineToContext(self.mainFunc.coro, self.ctx)

  local ok, ret = async.await(self.mainFunc)
  local err
  if ok then
    self.execRet = ret
  elseif self.mainFunc.cancelled or ret == async.CANCELLED then
    self.interrupted = true
  else
    err = ret
  end
  if err then
    warn(tostring(err) .. "\n" .. logic:dumpEventStack())
  end

  self.status = "exiting"
  local clearFunc = async.async(self.clearMain)(self)
  kt.gamethread:bindCoroutineToContext(clearFunc.coro, self.ctx)
  async.await(clearFunc)
  self.status = "dead"

  local okExit, exitErr = xpcall(self.exit, traceMsg, self)
  if not okExit then
    warn(exitErr .. "\n" .. logic:dumpEventStack())
  end
  for _, func in ipairs(self.extraExit) do
    if type(func) == "function" then
      local okExtra, extraErr = xpcall(func, traceMsg, self)
      if not okExtra then
        warn(extraErr .. "\n" .. logic:dumpEventStack())
      end
    end
  end

  if self.cancelParent then
    async.cancel(async.current())
  end

  return ok, ret
end

function GameEvent:shutdown()
  if self.status ~= "running" then return end
  local logic = self.ctx.logic
  local stack = logic.gameEventStack

  local from
  for i, e in ipairs(stack) do
    if e == self then
      from = i
      break
    end
  end
  if not from then return end

  for i = from, #stack do
    stack[i].interrupted = true
    if i > from then stack[i].cancelParent = true end
  end

  local leaf = stack[#stack]
  if leaf.mainFunc and not leaf.mainFunc.cancelled then
    async.cancel(leaf.mainFunc)
  end
end

function GameEvent:clearMain()
  local logic = self.ctx.logic

  local ok, clearErr = xpcall(self.clear, traceMsg, self)
  if not ok then
    warn(clearErr .. "\n" .. logic:dumpEventStack())
  end
  for _, func in ipairs(self.extraClear) do
    if type(func) == "function" then
      local ok2, extraErr = xpcall(func, traceMsg, self)
      if not ok2 then
        warn(extraErr .. "\n" .. logic:dumpEventStack())
      end
    end
  end

  local endId = logic.currentEventId + 1
  if self.id ~= endId - 1 then
    logic.allGameEvents[endId] = self.class
    logic.currentEventId = endId
    self.endId = endId
  else
    self.endId = self.id
  end

  logic:popEvent()
end

return GameEvent
