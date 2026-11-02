-- SPDX-License-Identifier: LGPL-2.1-or-later
local Engine = require "core.engine"
local Buff = require "seer.core.buff"
local BuffType = require "seer.core.buff.type"
local Abnormal = require "seer.core.abnormal"
local Skill = require "seer.core.skill"
local Effect = require "seer.core.effect"
local TriggerSkeleton = require "seer.core.effect_type.trigger_skeleton"
local EffectSkeleton = require "seer.core.effect_skeleton"
local References = require "seer.core.csv_util.effects"

---@class SeerEngine: Engine
---@field skills table<integer, table> @CSV 普通配置表，不保存本局 PP
---@field buffs table<integer, table> @CSV 普通配置表，不保存轮数、次数等局内状态
---@field abnormals table<integer, table> @异常静态定义索引，与 buffs 中的定义相同
---@field effects table<integer, EffectSkeleton> @共享骨架；实际 Effect 在局内创建
---@field packages table<integer, SeerPackage>
local SeerEngine = Engine:subclass("SeerEngine")

local function checkDefinition(definition)
    assert(type(definition) == "table" and math.type(definition.id) == "integer",
        "definition must have an integer id")
end

function SeerEngine:initialize()
    Engine.initialize(self)
    self.skills, self.buffs, self.effects, self.packages = {}, {}, {}, {}
    self.translations = {}
    self.abnormals = {}
end

-- 直接注册用于测试或手动装配，保留原 registerSkill 的覆盖行为。
function SeerEngine:registerSkill(definition)
    checkDefinition(definition)
    self.skills[definition.id] = definition
end

function SeerEngine:registerBuff(definition)
    checkDefinition(definition)
    if definition.type == BuffType.Abnormal then Abnormal.validateDefinition(definition) end
    self.buffs[definition.id] = definition
    self.abnormals[definition.id] = definition.type == BuffType.Abnormal and definition or nil
end

function SeerEngine:registerEffect(definition)
    checkDefinition(definition)
    assert(definition.isInstanceOf and definition:isInstanceOf(EffectSkeleton), "effects registry requires skeletons")
    self.effects[definition.id] = definition
end

--- 从普通静态配置创建局内技能。默认值由 Skill 类统一提供。
---@param id integer
---@return Skill
function SeerEngine:createSkill(id)
    local definition = assert(self:getSkill(id), "unknown skill: " .. tostring(id))
    local skill = Skill:new(id, definition.name)
    for _, key in ipairs({ "power", "priority", "type", "accuracy", "hits", "critChance" }) do
        if definition[key] ~= nil then skill[key] = definition[key] end
    end
    -- 保留终端测试旧数据入口；CSV 统一使用 type 和 maxPp。
    skill.type = definition.type or definition.category or skill.type
    skill.maxPp = definition.maxPp or definition.pp or 20
    skill.pp = skill.maxPp
    skill.element = { table.unpack(definition.element or {}) }
    skill.effects = self:resolveEffects(definition.effects, skill)
    return skill
end

---@class EffectSkeletonSpec
---@field id integer
---@field name? string
---@field type? EffectType @默认 Effect.Trigger
---@field event TriggerEvent
---@field priority? number
---@field can_trigger? fun(effect: TriggerEffect, event: TriggerEvent, target: GameUnit?, owner: GameUnit?, data: any, can_triggervalue: table): boolean
---@field on_cost? fun(effect: TriggerEffect, event: TriggerEvent, target: GameUnit?, owner: GameUnit?, data: any, on_usevalue: table): boolean
---@field on_use? fun(effect: TriggerEffect, event: TriggerEvent, target: GameUnit?, owner: GameUnit?, data: any, on_usevalue: table): boolean?
---@field validate_can_triggervalue? fun(parameters: table) @不修改参数；非法时 assert/error
---@field validate_on_usevalue? fun(parameters: table)

--- 内容脚本创建静态骨架。回调执行时 self 是实际 Effect，不是骨架。
---@param spec EffectSkeletonSpec
---@return TriggerEffectSkeleton
function SeerEngine.createEffectSkeleton(spec)
    checkDefinition(spec)
    assert((spec.type or Effect.Trigger) == Effect.Trigger, "unsupported effect type")
    local skeleton = TriggerSkeleton:new(spec.id, spec.name, spec.event)
    if spec.priority ~= nil then
        assert(type(spec.priority) == "number" and spec.priority == spec.priority
            and math.abs(spec.priority) < math.huge, "effect priority must be finite")
        skeleton.priority = spec.priority
    end
    for _, key in ipairs({ "can_trigger", "on_cost", "on_use", "validate_can_triggervalue", "validate_on_usevalue" }) do
        assert(spec[key] == nil or type(spec[key]) == "function", key .. " must be a function")
        skeleton[key] = spec[key]
    end
    return skeleton
end

--- 骨架 + 触发参数表 + 执行参数表 → 独立局内效果。
function SeerEngine:createEffect(id, can_triggervalue, on_usevalue, source)
    local skeleton = assert(self:getEffect(id), "unknown effect: " .. tostring(id))
    return skeleton:createEffect(can_triggervalue, on_usevalue, source)
end

function SeerEngine:getSkill(id) return self.skills[id] end
function SeerEngine:getBuff(id) return self.buffs[id] end
function SeerEngine:getAbnormal(id) return self.abnormals[id] end
function SeerEngine:getEffect(id) return self.effects[id] end
function SeerEngine:getPackage(id) return self.packages[id] end

--- 只校验，不创建实例。包安装前传入已注册及本包骨架，失败不部分注册。
function SeerEngine:validateEffects(references, available)
    available = available or self.effects
    for _, reference in ipairs(references or {}) do
        local id, can_triggervalue, on_usevalue = References.read(reference)
        local skeleton = assert(available[id], "unknown effect: " .. id)
        local ok, message = pcall(skeleton.validateParameters, skeleton, can_triggervalue, on_usevalue)
        assert(ok, "invalid parameters for effect " .. id .. ": " .. tostring(message))
    end
end

---@param references table[]
---@param source? Skill|Buff
---@return Effect[]
function SeerEngine:resolveEffects(references, source)
    local result = {}
    for _, reference in ipairs(references or {}) do
        local id, can_triggervalue, on_usevalue = References.read(reference)
        result[#result + 1] = self:createEffect(id, can_triggervalue, on_usevalue, source)
    end
    return result
end

--- 静态表只提供内容属性，持续轮数、次数、层数、数值由本次施加决定。
---@param id integer
---@param state? table @只允许局内状态字段，不能覆盖配置的类别和效果
---@return Buff
function SeerEngine:createBuff(id, state)
    local definition = assert(self:getBuff(id), "unknown buff: " .. tostring(id))
    local options = { type = definition.type, dispellable = definition.dispellable,
        scope = definition.scope, keepOnSwitch = definition.keepOnSwitch,
        abnormalKind = definition.abnormalKind, abnormalCategory = definition.abnormalCategory, effects = {} }
    local allowed = { turn = true, count = true, stacks = true, maxStacks = true, value = true }
    for key, value in pairs(state or {}) do
        assert(allowed[key], "unknown buff state field: " .. tostring(key))
        options[key] = value
    end
    local class = definition.type == BuffType.Abnormal and Abnormal or Buff
    local buff = class:new(id, definition.name, options)
    buff.effects = self:resolveEffects(definition.effects, buff)
    return buff
end

-- 兼容原实例创建入口；不再复制静态定义中的局内计数。
function SeerEngine:cloneBuff(id, state)
    return self:createBuff(id, state)
end

--- 加载某种语言的 key → 文本表。定义保留 key，显示时才决定语言。
---@param translations table<string, string>
---@param language string
function SeerEngine:loadTranslationTable(translations, language)
    self.translations[language] = self.translations[language] or {}
    for key, value in pairs(translations) do
        self.translations[language][key] = value
    end
end

--- 缺少目标语言的译文时回退到中文，再回退到 key，避免显示空文本。
---@param key string
---@param language? string @默认 zh_CN，可按玩家语言传入
---@return string
function SeerEngine:translate(key, language)
    local translations = self.translations[language or "zh_CN"] or {}
    local fallback = self.translations.zh_CN or {}
    return translations[key] or fallback[key] or key
end

return SeerEngine
