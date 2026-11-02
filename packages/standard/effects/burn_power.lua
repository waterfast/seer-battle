-- SPDX-License-Identifier: LGPL-2.1-or-later
local effect = sr.createEffectSkeleton {
    id = 10020,
    event = sr.BeforeSkillDamageCalculation,
    can_trigger = function(self, event, target, owner, data)
        return data.from == owner and (data.skill.type == "physical" or data.skill.type == "special")
    end,
    on_use = function(self, event, target, owner, data)
        data.power = data.power * 0.5
    end,
}
effect.description = effect.id .. ".description"
effect.translations = {
    zh_CN = { [effect.description] = "烧伤令攻击技能威力降低 50%。" },
    en_US = { [effect.description] = "Burn reduces attack skill power by 50%." },
}
return effect
