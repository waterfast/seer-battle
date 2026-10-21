-- SPDX-License-Identifier: LGPL-2.1-or-later
local Pattern = require "seer.core.pattern.pattern"
local StatStages = require "seer.core.stat-stages"

---@class StatPattern: Pattern
local StatPattern = Pattern:subclass("StatPattern")

--- 匹配六项能力等级名称，不包含体力；不读取或修改精灵当前等级。
---@param values? string[] 省略选全部，空数组选空集
---@param exclude? string[] 从选择结果中排除的名称
function StatPattern:initialize(values, exclude)
    Pattern.initialize(self, StatStages.getNames(), values, exclude)
end

return StatPattern
