-- SPDX-FileCopyrightText: 2026 Notify Ctrl <notify-ctrl@qq.com>
-- SPDX-License-Identifier: LGPL-2.1-or-later

local Lobby = require "server.lobby"
local Room = require "server.room"

local class = kt.class

---@class RoomManager: Object
---@field rooms table<integer, Room>
---@field lobby Lobby
local RoomManager = class("RoomManager")

function RoomManager:initialize()
  self.rooms = {}
  self.lobby = Lobby:new()
end

---@param sender ServerUser
---@param name string
---@param capacity integer
---@return Room
function RoomManager:createRoom(sender, name, capacity)
  local room = Room:new()
  self.rooms[room.id] = room
  room.name = name
  room.capacity = capacity
  return room
end

---@param id integer
function RoomManager:removeRoom(id)
  self.rooms[id] = nil
end

---@param id integer
function RoomManager:findRoomOrLobby(id)
  if id == 0 then return self.lobby end
  return self.rooms[id]
end

---@param id integer
---@return Room?
function RoomManager:findRoom(id)
  assert(id ~= 0, "RoomManager:findRoom cannot find Lobby!")
  return self.rooms[id]
end

return RoomManager
