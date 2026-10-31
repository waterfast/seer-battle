-- SPDX-License-Identifier: LGPL-2.1-or-later
--- 玩家意图在 Logic 校验后转换为带实例引用的数据；时机不接收网络原文。
---@class PetSwitchData: TriggerData
---@field from Pet
---@field to Pet
---@field forced boolean?
---@field prevented boolean?
PetSwitchData = TriggerData:subclass("PetSwitchData")
local PetSwitchEvent = TriggerEvent:subclass("PetSwitchEvent")
for _, name in ipairs({ "BeforePetSwitch", "PetSwitchCancelled", "BeforePetLeave",
    "AfterPetLeave", "BeforePetEnter", "AfterPetEnter", "PetSwitchFinished" }) do
  sr[name] = PetSwitchEvent:subclass("sr." .. name)
end

---@class ItemUseData: TriggerData
---@field from Pet
---@field to Pet
---@field itemId integer
---@field prevented boolean?
ItemUseData = TriggerData:subclass("ItemUseData")
local ItemUseEvent = TriggerEvent:subclass("ItemUseEvent")
for _, name in ipairs({ "BeforeItemUse", "ItemUseCancelled", "ItemUsed", "AfterItemUse" }) do
  sr[name] = ItemUseEvent:subclass("sr." .. name)
end
