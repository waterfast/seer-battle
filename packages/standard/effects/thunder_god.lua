-- SPDX-License-Identifier: LGPL-2.1-or-later
-- 按用户给定“使用攻击技能”的规则：成功开始使用后、命中判定前发动。
local Abnormal = require "seer.core.abnormal"
return sr.createEffectSkeleton {
    id = 10052,
    event = sr.SkillUsing,
    validate_on_usevalue = function(parameters)
        assert(math.type(parameters.buffId) == "integer" and parameters.buffId > 0, "invalid abnormal id")
        Abnormal.validateApplication(parameters)
    end,
    can_trigger = function(self, event, target, owner, data)
        return data.from == owner and owner.alive and data.to.alive
            and (data.skill.type == "physical" or data.skill.type == "special")
    end,
    on_use = function(self, event, target, owner, data, parameters)
        local chance = math.max(0, math.min(1, owner:getHp() / owner:getMaxHp()))
        event.ctx:inflictAbnormal { from=owner, who=data.to, buff=parameters.buffId, chance=chance,
            turns=parameters.turns, minTurns=parameters.minTurns, maxTurns=parameters.maxTurns,
            skill=data.skill }
    end,
}
