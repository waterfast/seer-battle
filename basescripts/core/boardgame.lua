-- SPDX-FileCopyrightText: 2026 Notify Ctrl <notify-ctrl@qq.com>
-- SPDX-License-Identifier: LGPL-2.1-or-later

local class = kt.class

---@class BoardgameSpec
---@field id string
---@field name string?

---@class Boardgame: Object
---@field id string
---@field name string
---@field pluginRoot string
---@field logicClass GameLogic
---@field page { url?: string, uri?: string, name?: string }
---@field viewModelClass GameViewModel
---@field publicActions table<string, fun(ctx: GameContextBase, ...): any>
local Boardgame = class("Boardgame")

function Boardgame:initialize(spec)
  assert(type(spec) == "table" and type(spec.id) == "string",
    "boardgame spec must have a string 'id'")
  self.id = spec.id
  self.name = spec.name or spec.id
  self.publicActions = {}
end

---@param name string
---@param fn fun(ctx: GameContextBase, ...): any
function Boardgame:addPublicAction(name, fn)
  self.publicActions[name] = fn
end

return Boardgame
