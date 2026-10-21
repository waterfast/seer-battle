-- SPDX-License-Identifier: LGPL-2.1-or-later

-- 仅表示业务类别。轮数、次数、层数由可选字段组合，不占用类别。
-- 能力升降由 Pet.statStages 管理；All 等筛选条件也不是 Buff 类别。
---@alias BuffType 0|1|2|3|4|5|8|9|10
-- 显式固定编号；6、7 保留给参考枚举中的持续方式，不用于业务分类。
local BuffType = {
    None = 0, -- 未分类的通用效果
    Feature = 1, -- 特性
    Emblem = 2, -- 纹章
    Mark = 3, -- 印记
    SoulMark = 4, -- 魂印
    Abnormal = 5, -- 异常状态
    Shield = 8, -- 护盾
    Weather = 9, -- 天气
    Item = 10, -- 道具效果
}

return BuffType
