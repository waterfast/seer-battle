-- SPDX-License-Identifier: LGPL-2.1-or-later

local SeerEngine = require "seer.core.engine"

---@type SeerEngine
sr = SeerEngine:new()

-- 时机定义会挂到 sr 上，因此必须先创建游戏实体，再加载事件。
require "seer.core.events"

-- 内容依赖 sr 的时机类，必须在事件定义就绪后安装。
require("packages.standard"):install(sr)

return sr
