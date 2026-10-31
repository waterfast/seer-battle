local class = kt.class

TriggerEvent = require "core.trigger_event"

---@class TriggerData: Object
---@field private _data any
---@field public extra_data any
TriggerData = class("TriggerData")

function TriggerData:initialize(spec)
  self._data = spec or {}
end

function TriggerData:__index(k)
  if k == "_data" then return rawget(self, k) end
  return self._data[k]
end

function TriggerData:__newindex(k, v)
  if k == "_data" then return rawset(self, k, v) end
  if not self._data then return rawset(self, k, v) end
  self._data[k] = v
end

-- sr 是游戏实体，由外部创建；这里仅向它挂载时机，不创建或替换 sr。
require "seer.core.events.gameflow"
require "seer.core.events.skill"
require "seer.core.events.hp"

require "seer.core.events.buff"
require "seer.core.events.stage"

require "seer.core.events.action"
