-- SPDX-License-Identifier: LGPL-2.1-or-later
local poisonBuffId = 10021 -- standard_buff.csv 中的固定内容编号
local effect = sr.createEffectSkeleton {
    id = 10014,
    event = sr.SkillHit,
    validate_on_usevalue = function(parameters)
        assert(math.type(parameters.turns) == "integer" and parameters.turns > 0, "poison duration must be a positive integer")
    end,
    can_trigger = function(self, event, target, owner, data, can_triggervalue)
        return data.from == owner and data.to.alive and not event.ctx:getBuff(data.to, poisonBuffId)
    end,
    on_use = function(self, event, target, owner, data, on_usevalue)
        event.ctx:applyAbnormal { from = owner, who = data.to, buff = poisonBuffId, state = { turn = on_usevalue.turns }, skill = data.skill }
    end,
}

-- 名称与描述保持为 key，显示时再按玩家语言翻译。
effect.description = effect.id .. ".description"
effect.translations = {
    zh_CN = {
        [effect.description] = "技能命中后使得对手中毒。",
    },
    en_US = {

    },
}

return effect
