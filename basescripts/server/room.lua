local RoomBase = require "server.roombase"
local tablib = kt.tablib

---@class Room: ServerRoomBase
---@field owner ServerUser
---@field gameThreadId integer?
local Room = RoomBase:subclass("Room")

local nextRoomId = 1

function Room:initialize()
  RoomBase.initialize(self)
  self.id = nextRoomId
  nextRoomId = nextRoomId + 1
  self.owner = nil
  self.name = ""
  self.capacity = 0

  self:setRequestHandler("Room::AddRobot", self.handleAddRobot)
  self:setRequestHandler("Room::Quit", self.handleQuitRoom)
  self:setRequestHandler("Room::StartGame", self.handleStartGame)
  self:setRequestHandler("Room::Ready", self.handleReady)

  self:setRequestHandler("PushRequest", function(user, data)
    self:pushRequest(user, data.command, data.data)
  end)
end

function Room:isFull()
  return #self.users >= self.capacity
end

---@return boolean
function Room:allReady()
  for _, p in ipairs(self.users) do
    if p ~= self.owner and not p.ready then
      return false
    end
  end
  return true
end

function Room:isStarted()
  return self.gameThreadId ~= nil
end

---@param user ServerUser
function Room:setOwner(user)
  self.owner = user
  self:broadcast("Room::Owner", { id = user.id })
end

---@param user ServerUser
function Room:addUser(user)
  if self:isFull() or self:isStarted() then
    user:notify("App::ShowToast", "room.full")
    return
  end

  if user.state ~= "robot" then
    user.ready = false
  end
  self:broadcast("Room::AddUser", {
    id = user.id,
    username = user.username,
    ready = user.ready,
  })

  RoomBase.addUser(self, user)
  user:notify("Room::Enter", {
    id = self.id,
    name = self.name,
    capacity = self.capacity,
  })

  for _, p in ipairs(self.users) do
    if p ~= user then
      user:notify("Room::AddUser", {
        id = p.id,
        username = p.username,
        ready = p.ready,
      })
    end
  end

  -- TODO: observer


  if self.owner == nil then
    self:setOwner(user)
  else
    user:notify("Room::Owner", { id = self.owner.id })
  end
end

---@param user ServerUser
function Room:handleAddRobot(user)
  if self.owner ~= user then
    return nil, "room.not_owner_add_robot"
  end

  if self:isFull() then
    return nil, "room.full"
  end

  local robot = kt.server.userManager:createRobot()
  self:addUser(robot)
end

---@param user ServerUser
function Room:handleReady(user)
  user.ready = not user.ready
  self:broadcast("Room::ReadyChanged", {
    id = user.id,
    ready = user.ready,
  })
end

---@param user ServerUser
function Room:handleStartGame(user)
  if user ~= self.owner then
    return nil, "room.not_owner_start"
  end

  if self:isStarted() then
    return nil, "room.already_started"
  end

  if not self:isFull() then
    return nil, "room.not_full_start"
  end

  if not self:allReady() then
    return nil, "room.not_all_ready"
  end

  for _, p in ipairs(self.users) do
    p.ready = (p == self.owner) or (p.state == "robot")
  end

  local users = tablib.map(self.users, function(u)
    return { connId = u.connId, id = u.id, username = u.username, state = u.state }
  end)

  kt.c.startGame(self.id, {
    id = self.id,
    name = self.name,
    capacity = self.capacity,
    users = users,
    gameType = self.gameType or "seer",
    -- 仅由服务端的数据加载器设置；选招请求不能提交账号存档或战斗属性。
    battleData = self.battleData,
    seed = self.seed,
  })
end

---@param user ServerUser
function Room:handleQuitRoom(user)
  self:removeUser(user)

  local lobby = kt.server.roomManager.lobby
  lobby:addUser(user)

  -- TODO: isOutdated
end

---@param user ServerUser
---@param data { command: string, data: any }
function Room:pushRequest(user, command, data)
  if not self.gameThreadId then return end
  kt.c.pushRequest(self.gameThreadId, self.id, user.id, command, data)
end

---@param user ServerUser
---@param state OnlineState
function Room:setUserState(user, state)
  user.state = state
  self:pushRequest(user, "setUserState", { state = state, connId = user.connId })
end

function Room:replaceRunnedUser(user)
  local um = kt.server.userManager
  local runned = um:createNewUser(0, user.username)
  runned.state = "run"

  for i, u in ipairs(self.users) do
    if u == user then
      self.users[i] = runned
      user.state = "online"
      return
    end
  end
end

---@param user ServerUser
function Room:removeUser(user)
  if not self:isStarted() then
    RoomBase.removeUser(self, user)
    self:broadcast("Room::RemoveUser", { id = user.id })
  else
    self:setUserState(user, "run")
    self:replaceRunnedUser(user)
  end

  if self:isAbandoned() then
    self:destroy()
  elseif user == self.owner then
    if #self.users > 0 then
      self:setOwner(self.users[1])
    else
      self.owner = nil
    end
  end
end

function Room:isAbandoned()
  return not tablib.find(self.users, function(p)
    return p.state == "online"
  end)
end

function Room:destroy()
  local rm = kt.server.roomManager
  local um = kt.server.userManager

  rm:removeRoom(self.id)
  for _, p in ipairs(self.users) do
    if p.state == "online" then
      self:removeUser(p)
      rm.lobby:addUser(p)
    else
      um:removeUser(p.connId)
    end
  end
end

function Room:gameOver()
  kt.c.removeRoom(self.gameThreadId, self.id)
  self.gameThreadId = nil

  local users = self.users
  local um = kt.server.userManager
  for i = #users, 1, -1 do
    local user = users[i]
    if user.state ~= "online" then
      self:removeUser(user)
      um:removeUser(user.id)
    end
  end
end

return Room
