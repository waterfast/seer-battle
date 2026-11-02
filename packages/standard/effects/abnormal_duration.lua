-- SPDX-License-Identifier: LGPL-2.1-or-later
-- 本轮中途施加时，先保留完整后续轮数；扣血/阻止技能若在本轮实际发生，
-- 对应效果会将首个扣减轮次提前到本轮。最终扣减仍全部由 ResolveRoundEnd 执行。
local effect = sr.createEffectSkeleton {
    id = 10028,
    event = sr.BuffAdded,
    can_trigger = function(self, event, target, owner, data)
        return data.buff == self.source and data.who == owner
    end,
    on_use = function(self, event)
        local logic = event.ctx.logic
        self.source.firstTickRound = (logic.roundEndNumber or logic.roundNumber) + 1
    end,
}
return effect
