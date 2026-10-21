-- SPDX-FileCopyrightText: 2026 Notify Ctrl <notify-ctrl@qq.com>
-- SPDX-License-Identifier: LGPL-2.1-or-later
---
--[[
精灵，赛尔号战斗中的基本作战单位，继承自 GameUnit。
--]]
local GameUnit = require "core.gameunit"
local Stat = require "seer.core.stat"
local StatStages = require "seer.core.stat-stages"

---@class Pet: GameUnit
---@field ctx GameContextBase @游戏上下文
---@field pet_id integer @精灵id，识别精灵的唯一字符，与unitid不同，unitid是游戏单位的唯一标识符，petid是精灵的唯一标识符
---@field name string @精灵名称
---@field stat Stat @未应用能力等级的面板及当前体力
---@field statStages StatStages @战斗中的能力等级
---@field alive boolean @是否存活，体力结算时同步
---@field level? integer @等级
---@field nature? integer @性格
---@field iv  integer @个体值 1-31
---@field skills Skill[] @精灵拥有的普通技能
---@field fifth_skill? Skill @精灵拥有的第五技能
---@field player ServerPlayer @控制该精灵的角色
---@field effects TriggerEffect[] @被动等持续效果
---@field element ElementType[] @元素属性,为支持双属性为表
---@field buffs Buff[] @精灵身上的buff，可能是debuff，我们统称为buff
local Pet = GameUnit:subclass("Pet")


--- 构造函数，不可随意调用。
---@param ctx GameContextBase
---@param pet_id integer 精灵id，识别精灵的唯一字符，与unitid不同，unitid是游戏单位的唯一标识符，petid是精灵的唯一标识符
---@param name string 精灵名称
---@param id integer 游戏单位id，唯一标识符
function Pet:initialize(ctx, pet_id, name, id)
    GameUnit.initialize(self, ctx, id, name)
    self.stat = Stat:new()
    self.statStages = StatStages:new()
    self.pet_id = pet_id
    self.alive = true
end


--- PetBattleData 描述精灵战斗属性的数据
---@class PetBattleData
---@field stat? Stat @可选嵌套面板；提供时优先于旧的平铺字段
---@field level integer @等级
---@field element ElementType[]  @元素属性,为支持双属性为表
---@field atk integer @攻击力
---@field def integer @防御力
---@field spatk integer @特殊攻击
---@field spdef integer @特殊防御
---@field speed integer @速度
---@field hp integer @当前体力值
---@field maxHp integer @体力上限
---@field nature integer @性格
---@field iv integer @个体值 1-31
---@field skills Skill[] @精灵拥有的普通技能
---@field fifth_skill? Skill @精灵拥有的第五技能
---@param data PetBattleData 根据战斗数据为精灵设置属性
function Pet:setup(data)
    self.stat = Stat:new(data.stat or data)
    self.statStages:reset()
    self.level = data.level
    self.alive = self.stat.hp > 0
    self.nature = data.nature
    self.iv = data.iv
    self.skills = data.skills
    self.fifth_skill = data.fifth_skill
    self.element = data.element
end

--- 获取精灵等级
---@return integer?
function Pet:getLevel()
    return self.level
end

--- 获取当前体力
---@return integer?
function Pet:getHp()
    return self.stat.hp
end

--- 获取最大体力
---@return integer?
function Pet:getMaxHp()
    return self.stat.maxHp
end

--- 获取攻击力
---@return integer?
function Pet:getAtk()
    return self:getStat("atk")
end

--- 获取防御力
---@return integer?
function Pet:getDef()
    return self:getStat("def")
end

--- 获取特殊攻击
---@return integer?
function Pet:getSpAtk()
    return self:getStat("spatk")
end

--- 获取特殊防御
---@return integer?
function Pet:getSpDef()
    return self:getStat("spdef")
end

--- 获取速度
---@return integer?
function Pet:getSpeed()
    return self:getStat("speed")
end

--- 获取性格
---@return integer?
function Pet:getNature()
    return self.nature
end

--- 获取个体值
---@return integer?
function Pet:getIv()
    return self.iv
end

--- 获取精灵元素属性
---@return ElementType[]?
function Pet:getElements()
    return self.element
end



--- 获取精灵技能列表
---@param includeFifth? boolean 是否包含第五技能，默认 false
---@return Skill[]
function Pet:getSkills(includeFifth)
    local result = {}

    for _, skill in ipairs(self.skills or {}) do
        result[#result + 1] = skill
    end

    if includeFifth and self.fifth_skill then
        result[#result + 1] = self.fifth_skill
    end

    return result
end

--- 获取第五技能
---@return Skill?
function Pet:getFifthSkill()
    return self.fifth_skill
end


--- 获取应用能力等级后的能力值，不回写原始面板，避免反复强化造成累乘。
---@param name string
---@return number
function Pet:getStat(name)
    local value = self.stat:get(name)
    if name == "hp" or name == "maxHp" then return value end
    return math.max(1, math.floor(value * self.statStages:getMultiplier(name)))
end

return Pet
