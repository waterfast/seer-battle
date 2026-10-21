-- SPDX-License-Identifier: LGPL-2.1-or-later

local Element = {}

---@alias ElementType string

Element.Grass = "Grass" -- 草
Element.Water = "Water" -- 水
Element.Fire = "Fire" -- 火
Element.Flying = "Flying" -- 飞行
Element.Electric = "Electric" -- 电
Element.Mechanical = "Mechanical" -- 机械
Element.Ground = "Ground" -- 地面
Element.Normal = "Normal" -- 普通
Element.Ice = "Ice" -- 冰
Element.Psychic = "Psychic" -- 超能
Element.Fighting = "Fighting" -- 战斗
Element.Light = "Light" -- 光
Element.Shadow = "Shadow" -- 暗影
Element.Mystery = "Mystery" -- 神秘
Element.Dragon = "Dragon" -- 龙
Element.Holy = "Holy" -- 圣灵
Element.Dimension = "Dimension" -- 次元
Element.Ancient = "Ancient" -- 远古
Element.Evil = "Evil" -- 邪灵
Element.Nature = "Nature" -- 自然
Element.King = "King" -- 王
Element.Chaos = "Chaos" -- 混沌
Element.Divine = "Divine" -- 神灵
Element.Reincarnation = "Reincarnation" -- 轮回
Element.Bug = "Bug" -- 虫
Element.Void = "Void" -- 虚空

-- 行是攻击属性，列是防守属性。未填写的组合为 1 倍；0 在 Lua 中为真。
-- 数据参考赛尔号 BWIKI「模块:属性克制」，仅整理单属性关系，未移植其代码。
-- https://wiki.biligame.com/seer/模块:属性克制
Element.chart = {
    [Element.Grass] = { [Element.Water] = 2, [Element.Ground] = 2, [Element.Light] = 2,
        [Element.Grass] = 0.5, [Element.Fire] = 0.5, [Element.Flying] = 0.5, [Element.Mechanical] = 0.5,
        [Element.Holy] = 0.5, [Element.Ancient] = 0.5, [Element.Chaos] = 0.5, [Element.Divine] = 0.5 },
    [Element.Water] = { [Element.Fire] = 2, [Element.Ground] = 2,
        [Element.Grass] = 0.5, [Element.Water] = 0.5, [Element.Holy] = 0.5, [Element.Nature] = 0.5,
        [Element.Chaos] = 0.5, [Element.Divine] = 0.5 },
    [Element.Fire] = { [Element.Grass] = 2, [Element.Mechanical] = 2, [Element.Ice] = 2,
        [Element.Water] = 0.5, [Element.Fire] = 0.5, [Element.Holy] = 0.5, [Element.Nature] = 0.5,
        [Element.Chaos] = 0.5, [Element.Divine] = 0.5 },
    [Element.Flying] = { [Element.Grass] = 2, [Element.Fighting] = 2, [Element.Bug] = 2,
        [Element.Electric] = 0.5, [Element.Mechanical] = 0.5, [Element.Dimension] = 0.5,
        [Element.Evil] = 0.5, [Element.Nature] = 0.5, [Element.Chaos] = 0.5 },
    [Element.Electric] = { [Element.Water] = 2, [Element.Flying] = 2, [Element.Shadow] = 2,
        [Element.Dimension] = 2, [Element.Chaos] = 2, [Element.Void] = 2, [Element.Ground] = 0,
        [Element.Grass] = 0.5, [Element.Electric] = 0.5, [Element.Mystery] = 0.5,
        [Element.Holy] = 0.5, [Element.Nature] = 0.5, [Element.Divine] = 0.5 },
    [Element.Mechanical] = { [Element.Ice] = 2, [Element.Fighting] = 2, [Element.Ancient] = 2,
        [Element.Evil] = 2, [Element.Divine] = 2, [Element.Water] = 0.5, [Element.Fire] = 0.5,
        [Element.Electric] = 0.5, [Element.Mechanical] = 0.5, [Element.Dimension] = 0.5 },
    [Element.Ground] = { [Element.Fire] = 2, [Element.Electric] = 2, [Element.Mechanical] = 2,
        [Element.King] = 2, [Element.Reincarnation] = 2, [Element.Flying] = 0,
        [Element.Grass] = 0.5, [Element.Psychic] = 0.5, [Element.Shadow] = 0.5, [Element.Dragon] = 0.5,
        [Element.Holy] = 0.5, [Element.Nature] = 0.5, [Element.Divine] = 0.5, [Element.Bug] = 0.5 },
    [Element.Normal] = {},
    [Element.Ice] = { [Element.Grass] = 2, [Element.Flying] = 2, [Element.Ground] = 2,
        [Element.Dimension] = 2, [Element.Ancient] = 2, [Element.Reincarnation] = 2, [Element.Bug] = 2,
        [Element.Water] = 0.5, [Element.Fire] = 0.5, [Element.Mechanical] = 0.5, [Element.Ice] = 0.5,
        [Element.Holy] = 0.5, [Element.Chaos] = 0.5, [Element.Divine] = 0.5 },
    [Element.Psychic] = { [Element.Fighting] = 2, [Element.Mystery] = 2, [Element.Nature] = 2,
        [Element.Mechanical] = 0.5, [Element.Psychic] = 0.5, [Element.Bug] = 0.5, [Element.Light] = 0 },
    [Element.Fighting] = { [Element.Mechanical] = 2, [Element.Ice] = 2, [Element.Dragon] = 2, [Element.Holy] = 2,
        [Element.Psychic] = 0.5, [Element.Fighting] = 0.5, [Element.Shadow] = 0.5, [Element.King] = 0.5 },
    [Element.Light] = { [Element.Psychic] = 2, [Element.Shadow] = 2, [Element.Bug] = 2, [Element.Grass] = 0,
        [Element.Mechanical] = 0.5, [Element.Ice] = 0.5, [Element.Light] = 0.5, [Element.Holy] = 0.5,
        [Element.Evil] = 0.5, [Element.Nature] = 0.5, [Element.Divine] = 0.5, [Element.Reincarnation] = 0.5, [Element.Void] = 0.5 },
    [Element.Shadow] = { [Element.Psychic] = 2, [Element.Shadow] = 2, [Element.Dimension] = 2,
        [Element.Mechanical] = 0.5, [Element.Ice] = 0.5, [Element.Light] = 0.5,
        [Element.Holy] = 0.5, [Element.Evil] = 0.5, [Element.Divine] = 0.5 },
    [Element.Mystery] = { [Element.Electric] = 2, [Element.Mystery] = 2, [Element.Holy] = 2,
        [Element.Nature] = 2, [Element.King] = 2, [Element.Divine] = 2, [Element.Reincarnation] = 2,
        [Element.Ground] = 0.5, [Element.Fighting] = 0.5, [Element.Evil] = 0.5, [Element.Chaos] = 0.5, [Element.Bug] = 0.5 },
    [Element.Dragon] = { [Element.Ice] = 2, [Element.Dragon] = 2, [Element.Holy] = 2, [Element.Evil] = 2,
        [Element.Grass] = 0.5, [Element.Water] = 0.5, [Element.Fire] = 0.5,
        [Element.Electric] = 0.5, [Element.Ancient] = 0.5, [Element.Bug] = 0.5 },
    [Element.Holy] = { [Element.Grass] = 2, [Element.Water] = 2, [Element.Fire] = 2, [Element.Electric] = 2,
        [Element.Ice] = 2, [Element.Ancient] = 2, [Element.Void] = 2,
        [Element.Fighting] = 0.5, [Element.Mystery] = 0.5, [Element.Dragon] = 0.5, [Element.Evil] = 0.5, [Element.Reincarnation] = 0.5 },
    [Element.Dimension] = { [Element.Flying] = 2, [Element.Mechanical] = 2, [Element.Psychic] = 2,
        [Element.Evil] = 2, [Element.Nature] = 2, [Element.Bug] = 2, [Element.Void] = 2, [Element.Shadow] = 0,
        [Element.Ice] = 0.5, [Element.King] = 0.5, [Element.Chaos] = 0.5, [Element.Divine] = 0.5, [Element.Reincarnation] = 0.5 },
    [Element.Ancient] = { [Element.Grass] = 2, [Element.Flying] = 2, [Element.Mystery] = 2, [Element.Dragon] = 2, [Element.Void] = 2,
        [Element.Mechanical] = 0.5, [Element.Ice] = 0.5, [Element.King] = 0.5, [Element.Reincarnation] = 0.5 },
    [Element.Evil] = { [Element.Light] = 2, [Element.Shadow] = 2, [Element.Mystery] = 2, [Element.Dimension] = 2, [Element.Nature] = 2,
        [Element.Mechanical] = 0.5, [Element.Ice] = 0.5, [Element.Psychic] = 0.5, [Element.Holy] = 0.5,
        [Element.King] = 0.5, [Element.Chaos] = 0.5, [Element.Reincarnation] = 0.5, [Element.Divine] = 0 },
    [Element.Nature] = { [Element.Grass] = 2, [Element.Water] = 2, [Element.Fire] = 2, [Element.Flying] = 2,
        [Element.Electric] = 2, [Element.Ground] = 2, [Element.Light] = 2, [Element.King] = 2, [Element.Reincarnation] = 2,
        [Element.Mechanical] = 0.5, [Element.Psychic] = 0.5, [Element.Fighting] = 0.5, [Element.Shadow] = 0.5,
        [Element.Mystery] = 0.5, [Element.Dimension] = 0.5, [Element.Evil] = 0.5, [Element.Chaos] = 0.5, [Element.Void] = 0.5 },
    [Element.King] = { [Element.Fighting] = 2, [Element.Shadow] = 2, [Element.Dimension] = 2, [Element.Evil] = 2,
        [Element.Psychic] = 0.5, [Element.Nature] = 0.5, [Element.Bug] = 0.5 },
    [Element.Chaos] = { [Element.Flying] = 2, [Element.Ice] = 2, [Element.Mystery] = 2,
        [Element.Dimension] = 2, [Element.Evil] = 2, [Element.Nature] = 2, [Element.Divine] = 2,
        [Element.Electric] = 0.5, [Element.Mechanical] = 0.5, [Element.Fighting] = 0.5, [Element.Reincarnation] = 0.5, [Element.Void] = 0 },
    [Element.Divine] = { [Element.Grass] = 2, [Element.Water] = 2, [Element.Fire] = 2, [Element.Electric] = 2,
        [Element.Ice] = 2, [Element.Ancient] = 2, [Element.Evil] = 2, [Element.Chaos] = 2,
        [Element.Mechanical] = 0.5, [Element.Fighting] = 0.5, [Element.Dragon] = 0.5 },
    [Element.Reincarnation] = { [Element.Light] = 2, [Element.Shadow] = 2, [Element.Holy] = 2,
        [Element.Dimension] = 2, [Element.Evil] = 2, [Element.Chaos] = 2,
        [Element.Ice] = 0.5, [Element.Psychic] = 0.5, [Element.Nature] = 0.5 },
    [Element.Bug] = { [Element.Grass] = 2, [Element.Ground] = 2, [Element.Fighting] = 2, [Element.Chaos] = 2, [Element.Bug] = 2,
        [Element.Water] = 0.5, [Element.Fire] = 0.5, [Element.Ice] = 0.5, [Element.Light] = 0.5 },
    [Element.Void] = { [Element.Psychic] = 2, [Element.Fighting] = 2, [Element.Light] = 2,
        [Element.Mystery] = 2, [Element.Nature] = 2, [Element.Reincarnation] = 2,
        [Element.Flying] = 0.5, [Element.Shadow] = 0.5, [Element.Holy] = 0.5, [Element.Dimension] = 0.5 },
}

-- 单、双属性统一使用长度为 1 或 2 的数组，避免枚举全部组合。
---@alias ElementSet ElementType[]

local function validate(elements)
    assert(type(elements) == "table" and (#elements == 1 or #elements == 2),
        "elements must contain one or two types")
    for key, value in pairs(elements) do
        assert((key == 1 or key == 2) and Element.chart[value], "invalid element type or array index")
    end
    assert(elements[1] ~= elements[2], "dual elements must be different")
end

-- 赛尔号单双属性合成规则，不能直接相乘；也不能将四个分量一次求平均。
local function combine(first, second)
    if first == 2 and second == 2 then
        return 4
    end
    if first == 0 or second == 0 then
        return (first + second) / 4
    end
    return (first + second) / 2
end

local function againstSingle(attack, defense)
    local first = Element.chart[attack[1]][defense] or 1
    if not attack[2] then
        return first
    end
    return combine(first, Element.chart[attack[2]][defense] or 1)
end

--- 获取技能属性对目标属性的克制系数；不包含本系加成等其他伤害修正。
---@param attack ElementSet 技能的属性，不是攻击精灵的属性
---@param defense ElementSet 防守精灵的属性
---@return number
function Element.getMultiplier(attack, defense)
    validate(attack)
    validate(defense)
    local first = againstSingle(attack, defense[1])
    if not defense[2] then
        return first
    end
    local second = againstSingle(attack, defense[2])
    if attack[2] then
        -- 双打双必须先拆防守方，此处仅取平均，不再触发 4 倍/无效规则。
        return (first + second) / 2
    end
    return combine(first, second)
end

return Element
