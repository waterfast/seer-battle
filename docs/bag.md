# 背包与精灵数据装配

## 当前结构

每个角色有一个 `player.bag`，其中保存 `owner`（角色）、`pets`（携带精灵列表）和 `items`（道具编号对应数量）。正常模式的数据约定是一方最多携带六只；本次只实现初始化与查询，不添加增删、扩容或道具使用流程。

`player.pet` 仍指向当前出战精灵。背包里的其他精灵不会成为普通技能目标，也不会自动参与场上效果收集。`ctx.pets` 保存本局双方的全部精灵，供按本局单位编号查询。

## 初始化和查询

```lua
local Bag = require "seer.core.bag"
local bag = Bag:new(player, pets, { [9001] = 3 })

bag:getOwner()
bag:getPets()
bag:getPet(unitId)
bag:getAlivePets()
bag:getItems()
bag:getItemCount(9001)
bag:hasItem(9001, 2)
```

精灵和道具参数可以省略，默认为空表。`getPet` 按本局单位编号查询，找不到返回 nil；没有某道具时数量返回 0。列表和道具表查询返回容器副本，精灵对象本身仍是同一个局内实例。

Pet 构造时 `alive = true`，填充战斗数据时根据 HP 更新。`changeHp` 提交体力变化时同时更新 `alive`，所以 HpChanged、PetFainted 的监听者读到的是新状态。以后新增复活流程也应通过统一体力入口维护状态，不直接改一份字段。

## 数据来源与实例创建分开

```text
ctx:getPlayerBattleData(player)  取数据接口
  → logic:createBag(player, data)
      → logic:createPet(player, petData)
          → Pet:setup + createSkills
  → player.bag、player.pet、ctx.pets
```

`loadRoleData` 只负责组织这些步骤。当前 `getPlayerBattleData` 从宿主测试快照读取，未来可以替换成数据导入器的结果，不修改背包或精灵创建代码。本次没有实现数据库读取、网络拉取或存档导入。

单个角色的数据结构改为：

```lua
{
  activePetId = 1, -- 本局单位编号；省略则使用第一只存活精灵
  items = { [9001] = 3 },
  pets = {
    {
      id = 1, pet_id = 10001, name = "雷伊",
      level = 100, atk = 300, def = 240, spatk = 280, spdef = 230,
      speed = 310, hp = 360, maxHp = 360,
      nature = 1, iv = 31, skills = { 101, 102, 301 },
      element = { "Electric" },
    },
    -- 同样格式继续填写其余携带精灵。
  },
}
```

数据源负责提供正确的队伍、唯一单位编号和有效首发编号；这里没有另建通用校验层。导入数据中的 skills 是编号列表，创建后才变为技能实例。

## turnNumber 与 skillUseStack

`roundNumber` 用于当前轮次、广播和轮次上限，继续保留。原来的 `turnNumber` 只在角色行动时累加，没有规则用途，已移除。

`skillUseStack` 是正在结算的技能列表：进入 UseSkill 时加入，退出时移除。效果收集只读取最内层技能，所以当前技能的附加效果不会常驻；嵌套使用技能结束后又恢复外层技能。它不存储角色背包，也不是每轮行动队列。当前机制仍有用途，保留并补充了注释。

## 文件与验收

| 实际文件 | 本次内容 |
| --- | --- |
| `seer/core/bag.lua` | 背包属性、初始化、拥有者/精灵/道具查询 |
| `seer/core/pet.lua` | 存活字段、构造与数据填充时的初始状态 |
| `seer/gamethread/game-context.lua` | 可替换的数据来源接口 getPlayerBattleData |
| `seer/gamethread/gamelogic.lua` | 拆分 createPet/createBag/loadRoleData；区分携带与出战；按背包存活精灵判断是否淘汰 |
| `seer/gamethread/events/hp.lua` | 扣血时同步 alive 并广播 |
| `seer/gamethread/events/gameflow.lua` | 去掉无用途的 turnNumber 累加 |
| `test/seer_data.lua` | 测试数据调整为背包结构 |
| `test/seer_battle.lua` | 从背包测试数据读取展示面板 |
| `tests/battle_flow.lua` | 适配数据结构，验证双方各六只、替换数据来源、存活同步和后备精灵行为 |

运行方式仍为 `lua55 tests/battle_flow.lua` 或 PowerShell 的 `test/run-seer.ps1 -Auto`。64 组流程测试通过；雷伊对盖亚的单精灵命令行战斗仍正常结束。

仍未实现：主动换宠、精灵倒下后的强制换宠、道具消耗、真实存档导入。当前精灵倒下但后备仍存活时不会误判整队失败，但也不会自动换宠；完整六对六战斗还需要后续换宠流程。当前等待期间没有可执行技能，达到既有轮次上限后按平局结束。
