-- SPDX-License-Identifier: LGPL-2.1-or-later
local StatPattern = require "seer.core.pattern.stat_pattern"

local effect = sr.createEffectSkeleton {
    id = 10016,
    name = "standard.effect.stage_change",
    event = sr.SkillHit,
    validate_on_usevalue = function(parameters)
        assert(parameters.target == "self" or parameters.target == "target", "target must be self or target")
        assert(math.type(parameters.stages) == "integer" and parameters.stages ~= 0,
            "stages must be a non-zero integer")
        assert(parameters.mode == nil or parameters.mode == "each" or parameters.mode == "random_total",
            "mode must be each or random_total")
        StatPattern:new(parameters.stats, parameters.exclude)
    end,
    can_trigger = function(self, event, target, owner, data)
        return data.from == owner and owner.alive
    end,
    on_use = function(self, event, target, owner, data, parameters)
        local who = parameters.target == "self" and owner or data.to
        if not who or not who.alive then return end
        local stats = StatPattern:new(parameters.stats, parameters.exclude):select()
        local changes = {}
        local sign = parameters.stages > 0 and 1 or -1
        local amount = math.abs(parameters.stages)
        if parameters.mode == "random_total" then
            -- 在本批拟变化量上判断上下限，避免重复抽取已经到顶/到底的能力。
            -- 这里只分配意图，统一事件仍可修改或阻止整批变化。
            for _ = 1, amount do
                local candidates = {}
                for _, name in ipairs(stats) do
                    local projected = who.statStages:get(name) + sign * (changes[name] or 0)
                    if (sign > 0 and projected < 6) or (sign < 0 and projected > -6) then
                        candidates[#candidates + 1] = name
                    end
                end
                if #candidates == 0 then break end
                local name = candidates[event.ctx:random(1, #candidates)]
                changes[name] = (changes[name] or 0) + 1
            end
        else
            for _, name in ipairs(stats) do changes[name] = amount end
        end
        local spec = { from = owner, who = who, skill = data.skill, changes = changes }
        if sign > 0 then event.ctx:strengthen(spec) else event.ctx:weaken(spec) end
    end,
}

effect.description = effect.id .. ".description"
effect.translations = {
    zh_CN = {
        [effect.description] = "技能命中后，改变自身或目标的所选能力，可逐项变化或随机分配总等级。",
    },
    en_US = {
        [effect.description] = "On hit, change selected stats of the user or target, individually or by a random total.",
    },
}
return effect
