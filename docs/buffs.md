# Buff：类别、归属与持续条件

## 数据结构

精灵状态保存在 Pet.buffs，玩家方状态保存在局内 Player.buffs；每个 Buff 持有自己的 Effect 实例，仅共享 EffectSkeleton。id 标识内容，type 表示业务类别，不决定归属或计时方式。

BuffType 的固定整数为 None=0、Feature=1、Emblem=2、Mark=3、SoulMark=4、Abnormal=5、Shield=8、Weather=9、Item=10；6、7 不使用。能力等级单独保存于 Pet.statStages。

| 字段 | 含义 |
| --- | --- |
| scope | pet（默认）或 side；决定目标是 Pet 还是战斗 Player |
| keepOnSwitch | 默认 false；pet 下场时是否留在原精灵身上 |
| turn | 可选非负整数，剩余完整轮数；nil 表示没有轮数限制 |
| count | 可选非负整数，剩余有效发动次数 |
| stacks / maxStacks | 可选层数及上限 |
| value | 具体效果解释的有限数值，不自动按零过期 |
| dispellable | 默认 true；是否接受 reason=dispel 的主动驱散 |
| owner | 运行时挂载目标，成功移除后清空 |
| firstTickRound | 框架及计时效果记录的首次扣轮时间，不由施加 state 指定 |

scope / keepOnSwitch / type / dispellable 来自静态配置。turn/count/stacks/maxStacks/value 来自本次施加 state，不能覆盖静态规则。异常必须绑定 pet。

## 创建和业务入口

```lua
ctx:applyAbnormal { from = attacker, who = pet, buff = 10021, state = { turn = 3 } }
ctx:addBuff { who = pet, buff = 10022, state = { count = 2 } }
local buff = ctx:getBuff(pet, 10022)
ctx:removeBuff { who = pet, buff = buff, reason = "dispel" }
```

也可传入独立 Buff 实例，但不能附加 state、使用共享定义或复用已挂载实例。构造器支持 type、scope、keepOnSwitch、dispellable、effects 及上述计数。引擎创建时会独立实例化效果和参数。

side 配置通过 ctx:addBuff {who=player,...} 施加；scope 与目标不一致时报错。查询、移除也使用同一目标对象。正式配置与引擎创建见 [内容引擎](seer-engine.md)。

## 计时、消耗和清理

isExpired 判断 turn/count/stacks 中任一已配置值是否为 0。nil 是没有该限制，0 是已耗尽。

- 每轮由 ResolveRoundEnd 在 RoundEnd 业务效果之后统一 advanceRound。中毒只负责扣血，不能再自行减轮。
- 通用 Buff 轮中新增时包含本轮；轮末新增/替换从下一轮扣减。首批经典异常会保留尚未发生的首次生效机会，详见[官方依据与计时边界](classic-abnormal-statuses.md)。使用实例快照避免旧状态的扣轮影响新实例。
- count 在实际成功发动时由效果调用 consume；框架不按监听次数或轮数盲目扣减。
- stacks 由 addStacks / consumeStacks 业务操作改变；这些操作校验正整数和上限。
- Buff 效果执行后由框架清理耗尽实例，剩余状态变化发 BuffUpdated；轮末和添加查重前也检查残留过期对象。
- 自然到期、次数耗尽和默认下场清除不受驱散免疫或移除取消阻止；普通移除仍可取消。

直接操作容器方法不会独立派发战斗事件。业务效果通过 ctx 入口和正常效果调度执行，禁止直接增删目标 buffs 列表。

## 下场行为

默认精灵 Buff 下场清除；keepOnSwitch=true 才保留在原精灵。保留状态在后备期间不执行场上常驻效果，轮数仍推进。side 状态属于玩家方，换宠不需要转移，并继续收集效果和计时。

可信精灵快照的 soulMark 编号可在开局自动装配魂印，初始状态随 BattleReady 同步。SoulMark 分类不会隐式创建保留或继承规则；雷神显式配置为下场保留。真正的精灵间转移尚未实现。

同编号有效状态仍拒绝重复；具备身份的异常也按 abnormalKind 查重，不自动刷新/叠加；已过期对象先经统一移除，不再占位。原版异常共存、抗性、反弹和持续时间细则仍需按目标规则增加。

## 验证与进一步说明

已有回归覆盖实例与计数隔离、非法配置、前置阻止、嵌套增删、到期重施加、轮末新增、最后一轮效果、下场清除/保留、玩家方印记和快照候选失效。历史执行结果见 [README](../README.md)。

完整时机见 [状态结算](state-flows.md)，设计取舍与独立伤害示例见 [生命周期与伤害计算](lifecycle-and-damage-design.md)。

已接入中毒、烧伤、冻伤、疲惫、麻痹、害怕、睡眠；官方来源、效果时点和未验证边界见[首批经典异常](classic-abnormal-statuses.md)。

异常/印记/魂印已分表，异常专用类和查询、雷神装配见[分类内容架构](content-and-soulmarks.md)。

普通技能和魂印可使用 `ctx:inflictAbnormal {who=pet, kind="paralysis"}`，默认随机 2～3 轮，可提供来源、概率及明确的持续时间。底层 applyAbnormal 保留精确 state 语义；详见[通用施加入口](content-and-soulmarks.md)。
