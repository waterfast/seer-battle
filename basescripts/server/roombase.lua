local RoomBase = require "core.room-base"

local json = kt.json
local tablib = kt.tablib
local utf8 = require("utf8")

local MAX_CHAT_LENGTH = 500

---@class ServerRoomBase: RoomBase
---@field users ServerUser[]
---@field observers ServerUser[]
local ServerRoomBase = RoomBase:subclass("ServerRoomBase")

function ServerRoomBase:initialize()
  RoomBase.initialize(self)
  self:setRequestHandler("Room::Chat", self.handleChat)
end

---@param users User[]
---@param command string
---@param data any
function ServerRoomBase:broadcastNotify(users, command, data)
  local jsonData = json.encode(data)
  for _, p in ipairs(users) do
    p:notify(command, jsonData, true)
  end
end

---@param command string
---@param data any
function ServerRoomBase:broadcast(command, data)
  local users = { table.unpack(self.users) }
  tablib.push(users, table.unpack(self.observers))
  self:broadcastNotify(users, command, data)
end

---@param user ServerUser
---@param data { text: string }
function ServerRoomBase:handleChat(user, data)
  local text = data and data.text

  if type(text) ~= "string" or text == "" then
    return nil, "chat.empty"
  end

  local char_count = utf8.len(text)
  if not char_count then
    return nil, "chat.invalid_utf8"
  end

  if char_count > MAX_CHAT_LENGTH then
    local offset = utf8.offset(text, MAX_CHAT_LENGTH + 1)

    if offset then
      text = text:sub(1, offset - 1)
    end
  end

  self:broadcast("Room::ChatMessage", {
    id = user.id,
    username = user.username,
    text = text,
    timestamp = os.time()
  })
end

return ServerRoomBase
