# 分类配置、异常身份与魂印

## 本次边界

异常、印记、魂印使用不同 CSV 和加载入口，继续共用 Buff 的挂载、效果调度、计时、移除与同步机制。精灵只有一个可变的 `buffs` 容器；异常专用查询从此容器筛选，避免额外维护一个容易不同步的异常列表。

```text
packages/standard/
  buffs/
    abnormal.csv          异常：身份、分类、下场策略、效果引用
    marks.csv             印记配置入口（当前只有表头，未编造具体内容）
    soulmarks.csv         魂印：当前包含雷神
    standard_buff.csv     通用 Buff：当前包含护盾
  skills/standard_skill.csv
  effect_sets.lua         有名称的效果组合和参数
  effects/               各效果的 Lua 行为
```

## 配置与索引

`loadAbnormalsFromCsv`、`loadMarksFromCsv`、`loadSoulMarksFromCsv` 分别隐含 Abnormal、Mark、SoulMark 类型；不用在每行重复填写魔法数字。加载器拒绝相冲突的 type。所有定义统一加入 Package.buffs / Engine.buffs 以保留通用 API；异常定义另加入 Engine.abnormals 索引。

```lua
local definition = sr:getAbnormal(10061) -- 静态定义
local abnormal = sr:createBuff(10061, { turn = 2 }) -- Abnormal 子类实例
ctx:getAbnormals(pet)                     -- 当前有效异常列表
ctx:getAbnormals(pet, "control")          -- 按控制类筛选
ctx:getAbnormal(pet, "paralysis")         -- 当前麻痹实例
ctx:hasAbnormal(pet, "sleep")             -- 睡眠条件判断
```

`seer/core/abnormal.lua` 是 Buff 的子类，增加 abnormalKind / abnormalCategory 的验证和实例字段。异常 CSV 必须提供二者；兼容旧的匿名异常定义，但匿名异常不能按身份查询。分类目前为 `control` / `weakening`，仅覆盖本次实现的异常。

同一 abnormalKind 的有效实例不会因为使用不同内容 ID 而重复挂载；重复施加仍采用拒绝策略，没有据此猜测官方叠加矩阵。新增实例的 BuffAdded 广播也带身份和分类。

## 效果参数

标准 CSV 用 `effectSet` 引用 `effect_sets.lua` 的具名配置，不再在表格里嵌套转义 JSON。例如：

```csv
id,name,scope,keepOnSwitch,dispellable,effectSet
10071,standard.soulmark.thunder_god,pet,true,false,thunder_god
```

效果组合的参数在 Lua 表中 review：

```lua
thunder_god = {
    effect(10051, { amount = 1 }),
    effect(10052, { buffId = 10061 }),
}
```

此文件是可信的包内配置模块，不执行来自 CSV 单元格的代码。`loadEffectSets` 必须先于 CSV 加载。具名引用解析成独立参数表，安装时仍检查骨架及其参数，运行时再创建独立 Effect。未知引用直接报错。旧 CSV 的 `effects` JSON 格式仍可读取；同一行不能同时提供非空 effects 和 effectSet。

## 通用异常施加入口

技能与魂印推荐调用 `ctx:inflictAbnormal`，统一处理成功率与持续时间，再进入已有 applyAbnormal 的免疫、查重、事件与生命周期管道：

```lua
-- 默认必定尝试施加，持续时间使用局内 RNG 随机选 2 或 3 轮。
ctx:inflictAbnormal { from = owner, who = target, kind = "paralysis", skill = skill }
-- 显式覆盖持续时间和成功率。
ctx:inflictAbnormal { from = owner, who = target, buff = 10061, chance = 0.5, turns = 2 }
ctx:inflictAbnormal { who = target, buff = 10061, minTurns = 3, maxTurns = 5 }
```

`buff` 编号和 `kind` 身份二选一。同一身份有多个定义时，身份入口报错，必须明确指定编号，避免任意选择变体。固定 turns 和随机范围互斥，范围的两个边界必须一起传入。非法参数在抽随机数前拒绝。

chance 默认 1，0 直接失败；成功率为 1 时不抽概率随机数，概率失败不抽持续时间随机数；固定轮数或相同上下界也不抽持续时间。所有随机数均来自当前战斗。返回值表示是否实际成功添加，免疫或有效状态重复返回 false。

底层 `ctx:applyAbnormal` 保留原语义：接受 buff 和精确 state，继续供特殊状态与已有代码使用，不隐式补轮数。

## 雷神魂印

本实现采用用户给定规则，不额外宣称为官方雷神魂印的完整复刻：攻击技能先制 +1；实际使用攻击技能时，以当前 HP / 最大 HP 的概率令目标麻痹。概率在发动当刻读取，满血必定触发，中间概率使用严格 `<` 判定。麻痹默认随机持续 2～3 轮，来自 GameContext 通用施加入口的默认值；效果参数可用 turns 或 minTurns/maxTurns 覆盖。

装配方式是在可信精灵战斗快照中指定：

```lua
{
    -- 原有面板、技能等字段
    soulMark = 10071,
}
```

开局创建精灵时装配独立魂印 Buff，不在尚未完成角色加载时派发 BuffAdded。BattleReady 同步初始 Buff 列表。配置只接受魂印类型，不能把异常 ID 当魂印装配。当前没有根据官方精灵 ID 自动推导魂印，也没有持久化养成解锁流程。

魂印绑定原精灵、不按轮到期、下场保留、不能常规驱散；后备时不收集其效果，换回继续发动。保留行为来自 CSV 的显式配置，不靠 SoulMark 类别隐式推断。

先制在 `BeforeActionOrder` 计算本轮 ActionData.priority。每次排序前由技能基础先制重新初始化，逐个派发修正时机后再排序；比较器内无战斗事件。物理/特殊技能享受加成，属性技能、道具、换宠不享受。技能原始 priority 不变。

麻痹在 `SkillUsing` 发动：已经通过使用前控制并消耗 PP，尚未判定命中，因此未命中仍可触发。这是按用户给定“使用攻击技能”的实现约定；如规则改为“攻击命中后”，应调整监听时机。被疲惫等控制阻止而未实际使用，不触发。施加走 applyAbnormal，能被异常免疫拦截。

## 新增异常

继续以[已核对的官方公开配置](classic-abnormal-statuses.md)为依据：

- 麻痹（10061）、害怕（10062）：控制类，共用 control.lua 阻止技能，不消耗 PP。
- 睡眠（10063）：同上；受到敌方未 miss 的物理/特殊技能时解除。唤醒判断在 SkillHit，因此护盾阻止伤害仍可解除；属性技能、未命中攻击不会解除。

三个演示技能为 10038～10040，持续时间由来源配置。新内容继续沿用已记录的计时约定与尚未验证的官方细节，未扩展猜测互斥、抗性或特殊例外。

## 验证

真实 Lua 5.5.0 下选跑 22 个相关流程用例，覆盖配置分类与错误、具名参数隔离、异常专用查询、睡眠解除、实际 Round 排序和控制、当前 HP 概率边界、异常免疫、魂印自动装配、下场保留与后备失活。未运行全面项目测试。

通用施加入口及雷神默认轮数调整后，在真实 Lua 5.5.0 下选跑 9 个相关用例通过；未运行全面项目测试。
