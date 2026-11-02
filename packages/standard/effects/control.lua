-- SPDX-License-Identifier: LGPL-2.1-or-later
local effect = sr.createEffectSkeleton {
    id = 10026,
    event = sr.BeforeSkillUse,
    priority = 100,
    can_trigger = function(self, event, target, owner, data)
        return data.from == owner and owner.alive
    end,
    on_use = function(self, event, target, owner, data)
        data.prevented = true
        data.preventReason = self.source.abnormalKind or "fatigue"
        -- 实际阻止了本轮出招，持续时间包含这一轮，仍由统一寿命管理扣减。
        local buff = self.source
        buff.firstTickRound = math.min(buff.firstTickRound or event.ctx.logic.roundNumber,
            event.ctx.logic.roundNumber)
        event.ctx:broadcast("Seer.SkillPrevented", { from = owner.id, skillId = data.skill.id,
            reason = data.preventReason, buffId = buff.id })
    end,
}
effect.description = effect.id .. ".description"
effect.translations = {
    zh_CN = { [effect.description] = "控制异常期间无法释放技能，不消耗 PP；不阻止道具和换宠。" },
    en_US = { [effect.description] = "Control statuses prevent skill use without spending PP; items and switching remain available." },
}
return effect
