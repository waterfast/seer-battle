# 效果骨架与两组参数表

## 当前分层

参考截图中“条件选项”和“能力选项”分别保存的思路，触发条件与效果执行现在使用不同参数表。没有引入截图中的 C# 枚举系统。

引擎仍使用 `sr.effects`、`sr:getEffect(id)`，保存的是静态 EffectSkeleton。运行时的 Effect 持有共享骨架、独立的 can_triggervalue、on_usevalue 和 source。当前只实现 TriggerEffectSkeleton / TriggerEffect。

```text
CSV effects 单元格
  {id, can_triggervalue, on_usevalue}
  → id 查找引擎骨架
  → 分别递归复制两组参数
  → 创建实际 TriggerEffect，source 指向承载它的 Skill/Buff
  → 原有 Logic 调度，不改变战斗事件流程
```

同一种技能在不同精灵上创建独立 Effect；同一只精灵多次使用技能时复用已创建的 Effect。Buff 每次独立施加时创建独立 Effect。只有骨架共享。

## 参数表与回调

| 字段 | 用途 | 接收它的回调 |
| --- | --- | --- |
| can_triggervalue | 触发条件参数，例如血量低于多少比例 | can_trigger |
| on_usevalue | 执行参数，例如回复多少、提升什么能力几级 | on_use；当前 on_cost 也接收此表 |

两个字段的顶层必须是普通表。省略时，运行时分别创建空表；不允许用数字、字符串或 false 代替参数表。表内可以保存可序列化的嵌套参数，例如列表、多组条件或带字段的选项。不会自动解释这些结构，具体语义由骨架回调实现。

```lua
can_trigger = function(self, event, target, owner, data, can_triggervalue)
    -- self 是实际 Effect；此参数就是 self.can_triggervalue。
end
on_use = function(self, event, target, owner, data, on_usevalue)
    -- 此参数就是 self.on_usevalue。
end
```

其余参数仍是实际 Effect、本次时机、时机目标、拥有者与事件数据。on_cost 当前复用 on_usevalue，不增加第三张成本参数表；如需读取条件参数，可使用 self.can_triggervalue。

骨架可分别声明 validate_can_triggervalue(parameters)、validate_on_usevalue(parameters)。安装包和创建实例时都执行校验，错误注明参数组。原 value / validate_value 已移除，不做静默兼容。

两张表及其嵌套数据会分别复制：不共享静态配置、不共享其他实例，也不会因为调用方把同一张表传给两组参数，就让实例内部的两组参数互相串改。不接受函数、对象元表、循环引用和非有限数。

## 运行时创建

```lua
local skeleton = sr:getEffect(10013)
local effect = sr:createEffect(
    10013,
    { hpBelow = 0.5 }, -- can_triggervalue
    { amount = 50 }   -- on_usevalue
)
```

效果是“自身血量严格低于 50% 时回复 50”。等于阈值时不触发。未配置 hpBelow 时默认为 1，即血量未满才触发。

正常装配不需要手动创建 Effect：createSkill/createBuff 会从 CSV 自动装配，source 指向运行时技能或 Buff。Effect.id 表示效果种类，区分实例仍用实际对象身份。

## CSV 配置

标准包已改为 effectSet 引用 [effect_sets.lua](../packages/standard/effect_sets.lua) 中的可读参数表，详见[分类内容配置](content-and-soulmarks.md)。下述 effects 单元格 JSON 数组是保留的兼容格式；同一行不能同时提供两者。

兼容格式中，技能和 Buff 在 effects 单元格填写 JSON 数组，每项明确绑定编号和两组参数。空单元格或 `[]` 表示没有额外效果。以下是单元格内容：

```json
[{"id":10013,"can_triggervalue":{"hpBelow":0.5},"on_usevalue":{"amount":50}}]
```

能力提升示例：

```json
[{"id":10011,"can_triggervalue":{},"on_usevalue":{"stat":"atk","stages":2}}]
```

兼容格式实际保存到 CSV 时需要转义双引号，例如：

```csv
id,name,type,maxPp,effects
10032,standard.skill.heal,status,5,"[{""id"":10013,""can_triggervalue"":{""hpBelow"":1},""on_usevalue"":{""amount"":50}}]"
```

不使用旧的 value 字段或 `10011|10013` 格式。缺省参数可直接省略字段，不填 null；现有 JSON 库将 null 解为 nil，入口拒绝 null 以免漏装数组项。程序化配置的单整数 ID 仅适用于不要求执行参数的骨架。

## 标准包参数

| ID / 骨架 | can_triggervalue | on_usevalue |
| --- | --- | --- |
| 10011 / strengthen.lua | 当前无可调条件，填 {} | {stat="atk", stages=1} |
| 10012 / guard.lua | 当前无可调条件，填 {} | {amount=10}，每次抵挡量 |
| 10013 / heal.lua | {hpBelow=0.5}，缺省阈值为 1 | {amount=50}，回复量 |
| 10014 / poison.lua | 当前无可调条件，填 {} | {turns=3}，本次施加轮数 |
| 10015 / poison_tick.lua | 当前无可调条件，填 {} | {ratio=0.125}，对手行动开始时失去最大体力的比例 |
| 10016 / stage_change.lua | 当前无可调条件，填 {} | {target="self", stages=3, exclude={"spatk"}}，能力变化 |
| 10017 / fixed_damage.lua | 当前无可调条件，填 {} | {amount=50}，基础伤害后追加固定伤害 |
| 10018 / ratio_damage.lua | 当前无可调条件，填 {} | {ratio=0.25}，基础伤害后追加最大体力比例固定伤害 |
| 10019 / apply_abnormal.lua | {} | {buffId, chance=1} 默认随机 2～3 轮；可用 turns 或 minTurns/maxTurns 覆盖 |
| 10020 / burn_power.lua | {} | {}；本次攻击技能威力减半 |
| 10026 / control.lua | {} | {}；释放技能前阻止且不扣 PP |
| 10028 / abnormal_duration.lua | {} | {}；经典异常首次计时约定 |
| 10051 / attack_priority.lua | {} | {amount=1}；攻击行动先制修正 |
| 10052 / thunder_god.lua | {} | {buffId=10061}；当前 HP 比例概率施加异常，默认随机 2～3 轮 |
| 10053 / sleep_wake.lua | {} | {}；未 miss 的敌方攻击解除睡眠 |

官方依据和未验证边界见[首批经典异常](classic-abnormal-statuses.md)。

## 参数化能力变化与固定伤害

`10016` 在 `sr.SkillHit` 执行，`on_usevalue` 的参数如下：

| 参数 | 含义 |
| --- | --- |
| target | 必填，`self` 表示技能使用者，`target` 表示技能目标 |
| stages | 必填非零整数，正数强化，负数弱化 |
| stats | 可选能力名称数组，省略时选择全部六项；空数组不选任何项 |
| exclude | 可选排除数组，优先于 stats；通过 StatPattern 校验与筛选 |
| mode | 默认 `each`，所选每项变化 stages 级；`random_total` 表示将 stages 的绝对值随机分配给所选能力 |

例如，雷伊技能 1 配置 `{target="self", exclude={"spatk"}, stages=3}`；技能 2 配置 `{target="target", mode="random_total", stages=-3}`。能力均不含体力。随机允许重复抽中，使用房间随机源，并排除本批分配后已达上下限的能力。容量不足时只分配剩余可变等级。分配完成后一次调用 strengthen/weaken，原因枚举、免疫、实际变化量和广播仍由已有统一能力事件处理。

`10017` 在 `sr.AfterSkillDamage` 执行，`amount` 为必填正整数。它向存活的技能目标提交独立 `ctx:damage`，类别为 HP 定义的 `sr.FixedDamage`。不把数值加进普通伤害。未命中、属性技未进行基础伤害、目标已倒下时不会追加；基础伤害被防止但仍进入 AfterSkillDamage 时，追加段仍独立结算，并可被伤害事件阻止。

两者由标包目录自动加载，技能只保存 `{id, on_usevalue}` 等静态数据。现有 `sr:createSkill(id)` → `resolveEffects` → `createEffect` 会校验并复制参数，效果 source 指向本次 Skill；不同技能实例只共享骨架。旧的 `10011` 单项强化配置继续可用。

实际修改包含 `packages/standard/effects/stage_change.lua`、`fixed_damage.lua`，以及测试配置 `test/seer_data.lua`、启动装配 `test/seer_battle.lua` 和回归 `tests/battle_flow.lua`；已删除演示专用 `test/seer_effects.lua`。本次不增加数据库或网络入口。既有战斗回归覆盖演示四招，以及不同目标/能力集合、随机强化封顶、不同固定数值、实例参数隔离和非法参数拒绝。

所有固有条件仍然存在，例如使用者匹配、存活、中毒不可重复添加；空条件参数不代表无条件触发。

能力提升继续调用 ctx:strengthen，参数来自 on_usevalue：

```lua
event.ctx:strengthen {
    from = owner, who = owner, skill = data.skill,
    changes = { [on_usevalue.stat] = on_usevalue.stages },
}
```

沿用 statstage_manager、ChangeStages、免疫、整数原因及 -6～+6 封顶。骨架不直接修改面板。护盾与中毒通过 self.source 访问自己的 Buff，轮数、次数属于 Buff 实例。中毒不再自行扣轮，轮数由 ResolveRoundEnd 管理；护盾只消费次数，框架在效果结束后同步状态并清理耗尽对象。

Buff.value 作为旧的独立通用状态字段继续保留，与已移除的 Effect.value 不同。标准护盾读取 Effect.on_usevalue.amount，次数读取 Buff.count，不隐式同步两者。

## 在效果文件里写描述翻译

标准效果统一使用 local effect = sr.createEffectSkeleton {...}，随后声明 effect.description、effect.translations，最后 return effect。包安装时加载各效果自身的翻译，实际 Effect 保留描述 key，显示时使用 sr:translate(effect.description, language)。

回复与强化校验已简化，公共层仍保留 CSV 结构、引用和参数表检查。meta.lua 中 I18nContext 是编辑器接口声明，原参考宿主才提供实际对象；四个方法的区别和可运行的当前写法见 [描述翻译说明](i18n.md)。

## 已验证与边界

验证入口为 `lua55 tests/battle_flow.lua`，已有用例覆盖两组参数的回调分发、默认空表、深层隔离、同表输入隔离、两组非法参数及安装不部分写入；相同回复量配不同血量阈值、相同条件配不同回复量；能力提升免疫/封顶、Buff 抵挡参数、原有战斗与嵌套事件流程。历史执行结果集中见 [README](../README.md)。

尚未实现通用条件表达式、多条件 AND/OR 解释器、自动目标解析、独立 on_cost 参数表、非触发效果、热加载和按行动等更多计时方式。现有表结构允许骨架自行组织多项参数；仅有字段并不意味着已实现截图中的完整条件系统。
