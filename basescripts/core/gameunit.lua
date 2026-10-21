-- SPDX-FileCopyrightText: 2026 Notify Ctrl <notify-ctrl@qq.com>
-- SPDX-License-Identifier: LGPL-2.1-or-later
---
--[[
游戏单位，游戏里的所有单位都继承自这个类，实现基本的作用
游戏启动时自动创建？
--]]
local class = kt.class

---@class GameUnit: Object
---@field ctx GameContextBase --所属的ctx
---@field id integer --id
---@field name string --名称
local GameUnit = class("GameUnit")

function GameUnit:initialize(ctx, id,name)
    self.ctx = ctx
    self.id = id
    self.name = name or ""
end







return GameUnit