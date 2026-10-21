-- SPDX-FileCopyrightText: 2026 Notify Ctrl <notify-ctrl@qq.com>
-- SPDX-License-Identifier: LGPL-2.1-or-later

local LObject = require "corelib.lobject"

-- Full dynamic property table.

---@class ObservableTable: Object, LObject
local ObservableTable = kt.class("ObservableTable")
ObservableTable:include(LObject)
ObservableTable:EnableDynamicProperties()

--- take snapshot for serialization.
---@return table
function ObservableTable:snapshot()
  local ret = {}
  for k in pairs(rawget(self, "__props") or {}) do
    ret[k] = self[k]
  end
  return ret
end

return ObservableTable
