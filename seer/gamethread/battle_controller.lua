-- SPDX-License-Identifier: LGPL-2.1-or-later
-- 只负责计算，不派发事件、不消耗 PP、不直接改体力。
local Element = require "seer.core.element"
local BattleController = kt.class("Seer.BattleController")

function BattleController:initialize(ctx)
  self.ctx = ctx
end

---@class DamageCalculationSpec
---@field from? Pet @使用攻防公式时需要来源，定值伤害可省略
---@field to Pet
---@field skill? Skill @可选配置来源，不要求技能正在使用
---@field baseDamage? number @已给定基础值，默认只应用元素克制
---@field power? number
---@field type? "physical"|"special"|"status"|"passive"
---@field element? ElementSet
---@field applyAttackModifiers? boolean @默认攻防公式启用、定值禁用；控制本系/浮动/暴击
---@field isCritical? boolean @显式判定结果；指定时不再抽取暴击随机数
---@field critChance? number @0～1，省略时使用技能配置或 1/16
---@field critChanceBonus? number @暴击概率加值，省略时读取来源精灵
---@field critResistance? number @0～1，省略时读取目标精灵
---@field randomRoll? integer @217～255，复现/预览可指定，不指定则使用局内随机源
---@class DamageCalculation
---@field type? string @计算类别，不表示一定发生了技能攻击
---@field power? number @实际代入公式的威力（含本次技能修正）
---@field baseDamage number @完整基础公式浮点结果，未提前截断
---@field element ElementSet
---@field effectivenessMultiplier number
---@field stabMultiplier number
---@field randomRoll integer
---@field varianceMultiplier number
---@field critChance number
---@field criticalRoll? number
---@field isCritical boolean
---@field critResistance number
---@field resistanceMultiplier number
---@field criticalMultiplier number
---@field afterTypeDamage integer
---@field afterVarianceDamage integer
---@field afterResistanceDamage integer
---@field damage integer @待结算伤害，不含护盾等事件阶段修正

local function finite(value, name)
  assert(type(value) == "number" and value == value and math.abs(value) < math.huge, "invalid " .. name)
  return value
end

local function probability(value, name)
  finite(value, name)
  assert(value >= 0 and value <= 1, name .. " must be between 0 and 1")
  return value
end

--- 技能、被动和场地效果共用的计算服务，不创建事件或修改精灵。
--- 普通红伤：完整基础式 → 本系/克制取整 → 浮动取整 → 暴击抗性取整 → 暴击。
function BattleController:calculateDamage(spec)
  local skill, from, to = spec.skill, spec.from, spec.to
  local kind = spec.type or (skill and skill.type)
  local base, formula = spec.baseDamage, spec.baseDamage == nil
  local power = spec.power or (skill and skill.power)
  if formula then
    finite(power, "damage power")
    assert(power >= 0, "damage power must be non-negative")
    if kind == "status" or kind == "passive" or power == 0 then
      base = 0
    else
      assert(kind == "physical" or kind == "special", "damage type must be physical or special")
      assert(from and to, "damage formula requires source and target")
      local attack = kind == "special" and from:getSpAtk() or from:getAtk()
      local defense = kind == "special" and to:getSpDef() or to:getDef()
      base = (2 * from.level / 5 + 2) * power * attack / math.max(1, defense) / 50 + 2
    end
  end
  finite(base, "base damage")
  assert(base >= 0, "base damage must be non-negative")

  local elements = spec.element or (skill and skill.element) or {}
  local copiedElements = { table.unpack(elements) }
  local targetElements = to and to:getElements()
  local effectiveness = 1
  if next(elements) then
    assert(to, "elemental damage requires a target")
    -- 兼容缺少元素的旧快照；有元素时使用严格单双属性规则。
    effectiveness = Element.getMultiplier(elements,
      targetElements and next(targetElements) and targetElements or { Element.Normal })
  end

  assert(spec.applyAttackModifiers == nil or type(spec.applyAttackModifiers) == "boolean",
    "applyAttackModifiers must be a boolean")
  assert(spec.isCritical == nil or type(spec.isCritical) == "boolean", "isCritical must be a boolean")
  local enabled = spec.applyAttackModifiers
  if enabled == nil then enabled = formula end
  assert(enabled or not spec.isCritical, "critical damage requires attack modifiers")
  local configuredChance = spec.critChance
  if configuredChance == nil then configuredChance = skill and skill.critChance end
  if configuredChance == nil then configuredChance = 1 / 16 end
  probability(configuredChance, "critChance")
  local bonus = spec.critChanceBonus
  if bonus == nil then bonus = from and from.critChanceBonus or 0 end
  finite(bonus, "critChanceBonus")
  local resistance = spec.critResistance
  if resistance == nil then resistance = to and to.critResistance or 0 end
  probability(resistance, "critResistance")
  if spec.randomRoll ~= nil then
    assert(math.type(spec.randomRoll) == "integer" and spec.randomRoll >= 217 and spec.randomRoll <= 255,
      "randomRoll must be an integer between 217 and 255")
  end

  local stab, chance = 1, 0
  local isCritical, criticalRoll, roll = false, nil, 255
  if enabled and base > 0 then
    stab = Element.getStabMultiplier(from and from:getElements(), elements)
    chance = math.max(0, math.min(1, configuredChance + bonus))
    if spec.isCritical ~= nil then
      isCritical = spec.isCritical
    elseif chance == 1 then
      isCritical = true
    elseif chance > 0 then
      criticalRoll = self.ctx:random()
      isCritical = criticalRoll < chance
    end
    roll = spec.randomRoll or self.ctx:random(217, 255)
  end
  local afterType = math.floor(base * stab * effectiveness)
  local afterVariance = math.floor(afterType * roll / 255)
  local appliedResistance = isCritical and resistance or 0
  local afterResistance = math.floor(afterVariance * (1 - appliedResistance))
  local criticalMultiplier = isCritical and 2 or 1
  local damage = math.max(0, math.floor(afterResistance * criticalMultiplier))
  return damage, { type = kind, power = formula and power or nil, baseDamage = base, element = copiedElements,
    effectivenessMultiplier = effectiveness, stabMultiplier = stab,
    randomRoll = roll, varianceMultiplier = roll / 255,
    critChance = chance, criticalRoll = criticalRoll, isCritical = isCritical,
    critResistance = resistance, resistanceMultiplier = 1 - appliedResistance, criticalMultiplier = criticalMultiplier,
    afterTypeDamage = afterType, afterVarianceDamage = afterVariance,
    afterResistanceDamage = afterResistance, damage = damage }
end

function BattleController:checkHit(from, skill)
  local accuracy = math.max(0, math.min(100, skill.accuracy * from.statStages:getMultiplier("accuracy")))
  return self.ctx:random(1, 100) <= accuracy
end

function BattleController:getSpeed(pet)
  return pet and pet:getSpeed() or 0
end

--- 只在确实需要托管时调用，合法选招不额外消耗随机数。
function BattleController:chooseDefaultAction(skills, targets)
  if #skills == 0 or #targets == 0 then return { type = "pass" } end
  local skill = skills[self.ctx:random(1, #skills)]
  local target = targets[self.ctx:random(1, #targets)]
  return { type = "skill", skillId = skill.id, targetId = target }
end

return BattleController
