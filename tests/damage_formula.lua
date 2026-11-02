-- Focused formula checks; no host or battle scheduler required.
local scriptDirectory = arg[0]:match("^(.*[/\\])") or "./"
local root = scriptDirectory .. "../"
package.path = root .. "?.lua;" .. root .. "?/init.lua;" .. root .. "basescripts/?.lua;" .. package.path
kt = { class = require "lib.middleclass" }
local Pet = require "seer.core.pet"
local Skill = require "seer.core.skill"
local Controller = require "seer.gamethread.battle_controller"
local Element = require "seer.core.element"
local Random = require "lib.xoshiro256starstar"
local passed = 0
local function test(name, fn)
  fn(); passed = passed + 1; print("PASS " .. name)
end
local function pet(values)
  local data = { level = 100, atk = 300, def = 200, spatk = 300, spdef = 200,
    speed = 100, hp = 1000, maxHp = 1000, element = { "Fire" }, skills = {} }
  for key, value in pairs(values or {}) do data[key] = value end
  local result = Pet:new({}, 1, "formula", 1)
  result:setup(data)
  return result
end
local function calculator(random)
  return Controller:new { random = random or function() error("unexpected random draw") end }
end
local function request(values)
  local spec = { from = pet(), to = pet { element = { "Grass" } }, type = "physical",
    power = 100, element = { "Fire" }, isCritical = false, randomRoll = 255 }
  for key, value in pairs(values or {}) do spec[key] = value end
  return spec
end
local function rejects(fn) assert(not pcall(fn), "invalid formula input must fail") end

test("ordinary formula combines STAB type variance and critical resistance", function()
  local calc, spec = calculator(), request()
  local amount, result = calc:calculateDamage(spec)
  assert(amount == 384 and result.baseDamage == 128 and result.stabMultiplier == 1.5)
  assert(result.effectivenessMultiplier == 2 and not result.isCritical and result.criticalMultiplier == 1)
  spec.isCritical = true
  amount, result = calc:calculateDamage(spec)
  assert(amount == 768 and result.isCritical and result.criticalMultiplier == 2)
  spec.to.critResistance = 0.35
  amount, result = calc:calculateDamage(spec)
  assert(amount == 498 and result.afterResistanceDamage == 249)
  spec.isCritical = false
  assert(calc:calculateDamage(spec) == 384) -- 抗性不减免非暴击伤害。
end)

test("full base formula retains fractions until STAB and type are combined", function()
  local spec = request { from = pet { level = 50, atk = 104, element = { "Normal" } },
    to = pet { def = 100, element = { "Normal" } }, power = 50, element = { "Normal" } }
  local amount, result = calculator():calculateDamage(spec)
  assert(math.abs(result.baseDamage - 24.88) < 1e-10)
  assert(amount == 37 and result.afterTypeDamage == 37)
  spec.randomRoll = 217
  assert(calculator():calculateDamage(spec) == 31)
end)

test("low power example preserves separate rounding at type variance and resistance", function()
  local spec = request { from = pet { atk = 602, element = { "Ice" } },
    to = pet { def = 393, element = { "Holy" } }, power = 1, element = { "Ice" }, randomRoll = 217 }
  local amount, result = calculator():calculateDamage(spec)
  assert(amount == 1 and result.afterTypeDamage == 2 and result.afterVarianceDamage == 1)
  spec.randomRoll = 255
  assert(calculator():calculateDamage(spec) == 2)
  spec.isCritical, spec.critResistance = true, 0.35
  assert(calculator():calculateDamage(spec) == 2)
end)

test("STAB matches exact dual types or their single components without partial overlap", function()
  assert(Element.getStabMultiplier({ "Fire" }, { "Fire" }) == 1.5)
  assert(Element.getStabMultiplier({ "Fire", "Flying" }, { "Flying" }) == 1.5)
  assert(Element.getStabMultiplier({ "Fire", "Flying" }, { "Flying", "Fire" }) == 1.5)
  assert(Element.getStabMultiplier({ "Fire" }, { "Fire", "Flying" }) == 1)
  assert(Element.getStabMultiplier({ "Fire", "Flying" }, { "Fire", "Dragon" }) == 1)
  assert(Element.getStabMultiplier({ "Normal" }, { "Normal" }) == 1.5)
  assert(Element.getStabMultiplier({}, { "Fire" }) == 1)
  assert(Element.getStabMultiplier({ "Fire" }, {}) == 1)
end)

test("page-game dual effectiveness uses fourfold zero and defense-first composition", function()
  assert(Element.getMultiplier({ "Grass" }, { "Water", "Ground" }) == 4)
  assert(Element.getMultiplier({ "Light" }, { "Grass", "Psychic" }) == 0.5)
  assert(Element.getMultiplier({ "Fire", "Water" }, { "Grass" }) == 1.25)
  assert(Element.getMultiplier({ "Electric" }, { "Ground" }) == 0)
  assert(Element.getMultiplier({ "Electric", "Fire" }, { "Ground", "Water" }) == 0.75)
  local spec = request { element = { "Electric" }, to = pet { element = { "Ground" } }, isCritical = true }
  assert(calculator():calculateDamage(spec) == 0)
end)

test("critical threshold is exact and explicit or guaranteed results avoid probability draws", function()
  local calls, chanceRoll = {}, 1 / 16
  local calc = calculator(function(_, low, high)
    calls[#calls + 1] = { low, high }
    if low then assert(low == 217 and high == 255); return 217 end
    return chanceRoll
  end)
  local spec = request()
  spec.isCritical, spec.randomRoll = nil, nil
  local _, result = calc:calculateDamage(spec)
  assert(not result.isCritical and result.critChance == 1 / 16 and #calls == 2)
  assert(calls[1][1] == nil and calls[2][1] == 217 and result.randomRoll == 217)
  chanceRoll = 1 / 16 - 0.00001
  _, result = calc:calculateDamage(spec)
  assert(result.isCritical)
  calls = {}; spec.critChance, spec.critChanceBonus = 0.9, 0.2
  _, result = calc:calculateDamage(spec)
  assert(result.isCritical and result.critChance == 1 and #calls == 1)
  calls = {}; spec.isCritical, spec.randomRoll = false, 255
  _, result = calc:calculateDamage(spec)
  assert(not result.isCritical and #calls == 0)
  spec.isCritical, spec.critChance, spec.critChanceBonus = nil, 0, 0
  _, result = calc:calculateDamage(spec)
  assert(not result.isCritical and #calls == 0)
end)

test("physical and special formulas use effective stats but never mutate stages", function()
  local spec = request { element = {} }
  spec.from.stat.spatk = 600
  spec.type = "special"
  assert(calculator():calculateDamage(spec) == 254)
  spec.from.statStages:set("spatk", 1)
  spec.to.statStages:set("spdef", 2)
  spec.isCritical = true
  local amount = calculator():calculateDamage(spec)
  assert(amount == 382 and spec.to.statStages.spdef == 2 and spec.from.statStages.spatk == 1)
end)

test("direct elemental values remain deterministic unless attack modifiers are explicitly enabled", function()
  local calc, target = calculator(), pet { element = { "Water" } }
  local spec = { from = pet { element = { "Electric" } }, to = target, baseDamage = 100, element = { "Electric" } }
  local amount, result = calc:calculateDamage(spec)
  assert(amount == 200 and not result.isCritical and result.stabMultiplier == 1 and result.randomRoll == 255)
  spec.applyAttackModifiers, spec.isCritical, spec.randomRoll = true, true, 255
  assert(calc:calculateDamage(spec) == 600)
  spec.power, spec.type, spec.baseDamage = 0, "physical", nil
  amount, result = calc:calculateDamage(spec)
  assert(amount == 0 and not result.isCritical)
end)

test("skill defaults preserve explicit zero chance and imported critical attributes validate", function()
  assert(Skill:new(1).critChance == 1 / 16)
  local Engine = require "seer.core.engine"
  local engine = Engine:new()
  engine:registerSkill { id = 1, critChance = 0 }
  engine:registerSkill { id = 2 }
  assert(engine:createSkill(1).critChance == 0 and engine:createSkill(2).critChance == 1 / 16)
  local attacker = pet { critChanceBonus = 0.2, critResistance = 0.35 }
  assert(attacker.critChanceBonus == 0.2 and attacker.critResistance == 0.35)
  rejects(function() pet { critResistance = 1.1 } end)
  rejects(function() pet { critResistance = false } end)
  rejects(function() pet { critChanceBonus = math.huge } end)
end)

test("invalid requests fail before consuming randomness and seeded rolls replay", function()
  local draws = 0
  local calc = calculator(function() draws = draws + 1; return 0.5 end)
  for _, override in ipairs { { critChance = -0.1 }, { critResistance = 1.1 },
      { randomRoll = 216 }, { randomRoll = 255.5 }, { isCritical = 1 },
      { applyAttackModifiers = "yes" }, { baseDamage = 0/0 }, { critChanceBonus = math.huge } } do
    rejects(function() calc:calculateDamage(request(override)) end)
  end
  assert(draws == 0)
  local function sequence(seed)
    local rng, results = Random(seed), {}
    local controller = calculator(function(_, low, high) return rng:random(low, high) end)
    local spec = request(); spec.isCritical, spec.randomRoll = nil, nil
    for _ = 1, 12 do
      local amount, result = controller:calculateDamage(spec)
      results[#results + 1] = table.concat({ amount, result.randomRoll, tostring(result.isCritical) }, ":")
    end
    return table.concat(results, ",")
  end
  assert(sequence(20261031) == sequence(20261031))
  assert(sequence(20261031) ~= sequence(20261030))
end)

print(string.format("%d damage formula tests passed", passed))
