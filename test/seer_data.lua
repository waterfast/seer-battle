-- SPDX-License-Identifier: LGPL-2.1-or-later
-- 仅用于命令行测试：编号、面板、性格编号和技能参数均为示例，不是正式图鉴数据。
local Element = require "seer.core.element"
local Data = {}

Data.skills = {
    { id = 101, name = "雷神觉醒（测试）", power = 0, type = "status", accuracy = 100, pp = 10,
        description = "自身除特攻外五项能力各提升 3 级",
        effects = { { id = 10016, on_usevalue = {
            target = "self", exclude = { "spatk" }, stages = 3,
        } } } },
    { id = 102, name = "雷霆干扰（测试）", power = 0, type = "status", accuracy = 100, pp = 10,
        description = "目标随机能力总计降低 3 级，允许重复抽中",
        effects = { { id = 10016, on_usevalue = {
            target = "target", mode = "random_total", stages = -3,
        } } } },
    { id = 104, name = "雷神天明闪（测试）", power = 100, type = "physical", accuracy = 100, pp = 10,
        description = "威力 100，随后额外造成 50 点固定伤害",
        effects = { { id = 10017, on_usevalue = { amount = 50 } } } },
    { id = 201, name = "石破天惊", power = 105, type = "physical", accuracy = 100, pp = 10 },
    { id = 202, name = "返璞归真", power = 80, type = "special", accuracy = 100, pp = 15 },
    { id = 301, name = "体力恢复（测试）", power = 0, type = "status", accuracy = 100,
        description = "自身回复 100 点体力，不超过体力上限",
        pp = 3, effects = { { id = 10013, can_triggervalue = {}, on_usevalue = { amount = 100 } } } },
}

Data.users = {
    { id = 11, connId = 1011, username = "雷伊训练师", state = "online" },
    { id = 22, connId = 1022, username = "盖亚训练师", state = "online" },
}

Data.players = {
    [11] = {
      activePetId = 1,
      items = { [9001] = 2 },
      pets = { {
        id = 1, pet_id = 10001, name = "雷伊", level = 100,
        element = { Element.Electric }, nature = 1, iv = 31,
        atk = 300, def = 240, spatk = 280, spdef = 230, speed = 310,
        hp = 360, maxHp = 360, skills = { 101, 102, 301, 104 },
      } },
    },
    [22] = {
      activePetId = 2,
      items = {},
      pets = { {
        id = 2, pet_id = 10002, name = "盖亚", level = 100,
        element = { Element.Fighting }, nature = 2, iv = 29,
        atk = 325, def = 250, spatk = 230, spdef = 235, speed = 270,
        hp = 390, maxHp = 390, skills = { 201, 202, 301 },
      } },
    },
}

Data.natures = { [1] = "开朗（测试编号）", [2] = "固执（测试编号）" }

return Data
