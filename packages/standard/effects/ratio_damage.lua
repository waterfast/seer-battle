-- SPDX-License-Identifier: GPL-3.0-or-later
-- 参考 seer-asio lua/specs/standard/effects.lua 的比例伤害，使用当前效果骨架。
local effect = sr.createEffectSkeleton {
    id = 10018,
    event = sr.SkillHit,
    validate_on_usevalue = function(parameters)
        assert(type(parameters.ratio) == "number" and parameters.ratio > 0 and parameters.ratio <= 1,
            "ratio must be in (0, 1]")
    end,
    can_trigger = function(self, event, target, owner, data)
        return data.from == owner and data.to.alive
    end,
    on_use = function(self, event, target, owner, data, parameters)
        -- 使用独立固定伤害事件，继续接受现有减伤、免疫和倒下处理。
        event.ctx:damage { from = owner, to = data.to, skill = data.skill,
            damage = math.floor(data.to:getMaxHp() * parameters.ratio), damageType = sr.FixedDamage }
    end,
}
effect.description = effect.id .. ".description"
effect.translations = {
    zh_CN = { [effect.description] = "造成目标最大体力一定比例的固定伤害。" },
    en_US = { [effect.description] = "Deal fixed damage based on the target's maximum HP." },
}
return effect
