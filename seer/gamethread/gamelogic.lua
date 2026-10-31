-- SPDX-License-Identifier: LGPL-2.1-or-later
-- 参考新月杀启动步骤与 Round/Turn 分层，按本项目接口独立实现。
local GameLogic = require "gamethread.gamelogic"
local InteractiveRequest = require "gamethread.interactive-request"
local GameFlowEvents = require "seer.gamethread.events.gameflow"
local UseSkill = require "seer.gamethread.events.skill"
local HpEvents = require "seer.gamethread.events.hp"
require "seer.core.events"
local Pet = require "seer.core.pet"
local Bag = require "seer.core.bag"
local BuffManager = require "seer.gamethread.buff.buff_manager"
local StatStageManager = require "seer.gamethread.statStage.statstage_manager"
local BattleController = require "seer.gamethread.battle_controller"

---@class PlayerBattleData
---@field pets PetImportData[]
---@field items table<integer, integer>?
---@field activePetId integer? @首发精灵的本局单位编号，省略时取第一只存活精灵

---@class PetImportData: PetBattleData
---@field id integer
---@field pet_id integer
---@field name string
---@field skills integer[] @导入的是编号，createPet 再创建技能实例

---@class ServerPlayer
---@field bag Bag
---@field pet Pet? @当前出战精灵；其余精灵保存在 bag 中

---@class Seer.GameLogic: GameLogic
local SeerGameLogic = GameLogic:subclass("Seer.GameLogic")
function SeerGameLogic:initialize(ctx)
  GameLogic.initialize(self, ctx)
  self.roundNumber = 0
  self.battleController = BattleController:new(ctx)
  -- 当前技能的临时效果范围；嵌套使用技能结束后恢复外层技能。
  self.skillUseStack = {}
end

function SeerGameLogic:run()
  self:prepareRoom()
  self:loadRoleData()
  self:prepareForStart()
  self:action()
end

function SeerGameLogic:prepareRoom()
  assert(#self.ctx.players >= 2, "Seer needs at least two players")
  -- 首版保留房间顺序；座位和速度排序是不同概念。
  self.ctx:arrangeSeats()
end

--- 从 sr 中的技能定义创建本局实例，PP 不与其他精灵共用。
function SeerGameLogic:createSkills(ids)
  local skills = {}
  for _, id in ipairs(ids) do
    local skill = sr:createSkill(id)
    skills[#skills + 1] = skill
  end
  return skills
end

--- 创建实例不读取数据库、网络或原始 battleData。
function SeerGameLogic:createPet(player, data)
  local pet = Pet:new(self.ctx, data.pet_id, data.name, data.id)
  pet:setup(data)
  pet.skills = self:createSkills(data.skills)
  pet.player = player
  pet.effects = {}
  pet.buffs = {}
  return pet
end

---@param player ServerPlayer
---@param data PlayerBattleData
---@return Bag
function SeerGameLogic:createBag(player, data)
  local pets = {}
  for _, petData in ipairs(data.pets) do
    pets[#pets + 1] = self:createPet(player, petData)
  end
  return Bag:new(player, pets, data.items)
end

--- 只负责装配角色、背包和当前出战精灵，数据来源交给 ctx 的接口。
function SeerGameLogic:loadRoleData()
  self.ctx.pets = {}
  for _, player in ipairs(self.ctx.players) do
    local data = self.ctx:getPlayerBattleData(player)
    player.bag = self:createBag(player, data)
    if data.activePetId then
      player.pet = player.bag:getPet(data.activePetId)
    else
      player.pet = player.bag:getAlivePets()[1]
    end
    -- ctx.pets 是本局全部精灵的查询索引，不代表全部都已上场。
    for _, pet in ipairs(player.bag.pets) do
      self.ctx.pets[#self.ctx.pets + 1] = pet
    end
  end
end

function SeerGameLogic:prepareForStart()
  local pets = {}
  for _, pet in ipairs(self.ctx.pets) do
    local skills = {}
    for _, skill in ipairs(pet.skills) do
      skills[#skills + 1] = { id = skill.id, name = skill.name, pp = skill.pp, maxPp = skill.maxPp }
    end
    pets[#pets + 1] = { id = pet.id, pet_id = pet.pet_id, playerId = pet.player.id,
      name = pet.name, hp = pet.stat.hp, maxHp = pet.stat.maxHp, alive = pet.alive,
      active = pet.player.pet == pet, skills = skills }
  end
  self.ctx:broadcast("Seer.BattleReady", { pets = pets })
  self:trigger(sr.GameStart, nil, {})
end

function SeerGameLogic:action()
  local limit = self.ctx.battleData.maxRounds or 999
  while not self.ctx.gameFinished do
    if self:checkGameOver() then return end
    if self.roundNumber >= limit then self.ctx:gameOver(); return end
    self.roundNumber = self.roundNumber + 1
    local data = RoundData:new {
      number = self.roundNumber, turn_table = { table.unpack(self.ctx.players) },
    }
    self:executeEvent(GameFlowEvents.Round, data)
    self:checkGameOver()
  end
end

function SeerGameLogic:canAct(player)
  return player.pet and player.pet.alive and player.pet.stat.hp > 0
end

function SeerGameLogic:checkGameOver()
  if self.ctx.gameFinished then return true end
  local alive = {}
  for _, player in ipairs(self.ctx.players) do
    if #player.bag:getAlivePets() > 0 then alive[#alive + 1] = player.id end
  end
  if #alive <= 1 then
    self.ctx:gameOver({ winners = alive })
    return true
  end
  return false
end

--- 所有人都提交行动以后才进入执行阶段。
function SeerGameLogic:chooseActions()
  local ctx = self.ctx
  local actions, participants, choices = {}, {}, {}

  for _, player in ipairs(ctx.players) do
    local action = ActionData:new { who = player, from = player.pet, type = "pass" }
    actions[#actions + 1] = action
    local broken = self:trigger(sr.BeforeActionChoice, player.pet, action)
    if broken then action.prevented = true end
    if self:canAct(player) and not action.prevented then
      local skills, targets = self:getSkillChoices(player.pet)
      local specialChoices = self:getSpecialChoices(player)
      if (skills[1] and targets[1]) or #specialChoices > 0 then
        local pets, inventory = {}, {}
        for id, count in pairs(player.bag.items) do
          inventory[#inventory + 1] = { itemId = id, count = count }
        end
        for _, pet in ipairs(player.bag:getAlivePets()) do pets[#pets + 1] = pet.id end
        participants[#participants + 1] = player
        choices[player.id] = { petId = player.pet.id, round = self.roundNumber, skills = skills, targets = targets,
          pets = pets, items = inventory, actions = specialChoices }
      end
    end
  end

  if ctx.gameFinished then return actions end
  local request
  if #participants > 0 then
    request = InteractiveRequest:new(participants, "Seer.ChooseAction")
    request.timeout = ctx.battleData.actionTimeout or 30 -- 秒；计时及迟到回复隔离由宿主 requestSocket 负责。
    for _, player in ipairs(participants) do request:setData(player, choices[player.id]) end
    request:ask()
  end
  if ctx.gameFinished then return actions end
  for _, action in ipairs(actions) do
    if not action.prevented then
      local reply = request and request.result[action.who.id]
      local special = self:selectSpecialAction(action, reply)
      local skill, target = self:getSelectedSkill(action.who, reply)
      if not special and not skill and not (type(reply) == "table" and reply.type == "pass") then
        if self:canAct(action.who) then
          local skills, targets = self:getSkillChoices(action.who.pet)
          local fallback = self.battleController:chooseDefaultAction(skills, targets)
          skill, target = self:getSelectedSkill(action.who, fallback)
        end
      end
      if skill then
        action.type = "skill"
        action.skill = skill
        action.to = target
      end
      local broken = self:trigger(sr.AfterActionChoice, action.from, action)
      if broken then action.prevented = true end
    end
  end
  return actions
end

--- 先制优先，其次速度；相同时暂按座位，便于首版调试。
function SeerGameLogic:sortActions(actions)
  table.sort(actions, function(a, b)
    -- 行动类别先于技能先制比较，避免用魔法先制值挤占技能的取值范围。
    local aSpecial = a.type == "switch" or a.type == "item"
    local bSpecial = b.type == "switch" or b.type == "item"
    if aSpecial ~= bSpecial then return aSpecial end
    local aPriority = a.skill and a.skill.priority or 0
    local bPriority = b.skill and b.skill.priority or 0
    if aPriority ~= bPriority then
      return aPriority > bPriority
    end
    local aSpeed = self.battleController:getSpeed(a.from)
    local bSpeed = self.battleController:getSpeed(b.from)
    if aSpeed ~= bSpeed then
      return aSpeed > bSpeed
    end
    return a.who.seat < b.who.seat
  end)
end

function SeerGameLogic:playTurn(turn)
  local action = turn.action
  if action.prevented or action.who.pet ~= action.from then return end
  if action.type == "switch" then self:switchPet(action); return end
  if action.type == "item" then self:useItem(action); return end
  if action.type ~= "skill" then return end
  -- 技能瞄准对方出战位置，换宠后命中新上场者。
  action.to = action.to.player.pet
  if self:canUseSkill(action.from, action.skill, action.to) then
    self:useSkill { from = action.from, to = action.to, skill = action.skill }
  end
end

function SeerGameLogic:getSkillChoices(pet)
  local skills, targets = {}, {}
  for _, skill in ipairs(pet.skills) do
    if skill.type ~= "passive" and skill.pp > 0 then
      skills[#skills + 1] = { id = skill.id, name = skill.name, pp = skill.pp }
    end
  end
  for _, player in ipairs(self.ctx.players) do
    if player ~= pet.player and self:canAct(player) then
      targets[#targets + 1] = player.pet.id
    end
  end
  return skills, targets
end

--- 请求只给出编号，实际技能与目标从当前战斗中取得。
function SeerGameLogic:getSelectedSkill(player, reply)
  if not self:canAct(player) then return end
  if type(reply) ~= "table" or reply.type ~= "skill" then return end
  local target = self.ctx:getPet(reply.targetId)
  for _, skill in ipairs(player.pet.skills) do
    if skill.id == reply.skillId and self:canUseSkill(player.pet, skill, target) then
      return skill, target
    end
  end
end

function SeerGameLogic:canUseSkill(from, skill, to)
  if self.ctx.gameFinished or not from or not skill or not to then return false end
  if from.player.pet ~= from or to.player.pet ~= to or from.player == to.player then return false end
  if skill.type == "passive" then return false end
  if not from.alive or not to.alive or from.stat.hp <= 0 or to.stat.hp <= 0 or skill.pp <= 0 then return false end
  for _, owned in ipairs(from.skills) do if owned == skill then return true end end
  return false
end

-- 保留业务入口，计算细节交给 controller，效果和旧调用方无需改接口。
function SeerGameLogic:calculateDamage(from, skill, to)
  return self.battleController:calculateDamage(from, skill, to)
end

function SeerGameLogic:collectEffects()
  local entries = GameLogic.collectEffects(self)
  local function append(effects, owner)
    for _, effect in ipairs(effects or {}) do
      effect.owner = owner
      entries[#entries + 1] = { effect = effect, owner = owner }
    end
  end
  for _, player in ipairs(self.ctx.players) do
    local pet = player.pet
    if pet then
      append(pet.effects, pet)
      for _, buff in ipairs(pet.buffs) do
        if not buff:isExpired() then append(buff.effects, pet) end
      end
    end
  end
  -- 只加入最内层正在使用的技能，未使用的普通技能不会常驻监听。
  local use = self.skillUseStack[#self.skillUseStack]
  if use then append(use.skill.effects, use.from) end
  return entries
end

function SeerGameLogic:useSkill(spec)
  return self:executeEvent(UseSkill, SkillUseData:new(spec))
end
function SeerGameLogic:damage(spec)
  return self:executeEvent(HpEvents.Damage, DamageData:new(spec))
end
function SeerGameLogic:recover(spec)
  return self:executeEvent(HpEvents.Recover, RecoverData:new(spec))
end
function SeerGameLogic:loseHp(spec)
  return self:executeEvent(HpEvents.LoseHp, HpLostData:new(spec))
end
function SeerGameLogic:changeHp(spec)
  return self:executeEvent(HpEvents.ChangeHp, HpChangedData:new(spec))
end
-- 按功能拆分业务入口；事件仍由同一个 Logic 执行，保留统一事件栈和触发栈。
SeerGameLogic:include(BuffManager, StatStageManager, (require "seer.gamethread.action_manager"))
return SeerGameLogic
