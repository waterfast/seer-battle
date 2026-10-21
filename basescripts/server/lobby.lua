local RoomBase = require "server.roombase"
local tablib = kt.tablib

---@class Lobby: ServerRoomBase
local Lobby = RoomBase:subclass("Lobby")

function Lobby:initialize()
  RoomBase.initialize(self)

  self.id = 0

  self:setRequestHandler("Lobby::FetchRooms", self.handleFetchRooms)
  self:setRequestHandler("Room::Create", self.handleCreateRoom)
  self:setRequestHandler("Room::Join", self.handleJoinRoom)
end

---@param user ServerUser
function Lobby:addUser(user)
  RoomBase.addUser(self, user)
  user:notify("Lobby::Enter", nil)
  self:updateOnlineInfo()
end

---@param user ServerUser
function Lobby:removeUser(user)
  RoomBase.removeUser(self, user)
  self:updateOnlineInfo()
end

function Lobby:updateOnlineInfo()
  local onlineUsers = 0
  for _, u in pairs(kt.server.userManager.users) do
    if u.state == "online" then
      onlineUsers = onlineUsers + 1
    end
  end
  self:broadcast("Lobby::UpdateOnlineInfo", {
    onlineUsers = onlineUsers,
    lobbyUsers = tablib.map(self.users, function(u)
      return { name = u.username }
    end),
  })
end

function Lobby:handleFetchRooms()
  local rm = kt.server.roomManager
  local rooms = {}
  for _, room in pairs(rm.rooms) do
    rooms[#rooms + 1] = {
      id = room.id,
      name = room.name,
      capacity = room.capacity,
      userCount = #room.users,
      ownerId = room.owner and room.owner.id or -1,
    }
  end
  return rooms
end

function Lobby:handleCreateRoom(user, data)
  local rm = kt.server.roomManager
  local room = rm:createRoom(user, data.name, data.capacity)
  if not room then
    return nil, "lobby.create_room_failed"
  end

  return room.id
end

function Lobby:handleJoinRoom(user, data)
  local rm = kt.server.roomManager
  local room = rm:findRoom(data.id)
  if not room then
    return nil, "lobby.no_such_room"
  end

  -- TODO: password check
  -- TODO: isOutdated check

  room:addUser(user)
  self:removeUser(user)
end

return Lobby
