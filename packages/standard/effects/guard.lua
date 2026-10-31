-- SPDX-License-Identifier: LGPL-2.1-or-later
local effect = sr.createEffectSkeleton {
    id = 10012,
    event = sr.DamageInflicted,
    validate_on_usevalue = function(parameters)
        assert(math.type(parameters.amount) == "integer" and parameters.amount >= 0,
            "amount must be a non-negative integer")
    end,
    can_trigger = function(self, event, target, owner, data, can_triggervalue)
        local buff = self.source
        return data.to == owner and data.damage > 0 and buff ~= nil
            and event.ctx:getBuff(owner, buff.id) == buff
    end,
    on_use = function(self, event, target, owner, data, on_usevalue)
        local buff = self.source
        if buff:consume() then
            data.damage = math.max(0, data.damage - on_usevalue.amount)
            if buff:isExpired() then
                event.ctx:removeBuff { who = owner, buff = buff, reason = "expired" }
            end
        end
    end,
}

-- 名称与描述保持为 key，显示时再按玩家语言翻译。
effect.description = effect.id .. ".description"
effect.translations = {
    zh_CN = {
        [effect.description] = "抵挡下次受到的X点伤害。",
    },
    en_US = {
        [effect.description] = "Reduce incoming damage by the configured amount and consume one guard charge.",
    },
}

return effect
