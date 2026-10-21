-- SPDX-FileCopyrightText: 2026 Notify Ctrl <notify-ctrl@qq.com>
-- SPDX-License-Identifier: LGPL-2.1-or-later

-- Engine: manage boardgames and other global, static stuff.

local class = kt.class
local Plugin = require "core.plugin"

---@class Engine: Object
---@field games table<string, Boardgame>
---@field plugins table<string, Plugin> Path->Plugin
local Engine = class("Engine")

function Engine:initialize()
  self.games = {}
  self.plugins = {}
end

---@param game Boardgame
function Engine:registerGame(game)
  if self.games[game.id] then
    kt.log.warn(("boardgame '%s' already registered, overwriting"):format(game.id))
  end
  game.pluginRoot = kt.c.getPluginRoot()
  self.games[game.id] = game
end

---@param id string
---@return Boardgame?
function Engine:getGame(id)
  if type(id) ~= "string" then return nil end
  return self.games[id]
end

---@param path string
function Engine:registerNewPlugin(path)
  self.plugins[path] = Plugin:new(path)
end

---@param path string
---@return Plugin?
function Engine:getPlugin(path)
  if type(path) ~= "string" then return nil end
  return self.plugins[path]
end

--- Returns the private global environment of the plugin at `path`, or nil.
---@param path string
---@return table?
function Engine:getPluginEnv(path)
  if type(path) ~= "string" then return nil end
  local plugin = self.plugins[path]
  return plugin and plugin.env or nil
end


--- Returns the game context currently in play, or nil.
---@return GameContextBase
function Engine:currentGameContext()
  if kt.client then
    return kt.client.gameContext
  end
  if kt.gamethread then
    return kt.gamethread:currentGameContext()
  ---@diagnostic disable-next-line
  end
end

return Engine
