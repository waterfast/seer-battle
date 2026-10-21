-- SPDX-FileCopyrightText: 2026 Notify Ctrl <notify-ctrl@qq.com>
-- SPDX-License-Identifier: LGPL-2.1-or-later

local User = require "core.user"

---@class ServerUser: User
local ServerUser = User:subclass("ServerUser")

return ServerUser
