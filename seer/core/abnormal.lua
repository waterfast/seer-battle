-- SPDX-License-Identifier: LGPL-2.1-or-later
local Buff = require "seer.core.buff"
local BuffType = require "seer.core.buff.type"

--- 异常共用 Buff 的归属与寿命；身份/分类用于免疫、净化及条件查询。
---@class Abnormal: Buff
---@field abnormalKind? string @稳定身份，如 paralysis；旧匿名异常可为空
---@field abnormalCategory? "control"|"weakening"
local Abnormal = Buff:subclass("Abnormal")
Abnormal.Category = { Control = "control", Weakening = "weakening" }

function Abnormal.validateDefinition(definition)
    assert(definition.type == BuffType.Abnormal, "abnormal definition requires Abnormal type")
    -- 兼容旧的匿名异常；正式异常 CSV 必须提供身份及分类。
    assert((definition.abnormalKind == nil) == (definition.abnormalCategory == nil),
        "abnormal identity and category must be provided together")
    if definition.abnormalKind then
        assert(type(definition.abnormalKind) == "string" and definition.abnormalKind:match("^[a-z][a-z_]*$"),
            "invalid abnormal kind")
        assert(definition.abnormalCategory == "control" or definition.abnormalCategory == "weakening",
            "invalid abnormal category")
    end
end

--- 施加参数共用校验：默认随机 2～3 轮，来源可显式覆盖。
function Abnormal.validateApplication(parameters)
    local chance = parameters.chance
    assert(chance == nil or (type(chance) == "number" and chance >= 0 and chance <= 1),
        "chance must be between 0 and 1")
    if parameters.turns ~= nil then
        assert(math.type(parameters.turns) == "integer" and parameters.turns > 0,
            "turns must be a positive integer")
        assert(parameters.minTurns == nil and parameters.maxTurns == nil,
            "choose fixed or random duration")
    elseif parameters.minTurns ~= nil or parameters.maxTurns ~= nil then
        assert(math.type(parameters.minTurns) == "integer" and parameters.minTurns > 0,
            "minTurns must be a positive integer")
        assert(math.type(parameters.maxTurns) == "integer" and parameters.maxTurns >= parameters.minTurns,
            "maxTurns must not be below minTurns")
    end
end

function Abnormal:initialize(id, name, options)
    Abnormal.validateDefinition(options)
    Buff.initialize(self, id, name, options)
    self.abnormalKind = options.abnormalKind
    self.abnormalCategory = options.abnormalCategory
end
return Abnormal
