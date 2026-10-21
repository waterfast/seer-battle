local async = require "corelib.async"
local class = kt.class
local json = kt.json

local UserManager = require "server.user-manager"
local RoomManager = require "server.room-manager"

---@class Server: Object
---@field userManager UserManager
---@field roomManager RoomManager
local Server = class("Server")

function Server:initialize()
  self._notificationHandlers = {}
  self._requestHandlers = {}
  self.taskScope = async.newscope()

  self.userManager = UserManager:new(self)
  self.roomManager = RoomManager:new()
end

---@param cmd string
---@param cb fun(self: Server, user: User, data: any)
function Server:setCallback(cmd, cb)
  assert(self._notificationHandlers[cmd] == nil)
  self._notificationHandlers[cmd] = cb
end

---@param cmd string
---@param cb fun(self: Server, user: User, data: any): any, string?
function Server:setRequestHandler(cmd, cb)
  assert(self._requestHandlers[cmd] == nil)
  self._requestHandlers[cmd] = async.async(cb)
end

----------------------------------------------------------
--- Below methods are called from C++ code.
----------------------------------------------------------

local handshake = async.async(function(connId)
  local requestFn = async.wrap(kt.c.requestSocket)

  local ok, ret = async.await(requestFn(connId, "Auth::RequestNonce", json.encode({}), 10, -1))
  if not ok then return "request nonce failed" end
  local nonce = json.decode(ret)

  local challenge = kt.c.makeAuthChallenge(connId, nonce)
  ok, ret = async.await(requestFn(connId, "Auth::ExchangeKey", json.encode(challenge), 10, -1))
  if not ok then return "key exchange failed" end
  local clientPub = json.decode(ret)

  kt.c.notifySocket(connId, "Auth::StartEncryption", "{}")
  ok = kt.c.acceptClientKey(connId, clientPub)
  if not ok then return "start encryption failed" end

  return nil
end)

local function isValidUsernameChar(b)
  return (b >= 128)
    or (b == 0x5F)                -- _
    or (b >= 0x30 and b <= 0x39)  -- 0-9
    or (b >= 0x41 and b <= 0x5A)  -- A-Z
    or (b >= 0x61 and b <= 0x7A)  -- a-z
end

local function validateUsername(username)
  if type(username) ~= "string" then
    return false
  end
  local len = utf8.len(username)
  if not len or len < 3 or len > 32 then
    return false
  end
  for i = 1, #username do
    if not isValidUsernameChar(username:byte(i)) then
      return false
    end
  end
  return true
end

local function validatePassword(password)
  if type(password) ~= "string" then
    return false
  end
  local len = utf8.len(password)
  return len ~= nil and len >= 4 and len <= 32
end

---@param connId integer
function Server:processNewConnection(connId)
  self.taskScope:spawn(function ()
    local requestFn = async.wrap(kt.c.requestSocket)
    local success = false
    local userErrCode = "auth.internal_error"
    local internal_errmsg
    local defer <close> = setmetatable({}, { __close = function()
      if success then return end
      kt.log.info(internal_errmsg or userErrCode)
      kt.c.notifySocket(connId, "App::ErrorDialog", json.encode(userErrCode))
      kt.c.disconnect(connId)
    end})

    local ok, ret = async.await(handshake(connId))
    if not ok then return end
    if ret then
      internal_errmsg = ret
      userErrCode = "auth.handshake_failed"
      return
    end

    ok, ret = async.await(requestFn(connId, "Auth::RequestUsername", json.encode({}), 10, -1))
    if not ok then return end
    local data = json.decode(ret)
    local username = data and data.username
    local password = data and data.password
    if not validateUsername(username) or not validatePassword(password) then
      userErrCode = "auth.invalid_credentials"
      return
    end

    local row
    ok, row = kt.c.findUserByUsername(username)
    if not ok then
      -- err branch: database lookup failed
      internal_errmsg = ("lookup username failed: %s"):format(tostring(row))
      return
    end
    if row == nil then
      -- TODO: request the user to re-enter the password before registering
      local errReg
      ok, errReg = kt.c.registerUser(username, password)
      if not ok then
        internal_errmsg = ("register user failed: %s"):format(tostring(errReg))
        return
      end
    else
      local salt = row.salt or ""
      local hash = kt.c.sha256(password .. salt)
      if hash ~= row.password then
        userErrCode = "auth.wrong_password"
        return
      end
    end

    -- TODO: banned check, etc..

    local user = self.userManager:createNewUser(connId, username)
    user:notify("User::Setup", { id = user.id, username = user.username })
    self.roomManager.lobby:addUser(user)

    success = true
  end, connId)
end

---@param connId integer
function Server:processDisconnected(connId)
  self.taskScope:cancel(connId)

  local user = self.userManager:findUser(connId)
  if not user then
    kt.log.info(string.format("ConnId %d disconnected", connId))
    return
  end

  kt.log.info(string.format("User %s (connId=%d) disconnected", user.username, connId))

  user.taskScope:destroy()

  local room = self.roomManager:findRoomOrLobby(user.roomId)
  if room then room:removeUser(user) end
  self.userManager:removeUser(connId)
end

---@param connId integer
---@param command string
---@param data any
function Server:processNotification(connId, command, data)
  local user = self.userManager:findUser(connId)
  if not user then return end

  local f = self._notificationHandlers[command]
  if f then
    return f(self, user, data)
  end

  local room = self.roomManager:findRoomOrLobby(user.roomId)
  if not room then return end

  f = room._notificationHandlers[command]
  if f then
    return f(room, user, data)
  end
end

local function requestDispatcher(server, user, requestId, command, data, timeout)
  local fn = server._requestHandlers[command]
  local arg1 = server
  if not fn then
    local room = server.roomManager:findRoomOrLobby(user.roomId)
    if room then
      fn = room._requestHandlers[command]
      arg1 = room
    end
  end

  if not fn then
    -- must reply an error message here. the peer is waiting for reply.
    user:reply(false, requestId, ("no match requestHandler for request '%s'"):format(command))
    return
  end

  local handler = fn(arg1, user, data, timeout) --[[@as AsyncFunction]]
  local ok, reply = async.await(handler)

  if not ok then
    if handler.errmsg and handler.errmsg ~= async.CANCELLED then
      warn(debug.traceback(handler.coro, handler.errmsg))
    end
    user:reply(false, requestId, reply)
  else
    user:reply(true, requestId, reply)
  end
end

---@param connId integer
---@param requestId integer
---@param command string
---@param data any
function Server:processRequest(connId, requestId, command, data, timeout)
  local user = self.userManager:findUser(connId)
  if not user then return end
  user.taskScope:spawn(function()
    requestDispatcher(self, user, requestId, command, data, timeout)
  end, requestId)
end

---@type table<string, fun(self: Server, data: any)>
local eventHandlers = {}
eventHandlers["gameStart"] = function(self, data)
  local room = self.roomManager:findRoom(data.roomId)
  if room then room.gameThreadId = data.threadId end
end

eventHandlers["gameOver"] = function(self, data)
  local room = self.roomManager:findRoom(data.roomId)
  if room then room:gameOver() end
end

function Server:dispatchLuaEvent(type, data)
  local f = eventHandlers[type]
  if f then
    f(self, data)
  end
end

return Server
