# 属性与克制

## 已实现

`seer/core/element.lua` 是独立的数据与计算模块，不依赖游戏上下文或类系统：

- `Element.Water = "Water"` 等 26 个字符串常量：直接通过模块访问，与技能标签的写法一致。
- `Element.chart[攻击属性][防守属性]`：单属性克制表，未填写的组合为 1 倍，可直接修改配置。
- `Element.getMultiplier(技能属性, 防守属性)`：按页游规则计算单打单、单打双、双打单、双打双。

单属性和双属性统一使用数组，例如 `{ Element.Fire }` 和 `{ Element.Fire, Element.Fighting }`。双属性无需单独定义常量，交换数组顺序不影响结果。最多两个不同的单属性；空数组、未知属性、重复属性和超过两项的配置会报错。这里允许自由组合，不检查该组合是否已有官方精灵。

```lua
local Element = require "seer.core.element"

local skillElements = { Element.Fire, Element.Fighting }
local targetElements = { Element.Ice, Element.Shadow }
local multiplier = Element.getMultiplier(skillElements, targetElements) -- 2.375

Element.chart[Element.Fire][Element.Grass] = 2 -- 配置单属性关系
```

判断单属性直接比较字符串常量，例如 `element == Element.Water`；数组中的某一项也可以这样比较，例如 `elements[1] == Element.Water`。属性常量区分大小写，统一使用 `Element.Water` 这样的首字母大写写法。

克制表继续保存在 Lua 中，暂不增加 CSV 文件与读取逻辑。模块仍然只有常量、克制表和倍率计算三个部分。

## 计算流程

单打单直接查表。单打双或双打单得到两个分量 x、y：两个都是 2 时返回 4；任一个为 0 时返回 `(x+y)/4`；其余返回 `(x+y)/2`。

双打双先拆防守方：计算攻击方双属性对防守方每个单属性的系数，再取这两个结果的平均值。例如火·战斗打冰·暗影：打冰为 4，打暗影为 0.75，最终为 2.375。拆分顺序会影响结果，不能交换攻击方与防守方的职责。

数据与规则核对来源：

- [赛尔号 BWIKI 属性克制模块](https://wiki.biligame.com/seer/模块:属性克制)：单属性关系数据；本模块自行实现，没有移植其源码。
- [4399 单双属性克制系数计算解析](https://news.4399.com/gonglue/seer/jingyanxinde/825548.html)：规则与实战解析。

不同资料的个别关系有出入，本版统一采用上述 BWIKI 模块的数据：战斗打邪灵 1 倍、圣灵打邪灵 0.5 倍、轮回打虚空 1 倍。这里是公开资料配置，尚未用官方客户端逐项实测；以后调整对应表项即可。

## 验证与边界

在项目根目录用 Lua 5.3 加载模块即可运行，不需要服务端宿主。已检查常规克制、微弱、无效、4 倍特殊规则、含无效分量的合成、双打双拆分顺序和非法配置，并遍历所有单、双属性组合检查顺序不变性。

当前独立伤害计算服务已调用本模块：技能可使用 skill.element，被动可显式传 element；直接固定伤害不自动应用倍率。本模块返回克制倍率及本系判断；完整计算服务负责组合威力、本系、浮动和暴击等，特性或特殊技能覆盖仍由规则效果处理；网络与数据库也不在本次范围内。累计实现状态见 [项目架构与当前状态](../README.md)。
