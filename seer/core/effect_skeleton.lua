-- SPDX-License-Identifier: LGPL-2.1-or-later
local class = kt.class

--- 引擎保存的静态效果骨架，不保存实例参数、拥有者或局内计数。
---@class EffectSkeleton: Object
---@field id integer
---@field name string
---@field description? string @描述翻译 key
---@field translations? table<string, table<string, string>> @骨架脚本内的多语言文本
---@field type EffectType
local EffectSkeleton = class("EffectSkeleton")

function EffectSkeleton:initialize(id, name)
    assert(math.type(id) == "integer" and id > 0, "effect skeleton requires a positive integer id")
    self.id = id
    self.name = name or ""
end

-- 参数是可序列化数据。递归复制，防止嵌套参数在配置及不同实例之间串改。
local function copyData(value, visiting)
    local kind = type(value)
    if kind == "number" then
        assert(value == value and math.abs(value) < math.huge, "effect parameters must be finite")
    elseif kind == "table" then
        assert(getmetatable(value) == nil, "effect parameters must be a plain data table")
        visiting = visiting or {}
        assert(not visiting[value], "effect parameters cannot contain cycles")
        visiting[value] = true
        local result = {}
        for key, item in pairs(value) do
            assert(type(key) == "string" or math.type(key) == "integer", "invalid effect parameters key")
            result[key] = copyData(item, visiting)
        end
        visiting[value] = nil
        return result
    else
        assert(kind == "nil" or kind == "string" or kind == "boolean", "effect parameters must be data")
    end
    return value
end

--- 两组参数的顶层必须是普通表；省略时得到独立空表。
function EffectSkeleton.copyParameters(parameters)
    if parameters == nil then return {} end
    assert(type(parameters) == "table", "effect parameters must be a table")
    return copyData(parameters)
end

--- 安装配置时也会调用，避免等到出招才发现参数有误。
function EffectSkeleton:validateParameters(can_triggervalue, on_usevalue)
    local function check(name, parameters)
        local ok, message = pcall(EffectSkeleton.copyParameters, parameters)
        assert(ok, name .. ": " .. tostring(message))
    end
    check("can_triggervalue", can_triggervalue)
    check("on_usevalue", on_usevalue)
end

function EffectSkeleton:createEffect(can_triggervalue, on_usevalue, source)
    error("unsupported effect skeleton type")
end

return EffectSkeleton
