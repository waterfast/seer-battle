-- SPDX-FileCopyrightText: 2026 Notify Ctrl <notify-ctrl@qq.com>
-- SPDX-License-Identifier: LGPL-2.1-or-later

local class = kt.class
local tablib = kt.tablib
local async = require "corelib.async"

---@class GameContextBase: Object
---@field players Player[]
---@field observers Player[]
---@field current Player
---@field capacity integer
---@field timeout integer
---@field G table<string, any> public state shared by both sides
local GameContextBase = class("GameContextBase")

function GameContextBase:initialize()
  self.players = {}
  self.observers = {}
  self.current = nil
  self.capacity = 0
  self.timeout = 0

  self._notificationHandlers = {}
  self._requestHandlers = {}
end

---@param cmd string
---@param cb function
function GameContextBase:setCallback(cmd, cb)
  assert(self._notificationHandlers[cmd] == nil)
  self._notificationHandlers[cmd] = cb
end

---@param cmd string
---@param cb function
function GameContextBase:setRequestHandler(cmd, cb)
  assert(self._requestHandlers[cmd] == nil)
  self._requestHandlers[cmd] = async.async(cb)
end

---@param id integer
---@return Player
function GameContextBase:getPlayer(id)
  ---@diagnostic disable-next-line
  return tablib.find(self.players, function(p) return p.id == id end)
end

---@param seat integer
---@return Player
function GameContextBase:getPlayerBySeat(seat)
  local try = self.players[seat]
  if try and try.seat == seat then
    return try
  end
  ---@diagnostic disable-next-line
  return tablib.find(self.players, function(p) return p.seat == seat end)
end

---@param ids integer[]
function GameContextBase:arrangeSeats(ids)
  local players = {}
  for i, id in ipairs(ids) do
    local player = self:getPlayer(id)
    player.seat = i
    players[i] = player
  end
  self.players = players
end

return GameContextBase
