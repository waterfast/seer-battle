-- SPDX-License-Identifier: LGPL-2.1-or-later
local ServerGameContext = require "gamethread.game-context"
local Abnormal = require "seer.core.abnormal"

---@class Seer.GameContext: ServerGameContext
---@field battleData table 宿主提供的可信战斗快照，不从选招请求中读取
---@field logic Seer.GameLogic
local SeerGameContext = ServerGameContext:subclass("Seer.GameContext")
function SeerGameContext:initialize(boardgame, data)
  ServerGameContext.initialize(self, boardgame, data)
  self.battleData = data.battleData or {}
  self.pets = {}
end

function SeerGameContext:getPet(id)
  for _, pet in ipairs(self.pets) do if pet.id == id then return pet end end
end

--- 临时数据来源接口。以后接数据库或宿主导入时替换此方法，不改实例创建流程。
---@param player ServerPlayer
---@return PlayerBattleData
function SeerGameContext:getPlayerBattleData(player)
  return self.battleData.players[player.id]
end

-- 业务入口留在 ctx，完整结算交给 Logic 和对应 GameEvent。
function SeerGameContext:useSkill(data)
  return self.logic:useSkill(data)
end
---@param spec DamageCalculationSpec
---@return integer damage
---@return DamageCalculation calculation
function SeerGameContext:calculateDamage(spec)
  return self.logic:calculateDamage(spec)
end
---@param data DamageDataSpec
---@return integer actualDamage
---@return DamageData damageEvent
function SeerGameContext:damage(data)
  return self.logic:damage(data)
end
function SeerGameContext:recover(data)
  return self.logic:recover(data)
end
function SeerGameContext:loseHp(data)
  return self.logic:loseHp(data)
end
function SeerGameContext:changeHp(data)
  return self.logic:changeHp(data)
end
function SeerGameContext:getBuff(who, id, includeExpired)
  return self.logic:getBuff(who, id, includeExpired)
end
function SeerGameContext:getAbnormals(who, category) return self.logic:getAbnormals(who, category) end
function SeerGameContext:getAbnormal(who, kind) return self.logic:getAbnormal(who, kind) end
function SeerGameContext:hasAbnormal(who, kind) return self.logic:hasAbnormal(who, kind) end
function SeerGameContext:addBuff(data)
  return self.logic:addBuff(data)
end
function SeerGameContext:applyAbnormal(data)
  return self.logic:applyAbnormal(data)
end
---@class InflictAbnormalSpec
---@field who Pet
---@field from? Pet
---@field buff? integer @异常配置 ID，与 kind 二选一
---@field kind? string @异常身份；多个配置使用同一身份时必须指定 buff ID
---@field chance? number @成功率，默认 1；0～1
---@field turns? integer @固定轮数；与随机范围二选一
---@field minTurns? integer @随机范围下界，需与 maxTurns 一起提供
---@field maxTurns? integer @随机范围上界；不指定轮数时默认 2～3
---@field skill? Skill

--- 技能/魂印共用的施加入口；随机只走局内 RNG，成功后进入完整异常管道。
---@param spec InflictAbnormalSpec
---@return boolean added
function SeerGameContext:inflictAbnormal(spec)
  local allowed = { who=true, from=true, buff=true, kind=true, chance=true,
    turns=true, minTurns=true, maxTurns=true, skill=true }
  for key in pairs(spec) do assert(allowed[key], "unknown abnormal application field: " .. tostring(key)) end
  Abnormal.validateApplication(spec)
  assert((spec.buff ~= nil) ~= (spec.kind ~= nil), "choose abnormal buff id or kind")
  assert(spec.who and spec.who.ctx == self and spec.who.player and type(spec.who.buffs) == "table",
    "abnormal target must be a pet in this battle")
  local definition
  if spec.buff ~= nil then
    assert(math.type(spec.buff) == "integer", "abnormal buff must be an integer id")
    definition = assert(sr:getAbnormal(spec.buff), "unknown abnormal id: " .. tostring(spec.buff))
  else
    assert(type(spec.kind) == "string", "abnormal kind must be a string")
    for _, candidate in pairs(sr.abnormals) do
      if candidate.abnormalKind == spec.kind then
        assert(not definition, "ambiguous abnormal kind; specify buff id: " .. spec.kind)
        definition = candidate
      end
    end
    assert(definition, "unknown abnormal kind: " .. spec.kind)
  end
  if self.gameFinished or not spec.who.alive then return false end
  local chance = spec.chance == nil and 1 or spec.chance
  if chance == 0 or (chance < 1 and self:random() >= chance) then return false end
  local turns = spec.turns
  if turns == nil then
    local low, high = spec.minTurns or 2, spec.maxTurns or 3
    turns = low == high and low or self:random(low, high)
  end
  return self:applyAbnormal { from=spec.from, who=spec.who, buff=definition.id,
    state={turn=turns}, skill=spec.skill }
end

function SeerGameContext:removeBuff(data)
  return self.logic:removeBuff(data)
end
function SeerGameContext:changeStages(data)
  return self.logic:changeStages(data)
end
function SeerGameContext:strengthen(data)
  return self.logic:strengthen(data)
end
function SeerGameContext:weaken(data)
  return self.logic:weaken(data)
end
function SeerGameContext:clearBoosts(data)
  return self.logic:clearBoosts(data)
end
function SeerGameContext:resetStages(data)
  return self.logic:resetStages(data)
end
function SeerGameContext:switchPet(data)
  return self.logic:switchPet(data)
end
function SeerGameContext:useItem(data)
  return self.logic:useItem(data)
end
return SeerGameContext
