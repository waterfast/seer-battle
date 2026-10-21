-- SPDX-License-Identifier: LGPL-2.1-or-later
local Json = require "lib.json"
local References = {}

--- 配置只存骨架编号及两组参数表，绝不存运行时 Effect 对象。
function References.read(reference)
    if type(reference) == "number" then reference = { id = reference } end
    assert(type(reference) == "table" and getmetatable(reference) == nil,
        "effect reference must be {id, can_triggervalue, on_usevalue}")
    assert(math.type(reference.id) == "integer" and reference.id > 0, "invalid effect reference id")
    for key in pairs(reference) do
        assert(key == "id" or key == "can_triggervalue" or key == "on_usevalue", "unknown effect reference field: " .. tostring(key))
    end
    for _, key in ipairs({ "can_triggervalue", "on_usevalue" }) do
        local parameters = reference[key]
        assert(parameters == nil or (type(parameters) == "table" and getmetatable(parameters) == nil),
            key .. " must be a plain parameter table")
    end
    return reference.id, reference.can_triggervalue, reference.on_usevalue
end

-- 现有 JSON 库把 null 解成 nil，会丢失数组位置。提前拒绝该值，避免漏装效果。
local function rejectNull(text)
    local quoted, escaped = false, false
    for index = 1, #text do
        local char = text:sub(index, index)
        if quoted then
            if escaped then escaped = false
            elseif char == "\\" then escaped = true
            elseif char == '"' then quoted = false end
        elseif char == '"' then quoted = true
        elseif text:sub(index, index + 3) == "null" then
            error("effect configuration does not accept null; omit optional parameters instead")
        end
    end
end

--- CSV effects 单元格为 JSON 数组，编号与参数配对，避免平行列表发生错位。
function References.parse(text)
    if text == "" then return {} end
    assert(text:match("^%s*%["), "effects must be a JSON array of {id, can_triggervalue, on_usevalue}")
    rejectNull(text)
    local references = Json.decode(text)
    assert(type(references) == "table", "effects must be an array")
    for index, reference in pairs(references) do
        assert(math.type(index) == "integer" and index >= 1 and index <= #references,
            "invalid effects array")
        assert(type(reference) == "table", "CSV effect entry must be {id, can_triggervalue, on_usevalue}")
        References.read(reference)
    end
    return references
end

return References
