-- SPDX-License-Identifier: LGPL-2.1-or-later
local EffectSkeleton = require "seer.core.effect_skeleton"
local TriggerEffect = require "seer.core.effect_type.trigger"
local Effect = require "seer.core.effect"

---@class TriggerEffectSkeleton: EffectSkeleton
---@field event TriggerEvent
---@field priority number
---@field can_trigger? fun(effect: TriggerEffect, event: TriggerEvent, target: GameUnit?, owner: GameUnit?, data: any, can_triggervalue: table): boolean
---@field on_cost? fun(effect: TriggerEffect, event: TriggerEvent, target: GameUnit?, owner: GameUnit?, data: any, on_usevalue: table): boolean
---@field on_use? fun(effect: TriggerEffect, event: TriggerEvent, target: GameUnit?, owner: GameUnit?, data: any, on_usevalue: table): boolean?
---@field validate_can_triggervalue? fun(parameters: table)
---@field validate_on_usevalue? fun(parameters: table)
local TriggerEffectSkeleton = EffectSkeleton:subclass("TriggerEffectSkeleton")

function TriggerEffectSkeleton:initialize(id, name, event)
    EffectSkeleton.initialize(self, id, name)
    assert(type(event) == "table" and event.isSubclassOf and event:isSubclassOf(TriggerEvent),
        "trigger skeleton requires a TriggerEvent class")
    self.type = Effect.Trigger
    self.event = event
    self.priority = 1
end

function TriggerEffectSkeleton:validateParameters(can_triggervalue, on_usevalue)
    EffectSkeleton.validateParameters(self, can_triggervalue, on_usevalue)
    local function check(name, callback, parameters)
        if not callback then return end
        local ok, message = pcall(callback, parameters or {})
        assert(ok, name .. ": " .. tostring(message))
    end
    check("can_triggervalue", self.validate_can_triggervalue, can_triggervalue)
    check("on_usevalue", self.validate_on_usevalue, on_usevalue)
end

function TriggerEffectSkeleton:createEffect(can_triggervalue, on_usevalue, source)
    return TriggerEffect:new(self, can_triggervalue, on_usevalue, source)
end

return TriggerEffectSkeleton
