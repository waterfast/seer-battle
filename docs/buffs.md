# 通用 Buff：类别与持续条件分开

## 架构与取舍

结构为 `Pet.buffs → Buff.effects → TriggerEffect`。每个 Buff 使用同一个通用类，`id` 标识具体内容，`type` 标识业务类别。轮数、次数、层数是可组合的状态字段，不再通过子类表示。

例如特性既可以常驻，也可以只生效三轮，或者三轮内最多发动两次；这些实例的 type 都是 Feature。异常也不必固定按轮持续。

`BuffType` 提供 None、Feature（特性）、Emblem（纹章）、Mark（印记）、Unhealthy（不良状态）、Abnormal（异常状态）、Shield（护盾）、Weather（天气）、Item（道具效果）。枚举只负责分类，不会自动赋予规则。使用显式整数编号：None=0、Feature=1、Emblem=2、Mark=3、Unhealthy=4、Abnormal=5、Shield=8、Weather=9、Item=10。保留参考截图的编号，6、7 不使用；代码通过 BuffType.Abnormal 等名称访问，实例及序列化结果保存整数。构造器拒绝字符串、非整数和未定义编号。

轮数类、次数类不再作为业务分类。能力变化继续使用 `Pet.statStages`，不重复表示成 Buff；All 是查询条件，不作为实际 Buff 类型。

## 创建与使用

```lua
local Buff = require "seer.core.buff"
local BuffType = require "seer.core.buff.type"

-- 三轮内最多发动两次的特性。
local feature = Buff:new(1001, "限时特性", {
    type = BuffType.Feature,
    turn = 3,
    count = 2,
    effects = { featureEffect }, -- 已定义的 TriggerEffect
})
ctx:addBuff { who = pet, buff = feature } -- 有编号的独立实例，不直接改列表

-- 异常不再需要专用子类。
local poison = Buff:new(2001, "中毒", {
    type = BuffType.Abnormal,
    turn = 3,
    effects = { poisonEffect }, -- 具体中毒规则需另行定义
})

-- 常驻特性没有 turn、count 字段。
local passive = Buff:new(1002, "常驻特性", { type = BuffType.Feature })

-- 有限层数印记、无轮数护盾。
local mark = Buff:new(3001, "印记", { type = BuffType.Mark, stacks = 1, maxStacks = 5 })
local shield = Buff:new(4001, "护盾", { type = BuffType.Shield, value = 100 })
```

省略 options 时创建 None 类型、可驱散且无持续限制的 Buff。effects 列表属于实例，各实例计数互不共享；由引擎创建时，每项 Effect 也独立创建，仅共享 EffectSkeleton 骨架。

## 字段与生命周期

| 字段 | 含义 |
| --- | --- |
| turn | 可选非负整数，剩余完整战斗轮数；nil 表示不按轮到期 |
| count | 可选非负整数，剩余有效发动次数；nil 表示不按次数到期 |
| stacks / maxStacks | 可选层数与正整数上限；上限必须配合层数使用 |
| value | 可选有限数值，由具体效果解释；不参与通用过期判断 |
| dispellable | 默认 true，仅声明可否常规驱散 |

`isExpired()`：已配置的 turn、count、stacks 任一为 0 即过期；全部省略则持续存在。nil 是没有该限制，0 是已经耗尽，不能混用。

`advanceRound()`：有 turn 时扣一轮，最低为 0，返回是否过期；无 turn 时不创建该字段。`consume(amount)`：默认消耗一次，缺少次数字段、已过期或余量不足时返回 false 且不修改。

`addStacks(amount)`：返回实际增加层数，不超过上限；未配置 stacks 时拒绝操作。`consumeStacks(amount)`：缺少层数、已过期或层数不足时返回 false。所有消耗或增加量必须是正整数。已耗尽印记可由调用方显式增加层数，是否重新加入列表由具体规则决定。

`value` 不采用统一的到零失效规则，因为护盾量、伤害倍率等不同数值含义不同。护盾耗尽移除等行为需在具体效果中处理。

## 迁移与实际修改

- `seer/core/buff.lua`：统一构造参数与可选字段、输入校验、轮数/次数/层数操作及组合过期判断。
- `seer/core/buff/type.lua`：持续方式枚举替换为整数业务类别枚举，编号显式固定。
- 删除 `seer/core/buff/round.lua`、`count.lua`、`mark.lua`、`abnormal.lua` 四个子类。旧 require 和构造方式不再保留，项目调用已迁移。
- `tests/battle_flow.lua`：用通用异常 Buff 验证真实技能触发流程，并覆盖可选字段、组合到期、分类独立、状态隔离和非法输入。
- `docs/buffs.md`、`README.md`、README 与终端说明同步当前结构和测试数。

旧 `RoundBuff:new(id, name, n)` 改为 `Buff:new(id, name, { turn = n })`；CountBuff 改为 `{ count = n }`；MarkBuff 改为 `{ type = BuffType.Mark, stacks = n }`；BuffAbnormal 改为 `{ type = BuffType.Abnormal, turn = n }`，也可以省略 turn。旧 remainingRounds/remainingCount 字段改为 turn/count。

## 验收与边界

在项目根目录运行 `lua55 tests/battle_flow.lua`，64 组全部通过，包括通用 Buff 的效果收集与触发、显式移除后停止触发、组合限制、常驻字段缺省、实例隔离、计数边界、全部整数类别及非法类别拒绝。

已实现的是状态容器和手动操作接口。已实现添加/移除和异常施加事件，含可实现免疫的前置时机。同编号默认拒绝，不自动刷新。尚未实现自动轮末推进、统一过期移除、驱散、同编号覆盖策略、异常互斥及换宠保留。`isExpired` 不会自动移除列表元素，但耗尽 Buff 不再被收集到新时机中；调用方通过 ctx:removeBuff 移除。

这些可选字段不自动扣减：轮数应由统一轮末流程推进，次数由实际成功发动的效果消耗，层数由技能意图改变，避免每次事件监听都误扣。

## 引擎配置来源

`sr:getBuff(id)` 返回 CSV 读取的普通静态表，只有 id/name/type/dispellable/effects，不含 turn/count/stacks/maxStacks/value。`sr:createBuff(id, state)` 在运行时创建 Buff 实例；例如 `sr:createBuff(10021, { turn = 3 })`。旧 cloneBuff 保留为同一运行时入口的别名。effects 在静态表里保存 {id, can_triggervalue, on_usevalue}，创建 Buff 时查骨架并创建独立 Effect。护盾抵挡量在 Effect.on_usevalue.amount，剩余次数在 Buff.count；已有 Buff.value 保留为独立通用状态字段。标准包配置位于 `packages/standard/buffs/standard_buff.csv`，没有逐 Buff 的定义类或 Lua 文件。详见 [静态配置与扩展包](seer-engine.md)。

## 战斗业务入口

技能应调用 ctx:addBuff / applyAbnormal / removeBuff / getBuff，不直接修改 pet.buffs。编号输入根据配置和 state 创建实例，添加异常不能绕过异常检查。完整时机、参数、返回值与修改文件见 [状态结算流程](state-flows.md)。
