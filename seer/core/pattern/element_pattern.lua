-- SPDX-License-Identifier: LGPL-2.1-or-later
local Pattern = require "seer.core.pattern.pattern"
local Element = require "seer.core.element"

---@class ElementPattern: Pattern
local ElementPattern = Pattern:subclass("ElementPattern")

--- 匹配元素名称，全集取自现有克制表；排序保证 select() 的默认结果稳定。
--- 规则可包含任意数量的元素，不受精灵最多双属性的限制。
---@param values? ElementType[] 省略选全部，空数组选空集
---@param exclude? ElementType[] 从选择结果中排除的元素
function ElementPattern:initialize(values, exclude)
    local names = {}
    for name in pairs(Element.chart) do
        names[#names + 1] = name
    end
    table.sort(names)
    Pattern.initialize(self, names, values, exclude)
end

return ElementPattern
