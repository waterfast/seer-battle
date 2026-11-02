-- SPDX-License-Identifier: LGPL-2.1-or-later
-- 静态参数配置；不会执行战斗逻辑，Effect 实例仍在局内独立创建。
local function effect(id, parameters, conditions)
    return { id = id, can_triggervalue = conditions or {}, on_usevalue = parameters or {} }
end
return {
    poison = { effect(10015, { ratio = 1/8 }), effect(10028) },
    burn = { effect(10015, { ratio = 1/8 }), effect(10020), effect(10028) },
    frostbite = { effect(10015, { ratio = 1/8 }), effect(10028) },
    fatigue = { effect(10026), effect(10028) },
    paralysis = { effect(10026), effect(10028) },
    fear = { effect(10026), effect(10028) },
    sleep = { effect(10026), effect(10053), effect(10028) },
    guard = { effect(10012, { amount = 10 }) },
    heal_skill = { effect(10013, { amount = 50 }, { hpBelow = 1 }) },
    focus_skill = { effect(10011, { stat = "atk", stages = 1 }) },
    poison_skill = { effect(10019, { buffId = 10021, turns = 3 }) },
    burn_skill = { effect(10019, { buffId = 10023, turns = 3 }) },
    frostbite_skill = { effect(10019, { buffId = 10024, turns = 3 }) },
    fatigue_skill = { effect(10019, { buffId = 10025, turns = 3 }) },
    paralysis_skill = { effect(10019, { buffId = 10061, turns = 3 }) },
    fear_skill = { effect(10019, { buffId = 10062, turns = 3 }) },
    sleep_skill = { effect(10019, { buffId = 10063, turns = 3 }) },
    thunder_god = { effect(10051, { amount = 1 }), effect(10052, { buffId = 10061 }) },
}
