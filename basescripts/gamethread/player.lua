-- SPDX-FileCopyrightText: 2026 Notify Ctrl <notify-ctrl@qq.com>
-- SPDX-License-Identifier: LGPL-2.1-or-later

local Player = require "core.player"

---@class ServerPlayer: Player
---@field getNext fun(self): ServerPlayer
---@field getPrev fun(self): ServerPlayer
---@field user ServerUser
---@field ctx ServerGameContext
local ServerPlayer = Player:subclass("ServerPlayer")

---@param user ServerUser
function ServerPlayer:initialize(user)
  Player.initialize(self)
  self.G = {}
  self.secret = {}

  self.user = user
  self.id = user.id
  self.username = user.username
end

---@param command string
---@param data any
function ServerPlayer:notify(command, data)
  self.user:notify(command, data)
end

---@param command string
---@param data any
---@param timeout? integer
---@return any
function ServerPlayer:request(command, data, timeout)
  return self.user:request(command, data, timeout)
end

return ServerPlayer
