-- SPDX-FileCopyrightText: 2026 Notify Ctrl <notify-ctrl@qq.com>
-- SPDX-License-Identifier: LGPL-2.1-or-later

local async = require "corelib.async"

local class = kt.class
local json = kt.json

---@alias OnlineState "invalid"|"online"|"trust"|"run"|"robot"|"offline"

---@class User: Object
---@field connId integer My socket
---@field id integer
---@field username string
---@field roomId integer
---@field state OnlineState
---@field ready boolean
---@field taskScope TaskScope
local User = class("User")

---@param connId integer
function User:initialize(connId)
  self.connId = connId
  self.id = connId
  self.state = "invalid"
  self.ready = false
  self.taskScope = async.newscope()
end

---@param command string
---@param data any
---@param isJson? boolean if true, should not json.encode here
function User:notify(command, data, isJson)
  if self.state ~= "online" then return end
  kt.c.notifySocket(self.connId, command, isJson and data or json.encode(data))
end

---@param command string
---@param data any
---@param timeout? integer
---@param timestamp? integer
---@param isJson? boolean if true, should not json.encode here
---@return any
function User:request(command, data, timeout, timestamp, isJson)
  if self.state ~= "online" then return "" end

  local requestFn = async.wrap(kt.c.requestSocket)
  data = isJson and data or json.encode(data)
  local ok, ret = async.await(requestFn(self.connId, command, data, timeout or 10, timestamp or -1))

  if not ok then
    local err = tostring(ret)
    return "", err
  else
    -- 空包或损坏 JSON 和超时一样交给业务默认行动，不能使整场战斗异常退出。
    if type(ret) ~= "string" or ret == "" then return "" end
    local decoded, reply = pcall(json.decode, ret)
    if not decoded then return "", "invalid reply JSON" end
    return reply
  end
end

---@param ok boolean
---@param requestId integer
---@param data any
---@param isJson? boolean if true, should not json.encode here
function User:reply(ok, requestId, data, isJson)
  kt.c.replySocket(self.connId, requestId, ok, isJson and data or json.encode(data))
end

return User
