-- SPDX-FileCopyrightText: 2026 Notify Ctrl <notify-ctrl@qq.com>
-- SPDX-License-Identifier: LGPL-2.1-or-later

local class = kt.class

---@class Player: Object
---@field ctx GameContextBase
---@field id integer
---@field username string
---@field seat integer
---@field G table<string, any> public state of this player
---@field secret table<string, any> private state, only synced to this player
local Player = class("Player")

function Player:initialize()
  self.id = 0
  self.seat = 0
end

---@return Player
function Player:getNext()
  local ctx = self.ctx
  local n = #ctx.players
  local seat = self.seat % n + 1
  return ctx:getPlayerBySeat(seat)
end

---@return Player
function Player:getPrev()
  local ctx = self.ctx
  local n = #ctx.players
  local seat = self.seat - 1
  if seat == 0 then seat = n end
  return ctx:getPlayerBySeat(seat)
end

return Player
