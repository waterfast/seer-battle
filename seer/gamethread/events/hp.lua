-- SPDX-License-Identifier: LGPL-2.1-or-later
local GameEvent = require "gamethread.gameevent"
require "seer.core.events"

local ChangeHp = GameEvent:subclass("Seer.GameEvent.ChangeHp")
function ChangeHp:main()
  local logic, data = self.ctx.logic, self.data
  if logic:trigger(sr.BeforeHpChanged, data.who, data) or data.prevented then
    data.prevented, data.num = true, 0
    return 0
  end
  local who = data.who
  local old = who.stat.hp
  who.stat.hp = math.max(0, math.min(who.stat.maxHp, old + data.num))
  who.alive = who.stat.hp > 0
  data.num = who.stat.hp - old
  self.ctx:broadcast("Seer.HpChanged", { id = who.id, hp = who.stat.hp, maxHp = who.stat.maxHp, alive = who.alive })
  logic:trigger(sr.HpChanged, who, data)
  if old > 0 and who.stat.hp == 0 then logic:trigger(sr.PetFainted, who, data) end
  return data.num
end

local Damage = GameEvent:subclass("Seer.GameEvent.Damage")
function Damage:main()
  local logic, data = self.ctx.logic, self.data
  data.actualDamage = 0
  local stages = {
    { sr.PreDamage, data.to }, { sr.DamageCaused, data.from },
    { sr.DetermineDamageCaused, data.from }, { sr.DamageInflicted, data.to },
    { sr.DetermineDamageInflicted, data.to },
  }
  for _, stage in ipairs(stages) do
    if data.prevented or data.damage <= 0 or self.ctx.gameFinished then break end
    if logic:trigger(stage[1], stage[2], data) then data:preventDamage() end
  end
  if not self.ctx.gameFinished and not data.prevented and data.damage > 0 and data.to.stat.hp > 0 then
    local changed = logic:changeHp {
      who = data.to, num = -data.damage, reason = "damage", damageEvent = data,
    }
    data.actualDamage = math.max(0, -changed)
    if data.actualDamage > 0 then
      logic:trigger(sr.Damage, data.from, data)
      logic:trigger(sr.Damaged, data.to, data)
    end
  end
  if not self.ctx.gameFinished then logic:trigger(sr.DamageFinished, data.to, data) end
  return data.actualDamage
end

local Recover = GameEvent:subclass("Seer.GameEvent.Recover")
function Recover:main()
  local logic, data = self.ctx.logic, self.data
  if logic:trigger(sr.PreHpRecover, data.who, data) or data.prevented then return 0 end
  -- 普通回复不复活；将来复活机制应单独定义。
  if data.who.stat.hp <= 0 then return 0 end
  data.num = math.min(data.num, data.who.stat.maxHp - data.who.stat.hp)
  if data.num <= 0 then return 0 end
  data.actualRecover = logic:changeHp { who = data.who, num = data.num, reason = "recover" }
  if data.actualRecover > 0 then logic:trigger(sr.HpRecover, data.who, data) end
  return data.actualRecover
end

local LoseHp = GameEvent:subclass("Seer.GameEvent.LoseHp")
function LoseHp:main()
  local logic, data = self.ctx.logic, self.data
  if logic:trigger(sr.PreHpLost, data.who, data) or data.prevented then return 0 end
  if data.num <= 0 then return 0 end
  data.actualLost = math.max(0, -logic:changeHp { who = data.who, num = -data.num, reason = "loseHp" })
  if data.actualLost > 0 then logic:trigger(sr.HpLost, data.who, data) end
  return data.actualLost
end
return { ChangeHp = ChangeHp, Damage = Damage, Recover = Recover, LoseHp = LoseHp }
