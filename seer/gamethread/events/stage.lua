-- SPDX-License-Identifier: LGPL-2.1-or-later
local GameEvent = require "gamethread.gameevent"
local StatPattern = require "seer.core.pattern.stat_pattern"
require "seer.core.events"

local function blocked(logic, timing, data)
    if data.prevented or logic.ctx.gameFinished then return true end
    if logic:trigger(timing, data.who, data) then data:preventStageChange() end
    return data.prevented or logic.ctx.gameFinished
end

local function hasChanges(changes)
    for _, delta in pairs(changes) do if delta ~= 0 then return true end end
    return false
end

-- 增减直接使用 changes；消强保留意图，直到前置嵌套效果结束后再解析。
local ChangeStages = GameEvent:subclass("Seer.GameEvent.ChangeStages")
function ChangeStages:main()
    local logic, data = self.ctx.logic, self.data
    data.actualChanges = {}
    if data.who.alive and not blocked(logic, sr.BeforeStageChange, data) and data.who.alive then
        -- 在前置效果之后取快照，避免嵌套变化后使用过期的等级值。
        data.oldStages = data.who.statStages:toTable()
        if data.operation == "clearBoosts" or data.operation == "reset" then
            local changes = {}
            for _, name in ipairs(StatPattern:new(data.stats):select()) do
                local stage = data.who.statStages:get(name)
                if stage > 0 or (data.operation == "reset" and stage < 0) then changes[name] = -stage end
            end
            data.changes = changes
        end
        data.actualChanges = data.who.statStages:changeMany(data.changes)
        data.newStages = data.who.statStages:toTable()
        if hasChanges(data.actualChanges) then
            self.ctx:broadcast("Seer.StagesChanged", { id = data.who.id, reason = data.reason,
                changes = data.actualChanges, stages = data.newStages })
            logic:trigger(sr.StagesChanged, data.who, data)
        end
    end
    if not self.ctx.gameFinished then logic:trigger(sr.StageChangeFinished, data.who, data) end
    return data.actualChanges
end

return { ChangeStages = ChangeStages }
