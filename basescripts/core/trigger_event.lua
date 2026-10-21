-- SPDX-License-Identifier: LGPL-2.1-or-later
local class = kt.class

---@class TriggerEvent: Object
---@field ctx ServerGameContext
---@field target GameUnit|ServerPlayer|nil
---@field data any
---@field id integer
---@field broken boolean
local TriggerEvent = class("TriggerEvent")

function TriggerEvent:initialize(ctx, target, data)
  self.ctx, self.target, self.data = ctx, target, data or {}
  ctx.logic.current_trigger_event_id = ctx.logic.current_trigger_event_id + 1
  self.id = ctx.logic.current_trigger_event_id
  self.broken = false
  -- 以效果实例及拥有者为键，避免同名效果、多个拥有者和嵌套触发串数据。
  self.effect_data = {}
end

function TriggerEvent:setCostData(effect, value, owner)
  local values = self.effect_data[effect] or {}
  self.effect_data[effect] = values
  values[owner or self] = value
end

function TriggerEvent:getCostData(effect, owner)
  local values = self.effect_data[effect]
  return values and values[owner or self]
end

function TriggerEvent:breakCheck()
  return false
end

-- 触发事件只携带时机数据；判断、消耗、执行顺序统一由 Logic 决定。
function TriggerEvent:exec()
  return self.ctx.logic:dispatchTrigger(self)
end

return TriggerEvent
