# 精灵面板与能力等级

## 已实现的结构

`Pet` 持有两个独立对象，各精灵互不共享状态：

- `pet.stat`（`seer/core/stat.lua`）：攻击 atk、防御 def、特攻 spatk、特防 spdef、速度 speed、当前体力 hp、体力上限 maxHp。保存未应用能力等级的面板，支持 get、setMany、toTable。
- `pet.statStages`（`seer/core/stat-stages.lua`）：前五项能力及 accuracy 命中等级，初始为 0，设置和增减均限制在 -6～+6。没有体力、暴击、闪避等级。
- 等级、性格、个体值、元素属性继续由 Pet 保存，它们不是本次能力等级操作的对象。

原来的 pet.atk、pet.hp 等字段已迁移到 pet.stat，不保留重复数据。输入数据仍兼容平铺的 PetBattleData，也可以提供 data.stat；setup 会复制面板并清零能力等级。旧输入快照和体力通知格式保持不变。

## 使用

```lua
pet.stat:setMany { atk = 200, speed = 150 }
local changes = pet.statStages:changeMany { atk = 2, speed = 1, accuracy = -1 }
pet.statStages:set("def", 6)
pet.statStages:reset()
local attack = pet:getAtk() -- 应用等级后的战斗能力
local panel = pet.stat:toTable() -- 独立的原始面板快照
```

change/set 返回实际等级变化量；changeMany 返回每项实际变化量。批量操作先检查全部参数，出现非法名称或非整数等级时不修改任何项。toTable 返回副本。直接字段赋值会绕过校验，能力等级请使用方法修改。

当前体力变化仍应通过 logic:damage/recover/loseHp/changeHp 结算；直接改 stat.hp 或批量写体力不会触发事件、广播或更新 alive。setMany 用于面板装配与调整，不代替体力结算入口。

## 结算路径与取舍

技能结算 → Pet:getAtk/getSpAtk 与目标 getDef/getSpDef → 原始面板乘能力倍率 → 向下取整且最低为 1 → 基础伤害公式。行动排序使用 getSpeed。原始面板不回写强化结果，避免多次读取导致倍率累乘。

普通能力正等级倍率为 (2+n)/2，负等级为 2/(2-n)。命中正等级使用相同强化倍率；负等级 -1～-6 分别为 85%、70%、55%、45%、35%、25%，再乘技能命中率。显式指定技能事件 hit 时仍跳过随机判定。

命中表参考民间整理，便于后续核对版本时集中修改：[赛尔号 PVE 百科全书](https://jiangshibiao.github.io/Summary-of-Game-Mechanism-in-Seer/index.html)。不套用宝可梦命中公式。

## 文件与验收

新增 stat.lua、stat-stages.lua；pet.lua 装配两个对象并提供有效能力读取；gamelogic.lua 接入伤害和排序；events/skill.lua 接入命中；events/hp.lua 迁移体力存储；test/seer_data.lua、test/seer_battle.lua 迁移示例运行时访问；tests/battle_flow.lua 迁移旧断言并新增批量、边界、隔离、伤害、排序、命中测试。

运行：`lua55 tests/battle_flow.lua`，以及 PowerShell `./test/run-seer.ps1 -Auto`。当前已验证 48 组回归与终端自动对战。

已实现能力等级统一变化事件、manager 中的强化/弱化/消强数据封装、整数原因与结果广播。尚未实现反转、偷取和换宠时清除等级。这些属于后续战斗规则；本次没有加入数据库或网络协议。

## 代码风格与类入口

`stat.lua` 和 `stat-stages.lua` 与现有 Skill、Buff 一样使用 `local class = kt.class`，由运行入口统一准备类库。字段和公开方法提供中文 LuaDoc 注释，说明参数、返回值与边界；循环和条件分支展开书写。此次整理保持面板校验、批量更新和能力倍率行为不变。

## 技能中的能力变化

StatStages 是低层数据容器，直接调用 change/set 不产生战斗时机。技能使用 ctx:changeStages / strengthen / weaken / clearBoosts，由 manager 将操作转换为变化量，统一执行 ChangeStages 基础事件，处理阻止、上下限、实际变化与广播。接口示例和完整时机见 [状态结算流程](state-flows.md)。
