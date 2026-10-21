-- SPDX-License-Identifier: LGPL-2.1-or-later
local effect = sr.createEffectSkeleton {
    id = 10017,
    name = "standard.effect.fixed_damage",
    event = sr.AfterSkillDamage,
    validate_on_usevalue = function(parameters)
        assert(math.type(parameters.amount) == "integer" and parameters.amount > 0,
            "amount must be a positive integer")
    end,
    can_trigger = function(self, event, target, owner, data)
        return data.from == owner and owner.alive and data.to.alive
    end,
    on_use = function(self, event, target, owner, data, parameters)
        -- 独立伤害事件保留固定伤害类别，便于免疫、抵挡等效果识别。
        event.ctx:damage { from = owner, to = data.to, skill = data.skill,
            damage = parameters.amount, damageType = sr.FixedDamage }
    end,
}

effect.description = effect.name .. ".description"
effect.translations = {
    zh_CN = {
        [effect.name] = "追加固定伤害",
        [effect.description] = "技能基础伤害结算后，对仍存活的目标额外造成指定数值的固定伤害。",
    },
    en_US = {
        [effect.name] = "Extra Fixed Damage",
        [effect.description] = "After base skill damage, deal the configured fixed damage to the surviving target.",
    },
}
return effect
