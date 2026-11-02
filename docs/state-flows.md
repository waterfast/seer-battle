# Buff、异常与能力等级的结算流程

## 架构和实际入口

结构沿用已有 HP / Skill：Context 供技能调用 → Logic manager 包装输入数据 → GameEvent 执行完整流程 → TriggerEvent 提供可监听时机 → 提交状态并广播。

用户创建的 `seer/gamethread/buff/buff_manager.lua` 和 `seer/gamethread/statStage/statstage_manager.lua` 现在作为 mixin 加入 Seer.GameLogic。它们不创建第二套引擎或事件栈，所有嵌套流程仍使用原 Logic.executeEvent 和 trigger。

通用查询、添加、移除已经从 `packages/standard/buff_helpers.lua` 移入引擎，该 helper 文件已删除。具体中毒伤害及抵挡数值继续留在标包。

## Buff 和异常

```lua
ctx:applyAbnormal { from = attacker, who = defender, buff = 10021, state = { turn = 3 }, skill = skill }

ctx:addBuff { from = attacker, who = defender, buff = 10022, state = { count = 2 }, skill = skill }
local instance = ctx:getBuff(defender, 10022)
ctx:removeBuff { who = defender, buff = instance, reason = "expired" }
```

buff 参数可以是注册编号或独立的局内实例。传编号时通过 sr:createBuff(id, state) 创建，轮数、次数、层数与数值由 state 提供，CSV 不保存这些状态；不能直接挂载共享定义，也不能把已属于另一精灵的实例再次添加。成功添加后实例.owner 为目标，移除后清空。scope=pet 使用 Pet 目标，scope=side 使用局内 Player 目标；配置 scope 与目标必须一致。

默认同编号不叠加、不刷新。getBuff 默认排除耗尽状态，传第三个参数 true 可以查询仍在列表内的耗尽实例。添加前会统一清理残留的耗尽实例，不再阻止重施加。

| 操作 | 时机顺序 |
| --- | --- |
| 添加普通 Buff | BeforeBuffAdded → 提交列表与 BuffAdded 广播 → BuffAdded → BuffAddFinished |
| 施加异常 | PreAbnormal → AbnormalCaused → AbnormalInflicted → 添加 Buff 子流程 → AbnormalApplied → AbnormalFinished |
| 移除 Buff | BeforeBuffRemoved → 按实例移除与 BuffRemoved 广播 → BuffRemoved → BuffRemoveFinished |

上表中的时机均挂在 sr 上。AbnormalCaused 的 target 是来源，其余 Buff 时机的 target 是目标。data 包含 from、who、buff、skill、prevented 以及 added/removed 结果。前置效果可修改 Buff 的轮数、次数等参数；目标和 Buff 实例身份应保持不变。效果参数由 CSV 的 {id, can_triggervalue, on_usevalue} 提供；状态施加时创建独立 Effect，骨架保持共享。

`addBuff` 检测到 BuffType.Abnormal 时也进入异常流程，防止通过通用入口绕过异常免疫。异常流程通过内部 AddBuff 子事件提交，不再递归调用公共 addBuff 入口。

免疫不是硬编码到某种异常上，而是通过承受异常时机表达。例如下面的效果挂到拥有者身上时，可以阻止其承受异常：

```lua
sr.createEffectSkeleton {
    id = 10111,
    name = "example.abnormal_immunity",
    event = sr.AbnormalInflicted,
    can_trigger = function(self, event, target, owner, data)
        return data.who == owner
    end,
    on_use = function(self, event, target, owner, data)
        data:preventBuff()
    end,
}
```

普通前置时机返回 true 也表示阻止。自然到期或下场清理的移除 data.forced=true，不允许取消；reason=dispel 另检查 dispellable。被阻止、不满足存活/持续条件、已存在同编号状态时，返回 false；相应 Finished 时机仍报告 added/removed=false。异常在免疫阶段结束时，不会进入 BeforeBuffAdded。战斗已经结束时停止后续时机和状态修改。

移除按具体实例比较，即使前置时机嵌套移除旧 Buff 并添加了同编号新 Buff，也不会误删新实例。添加在前置时机结束后重新检查目标、过期、拥有者和同编号状态，避免嵌套添加造成重复。

## 能力等级变化与整数原因

原因枚举定义在 core/events/stage.lua，沿用 sr 上的整数常量：

| 常量 | 值 | 含义 |
| --- | --- | --- |
| sr.ReasonStageChange | 1 | 通用变化，可同时升降不同能力 |
| sr.ReasonStrengthen | 2 | 强化 |
| sr.ReasonWeaken | 3 | 弱化 |
| sr.ReasonClearBoosts | 4 | 消强 |
| sr.ReasonCriticalBreak | 5 | 暴击后对应防御等级归零 |

reason 由技能传入，各专用入口提供对应默认值。它是供监听效果区分变化类别的元数据，实际算法由调用的流程决定。

```lua
ctx:strengthen {
    from = user, who = user, skill = skill,
    reason = sr.ReasonStrengthen, changes = { atk = 2, speed = 1 },
}
-- 专用弱化入口传正的幅度，进入时机前转换为负变化量。
ctx:weaken { from = user, who = target, changes = { def = 1, accuracy = 1 } }
-- 默认消除全部六项能力的正等级，不恢复任何负等级。
ctx:clearBoosts { from = user, who = target }
-- 也可以只消除特定能力的正等级。
ctx:clearBoosts { who = target, stats = { "atk", "speed" } }
-- 通用入口则直接传有符号的变化量。
ctx:changeStages { who = target, reason = sr.ReasonStageChange, changes = { atk = 1, def = -1 } }
```

上述入口及 resetStages 返回 actualChanges 表。被阻止时为 {}，达到上限的项为 0。变更参数在入口处复制，不改动技能复用的请求表。

能力等级只保留一个基础 GameEvent：ChangeStages。统一时机为：

`BeforeStageChange → 批量提交 → StagesChanged → StageChangeFinished`

strengthen、weaken、clearBoosts 是 manager 的便捷方法，不建立额外 GameEvent，也没有 BeforeStrengthen、BeforeWeaken、BeforeClearBoosts 等业务专用时机。强化/弱化转换成有符号 changes；消强保留 operation=clearBoosts 和 stats，在提交点解析。reason 只表示原因，不决定算法。

BeforeStageChange 允许修改 data.changes 或调用 data:preventStageChange()。需要只防止消强等效果时，在同一时机按 reason 区分：

```lua
if data.reason == sr.ReasonClearBoosts then
    data:preventStageChange()
end
```

只有至少一项实际非零变化才触发 StagesChanged；被阻止或达到上限时仍触发 StageChangeFinished，除非战斗已经结束。

基础事件在前置效果结束后取得 oldStages，再调用 StatStages:changeMany 校验并一次提交，限制在 -6～+6；newStages 记录此次提交结果，actualChanges 记录实际变化量。Seer.StagesChanged 广播包含目标 id、整数 reason、实际 changes 和提交后的 stages。非法变化批次不产生部分写入。

消强由 manager 传递 operation=clearBoosts 和复制的能力集合 stats；BeforeStageChange 结束后按最新正等级计算归零量，已为负的项保持不变。前置要限制消强集合时修改 data.stats，要阻止整次操作时调用 preventStageChange；消强不使用前置自填的 changes。resetStages 使用 operation=reset，将所选正负等级均归零；用于暴击破防，仍经过统一等级事件。普通增减仍允许修改 changes。完整说明见 [生命周期与伤害计算](lifecycle-and-damage-design.md)。

## 验证与边界

验证入口为 `lua55 tests/battle_flow.lua`；历史执行记录见 [README](../README.md)。已有测试覆盖 Buff 时机顺序及子事件父关系、异常免疫、返回 true 阻止、同编号拒绝、实例隔离/拥有者、移除取消、过期过滤、嵌套增删、变化类别、实际封顶变化量、弱化符号转换、消强保留负等级、局部修改、非法批次不部分写入、结束后不再变更和事件栈清理。

能力事件的这次收敛参考用户提供的新月杀 `ltk/server/events/movecard.lua` 的基础事件与包装入口分工，独立实现，没有复制代码。已删除强化/弱化/消强三个二级事件及九个专用时机；测试迁移为检查统一时机、原因和同一事件记录。

本次提供免疫的扩展时机，没有预设异常免疫名单或异常互斥矩阵。原版重复刷新/覆盖、异常概率与持续时间细则、反转/偷取能力等级尚未实现。已由 ResolveRoundEnd 统一推进完整轮数并清理到期；中毒只扣血，护盾自己消费次数后由框架收尾。默认下场清除、显式保留、side 状态和常规驱散限制已实现。已移除/耗尽的 Buff 不会继续执行既有候选快照。状态变化广播包含 scope，计数变化使用 BuffUpdated。

没有新增网络请求入口或数据库设计。广播仅传可序列化结果，不传 Buff 对象、Pet 或 Effect。

首批中毒/烧伤/冻伤在对手 BeforeTurnStart 扣体力；疲惫在 BeforeSkillUse 阻止技能；烧伤在 BeforeSkillDamageCalculation 修改本次威力。计时仍统一收尾，见[异常规则与官方证据](classic-abnormal-statuses.md)。
