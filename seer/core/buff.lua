-- SPDX-License-Identifier: LGPL-2.1-or-later
local class = kt.class
local BuffType = require "seer.core.buff.type"
local validTypes = {}
for _, value in pairs(BuffType) do validTypes[value] = true end

---@class BuffOptions
---@field type? BuffType @业务类别，与持续条件无关
---@field turn? integer @剩余完整轮数；nil 表示不按轮到期
---@field count? integer @剩余发动次数；nil 表示不按次数到期
---@field stacks? integer @层数；nil 表示没有层数
---@field maxStacks? integer @可选层数上限
---@field value? number @效果数值，例如护盾量；不参与通用过期判断
---@field effects? Effect[]
---@field dispellable? boolean

---@class Buff: Object
---@field id? integer @具体 Buff 的静态配置编号
---@field name string
---@field type BuffType @业务类别
---@field turn? integer
---@field count? integer
---@field stacks? integer
---@field maxStacks? integer
---@field value? number
---@field effects Effect[]
---@field owner? Pet @挂载后的拥有者，由 Buff 流程管理；共享定义不设置
---@field dispellable boolean
local Buff = class("Buff")

local function checkCounter(value, name)
    assert(value == nil or (math.type(value) == "integer" and value >= 0),
        name .. " must be a non-negative integer")
end

local function checkAmount(amount)
    assert(math.type(amount) == "integer" and amount > 0, "amount must be a positive integer")
end

---@param id integer
---@param name? string
---@param options? BuffOptions
function Buff:initialize(id, name, options)
    options = options or {}
    local kind = options.type or BuffType.None
    assert(math.type(kind) == "integer" and validTypes[kind], "unknown buff type: " .. tostring(kind))
    checkCounter(options.turn, "turn")
    checkCounter(options.count, "count")
    checkCounter(options.stacks, "stacks")
    assert(options.maxStacks == nil or (math.type(options.maxStacks) == "integer" and options.maxStacks > 0),
        "maxStacks must be a positive integer")
    assert(options.maxStacks == nil or options.stacks ~= nil, "maxStacks requires stacks")
    assert(options.value == nil or (type(options.value) == "number" and options.value == options.value
        and math.abs(options.value) < math.huge), "value must be a finite number")
    assert(options.dispellable == nil or type(options.dispellable) == "boolean", "dispellable must be a boolean")
    self.id = id
    self.name = name or ""
    self.type = kind
    self.turn = options.turn
    self.count = options.count
    self.stacks = options.stacks
    self.maxStacks = options.maxStacks
    if self.maxStacks then self.stacks = math.min(self.stacks, self.maxStacks) end
    self.value = options.value
    -- 列表及实际 Effect 属于本局对象；只有 EffectSkeleton 在实例之间共享。
    self.effects = { table.unpack(options.effects or {}) }
    self.dispellable = options.dispellable ~= false
end

--- 多个限制同时存在时，任意一个耗尽即过期；nil 和 0 含义不同。
function Buff:isExpired()
    return self.turn == 0 or self.count == 0 or self.stacks == 0
end

--- 没有轮数限制时不创建 turn 字段，也不影响其他持续条件。
function Buff:advanceRound()
    if self.turn ~= nil then self.turn = math.max(0, self.turn - 1) end
    return self:isExpired()
end

--- 没有次数计数、已过期或余量不足时均不消耗。
function Buff:consume(amount)
    amount = amount or 1
    checkAmount(amount)
    if self.count == nil or self:isExpired() or self.count < amount then return false end
    self.count = self.count - amount
    return true
end

function Buff:addStacks(amount)
    amount = amount or 1
    checkAmount(amount)
    assert(self.stacks ~= nil, "buff has no stacks")
    local old = self.stacks
    self.stacks = self.stacks + amount
    if self.maxStacks then self.stacks = math.min(self.stacks, self.maxStacks) end
    return self.stacks - old
end

function Buff:consumeStacks(amount)
    amount = amount or 1
    checkAmount(amount)
    if self.stacks == nil or self:isExpired() or self.stacks < amount then return false end
    self.stacks = self.stacks - amount
    return true
end

return Buff
