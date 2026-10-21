-- SPDX-License-Identifier: LGPL-2.1-or-later
local effect = sr.createEffectSkeleton {
    id = 10015,
    name = "standard.effect.poison_tick",
    event = sr.RoundEnd,
    validate_on_usevalue = function(parameters)
        assert(type(parameters.ratio) == "number" and parameters.ratio > 0 and parameters.ratio <= 1,
            "ratio must be in (0, 1]")
    end,
    can_trigger = function(self, event, target, owner, data, can_triggervalue)
        local buff = self.source
        return owner.alive and buff ~= nil and event.ctx:getBuff(owner, buff.id) == buff
    end,
    on_use = function(self, event, target, owner, data, on_usevalue)
        local buff = self.source
        event.ctx:loseHp { who = owner, num = math.max(1, math.floor(owner:getMaxHp() * on_usevalue.ratio)) }
        -- 剩余轮数在 Buff 实例上，伤害比例在实际 Effect.on_usevalue.ratio 上。
        if buff:advanceRound() then
            event.ctx:removeBuff { who = owner, buff = buff, reason = "expired" }
        end
    end,
}

-- 名称与描述保持为 key，显示时再按玩家语言翻译。
effect.description = effect.name .. ".description"
effect.translations = {
    zh_CN = {
        [effect.name] = "中毒轮末扣血",
        [effect.description] = "每轮结束时损失最大体力的一定比例，持续轮数耗尽后移除。",
    },
    en_US = {
        [effect.name] = "Poison Damage",
        [effect.description] = "At round end, lose the configured fraction of maximum HP and remove the buff when its duration expires.",
    },
}

return effect
