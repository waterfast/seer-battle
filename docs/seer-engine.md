# 静态配置、运行时实例与扩展包

## 当前架构

技能和 Buff 的静态配置是从 CSV 读取的普通 Lua 表，没有元表，不创建 Skill 或 Buff 对象。已有的 `Skill`、`Buff` 类只表示运行时实例。CSV 工具也是普通函数模块，不引入配置类。

```text
技能 CSV / 异常 CSV / 印记 CSV / 魂印 CSV / 通用 Buff CSV
  → csv_util 解析文本、转换类型并校验
  → Package 保存普通配置表
  → install 检查编号和效果引用，写入 Engine 索引
  → 进入战斗：createSkill(id) 创建独立技能，初始化 PP
  → 施加状态：createBuff(id, state) 创建独立 Buff
  → 原有 GameEvent / TriggerEvent 结算与广播
```

引擎的 effects 表保存 Lua 创建的 EffectSkeleton 骨架。标准 CSV 用 effectSet 引用具名效果参数配置，旧 effects JSON 格式保留兼容。解析后每项效果记录 {id, can_triggervalue, on_usevalue}；创建局内技能或 Buff 时，根据骨架和分别复制的两组参数表创建实际 TriggerEffect。仅骨架共享，Effect 不共享，也不会每次出招重建。回调中的 self 是实际 Effect，完整用法见 [效果骨架与参数](effects.md)。

## 标准包文件

```text
packages/standard/
  init.lua
  skills/standard_skill.csv
  buffs/abnormal.csv
  buffs/marks.csv
  buffs/soulmarks.csv
  buffs/standard_buff.csv
  effect_sets.lua
  effects/strengthen.lua
  effects/guard.lua
  effects/stage_change.lua
  effects/fixed_damage.lua
  effects/ratio_damage.lua
  effects/heal.lua
  effects/poison.lua
  effects/poison_tick.lua
  i18n/zh_CN.lua
  i18n/en_US.lua
```

原来四个技能 Lua 文件和两个 Buff Lua 文件已删除；新增普通技能或 Buff 配置时，直接添加 CSV 行。

```lua
extension:loadEffectsByPath("packages/standard/effects")
extension:loadEffectSets(require "packages.standard.effect_sets")
extension:loadAbnormalsFromCsv("packages/standard/buffs/abnormal.csv")
extension:loadMarksFromCsv("packages/standard/buffs/marks.csv")
extension:loadSoulMarksFromCsv("packages/standard/buffs/soulmarks.csv")
extension:loadSkillsFromCsv("packages/standard/skills/standard_skill.csv")
extension:loadBuffsFromCsv("packages/standard/buffs/standard_buff.csv")
```

效果目录仍支持单 EffectSkeleton / 骨架数组，排序只决定加载顺序，不再决定编号。技能和 Buff 明确指定 CSV 文件，不扫描它们的 Lua 目录。

## CSV 填写方式

UTF-8 编码，支持 BOM、LF/CRLF、带逗号或换行的双引号字段、双引号转义 `""`。第一行为列名，空白行忽略；列名及枚举值区分大小写，不自动清理空格。不把单元格当 Lua 代码执行。属性列表使用 `|` 分隔，例如 `Fire|Water`。标准表使用 effectSet 引用 effect_sets.lua 中的配置；effectSet 和非空 effects 不可同时填写。兼容的 effects 单元格使用 JSON 数组绑定 id、can_triggervalue、on_usevalue，例如 `[{"id":10013,"can_triggervalue":{},"on_usevalue":{"amount":50}}]`；保存到 CSV 时双引号需转义。

技能表字段：

| 字段 | 含义与约束 |
| --- | --- |
| id | 显式固定的正整数，必填 |
| name | 名称或翻译 key，必填 |
| type | physical / special / status / passive，必填 |
| maxPp | 最大 PP，非负整数，必填；配置没有当前 pp |
| power | 非负整数，缺省使用 Skill 的 0 |
| priority | 整数，可为负数，缺省 0 |
| element | 属性名称列表，空为无属性 |
| accuracy | 0～100 整数，缺省 100 |
| hits | 正整数，缺省 1 |
| critChance | 0～1，缺省 1/16；显式 0 表示不自然暴击 |
| effectSet | 包内具名效果组合，与非空 effects 二选一 |
| effects | JSON 数组，每项为 {id, can_triggervalue, on_usevalue}，空为无额外效果 |

Buff 表字段：

| 字段 | 含义与约束 |
| --- | --- |
| id | 显式固定的正整数，必填 |
| name | 名称或翻译 key，必填 |
| type | 通用 Buff CSV 必填整数类别；异常/印记/魂印专用 CSV 由加载器确定类型 |
| abnormalKind / abnormalCategory | 异常专用 CSV 必填；身份及 control / weakening 分类 |
| dispellable | true / false，缺省 true |
| scope | pet / side，缺省 pet，决定绑定 Pet 或战斗 Player |
| keepOnSwitch | true / false，缺省 false；pet 下场是否保留 |
| effectSet | 包内具名效果组合，与非空 effects 二选一 |
| effects | JSON 数组，每项为 {id, can_triggervalue, on_usevalue}，空为无额外效果 |

**Buff 静态表不允许顶层 turn、count、stacks、maxStacks、value 等局内状态列。** effects 中的 can_triggervalue/on_usevalue 是某个效果的条件/执行参数表，允许配置，与 Buff 的局内计数不同。 未知列、重复列、必填值为空、重复 ID、非法枚举和数值、列数不一致、损坏引号均直接报错。配置转换错误提供文件、行和字段信息。

## 运行时创建

```lua
local config = sr:getSkill(10032) -- 普通静态表
local skill = sr:createSkill(10032) -- 新 Skill，pp 初始化为 maxPp

local buff = sr:createBuff(10021, { turn = 3 }) -- 新 Buff，尚未挂载
ctx:applyAbnormal {
    from = attacker, who = defender, buff = 10021,
    state = { turn = 3 }, skill = skill,
}
ctx:addBuff {
    from = attacker, who = defender, buff = 10022,
    state = { count = 2 },
}
```

`state` 只接受 turn/count/stacks/maxStacks/value，不能覆盖 ID、名称、类别、可驱散标志或效果。省略 state 不会生成轮数或次数限制，显式传 0 则是已耗尽状态。不同施加可以有不同的持续时间。

传入已有 Buff 实例时不要再传 state，先在构造时确定其状态。添加、异常、移除仍经过原有 manager 和事件流程，见 [状态流程](state-flows.md)。中毒示例在施加时传入 3 回合，统一轮末事件负责扣减；护盾每次抵挡量从效果配置 on_usevalue.amount 读取，剩余次数由施加方 state 提供。

`Logic:createSkills` 委托 `Engine:createSkill`，每只精灵各有独立 PP、属性列表和效果列表；Buff 实例也分别保存计数。静态表中的 effects 保存 {id, can_triggervalue, on_usevalue}，运行时查找共享骨架并创建独立 Effect。

## 固定编号

Package 不再通过“包编号 + 类别 + 列表位置”计算 ID。CSV 的 id 和 Lua Effect 的 id 是内容身份，调整行顺序、文件名或在前面插入内容均不改变已有编号。

当前保留示例原编号作为固定值：技能 10031～10034，Buff 10021～10022，Effect 10011～10018。数字现在不承担自动编码规则。包自身仍有编号 100，用于查询和冲突检查。

```lua
return sr.createEffectSkeleton {
    id = 10013,
    name = "standard.effect.heal",
    event = sr.SkillHit,
    validate_on_usevalue = function(parameters)
        assert(math.type(parameters.amount) == "integer" and parameters.amount >= 0)
    end,
    can_trigger = function(self, event, target, owner, data, can_triggervalue)
        return data.from == owner and owner.alive
    end,
    on_use = function(self, event, target, owner, data, on_usevalue)
        event.ctx:recover { who = owner, num = on_usevalue.amount }
    end,
}
```

安装前验证三类内容编号不重复、包编号/名称不重复、同一定义不重复加入，以及技能和 Buff 引用的效果已存在或属于同包。失败不产生部分注册；同包内容可安装到另一个空引擎。

## 接口迁移与翻译

旧 `sr.createSkill(spec)` / `sr.createBuff(spec)` 静态工厂已移除。改为 CSV 配置；运行时使用带冒号的 `sr:createSkill(id)` / `sr:createBuff(id, state)`。`sr:cloneBuff(id, state)` 暂留为运行时创建的兼容入口，不再从配置复制计数。

`sr.createEffectSkeleton(spec)` 创建静态骨架；`sr:createEffect(id, can_triggervalue, on_usevalue)` 创建实际效果。原 `sr.createEffect(spec)` 定义工厂已迁移，避免与实际实例混淆。直接 registerSkill/registerBuff/registerEffect 保留给测试和手动装配；旧终端技能数据的 pp/category 仍兼容，CSV 统一使用 maxPp/type。

名称继续保留翻译 key，显示时调用 `sr:translate(key, language)`，默认中文，缺少目标语言时回退中文，再回退 key；未接入客户端语言协商。

## 已验证与尚未实现

验证入口为 `lua55 tests/battle_flow.lua`，已有用例覆盖条件/执行参数的分发、两组参数的深层隔离、同表输入隔离、缺省空表、两组非法输入拒绝与安装原子性；同骨架不同回复量、相同回复量不同触发阈值、强化免疫/封顶及 Buff 抵挡参数。历史执行结果集中见 [README](../README.md)。

尚未实现：通用多条件表达式、独立成本参数表、自动目标解析、非触发效果类型、热加载、完整 Mod 编号体系、按行动等更多计时方式及真实宿主文件联调。此阶段没有新增数据库表或网络协议。

分类加载、异常子类、查询及魂印自动装配见[分类内容架构](content-and-soulmarks.md)。
