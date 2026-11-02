-- SPDX-License-Identifier: LGPL-2.1-or-later
local effect = sr.createEffectSkeleton {
    id = 10015,
    event = sr.BeforeTurnStart,
    validate_on_usevalue = function(parameters)
        assert(type(parameters.ratio) == "number" and parameters.ratio > 0 and parameters.ratio <= 1,
            "ratio must be in (0, 1]")
    end,
    can_trigger = function(self, event, target, owner, data, can_triggervalue)
        local buff = self.source
        return owner.alive and data.who ~= owner.player and buff ~= nil
            and event.ctx:getBuff(owner, buff.id) == buff
            and buff.lastDamageRound ~= event.ctx.logic.roundNumber
    end,
    on_use = function(self, event, target, owner, data, on_usevalue)
        local buff = self.source
        local round = event.ctx.logic.roundNumber
        buff.lastDamageRound = round -- 嵌套结算也不能重复扣血。
        buff.firstTickRound = math.min(buff.firstTickRound or round, round)
        event.ctx:loseHp { who = owner, num = math.max(1, math.floor(owner:getMaxHp() * on_usevalue.ratio)) }
        -- 这里只处理业务效果；轮数与到期移除统一由 ResolveRoundEnd 负责。
    end,
}

-- 名称与描述保持为 key，显示时再按玩家语言翻译。
effect.description = effect.id .. ".description"
effect.translations = {
    zh_CN = {
        [effect.description] = "对手行动开始时扣除一定生命值，每轮最多一次。",
    },
}

return effect
