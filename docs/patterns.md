# 能力与元素筛选规则

## 已实现的架构

`seer/core/pattern` 使用基类与两个子类组织筛选逻辑：

- `pattern.lua`：`Pattern` 基类，保存合法名称与选择集合，实现包含、排除、单项匹配、数组匹配和筛选。构造时复制配置，不持有精灵或上下文。
- `stat_pattern.lua`：`StatPattern` 子类，从 `StatStages.getNames()` 获取六项能力等级名称：atk、def、spatk、spdef、speed、accuracy。不包含 hp 和 maxHp。
- `element_pattern.lua`：`ElementPattern` 子类，从 `Element.chart` 获取合法元素名称，默认结果按名称排序。规则可以选择多个元素，不限于两个；精灵和技能自身的元素组合仍由现有模块管理。

`seer/core/stat-stages.lua` 新增 getNames，返回固定顺序的独立数组，让能力数据与筛选规则共用一份定义。无需在 sr 上注册，按需 require 即可，运行入口需先准备项目已有的 kt.class。

这些类自行实现集合筛选，没有复制 FreeKill Exppattern 的代码或字符串解析器。目前没有多字段联合条件，也不读取能力数值。

## 使用方式

```lua
local StatPattern = require "seer.core.pattern.stat_pattern"
local ElementPattern = require "seer.core.pattern.element_pattern"
local Element = require "seer.core.element"

local attacks = StatPattern:new { "atk", "spatk" }
assert(attacks:match("atk"))
assert(not attacks:match("speed"))

-- 省略包含列表代表全部；第二个列表从结果中排除。
local exceptAccuracy = StatPattern:new(nil, { "accuracy" })
local none = StatPattern:new({}) -- 显式空数组代表不选择任何项

-- 返回新数组，默认按全集顺序；指定候选则按候选顺序筛选并去重。
local selected = attacks:select() -- { "atk", "spatk" }
local filtered = attacks:select { "spatk", "speed", "atk" } -- { "spatk", "atk" }

-- 兼容现有消强入口，能力等级的正负判断继续由 manager 负责。
ctx:clearBoosts { who = target, stats = attacks:select() }

local fire = ElementPattern:new { Element.Fire }
local dual = { Element.Fire, Element.Fighting }
assert(fire:matchAny(dual))
assert(not fire:matchAll(dual))
```

`matchAny` 表示候选数组中至少一项被规则选中；`matchAll` 表示候选非空且每项都被选中。两者遇到空数组都返回 false，避免属性技能的空元素数组意外触发效果。`matchAll` 不表示双方集合完全相同：选择火、水、草的规则，也能 matchAll 水、草组合。

包含与排除同时指定同一个名称时，以排除为准。构造规则时未知名称报错，匹配和筛选候选时未知名称不命中。数组必须连续、只包含字符串，错误键和空洞会报错。修改构造参数或 select 返回值不会影响规则。

## 调用流程与边界

技能脚本构造规则 → match / matchAny / matchAll 判断是否满足条件，或 select 得到名称数组 → 技能将操作意图提交给现有战斗入口 → manager 与事件处理等级校验、实际变化和通知。规则本身不修改状态，不产生事件，不引入网络协议或数据库。

规则类已用于标包能力筛选与随机能力变化。字符串表达式、数值范围、多个字段组合、精确双属性组合匹配均未实现；以后有具体技能需求时再扩展。

## 验证

新增 `tests/pattern.lua`，在项目根目录执行 `lua tests/pattern.lua`（Lua 5.3 及以上）。覆盖继承关系、合法名称范围、全部与空集、排除优先、输入输出隔离、稳定顺序与去重、双属性任一/全部判断、空元素数组、非法数组，以及选择指定能力清除正等级的组合行为。

已有战斗流程另用 Lua 5.5 执行 `tests/battle_flow.lua`，用于确认新增名称查询接口没有影响原有结算。

本次实际验证结果：6 组 Pattern 测试通过，64 组战斗流程回归通过。
