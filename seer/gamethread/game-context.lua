-- SPDX-License-Identifier: LGPL-2.1-or-later
local ServerGameContext = require "gamethread.game-context"

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
function SeerGameContext:addBuff(data)
  return self.logic:addBuff(data)
end
function SeerGameContext:applyAbnormal(data)
  return self.logic:applyAbnormal(data)
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
function SeerGameContext:switchPet(data)
  return self.logic:switchPet(data)
end
function SeerGameContext:useItem(data)
  return self.logic:useItem(data)
end
return SeerGameContext
