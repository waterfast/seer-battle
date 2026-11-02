# 行动请求与战斗计算

本文说明当前请求、技能事件和计算分层；完整行动格式见 [行动协议](action-protocol.md)，历史验证记录见 [README](../README.md)。真实网络宿主尚未完成端到端验收。

## 架构与模块职责

```text
可信宿主：battleData、seed、玩家身份
  → Context：本局状态和独立随机数发生器
  → Logic：合法技能、目标、双方选招及排序
  → InteractiveRequest：并发等待所有参与者的回复
  → Round → Turn → UseSkill → Damage → ChangeHp
                    ↓
              BattleController：命中、伤害、速度、随机默认行动
```

沿用新月杀风格：`GameEvent` 包住完整结算，`TriggerEvent` 是其中的检查点。效果仍走已有的条件、消耗、执行和嵌套事件机制；没有另建一套事件总线。

计算层不派发事件，不改 PP 或 HP。`Pet:getAtk()` 等现有接口已经应用能力等级，controller 直接读取它们，避免强化倍率乘两遍。命中使用现有命中等级表。当前攻防基础公式保留，物理使用物攻/物防，特殊使用特攻/特防；防御下限为 1，属性技基础伤害为 0。独立 ctx:calculateDamage 支持 baseDamage 定值或 power/type 攻防计算，再应用相应修正，并返回 calculation 记录；普通公式含本系、克制、浮动、暴击和暴击抗性；被动可直接调用。

## 每轮请求怎么走

1. 对各玩家触发 `BeforeActionChoice`，检查能否行动及可用技能、目标。
2. 只向有合法选项且未被阻止的玩家发送 `Seer.ChooseAction`；倒下或被阻止者不会额外等待；PP 耗尽但仍可换宠或用药者仍会收到请求。
3. 使用 base 的 `async.awaitall` 同时启动请求，收齐以后才恢复轮次流程。每人等待时长为 `battleData.actionTimeout` 秒，缺省 30 秒，不再把两人的等待时间串起来。
4. 按房间玩家顺序处理回复。合法回复使用服务端持有的技能实例；明确 `pass` 就跳过。超时、离线、空回复、损坏 JSON 或非法编号，随机选择当前仍合法且 PP 大于 0 的主动技能和目标；无合法选项就跳过。
5. 触发 `AfterActionChoice`，换宠/道具优先于技能，技能按先制、已应用能力等级的速度、座位排序，执行各自 Turn。实际执行前再次检查归属、存活、出战状态、PP 和目标。

请求数据示例：

```lua
-- 服务端 → 客户端。round 便于显示；请求关联与迟到回复隔离仍由宿主完成。
{ petId = 1, round = 3,
  skills = { { id = 10031, name = "standard.skill.spark", pp = 9 } },
  targets = { 2 }, pets = { 1, 3 }, items = {},
  actions = { { type = "switch", targetId = 3 } } }

-- 客户端 → 服务端，只提交操作意图。
{ type = "skill", skillId = 10031, targetId = 2 }
-- 或 { type = "pass" }
```

服务端不接受客户端提交伤害、面板、账号编号或技能对象。账号身份沿用房间玩家身份，不用连接编号作为账号。

`kt.c.requestSocket` 必须立即返回，在回复或超时后回调一次，并隔离过期请求。Lua 复用这个宿主接口，不另造网络计时器。终端的 `io.read` 仍然是阻塞输入，不能据此宣称手动终端已经有真实 30 秒超时；自动测试使用可控的延后回调验证超时与并发逻辑。

## 随机数与房间种子

宿主可在建局数据中提供整数 `seed`，房间启动会转交 `room.seed`。base Context 将种子保存在 `ctx.secret.seed`，通过 `kt.rand(seed)` 创建每局独立的发生器；未提供时只在创建上下文时生成一次种子。

默认行动和命中判定均使用 `ctx:random`。随机默认行动在收齐回复后按座位计算，不在网络回调中抽取，因此相同快照、种子、配置和行动序列可以复现；回复先后不会改变随机序列。合法选招与明确跳过不消耗默认选招随机数。同速仍按座位，本版没有改成随机同速。

## 技能事件实际执行顺序

```text
合法性检查 → 进入当前技能效果作用域
  → BeforeSkillUse → 再检查 → 扣一次 PP → SkillUsing
  → BeforeSkillHit → controller 命中判定
      未命中：SkillMissed
      命中：SkillHit
        → 物理/特殊基础伤害 → BeforeSkillDamage
        → Damage 完整事件 → AfterSkillDamage
        → SkillEffectFinished
  → SkillUseFinished → 清理当前技能效果作用域
```

| 时机 | 可用于什么；实际边界 |
| --- | --- |
| `BeforeSkillUse` | 禁止使用或修改本次数据；阻止时不扣 PP、不发使用结束时机 |
| `SkillUsing` | 已扣 PP，可以阻止后续命中结算；之后仍有使用结束时机 |
| `BeforeSkillHit` | 可阻止命中阶段，或通过 `data.hit` 显式指定命中结果 |
| `SkillHit` / `SkillMissed` | 命中附加效果、未命中效果；未命中不造成基础伤害 |
| `BeforeSkillDamage` | 修改 `data.damage` 或阻止进入伤害事件 |
| `AfterSkillDamage` | 伤害事件返回后读取 `data.actualDamage` 和 `data.damageEvent`；被防止的伤害为 0，未进入伤害事件则不触发 |
| `SkillEffectFinished` | 已判定命中后的效果阶段结束，属性技同样经过；未命中或命中前被阻止不触发 |
| `SkillUseFinished` | 扣 PP 后的使用结束，包含未命中、属性技和伤害被阻止 |

以上时机都有实际调用位置，可以挂接扩展效果。属性技不进入基础伤害分支，通过 `SkillHit` 等时机实现具体效果。技能作用域在正常结束和异常退出时都由 GameEvent 清理；战斗已终止后不继续派发上述后续时机。后置时机不能用返回值撤销已经提交的伤害。

轮次事件继续使用 `RoundStart`、`EventTurnChanging`、`BeforeTurnStart`、`TurnStart`、`TurnEnd`、`RoundEnd`。轮开始返回中断时不收集行动；回合切换返回中断时跳过该角色；回合开始的中断会跳过行动并进入 Turn 清理。

## 验收与未实现

运行 `lua55 tests/battle_flow.lua` 和 `./test/run-seer.ps1 -Auto`。新增测试覆盖双方请求在回复前已发出、单方回复不能提前结算、反序回复、宿主超时与损坏 JSON 回退、合法随机技能、主动跳过、无行动不发请求、相同种子复现，以及命中/未命中/取消/伤害被防止的事件顺序。当前全项目验收结果见 [README](../README.md)。

仍未实现：真实网络宿主超时与过期请求的端到端验收，Unity 界面、手选倒下补位、自用和多目标选择、连击/变威力特例及完整装备/魂印修正、行动回放记录。通用 DamageData 不负责攻击计算。当前技能流程通过 damageEvent 取得本段伤害对象，伤害对象通过可选 skillUse 引用来源技能流程。calculation 是可选的独立计算结果引用，可用于技能与被动；已保存普通红伤各阶段与暴击结果，具体规则和实测边界见 [伤害公式](damage-formula.md)；分层与后续方案见 [生命周期与伤害数据设计](lifecycle-and-damage-design.md)。
