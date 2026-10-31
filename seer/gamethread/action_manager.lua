-- SPDX-License-Identifier: LGPL-2.1-or-later
local Events = require "seer.gamethread.events.action"
local items = require "packages.standard.items"
local Actions = {}
function Actions:getItemDefinition(id)
  return items[id]
end
function Actions:canSwitchPet(from, to)
  return not self.ctx.gameFinished and to ~= nil and from.player.pet == from
    and from.player.bag:getPet(to.id) == to and to ~= from and to.alive and to.stat.hp > 0
end
function Actions:canUseItem(from, itemId, to)
  local item = self:getItemDefinition(itemId)
  if self.ctx.gameFinished or not item or not to then return false end
  if from.player.pet ~= from or not from.alive or not to.alive then return false end
  if from.player.bag:getPet(to.id) ~= to or not from.player.bag:hasItem(itemId) then return false end
  if item.kind == "heal" then return to.stat.hp < to.stat.maxHp end
  for _, skill in ipairs(to.skills) do
    if skill.pp < skill.maxPp then return true end
  end
  return false
end
--- 网络边界只解析编号，不接受客户端指定数量、恢复量和实例。
function Actions:selectSpecialAction(action, reply)
  if type(reply) ~= "table" or not self:canAct(action.who) then return false end
  local to = action.who.bag:getPet(reply.targetId)
  if reply.type == "switch" and self:canSwitchPet(action.from, to) then
    action.type, action.to = "switch", to
    return true
  end
  if reply.type == "item" and self:canUseItem(action.from, reply.itemId, to) then
    action.type, action.to, action.itemId = "item", to, reply.itemId
    return true
  end
  return false
end
function Actions:switchPet(spec)
  return self:executeEvent(Events.SwitchPet, PetSwitchData:new(spec))
end
function Actions:useItem(spec)
  return self:executeEvent(Events.UseItem, ItemUseData:new(spec))
end
--- 补位是规则动作，不占下一轮行动；当前按背包顺序选择。
function Actions:replaceFaintedPets()
  for _, player in ipairs(self.ctx.players) do
    if not player.pet.alive then
      local replacement = player.bag:getAlivePets()[1]
      if replacement then self:switchPet { from = player.pet, to = replacement, forced = true } end
    end
  end
end
--- 将当前合法特殊行动显式告知客户端；没有技能时仍可选择换宠或用药。
function Actions:getSpecialChoices(player)
  local choices = {}
  for _, pet in ipairs(player.bag.pets) do
    if self:canSwitchPet(player.pet, pet) then
      choices[#choices + 1] = { type = "switch", targetId = pet.id }
    end
    for id in pairs(items) do
      if self:canUseItem(player.pet, id, pet) then
        choices[#choices + 1] = { type = "item", targetId = pet.id, itemId = id }
      end
    end
  end
  return choices
end
return Actions
