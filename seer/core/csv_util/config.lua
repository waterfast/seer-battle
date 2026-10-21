-- SPDX-License-Identifier: LGPL-2.1-or-later
-- 把 CSV 字符串转换为普通配置表。静态配置校验与局内状态构造分别负责。
local Csv = require "seer.core.csv_util"
local Element = require "seer.core.element"
local BuffType = require "seer.core.buff.type"
local References = require "seer.core.csv_util.effects"
local Config = {}

local function integer(value, minimum, maximum)
    local result = tonumber(value)
    assert(result and math.type(result) == "integer" and result >= minimum
        and (not maximum or result <= maximum), "invalid integer: " .. value)
    return result
end

local function list(value, convert)
    if value == "" then return {} end
    local result = {}
    for part in (value .. "|"):gmatch("(.-)|") do
        assert(part ~= "", "empty list entry")
        result[#result + 1] = convert(part)
    end
    return result
end

local function choice(value, choices)
    assert(choices[value], "unknown value: " .. value)
    return value
end

local function boolean(value)
    assert(value == "true" or value == "false", "expected true or false")
    return value == "true"
end

local positiveId = function(value) return integer(value, 1) end
local nonnegative = function(value) return integer(value, 0) end
local text = function(value) assert(value ~= "", "empty text"); return value end
local effects = References.parse
local skillTypes = { physical = true, special = true, status = true, passive = true }
local skillSchema = {
    id = positiveId, name = text,
    type = function(value) return choice(value, skillTypes) end,
    power = nonnegative, priority = function(value) return integer(value, math.mininteger) end,
    accuracy = function(value) return integer(value, 0, 100) end,
    hits = positiveId, maxPp = nonnegative, effects = effects,
    element = function(value)
        return list(value, function(part)
            assert(type(Element[part]) == "string", "unknown element: " .. part)
            return Element[part]
        end)
    end,
    critChance = function(value)
        local result = tonumber(value)
        assert(result and result >= 0 and result <= 1, "critChance must be between 0 and 1")
        return result
    end,
}
local buffSchema = {
    id = positiveId, name = text, effects = effects, dispellable = boolean,
    type = function(value)
        local result = integer(value, 0)
        for _, kind in pairs(BuffType) do if kind == result then return result end end
        error("unknown buff type: " .. value)
    end,
}

function Config.convert(rows, headers, kind, source)
    local schema = assert(({ skill = skillSchema, buff = buffSchema })[kind], "unknown config kind")
    local columns = {}
    for _, header in ipairs(headers) do
        assert(schema[header], source .. ": unknown " .. kind .. " column: " .. header)
        columns[header] = true
    end
    local required = kind == "skill" and { "id", "name", "type", "maxPp" } or { "id", "name", "type" }
    for _, key in ipairs(required) do assert(columns[key], source .. ": missing column: " .. key) end
    local result, ids = {}, {}
    for _, row in ipairs(rows) do
        local definition = {}
        for _, key in ipairs(headers) do
            local value = row.data[key]
            if value ~= "" or key == "effects" or key == "element" then
                local ok, converted = pcall(schema[key], value)
                assert(ok, source .. ":" .. row.line .. " [" .. key .. "]: " .. tostring(converted))
                definition[key] = converted
            end
        end
        for _, key in ipairs(required) do
            assert(definition[key] ~= nil, source .. ":" .. row.line .. ": missing value: " .. key)
        end
        assert(not ids[definition.id], source .. ":" .. row.line .. ": duplicate id: " .. definition.id)
        ids[definition.id] = true
        result[#result + 1] = definition
    end
    return result
end

function Config.load(path, kind)
    local rows, headers = Csv.read(path)
    return Config.convert(rows, headers, kind, path)
end

return Config
