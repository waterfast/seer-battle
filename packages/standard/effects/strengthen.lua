-- SPDX-License-Identifier: LGPL-2.1-or-later
local StatStages = require "seer.core.stat-stages"

-- 一个骨架可被不同技能配置为攻击 +1、速度 +2 等，无需为每组数值写脚本。
local effect = sr.createEffectSkeleton {
    id = 10011,
    name = "standard.effect.strengthen",
    event = sr.SkillHit,
    validate_on_usevalue = function(parameters)
        assert(StatStages.isValidName(parameters.stat), "unknown stat: " .. tostring(parameters.stat))
        assert(math.type(parameters.stages) == "integer" and parameters.stages > 0, "stages must be a positive integer")
    end,
    can_trigger = function(self, event, target, owner, data, can_triggervalue)
        return data.from == owner and owner.alive
    end,
    on_use = function(self, event, target, owner, data, on_usevalue)
        -- 不直接修改 statStages，复用 manager 的原因枚举、免疫时机和批量提交。
        event.ctx:strengthen {
            from = owner, who = owner, skill = data.skill,
            changes = { [on_usevalue.stat] = on_usevalue.stages },
        }
    end,
}

-- 名称与描述保持为 key，显示时再按玩家语言翻译。
effect.description = effect.name .. ".description"
effect.translations = {
    zh_CN = {
        [effect.name] = "能力提升",
        [effect.description] = "技能命中后，提升自身指定能力若干级。",
    },
    en_US = {
        [effect.name] = "Raise Stat",
        [effect.description] = "After the skill hits, raise the selected stat of the user by the configured number of stages.",
    },
}

return effect
