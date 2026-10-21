-- SPDX-License-Identifier: LGPL-2.1-or-later
-- 只负责计算，不派发事件、不消耗 PP、不直接改体力。
local BattleController = kt.class("Seer.BattleController")

function BattleController:initialize(ctx)
  self.ctx = ctx
end

--- Pet 的能力接口已应用能力等级；公式层不再重复乘倍率。
function BattleController:calculateDamage(from, skill, to)
  if skill.type == "status" or skill.type == "passive" or skill.power <= 0 then return 0 end
  local attack = skill.type == "special" and from:getSpAtk() or from:getAtk()
  local defense = skill.type == "special" and to:getSpDef() or to:getDef()
  return math.max(1, math.floor((2 * from.level / 5 + 2) * skill.power * attack / math.max(1, defense) / 50) + 2)
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
