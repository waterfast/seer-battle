local class = kt.class
local tablib = kt.tablib
local async = require "corelib.async"

---@class RoomBase: Object
---@field id integer
---@field name string
---@field capacity integer
---@field users User[]
---@field observers User[]
local RoomBase = class("RoomBase")

function RoomBase:initialize()
  self.id = 0
  self.users = {}
  self.observers = {}

  self._notificationHandlers = {}
  self._requestHandlers = {}

  self:setCallback("Socket::CancelRequest", self.handleCancelRequest)
end

---@param cmd string
function RoomBase:setCallback(cmd, cb)
  assert(self._notificationHandlers[cmd] == nil)
  self._notificationHandlers[cmd] = cb
end

---@param cmd string
function RoomBase:setRequestHandler(cmd, cb)
  assert(self._requestHandlers[cmd] == nil)
  self._requestHandlers[cmd] = async.async(cb)
end

-- Peer asked to cancel the running request handler `requestId` of `user`.
---@param user User
---@param data { requestId: integer }
function RoomBase:handleCancelRequest(user, data)
  local requestId = data and data.requestId
  if not requestId then return end

  user.taskScope:cancel(requestId)
end

---@param user User
function RoomBase:addUser(user)
  self.users[#self.users + 1] = user
  user.roomId = self.id
end

---@param user User
---@return boolean removed
function RoomBase:removeUser(user)
  return tablib.removeOne(self.users, user)
  -- note that user.roomId is not set. Please add they to somewhere.
end

---@param id integer
---@return User
function RoomBase:findUserById(id)
  ---@diagnostic disable-next-line
  return tablib.find(self.users, function(p) return p.id == id end)
end

return RoomBase
