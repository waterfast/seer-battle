# Buff 生命周期、归属与伤害计算

2026-10-31 实施说明。统一轮末计时、过期清理、下场策略、玩家方印记、消强提交修复、独立伤害计算与元素倍率已实现。普通暴击、本系、浮动及暴击抗性已接入，连击等特殊流程尚未实现。

## 1. 统一寿命管理

Round 调用 `logic:finishRound(data)`，执行独立 ResolveRoundEnd 事件：

```text
保存精灵、后备精灵与玩家方 Buff 实例快照
  → 触发 RoundEnd 业务效果（轮末回血等）
  → 对快照内仍属于原目标的实例统一扣一次 turn
  → 清理到期实例、解除 owner、广播移除
  → 检查胜负
```

当前规则：轮中获得的 Buff 包含本轮；轮末结算中新增或替换的实例从下一轮开始扣减。`firstTickRound` 是框架记录的首次计时轮次，内容不能通过 state 覆盖。按实例身份处理快照，避免旧实例的计时误扣到同编号新实例。同一轮 finishRound 不重复执行，报错时恢复轮末作用域。

中毒在对手行动开始时扣血，不再自行扣轮。经典异常的首次计时约定见[官方依据与边界](classic-abnormal-statuses.md)。最后一轮先发挥效果，再到期。`turn=nil` 不会生成轮数限制；count-only 状态不会按轮减次数。按行动/技能次数的规则仍由实际发动效果调用 consume；层数仍由业务操作改变。

Buff 效果正常执行返回后，框架检查耗尽并清理，状态变化时发 BuffUpdated；护盾脚本只负责 consume 和减少伤害。轮末也做兜底过期检查。直接手改计数不会自动派发事件，技能应通过已有业务入口与效果流程操作。

普通移除可被 BeforeBuffRemoved 取消；`reason="dispel"` 还检查 dispellable。自然耗尽与下场清除属于强制规则移除，data.forced=true，不受该取消或驱散免疫阻止，但仍会通知移除检查点。战斗已结束则停止新业务结算。

## 2. 过期占位和候选快照

添加 Buff 前、前置添加效果结束后，会先清理目标列表中残留的过期对象。旧 turn=0 对象不会再阻止同编号新状态施加。有效的同编号状态仍默认拒绝重复；本次没有实现原版叠毒或刷新策略。

移除按实例身份进行，不误删嵌套替换的新实例。效果候选形成快照后，已经被其他效果移除或耗尽的 Buff 不再继续发动。

## 3. 下场策略与玩家方印记

静态配置支持 `scope` 和 `keepOnSwitch`，构造、CSV、Engine.createBuff 均已接入，不能通过 state 改写配置。

| 配置 | 行为 |
| --- | --- |
| scope=pet（默认），keepOnSwitch=false（默认） | 精灵下场时清除 |
| scope=pet，keepOnSwitch=true | 留在原精灵身上，不转给下一只；场下不发挥常驻业务效果，但轮数仍推进 |
| scope=side | 挂在局内战斗 Player.buffs，换宠不转移、不清除；继续参与效果收集与轮末计时 |

side 的操作目标是战斗 Player，pet 的目标是 Pet；框架检查二者与配置 scope 一致。异常仅接受 pet 归属。玩家方状态是本局状态，不是登录账号或存档。

```lua
-- 定义玩家方印记；正式内容可放到 Buff CSV。
sr:registerBuff { id = 96021, name = "示例印记", type = 3, scope = "side" }
ctx:addBuff { who = player, buff = 96021, state = { turn = 3 } }
```

SoulMark / Mark 等 type 只表示业务分类，不隐含 scope、生效范围或保留行为。已支持按可信精灵快照的 soulMark 编号装配；雷神显式配置下场保留，并仅在所属精灵出战时激活。详见[分类内容架构](content-and-soulmarks.md)。

换宠顺序：BeforePetSwitch → BeforePetLeave → AfterPetLeave → 清理非保留 Buff → 清零并同步离场者能力等级 → 切换 player.pet → BeforePetEnter → AfterPetEnter → PetSwitchFinished。离场时机仍从旧宠收集效果，新宠只在提交出战位置后参与收集。下场清理回调不能重新给旧宠附加默认清除的临时状态。

真正的转移/继承操作仍需另行定义；keepOnSwitch 是保留在原精灵，scope=side 是属于玩家方，不能混用。

## 4. 计算服务独立于技能和攻击事件

当前分层：

```text
技能 → UseSkill → 独立计算服务 → Damage → ChangeHp
被动 / 场地效果 → 独立计算服务 → Damage → ChangeHp
直接固定伤害 → Damage → ChangeHp
体力流失 → LoseHp → ChangeHp
```

`UseSkill` 组织扣 PP、命中、技能效果和技能造成伤害的流程。计算留在 BattleController，ctx:calculateDamage 可在没有 UseSkill 的情况下调用，不会生成事件、扣 PP、做命中随机或直接改 HP；普通攻防公式会使用局内随机源做暴击与浮动判定。当前无需另建 Attack 事件；连击每段判定或独立攻击时机有具体需求后再提取。

```lua
-- 被动造成基础 100 点电系伤害；克制结果由计算服务给出。
local amount, calculation = ctx:calculateDamage {
    from = owner, to = target,
    baseDamage = 100, element = { "Electric" },
}
local actual, damage = ctx:damage {
    from = owner, to = target,
    damage = amount, damageType = sr.NormalDamage,
    calculation = calculation,
}
```

基础值 100 对水系经克制可变成 200，对地面系可变成 0。若规则要求无视属性的固定 100，直接提交 damage=100、damageType=sr.FixedDamage，不调用属性计算。Damage 不会根据 calculation 重复乘倍率。

也可给计算服务传 from/to、power/type、element，或以 skill 提供配置来源。baseDamage 存在时不读取等级和攻防；没有 baseDamage 时使用现有物理/特殊攻防公式。普通技能通过同一接口取得伤害和 calculation；旧 Logic:calculateDamage(from,skill,to) 调用仍兼容。元素配置来自显式 element 或 skill.element；旧目标快照缺元素时按中性处理。普通攻防公式默认应用本系、浮动、暴击及目标暴击抗性；基础定值默认仅用元素克制，可显式启用完整修正。详见 [公式与实测边界](damage-formula.md)。

DamageCalculation 保存 type、基础值、元素副本、本系/克制/浮动/暴击/抗性及各阶段数值。它属于独立计算结果，不依赖攻击事件。DamageData 可引用 calculation 或来源 skillUse；两者均可省略，普通追加固伤不自动继承。skill 表示来源技能，skillUse 表示明确关联的技能使用流程。

`ctx:damage` 第一返回值仍是实际扣血，第二返回值是实际 DamageData。技能在 AfterSkillDamage 可读 damageEvent。基础公式结果、待结算 damage、actualDamage 要分别理解。暴击由计算服务判定并保存在 calculation.isCritical，供减伤效果查询，通用 Damage 不重复判定。普通技能伤害后破防由 UseSkill 组织，不在计算服务中修改等级。

技能攻击行为、伤害元素、伤害类别是不同维度：被动电系伤害有元素，不因此成为一次玩家技能攻击。局内引用不直接作为 JSON 广播，也不等于持久回放。

## 5. 消强按最新等级提交

clearBoosts 不再预先把 +3 固化成 changes=-3，而是传 `operation="clearBoosts"` 和所选 stats。BeforeStageChange 结束后，ChangeStages 按最新正等级计算归零变化；已变成负等级的项保持不变。

reason 仅供监听者识别业务原因，不决定算法；即使调用方覆盖 reason，消强行为仍由 operation 决定。普通 changeStages / strengthen / weaken 使用 operation=add 和有符号 changes，保留既有行为。

前置监听者阻止整次操作仍调用 preventStageChange；消强要限制能力集合时修改 data.stats，不修改尚未解析的 data.changes。普通增减继续允许修改 changes。所选能力经过 Pattern 校验；实际变化、快照、封顶和广播仍由原统一事件处理。

换宠清零不受强化/弱化免疫阻止；有非零等级时广播 StagesChanged，cause=switch，通知客户端最新六项等级。

## 6. 验证与限制

针对生命周期、消强、换宠、玩家方归属和独立元素计算的用例位于 tests/battle_flow.lua。执行记录集中见 README；本次使用临时编译的真实 Lua 5.5，未运行全面项目测试。

尚未实现原版异常共存/叠加矩阵、完整控制异常、按行动计时的通用枚举、能力转移/反转、全量魂印及精灵身份映射、完整抗性养成/装备数据、连击与变威力特例、客户端实机与持久回放。
