# 战斗流程与事件

累计完成清单、最新验证与后续规划见 [项目架构与当前状态](../README.md)。

本次并发选招、随机默认行动、计算层与新增技能后置事件的完整说明见 [行动请求与战斗计算](requests-and-battle-controller.md)。

## 当前架构

保留项目原来的三层组织：`ctx` 表示本局上下文，`Logic` 组织规则流程，`GameEvent` 包住一段完整结算；结算过程中的检查点用 `TriggerEvent` 表示。

`sr` 是 SeerEngine 的游戏实体实例，由 `seer/init.lua` 初始化。事件文件不会创建或替换它，仍按原有的全局数据类、事件家族和 `sr.XXX` 时机格式定义。没有增加 validation 模块。

## 启动步骤

房间加入、准备和开始请求沿用 `basescripts/server/room.lua`。开始时把房间用户、游戏类型和宿主准备好的 `battleData` 传给游戏线程。

`ServerGameContext:run()` 根据房间用户创建 ServerPlayer；注册的 Boardgame 可以通过 `contextClass` 指定 `Seer.GameContext`。随后创建 Logic 并启动根 GameEvent。

`SeerGameLogic:run()` 分为四步：

1. `prepareRoom`：整理座位。
2. `loadRoleData`：通过 `ctx:getPlayerBattleData` 获取队伍快照，再创建 Bag、Pet 与独立 PP 的 Skill 实例；数据来源与实例创建分开。技能定义从 `sr.skills` 获取。
3. `prepareForStart`：广播初始精灵和技能状态，触发 `sr.GameStart`。
4. `action`：进入轮次循环，直到胜负确定或达到轮次上限。

## 一轮如何执行

这里用 Round 表示双方完成一次选行动与结算的周期，Turn 表示某个角色执行已选行动的回合。日常说的“赛尔号一回合双方行动”对应这一整轮。

```text
RoundStart
  → 双方选择 action
  → 收齐双方行动
  → 按技能先制、精灵速度排序（相同暂按座位）
  → 第一个角色 Turn → 使用技能事件
  → 检查战斗是否结束
  → 第二个角色 Turn → 使用技能事件
  → RoundEnd
```

不会出现第一方选完招就先攻击、第二方之后才选招的流程。后手若已被击倒，不会继续执行已选技能。

行动选择时机为 `sr.BeforeActionChoice`、`sr.AfterActionChoice`。首版支持 `skill` 和 `pass`，还没有换精灵、道具或逃跑。InteractiveRequest 使用 base 的 awaitall 并发启动请求，全部回复后才执行；不能行动或没有合法选项者不发请求。

请求命令为 `Seer.ChooseAction`，内容包括本方精灵编号、可用技能和目标编号。回复示例：

```lua
{ type = "skill", skillId = 1, targetId = 2 }
-- 或 { type = "pass" }
```

选招只给编号，流程从角色实际持有的技能中取实例，并判断 PP、存活和目标。超时、离线或无效选招使用房间随机源选择合法技能与目标；没有可用技能时跳过。明确 pass 不随机。默认等待 30 秒，可通过 battleData.actionTimeout 设置；真实计时与过期回复隔离由宿主负责。

## 使用技能与体力结算

`useSkill` 创建 SkillUseData，再执行独立 UseSkill 事件：使用前 → 消耗一次 PP → 使用时 → 命中前 → 命中或未命中 → 基础伤害计算 → 技能伤害前 → 伤害事件 → 使用结束。

普通攻击的基础伤害由 Logic 委托给 battle_controller 计算，不包装成 Effect。命中和速度也通过 controller，读取 Pet 已应用能力等级的属性；当前公式只区分物理和特殊攻击。伤害事件之后有 AfterSkillDamage，命中效果处理结束有 SkillEffectFinished，属性技也经过效果结束时机；具体语义见请求与计算文档。

伤害经过 PreDamage、DamageCaused、DetermineDamageCaused、DamageInflicted、DetermineDamageInflicted 等原有时机，再调用 `changeHp`。之后发出 Damage、Damaged、DamageFinished；伤害被防止时仍有 DamageFinished，实际伤害量为 0。

`recover` 和 `loseHp` 也汇入 `changeHp`，但不经过伤害时机。`changeHp` 发出 BeforeHpChanged、提交体力、广播状态，再发出 HpChanged；体力归零时发出 PetFainted。回复不会超过上限，普通回复不会复活。

上下文提供 `ctx:useSkill(data)`、`ctx:damage(data)`、`ctx:recover(data)`、`ctx:loseHp(data)`、`ctx:changeHp(data)`。效果可直接调用这些入口。

## 数据从哪里来

当前数据源接口 `ctx:getPlayerBattleData(player)` 暂从宿主的 `battleData.players[playerId]` 读取。单角色数据已改为背包结构：

```lua
{
  activePetId = 1,
  items = {},
  pets = {
    {
      id = 1, pet_id = 1001, name = "精灵",
      level = 50, atk = 100, def = 100, spatk = 100, spdef = 100,
      speed = 100, hp = 200, maxHp = 200,
      nature = 1, iv = 31, skills = { 1, 2 },
    },
  },
}
```

`id` 是本局精灵单位编号，`pet_id` 沿用现有 Pet 的身份定义，映射键 playerId 是角色/账号编号，均不使用连接编号替代。

`sr.skills[id]` 保存内容包提供的定义：`name`、`power`、`type`、`element`、`accuracy`、`hits`、`critChance`、`priority`、`maxPp`、`effects`。`type` 支持 physical、special、status、passive；旧 `category` 仅在导入时兼容，优先使用 `type`。被动技能不能主动选用，但被动技能的自动挂载尚未实现。`element`、`hits`、`critChance` 已导入实例，属性克制、连击与暴击仍未接入结算。战斗快照和技能定义不能由选招请求代填。

每只精灵持有自己的技能、PP 和实际效果实例；只共享效果骨架，两组效果参数独立复制。整体架构见 [README](../README.md)。

极简 sr 引擎已实现，启动时加载 `seer.init` 即可创建它并加载事件。宿主仍需填充技能定义、在 `kt.engine` 注册对应 Boardgame，并设置其 logicClass 和 contextClass。引擎用法见 `docs/seer-engine.md`；测试使用真实 sr 引擎与宿主网络替身。

背包接口、存活字段、出战精灵与导入边界的本次改动详见 [背包说明](bag.md)。

## 实际文件改动

| 文件 | 实现内容 |
| --- | --- |
| `basescripts/core/trigger_event.lua` | 适配 ctx 的时机实例，提供临时 cost 数据；移除无法运行的旧 room 依赖 |
| `basescripts/gamethread/gamelogic.lua` | trigger、效果收集排序、条件/消耗/执行、完整事件执行入口 |
| `basescripts/gamethread/gamethread.lua` | 使用注册游戏的 contextClass，读取传入的 gameType |
| `basescripts/server/room.lua` | 开始战斗时转交 gameType 和宿主 battleData |
| `seer/core/events/init.lua` | 保留原 TriggerData 格式，加载事件文件 |
| `seer/core/events/gameflow.lua` | Round、Turn、Action 数据和触发时机 |
| `seer/core/events/skill.lua` | 使用技能的数据和触发时机 |
| `seer/core/events/hp.lua` | 恢复原有数据/时机格式，保留伤害类型；增加 PetFainted |
| `seer/gamethread/game-context.lua` | 本局精灵查询、战斗数据及业务入口 |
| `seer/gamethread/gamelogic.lua` | 分步启动、导入、选 action、排序、回合行动、基础伤害和胜负 |
| `seer/gamethread/events/gameflow.lua` | 双方先选 action，再执行 Round/Turn |
| `seer/gamethread/events/skill.lua` | 使用技能与当前技能效果的生效范围 |
| `seer/gamethread/events/hp.lua` | 伤害、回复、流失和实际体力变化 |
| `seer/core/skill.lua` | PP、威力、类别、先制、命中率与效果字段 |
| `seer/core/pet.lua` | 补充角色、持续效果与 Buff 字段注解 |
| `tests/battle_flow.lua` | 用真实事件与协程流程验证，替换宿主网络接口 |
| `docs/effects.md` | 同步触发效果接口与已实现状态 |

## 参考与验收

参考用户提供的新月杀 `ltk/server/room.lua`、`serverplayer.lua`，以及同仓库的 `server/gamelogic.lua`、`server/events/gameflow.lua`、`server/events/skill.lua`、`server/events/hp.lua` 和 `core/events`。HP 数据定义恢复自原有新月杀格式，适配文件保留 GPL-3.0-or-later 标记与来源。其他新流程使用本项目 ctx 与 GameEvent 接口实现。

项目现有协程库使用 Lua 5.5 语法，测试需用 Lua 5.5，在项目根目录运行：

```text
lua55 tests/battle_flow.lua
```

已验证效果顺序与消耗取消、嵌套触发、伤害防止、体力边界、PP、未命中与属性技能、双方先选再行动、速度和先制顺序、先手击倒后手、回合跳过、胜负结束和轮次上限。宿主启动流程使用替身网络接口验证，未连接真实客户端。

本次请求与计算工作尚未实现：数据库导入、换宠（已可创建多精灵背包）、道具使用、完整属性克制/暴击公式、额外回合、真实联网验收。其他模块的最新状态以 README 为准。护甲与体力上限的数据和时机按原格式保留，本次没有实现其完整结算封装。
