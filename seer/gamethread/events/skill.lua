-- SPDX-License-Identifier: LGPL-2.1-or-later
local GameEvent = require "gamethread.gameevent"
require "seer.core.events"
local UseSkill = GameEvent:subclass("Seer.GameEvent.UseSkill")

function UseSkill:main()
  local logic, data = self.ctx.logic, self.data
  if not logic:canUseSkill(data.from, data.skill, data.to) then return false end
  -- 本次技能效果仅在这段结算的生命周期内有效；clear 在异常退出时也会清理。
  logic.skillUseStack[#logic.skillUseStack + 1] = data
  self.scoped = true
  if logic:trigger(sr.BeforeSkillUse, data.from, data) or data.prevented then return false end
  if not logic:canUseSkill(data.from, data.skill, data.to) then return false end
  data.skill.pp = data.skill.pp - 1
  data.actualDamage = 0
  data.damageEvent = nil
  self.ctx:broadcast("Seer.SkillUsing", {
    from = data.from.id, to = data.to.id, skillId = data.skill.id, pp = data.skill.pp,
  })
  local broken = logic:trigger(sr.SkillUsing, data.from, data)
  if not broken and not data.prevented and not self.ctx.gameFinished then self:resolveHit() end
  if self.hitResolved and not self.ctx.gameFinished then logic:trigger(sr.SkillEffectFinished, data.to, data) end
  if not self.ctx.gameFinished then logic:trigger(sr.SkillUseFinished, data.from, data) end
  return true
end

function UseSkill:resolveHit()
  local logic, data = self.ctx.logic, self.data
  if logic:trigger(sr.BeforeSkillHit, data.to, data) or data.prevented then return end
  if self.ctx.gameFinished then return end
  -- 效果可以显式指定 hit；未指定时才进行基础命中判定。
  if data.hit == nil then data.hit = logic.battleController:checkHit(data.from, data.skill) end
  if not data.hit then logic:trigger(sr.SkillMissed, data.to, data); return end
  self.hitResolved = true
  if logic:trigger(sr.SkillHit, data.to, data) or data.prevented then return end
  if self.ctx.gameFinished or data.from.stat.hp <= 0 or data.to.stat.hp <= 0 then return end
  if data.skill.type == "status" or data.skill.power <= 0 then return end
  if data.power == nil then data.power = data.skill.power end
  if logic:trigger(sr.BeforeSkillDamageCalculation, data.from, data) or data.prevented then return end
  if self.ctx.gameFinished or not data.from.alive or not data.to.alive then return end
  data.damage, data.calculation = logic:calculateDamage {
    from = data.from, skill = data.skill, to = data.to, power = data.power,
    isCritical = data.isCritical, critChance = data.critChance,
    critChanceBonus = data.critChanceBonus, critResistance = data.critResistance,
    randomRoll = data.randomRoll,
  }
  data.isCritical = data.calculation.isCritical
  if logic:trigger(sr.BeforeSkillDamage, data.to, data) or data.prevented then return end
  if not self.ctx.gameFinished then
    -- 技能流程持有攻击判定，Damage 只负责这一段数值的修正与提交。
    data.actualDamage, data.damageEvent = logic:damage { from = data.from, to = data.to,
      skill = data.skill, skillUse = data, calculation = data.calculation,
      damage = data.damage, damageType = sr.NormalDamage }
    -- 普通定威力技能先结算本次伤害，再清零对应防御等级；计算服务本身不改状态。
    if not self.ctx.gameFinished and data.actualDamage > 0 and data.calculation.isCritical and data.to.alive then
      local stat = data.calculation.type == "special" and "spdef" or "def"
      logic:resetStages { from = data.from, who = data.to, skill = data.skill,
        stats = { stat }, reason = sr.ReasonCriticalBreak }
    end
    if not self.ctx.gameFinished then logic:trigger(sr.AfterSkillDamage, data.to, data) end
  end
end

function UseSkill:clear()
  if self.scoped then table.remove(self.ctx.logic.skillUseStack) end
end
return UseSkill
