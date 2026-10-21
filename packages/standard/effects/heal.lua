-- SPDX-License-Identifier: LGPL-2.1-or-later
local effect = sr.createEffectSkeleton {
    id = 10013,
    name = "standard.effect.heal",
    event = sr.SkillHit,
    validate_can_triggervalue = function(parameters)
        local threshold = parameters.hpBelow
        assert(threshold == nil or (threshold > 0 and threshold <= 1), "hpBelow must be in (0, 1]")
    end,
    validate_on_usevalue = function(parameters)
        assert(math.type(parameters.amount) == "integer" and parameters.amount >= 0,
            "amount must be a non-negative integer")
    end,
    can_trigger = function(self, event, target, owner, data, can_triggervalue)
        return data.from == owner and owner.alive
            and owner:getHp() < owner:getMaxHp() * (can_triggervalue.hpBelow or 1)
    end,
    on_use = function(self, event, target, owner, data, on_usevalue)
        event.ctx:recover { from = owner, who = owner, num = on_usevalue.amount, skill = data.skill }
    end,
}

-- 名称与描述保持为 key，显示时再按玩家语言翻译。
effect.description = effect.name .. ".description"
effect.translations = {
    zh_CN = {
        [effect.name] = "回复体力",
        [effect.description] = "自身血量低于设定比例时，回复指定数量的体力。",
    },
    en_US = {
        [effect.name] = "Recover HP",
        [effect.description] = "Recover the configured amount of HP when the owner is below the configured HP ratio.",
    },
}

return effect
