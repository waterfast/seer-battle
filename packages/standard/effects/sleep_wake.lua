-- SPDX-License-Identifier: LGPL-2.1-or-later
-- 官方说明以攻击技能未 miss 为条件；护盾挡住伤害也不妨碍唤醒。
return sr.createEffectSkeleton {
    id = 10053,
    event = sr.SkillHit,
    can_trigger = function(self, event, target, owner, data)
        return data.to == owner and data.from.player ~= owner.player
            and (data.skill.type == "physical" or data.skill.type == "special")
    end,
    on_use = function(self, event, target, owner)
        event.ctx:removeBuff { who = owner, buff = self.source, reason = "wake" }
    end,
}
