-- SPDX-License-Identifier: LGPL-2.1-or-later
local Events = require "seer.gamethread.events.stage"
local Manager = {}

--- 复制调用参数，避免回调改动技能复用的参数表；实际等级在事件提交时校验。
local function prepare(self, spec, defaultReason, sign)
    assert(spec.who and spec.who.ctx == self.ctx, "stage target must belong to this battle")
    local data = {}
    for key, value in pairs(spec) do data[key] = value end
    data.reason = data.reason or defaultReason
    assert(math.type(data.reason) == "integer" and data.reason >= sr.ReasonStageChange
        and data.reason <= sr.ReasonClearBoosts, "unknown stage change reason")
    data.changes = {}
    for name, amount in pairs(spec.changes or {}) do
        spec.who.statStages:get(name)
        assert(math.type(amount) == "integer", "stage amount must be an integer")
        if sign then assert(amount >= 0, "strengthen/weaken amounts must be non-negative") end
        data.changes[name] = amount * (sign or 1)
    end
    -- stats 是消强包装方法的选项，不属于基础事件数据。
    data.stats = nil
    return StageChangeData:new(data)
end

--- 通用变化入口，changes 可同时包含正数、负数；reason 由技能传入。
---@param spec StageChangeDataSpec
---@return table<string, integer> actualChanges
function Manager:changeStages(spec)
    return self:executeEvent(Events.ChangeStages, prepare(self, spec, sr.ReasonStageChange))
end

--- 强化只封装变化数据，不建立独立事件；changes 使用非负幅度。
function Manager:strengthen(spec)
    return self:executeEvent(Events.ChangeStages, prepare(self, spec, sr.ReasonStrengthen, 1))
end

--- 弱化只把非负幅度换算为负变化量，仍执行同一个基础事件。
function Manager:weaken(spec)
    return self:executeEvent(Events.ChangeStages, prepare(self, spec, sr.ReasonWeaken, -1))
end

--- 清除所选能力的正等级，stats 省略时包含全部六项；负等级保持不变。
---@param spec StageChangeDataSpec @可额外提供 stats: string[] 选择消强能力
function Manager:clearBoosts(spec)
    local data = prepare(self, spec, sr.ReasonClearBoosts)
    data.changes = {}
    local selected = spec.stats or { "atk", "def", "spatk", "spdef", "speed", "accuracy" }
    for _, name in ipairs(selected) do
        local stage = spec.who.statStages:get(name)
        -- 将业务意图转换为基本变化量，消强不恢复负等级。
        if stage > 0 then data.changes[name] = -stage end
    end
    return self:executeEvent(Events.ChangeStages, data)
end

return Manager
