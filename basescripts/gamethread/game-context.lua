-- SPDX-FileCopyrightText: 2026 Notify Ctrl <notify-ctrl@qq.com>
-- SPDX-License-Identifier: LGPL-2.1-or-later

local async = require "corelib.async"
local GameContextBase = require "core.game-context"
local ServerUser = require "server.user"
local ServerPlayer = require "gamethread.player"
local tablib = kt.tablib

---@class ServerGameContext: GameContextBase
---@field players ServerPlayer[]
---@field observers ServerPlayer[]
---@field current ServerPlayer
---@field getPlayer fun(self, id): ServerPlayer
---@field getPlayerBySeat fun(self, seat): ServerPlayer
---@field id integer
---@field rawUsers table[]
---@field logic GameLogic
---@field gameFinished boolean
---@field bg Boardgame
---@field secret table<string, any>
---@field callbacks table<string, fun(ctx: ServerGameContext, player: ServerPlayer, data: any)>
local ServerGameContext = GameContextBase:subclass("ServerGameContext")

---@param boardgame Boardgame
---@param data table
function ServerGameContext:initialize(boardgame, data)
  GameContextBase.initialize(self)
  self.G = {}
  -- 种子由可信宿主提供；未提供时只在建房时生成一次，局内随机统一走此发生器。
  local seed = data.seed or math.random(math.maxinteger)
  self.secret = { seed = seed, rng = kt.rand(seed) }

  self.id = data.id
  self.rawUsers = data.users or {}
  self.gameFinished = false
  self.callbacks = {}

  assert(boardgame.logicClass, ("boardgame '%s' must define logicClass"):format(boardgame.id))
  self.bg = boardgame
end

function ServerGameContext:run()
  self.players = tablib.map(self.rawUsers, function(u)
    local user = ServerUser:new(u.connId)
    user.id = u.id
    user.username = u.username
    user.state = u.state or "online"
    local player = ServerPlayer:new(user)
    player.ctx = self
    return player
  end)
  self.logic = self.bg.logicClass:new(self)
  self.logic:start()
end

function ServerGameContext:checkNoHuman(chkOnly)
  if #self.players == 0 then return end
  for _, p in ipairs(self.players) do
    local state = p.user.state
    if state == "online" or state == "trust" then
      return
    end
  end

  if not chkOnly then
    self:gameOver()
  end
  return true
end

---@class GameOverResult
---@field winners integer[]? winning player ids, empty or nil means a draw

---@param result? GameOverResult
function ServerGameContext:gameOver(result)
  if self.gameFinished then return end
  self.gameFinished = true

  self:broadcast("Room::GameOver", result or {})
  kt.log.info(("[GameOver] roomId=%d"):format(self.id))

  kt.gamethread:removeContext(self.id)
  if self.logic and self.logic.root then
    self.logic.root:shutdown()
  end
end

---@param command string
---@param data any
---@param players? ServerPlayer[]
function ServerGameContext:broadcast(command, data, players)
  players = players or self.players
  for _, player in ipairs(players) do
    player:notify(command, data)
  end
end

---@param name string
function ServerGameContext:act(name, ...)
  local move = assert(self.bg.publicActions[name], ("unknown public action '%s'"):format(name))
  move(self, ...)
  self:broadcast(self.bg.id .. "." .. name, { ... })
end

---@param command string
---@param fn fun(ctx: ServerGameContext, player: ServerPlayer, data: any)
function ServerGameContext:addCallback(command, fn)
  self.callbacks[command] = fn
end

function ServerGameContext:setG(k, v)
  self.G[k] = v
  self:broadcast("Game::setG", { k = k, v = v })
end

---@param player ServerPlayer
function ServerGameContext:setPlayerG(player, k, v)
  player.G[k] = v
  self:broadcast("Game::setPlayerG", { id = player.id, k = k, v = v })
end

---@param players? ServerPlayer[]
function ServerGameContext:arrangeSeats(players)
  players = players or self.players
  local ids = tablib.map(players, function(player) return player.id end)
  GameContextBase.arrangeSeats(self, ids)
  self:broadcast("Game::ArrangeSeats", { ids = ids })
end

---@param ms integer
function ServerGameContext:delay(ms)
  return async.await(async.wrap(kt.c.delay)(ms))
end

---@param m? integer
---@param n? integer
---@return any
function ServerGameContext:random(m, n)
  return self.secret.rng:random(m, n)
end

---@param x? integer
---@param y? integer
function ServerGameContext:randomseed(x, y)
  return self.secret.rng:randomseed(x, y)
end

---@generic T
---@param t T[]
function ServerGameContext:shuffleTable(t)
  if #t == 2 then
    if self:random() < 0.5 then
      t[1], t[2] = t[2], t[1]
    end
  else
    for i = #t, 2, -1 do
      local j = self:random(i)
      t[i], t[j] = t[j], t[i]
    end
  end
end

---@generic T
---@param t T[]
---@param n? integer
---@return T|T[]
function ServerGameContext:tableRandomPick(t, n)
  local n0 = n
  n = n or 1
  if #t == 0 then return n0 ~= nil and {} or nil end
  local tmp = { table.unpack(t) }
  local ret = {}
  while n > 0 and #tmp > 0 do
    local i = self:random(1, #tmp)
    ret[#ret + 1] = table.remove(tmp, i)
    n = n - 1
  end
  return n0 == nil and ret[1] or ret
end

return ServerGameContext
