-- SPDX-FileCopyrightText: 2026 Notify Ctrl <notify-ctrl@qq.com>
-- SPDX-License-Identifier: LGPL-2.1-or-later

local class = kt.class
local ServerGameContext = require "gamethread.game-context"

---@class GameThread: Object
---@field id integer
---@field contexts table<integer, ServerGameContext>
---@field contextRegistry table<thread, ServerGameContext>
local GameThread = class("GameThread")

function GameThread:initialize()
  self.contexts = {}
  self.contextRegistry = setmetatable({}, { __mode = "k" })
end

-- called from C++...
function GameThread:setId(id)
  self.id = id
end

---@param boardgame Boardgame
---@param data table
---@return ServerGameContext
function GameThread:registerContext(boardgame, data)
  local contextClass = boardgame.contextClass or ServerGameContext
  local context = contextClass:new(boardgame, data)
  self.contexts[data.id] = context
  return context
end

---@param roomId integer
function GameThread:removeContext(roomId)
  self.contexts[roomId] = nil
end

---@param co thread
---@param context ServerGameContext
function GameThread:bindCoroutineToContext(co, context)
  self.contextRegistry[co] = context
end

---@return GameContextBase
function GameThread:currentGameContext()
  return self.contextRegistry[coroutine.running()]
end

---@param roomId integer
---@param userId integer
---@param command string
---@param data any
function GameThread:handleRequest(roomId, userId, command, data)
  if command == "newroom" then
    local gameType = data.gameType or "seer"
    local boardgame = kt.engine:getGame(gameType)
    if not boardgame then
      error(("unknown boardgame '%s', cannot create new room"):format(gameType))
    end
    self:registerContext(boardgame, data):run()
    return
  elseif command == "setUserState" then
    local ctx = self.contexts[roomId]
    if not ctx then return end
    local p = ctx:getPlayer(userId)
    p.user.state = data.state
    p.user.connId = data.connId
    ctx:checkNoHuman()
  end

  local ctx = self.contexts[roomId]
  if not ctx then return end
  local f = ctx.callbacks[command]
  if f then f(ctx, ctx:getPlayer(userId), data) end
end

return GameThread
