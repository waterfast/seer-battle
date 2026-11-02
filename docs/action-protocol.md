# 玩家行动、独立事件与移植说明

## 范围与架构

2026-10-31：将 seer-asio 与 Re-Seer 的换宠、道具规则适配到 seer-battle。参考来源为 `seer-asio/packages/seer-core/lua/server/battle/actions.lua`、`item.lua`，比例伤害参考 `lua/specs/standard/effects.lua`；适配文件保留 GPL-3.0-or-later 标识。没有复制另一套 BattleLogic、Timing 或 RPC 运行时。

客户端意图 → ChooseAction 收集 → Logic 校验并解析实例 → Turn → SwitchPet / UseItem / UseSkill → TriggerEvent → 既有 HP 和效果事件。

玩家能提交的行动和独立结算事件是两个层次：行动用于选择与排序，事件负责完整生命周期。规则导致的倒下补位也调用 SwitchPet，但不是额外的玩家行动。系统内部使用已装配的玩家、背包、精灵实例；只在网络编号边界和前置效果可能改变状态的提交点校验，不到处添加判空。

## 共用意图格式

| type | 字段 | 含义 |
| --- | --- | --- |
| skill | skillId、targetId | 使用当前精灵技能；targetId 指明敌方出战位置 |
| switch | targetId | 换到本方存活后备精灵 |
| item | itemId、targetId | 对本方存活精灵使用局内药品 |
| pass | 无 | 跳过 |

保留既有 `Seer.ChooseAction`。请求继续提供 petId、round、skills、targets，并新增 pets（存活单位编号）、items（itemId/count 数组，避免稀疏数字键无法编码为 JSON）、actions（当前合法特殊意图列表）。客户端可直接提交 actions 中的条目，但服务端仍重新验证，不能信任客户端缓存。每轮只提交一个行动。身份由宿主认证会话决定，不能在回复中指定玩家；targetId 是本局精灵实例编号，不是物种编号、连接编号或账号编号。

非法或超时回复沿用既有技能随机回退，无合法技能时 pass；执行时失效则跳过。请求关联、超时与迟到隔离仍由宿主 InteractiveRequest 适配器负责。本次没有新增网络序列号或声称完成 Unity 联网联调。

换宠和道具先于技能；同类别仍按速度、座位排序，技能内部先比较技能先制。技能执行前根据目标玩家重新读取出战精灵，避免攻击已退场者。行动发起精灵退场后不能由替补代执行原行动。

后续变身应增加明确 type、专用数据类、合法选项和独立 Transform 事件，再定义类别排序与时机。不要让客户端提交事件名、Lua 回调或面板变化；本次尚未实现变身，也未为假想动作引入通用注册框架。

## 时机与状态

换宠：BeforePetSwitch → BeforePetLeave → AfterPetLeave → 清理非保留 Buff → 清零并通知能力等级 → 提交当前精灵 → BeforePetEnter → AfterPetEnter → PetSwitchFinished。离场时机仍从旧宠收集，新宠仅在出战位置提交后加入收集。主动换宠在 BeforePetSwitch 可取消并发出 PetSwitchCancelled。倒下补位忽略该取消，但仍检查目标归属与存活。BeforePetEnter 表示入场效果开始，此时 player.pet 已指向新精灵。只在下一轮收行动前按背包顺序自动补位；手选补位尚未实现。

道具：合法检查 → BeforeItemUse → 再检查 → 扣一次库存 → ItemUsed → Recover 或 PP 恢复 → AfterItemUse。前置取消发出 ItemUseCancelled，不扣库存；满血、PP 全满、无库存、敌方目标都无效。回血嵌套已有 Recover，禁疗仍消耗道具；PP 以各技能 maxPp 截断。

新增广播 `Seer.PetSwitched {from,to,forced}`、`Seer.ItemUsed {from,to,itemId,count,skills}`；后者 skills 含技能 id 与最新 pp。HP 仍由原有 HpChanged 广播。

道具 1 为回复 50 HP，2 为全技能回复 5 PP，均为演示编号。数据库设计没有变化：Bag.items 是宿主快照的局内副本，不等于 PostgreSQL 背包已扣款。持久扣款、并发消费与战斗结果落库仍属于宿主接入工作。

## 修改文件与职责

| 文件 | 实现 |
| --- | --- |
| seer/core/events/action.lua、events/init.lua | 换宠/道具数据类、时机家族及加载 |
| seer/core/events/gameflow.lua | ActionData 类型和道具字段 |
| seer/gamethread/action_manager.lua | 合法意图、查询、业务入口与倒下补位 |
| seer/gamethread/events/action.lua | 两个完整事件、取消、扣数和广播 |
| seer/gamethread/gamelogic.lua | 收集特殊行动、排序、分发、换宠后目标解析 |
| seer/gamethread/events/gameflow.lua | 每轮开始补位 |
| seer/gamethread/game-context.lua | 对效果公开 switchPet / useItem |
| packages/standard/items.lua | 演示道具定义 |
| packages/standard/effects/ratio_damage.lua | 参数化最大体力比例固定伤害（10018） |
| packages/standard/effects 下既有效果、seer/core/effect.lua、effect_skeleton.lua | 保留工作区既有效果名称移除修改；补齐遗留描述引用，按编号翻译 |
| tests/battle_flow.lua | 行动、库存、取消、补位、目标转移、比例伤害回归，更新描述断言 |
| test/seer_battle.lua | 终端通过 a序号 选择特殊行动 |
| README.md、test/README.md、本文 | 当前行为、运行方法和协议说明 |

## 验证与尚未实现

历史执行结果集中见 [README](../README.md)。验证入口：`lua55 tests/battle_flow.lua`、`lua55 tests/pattern.lua`、`lua55 test/seer_battle.lua --auto`。运行时可用绝对路径代替 lua55。

标包本次只新增比例固定伤害骨架，配置 ratio 为 (0,1]，结果向下取整；尚未绑定新的正式技能。没有搬运偷取能力、封招和抵挡致死；它们应在持续效果/能力事件规则明确后分别适配。当前默认下场清除 pet Buff，keepOnSwitch=true 保留于原精灵，scope=side 绑定玩家方。保留的场下 pet Buff 不发挥常驻效果，但 turn 继续推进；这些是当前明确实现的规则，不代表完成全部原版异常机制。未验证 Unity 实机、真实网络、道具落库和完整官方战斗规则。
