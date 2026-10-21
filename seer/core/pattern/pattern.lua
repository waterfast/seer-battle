-- SPDX-License-Identifier: LGPL-2.1-or-later
local class = kt.class

---@class Pattern: Object
---@field private _names string[]
---@field private _selected table<string, boolean>
local Pattern = class("Pattern")

--- 只接受连续字符串数组，防止拼错字段或数组空洞被 ipairs 静默忽略。
local function checkList(values)
    assert(type(values) == "table", "pattern values must be an array")
    local count = 0
    for index, value in pairs(values) do
        assert(math.type(index) == "integer" and index >= 1 and type(value) == "string",
            "pattern values must be a string array")
        count = count + 1
    end
    for index = 1, count do
        assert(values[index] ~= nil, "pattern array must not contain holes")
    end
end

--- 子类提供合法名称全集；values 省略选全部，空数组选空集，exclude 最后排除。
--- 构造时复制输入，之后改动配置数组不会影响规则。
---@param names string[] 合法名称，顺序也是默认筛选顺序
---@param values? string[] 要包含的名称
---@param exclude? string[] 要排除的名称，优先于包含
function Pattern:initialize(names, values, exclude)
    checkList(names)
    local valid = {}
    self._names = {}
    self._selected = {}
    for _, name in ipairs(names) do
        if not valid[name] then
            self._names[#self._names + 1] = name
            valid[name] = true
        end
    end

    local function apply(list, selected)
        checkList(list)
        for _, name in ipairs(list) do
            assert(valid[name], "unknown pattern name: " .. tostring(name))
            self._selected[name] = selected
        end
    end

    if values == nil then
        values = self._names
    end
    apply(values, true)
    if exclude ~= nil then
        apply(exclude, false)
    end
end

--- 判断单个名称，未知名称返回 false；构造规则时的未知名称则报错。
---@param name string
---@return boolean
function Pattern:match(name)
    return self._selected[name] == true
end

--- 筛选候选名称，保持输入顺序并去重；省略候选时筛选全集，返回独立数组。
---@param candidates? string[]
---@return string[]
function Pattern:select(candidates)
    if candidates == nil then
        candidates = self._names
    end
    checkList(candidates)
    local result, seen = {}, {}
    for _, name in ipairs(candidates) do
        if self:match(name) and not seen[name] then
            result[#result + 1] = name
            seen[name] = true
        end
    end
    return result
end

--- 候选中至少一项命中；空数组返回 false。
---@param candidates string[]
---@return boolean
function Pattern:matchAny(candidates)
    checkList(candidates)
    for _, name in ipairs(candidates) do
        if self:match(name) then
            return true
        end
    end
    return false
end

--- 候选非空且每一项均命中，不要求覆盖规则中的所有项，也不表示组合完全相同。
---@param candidates string[]
---@return boolean
function Pattern:matchAll(candidates)
    checkList(candidates)
    if #candidates == 0 then
        return false
    end
    for _, name in ipairs(candidates) do
        if not self:match(name) then
            return false
        end
    end
    return true
end

return Pattern
