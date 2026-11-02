# 页游普通伤害公式

## 范围与依据

实现的是普通定威力技能的通用红伤计算，保留独立计算服务供被动使用。公式、本系、整数浮动与单双属性合成参考[页游 PVE 机制整理](https://wiki.biligame.com/seer/赛尔号PVE概论)；分步取整采用[2026 年低威力实测](https://www.bilibili.com/opus/1173979935440633860)展示的顺序；暴击及普通技能破防参考[机制研究汇总](https://jiangshibiao.github.io/Summary-of-Game-Mechanism-in-Seer/index.html)。

2026-10-31 已将本地 26×26 共 676 个单属性系数与 [BWIKI 属性克制数据](https://wiki.biligame.com/seer/模块:属性克制)逐项比较，无差异。双属性使用页游合成算法，不使用宝可梦乘法，也不使用星球大战的拆分顺序。

这些是公开整理与玩家实测，不是官方服务端源码。尚未获得完整官方对照向量，不能宣称所有版本、特殊技能及全部内部取整均已百分之百还原；遇到特例应增加来源和数值用例后修改，不能静默套近似规则。

## 普通定威力公式与取整

```text
B = (0.4 × 等级 + 2) × 威力 × 有效攻击 / 有效防御 / 50 + 2
T = floor(B × 本系加成 × 克制倍率)
V = floor(T × R / 255)                     R 为 217～255 的均匀整数
A = 暴击时 floor(V × (1 - 暴击抗性))，否则 V
D = 暴击时 A × 2，否则 A
```

B 的完整算式不提前取整；有效攻击和防御已经由 Pet 能力接口应用等级并取整。物理读取 atk/def，特殊读取 spatk/spdef。无效克制保留零伤害，不强制抬为 1。

抗性、暴击分开取整，不把它们合并成一个倍率后一次取整。例如 V=384、抗性=0.35 时，暴击结果为 floor(384×0.65)×2=498。它与最后一次性取整的结果不同。非暴击不减免这项抗性。

本系为 1.5 或 1。精灵使用自身完整属性或其单属性分量时获得本系；只有部分重叠的双属性技能不算本系。例如火·飞行精灵使用火、飞行、火·飞行可获得加成，使用火·龙没有加成；单火精灵使用火·飞行也不算本系。普通系使用普通系同样享受本系。

单打双、双打单都按既有特殊合成规则处理：两个 2 得 4，出现 0 则和除以 4，其余取平均。双打双先拆防守方，各自计算后取平均。

## 概率、随机数和计算记录

Skill.critChance 缺省 1/16，明确配置 0 仍是不会自然暴击。来源精灵 critChanceBonus 或本次覆盖值与基础概率相加，再限制到 0～1。暴击使用局内浮点随机数，严格以 roll < chance 判断，不压成整数百分比。

计算前校验请求，然后先判暴击，再抽伤害浮动。概率为 0/1、或显式指定 isCritical 时不抽暴击随机数；randomRoll 已指定时不抽浮动。未命中和属性技不进入红伤计算，不额外消耗这两种随机数。相同版本、配置、种子和调用顺序可以复现结果。

目标 Pet.critResistance 和来源 Pet.critChanceBonus 由可信队伍快照导入，缺省为 0。critResistance 使用 0～1 的归一化数值，不使用 35 代表 35%；这里不自动为所有精灵开抗性，也不实现装备/套装的装配系统。

计算记录保存 baseDamage、stabMultiplier、effectivenessMultiplier、randomRoll、varianceMultiplier、critChance、criticalRoll、isCritical、critResistance、resistanceMultiplier、criticalMultiplier 和每阶段整数结果。DamageData.calculation 引用同一次结果，通用 Damage 不再次抽随机数或乘这些倍率。SkillUseData.isCritical 在计算后保存结果，BeforeSkillDamage 与伤害检查点可以读取；要强制暴击应在计算前（例如 SkillHit）指定。

## 普通暴击破防

计算接口始终不修改等级或派发事件。UseSkill 在普通暴击实际造成伤害后，对存活目标调用 resetStages：物理清零 def，特殊清零 spdef，正负等级均归零；另一项防御不变。通过统一等级事件提交，reason=ReasonCriticalBreak，操作独立于 reason。附加固伤不继承暴击或破防。

本次规则为：没有实际伤害、未命中、技能被取消或伤害被完全防止时不破防。等级事件仍提供监听与阻止入口，特殊魂印是否穿透这类处理需按具体规则接入。普通破防发生在 DamageFinished 之后、AfterSkillDamage 之前，计算本次伤害时仍读取破防前的等级。

变威力及部分连击存在先破防的例外，当前尚未实现这些技能的完整流程，不能用默认的后破防规则宣称已支持它们。

## 独立调用和定值伤害

```lua
-- 常规攻防计算：自然暴击与浮动默认启用，不要求存在 UseSkill。
local amount, calculation = ctx:calculateDamage {
    from = source, to = target,
    type = "special", power = 100, element = { "Electric" },
}
ctx:damage { from = source, to = target, damage = amount, calculation = calculation }

-- 基础定值：默认仅计算元素克制，不自动暴击、本系或浮动。
local amount, calculation = ctx:calculateDamage {
    from = source, to = target, baseDamage = 100, element = { "Electric" },
}

-- 需要让定值也经过完整修正时显式启用；复现时可固定结果。
local amount, calculation = ctx:calculateDamage {
    from = source, to = target, baseDamage = 100, element = { "Electric" },
    applyAttackModifiers = true, isCritical = true, randomRoll = 255,
}
```

未经过 UseSkill 的计算不会自动制造攻击行为或破防事件。固定/百分比/体力流失沿用各自业务入口，不因为来源技能打出暴击而自动翻倍。本系/浮动/暴击与技能 PP、命中、伤害修正事件仍是不同层次。

## 验证与未覆盖项

独立数值用例在 `tests/damage_formula.lua`，覆盖数值向量、分步取整、低威力边界、单双属性、本系、概率阈值、抗性、非法请求和种子复现；技能传递与破防用例在 `tests/battle_flow.lua`。执行记录集中见 [README](../README.md)，本次只运行相关用例。

未覆盖：完整套装/称号/抗性养成数据装配、所有增减伤乘区、变威力与连击特例、特殊魂印及 BOSS 规则、官方全量差分实测。已有伤害检查点保留，不能把这些内容当作通用基础公式的默认常量。
