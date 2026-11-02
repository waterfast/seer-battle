-- SPDX-License-Identifier: GPL-3.0-or-later
-- 参考 seer-asio 的 battle/actions.lua、item.lua，适配当前事件栈。
local GameEvent = require "gamethread.gameevent"
require "seer.core.events"
local SwitchPet = GameEvent:subclass("Seer.GameEvent.SwitchPet")
function SwitchPet:main()
  local logic, data = self.ctx.logic, self.data
  if not logic:canSwitchPet(data.from, data.to) then return false end
  local blocked = logic:trigger(sr.BeforePetSwitch, data.from, data)
  if (blocked or data.prevented) and not data.forced then
    logic:trigger(sr.PetSwitchCancelled, data.from, data)
    return false
  end
  -- 前置效果可能嵌套结算，提交前复查出战位置和目标存活。
  if not logic:canSwitchPet(data.from, data.to) then return false end
  logic:trigger(sr.BeforePetLeave, data.from, data)
  if not logic:canSwitchPet(data.from, data.to) then return false end
  -- 旧宠的离场监听仍从旧宠收集；切换位置后才启用新宠的入场效果。
  logic:trigger(sr.AfterPetLeave, data.from, data)
  if not logic:canSwitchPet(data.from, data.to) then return false end
  logic:clearSwitchBuffs(data.from)
  if not logic:canSwitchPet(data.from, data.to) then return false end
  local changes = {}
  for name, stage in pairs(data.from.statStages:toTable()) do
    if stage ~= 0 then changes[name] = -stage end
  end
  data.from.statStages:reset()
  if next(changes) then
    self.ctx:broadcast("Seer.StagesChanged", { id = data.from.id, reason = sr.ReasonStageChange,
      cause = "switch", changes = changes, stages = data.from.statStages:toTable() })
  end
  data.from.player.pet = data.to
  logic:trigger(sr.BeforePetEnter, data.to, data)
  logic:trigger(sr.AfterPetEnter, data.to, data)
  self.ctx:broadcast("Seer.PetSwitched", { from = data.from.id, to = data.to.id, forced = data.forced == true })
  logic:trigger(sr.PetSwitchFinished, data.to, data)
  return true
end
local UseItem = GameEvent:subclass("Seer.GameEvent.UseItem")
function UseItem:main()
  local logic, data = self.ctx.logic, self.data
  if not logic:canUseItem(data.from, data.itemId, data.to) then return false end
  if logic:trigger(sr.BeforeItemUse, data.from, data) or data.prevented then
    logic:trigger(sr.ItemUseCancelled, data.from, data)
    return false
  end
  if not logic:canUseItem(data.from, data.itemId, data.to) then return false end
  local bag = data.from.player.bag
  local item = logic:getItemDefinition(data.itemId)
  -- 先扣库存再进入子事件，防止嵌套使用重复消耗；禁疗不退还药品。
  bag.items[data.itemId] = bag.items[data.itemId] - 1
  logic:trigger(sr.ItemUsed, data.from, data)
  if item.kind == "heal" then
    data.actual = logic:recover { from = data.from, who = data.to, num = item.amount }
  else
    for _, skill in ipairs(data.to.skills) do
      skill.pp = math.min(skill.maxPp, skill.pp + item.amount)
    end
  end
  local skills = {}
  for _, skill in ipairs(data.to.skills) do skills[#skills + 1] = { id = skill.id, pp = skill.pp } end
  self.ctx:broadcast("Seer.ItemUsed", { from = data.from.id, to = data.to.id,
    itemId = data.itemId, count = bag.items[data.itemId], skills = skills })
  logic:trigger(sr.AfterItemUse, data.from, data)
  return true
end
return { SwitchPet = SwitchPet, UseItem = UseItem }
