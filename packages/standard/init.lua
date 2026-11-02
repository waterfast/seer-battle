-- SPDX-License-Identifier: LGPL-2.1-or-later
local Package = require "seer.core.package"
local extension = Package:new("standard", 100)

-- 效果由 Lua 提供行为；Buff 和技能由 CSV 提供静态数据。
extension:loadEffectsByPath("packages/standard/effects")
extension:loadEffectSets(require "packages.standard.effect_sets")
extension:loadAbnormalsFromCsv("packages/standard/buffs/abnormal.csv")
extension:loadMarksFromCsv("packages/standard/buffs/marks.csv")
extension:loadSoulMarksFromCsv("packages/standard/buffs/soulmarks.csv")
extension:loadBuffsFromCsv("packages/standard/buffs/standard_buff.csv")
extension:loadSkillsFromCsv("packages/standard/skills/standard_skill.csv")
extension.translations = {
    zh_CN = require "packages.standard.i18n.zh_CN",
    en_US = require "packages.standard.i18n.en_US",
}
-- 道具仅保留表，不注册或实现使用行为。
return extension
