-- SPDX-FileCopyrightText: 2026 Notify Ctrl <notify-ctrl@qq.com>
-- SPDX-License-Identifier: LGPL-2.1-or-later

local class = kt.class
local async = require "corelib.async"

---@class InteractiveRequest: Object
---@field players ServerPlayer[]
---@field n integer
---@field command string
---@field data table<integer, any>
---@field defaultReply table<integer, any>
---@field timeout integer?
---@field result table<integer, any>
---@field _asked boolean?
local InteractiveRequest = class("InteractiveRequest")

---@param players Player|Player[]
---@param command string
---@param n? integer
function InteractiveRequest:initialize(players, command, n)
  if (not players[1]) and players.class then players = { players } end
  assert(#players > 0)
  self.players = players
  self.n = n or #players
  self.command = command
  self.data = {}
  self.defaultReply = {}
  self.timeout = nil
  self.result = {}
  self._asked = false
end

---@param player Player
---@param data any
function InteractiveRequest:setData(player, data)
  self.data[player.id] = data
end

---@param player Player
---@param reply any
function InteractiveRequest:setDefaultReply(player, reply)
  self.defaultReply[player.id] = reply
end

function InteractiveRequest:ask()
  if self._asked then return end
  local tasks = {}
  for _, player in ipairs(self.players) do
    local task = async.async(function()
      return player:request(self.command, self.data[player.id], self.timeout)
    end)()
    if player.ctx then
      kt.gamethread:bindCoroutineToContext(task.coro, player.ctx)
    end
    tasks[#tasks + 1] = task
  end
  local group = async.awaitall(table.unpack(tasks))
  if group.errmsg ~= "" then error(group.errmsg) end
  -- 只在全部收齐后按座位消费默认值，避免回复先后影响战斗随机数序列。
  for index, player in ipairs(self.players) do
    local reply = group:getResult(index)
    if reply == "" or reply == nil then reply = self.defaultReply[player.id] end
    self.result[player.id] = reply
  end
  self._asked = true
end

---@param player Player
---@return any
function InteractiveRequest:getResult(player)
  if not self._asked then self:ask() end
  return self.result[player.id]
end

return InteractiveRequest
