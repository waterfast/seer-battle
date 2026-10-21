-- SPDX-FileCopyrightText: 2026 Notify Ctrl <notify-ctrl@qq.com>
-- SPDX-License-Identifier: LGPL-2.1-or-later

local ServerUser = require "server.user"

local class = kt.class

---@class UserManager: Object
---@field users table<integer, ServerUser>
local UserManager = class("UserManager")

---@param server Server
function UserManager:initialize(server)
  self.server = server
  self.users = setmetatable({}, { __mode = "v" })
end

---@param connId integer
---@return ServerUser
function UserManager:createNewUser(connId, username)
  local user = ServerUser:new(connId)
  user.id = connId
  user.username = username
  user.state = "online"

  self:addUser(user)
  return user
end

local nextRobotId = -2
function UserManager:createRobot()
  local robot = ServerUser:new(0)
  robot.state = "robot"
  robot.id = nextRobotId
  nextRobotId = nextRobotId - 1
  robot.username = ("COMP%d"):format(robot.id)
  robot.ready = true

  return robot
end

---@param user ServerUser
function UserManager:addUser(user)
  self.users[user.connId] = user
end

---@param connId integer
function UserManager:removeUser(connId)
  self.users[connId] = nil
end

---@param connId integer
---@return ServerUser?
function UserManager:findUser(connId)
  return self.users[connId]
end

return UserManager
