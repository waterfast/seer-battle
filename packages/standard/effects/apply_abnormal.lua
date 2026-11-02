-- SPDX-License-Identifier: LGPL-2.1-or-later
-- 只施加异常，不在技能内重复实现状态行为和寿命。
local Abnormal = require "seer.core.abnormal"
local effect = sr.createEffectSkeleton {
    id = 10019,
    event = sr.SkillHit,
    validate_on_usevalue = function(parameters)
        assert(math.type(parameters.buffId) == "integer" and parameters.buffId > 0, "buffId must be positive")
        Abnormal.validateApplication(parameters)
    end,
    can_trigger = function(self, event, target, owner, data)
        return data.from == owner and data.to.alive
    end,
    on_use = function(self, event, target, owner, data, parameters)
        event.ctx:inflictAbnormal { from=owner, who=data.to, buff=parameters.buffId,
            chance=parameters.chance, turns=parameters.turns,
            minTurns=parameters.minTurns, maxTurns=parameters.maxTurns, skill=data.skill }
    end,
}
effect.description = effect.id .. ".description"
effect.translations = {
    zh_CN = { [effect.description] = "命中后按配置概率施加异常，可指定持续时间或随机范围。" },
    en_US = { [effect.description] = "On hit, apply an abnormal status with configured chance and duration." },
}
return effect
