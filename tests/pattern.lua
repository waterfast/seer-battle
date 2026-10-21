-- Run from the project root: lua tests/pattern.lua (Lua 5.3 or newer).
local scriptDirectory = arg[0]:match("^(.*[/\\])") or "./"
local root = scriptDirectory .. "../"
package.path = root .. "?.lua;" .. root .. "?/init.lua;"
    .. root .. "basescripts/?.lua;" .. package.path
kt = { class = require "lib.middleclass" }

local Pattern = require "seer.core.pattern.pattern"
local StatPattern = require "seer.core.pattern.stat_pattern"
local ElementPattern = require "seer.core.pattern.element_pattern"
local Element = require "seer.core.element"
local StatStages = require "seer.core.stat-stages"
local passed = 0

local function test(name, fn)
    fn()
    passed = passed + 1
    print("PASS " .. name)
end

local function equal(actual, expected)
    assert(#actual == #expected, "array lengths differ")
    for index, value in ipairs(expected) do
        assert(actual[index] == value, "array values differ at " .. index)
    end
end

local function rejects(fn)
    assert(not pcall(fn), "invalid input must fail")
end

test("subclasses share matching and respect domain boundaries", function()
    local attacks = StatPattern:new { "atk", "spatk" }
    assert(attacks:isInstanceOf(Pattern))
    assert(ElementPattern:new():isInstanceOf(Pattern))
    assert(attacks:match("atk") and attacks:match("spatk"))
    assert(not attacks:match("speed") and not attacks:match("typo"))
    rejects(function() StatPattern:new { "hp" } end)
    rejects(function() StatPattern:new { Element.Fire } end)
    rejects(function() ElementPattern:new { "atk" } end)
end)

test("omitted selection, empty selection and exclusions are distinct", function()
    equal(StatPattern:new():select(), { "atk", "def", "spatk", "spdef", "speed", "accuracy" })
    equal(StatPattern:new({}):select(), {})
    equal(StatPattern:new(nil, { "accuracy" }):select(), { "atk", "def", "spatk", "spdef", "speed" })
    equal(StatPattern:new({ "atk", "spatk" }, { "atk" }):select(), { "spatk" })
    rejects(function() StatPattern:new(nil, { "typo" }) end)
end)

test("selection preserves candidate order, removes duplicates and copies configuration", function()
    local included, excluded = { "atk", "spatk", "atk" }, { "speed" }
    local rule = StatPattern:new(included, excluded)
    included[1], excluded[1] = "def", "atk"
    equal(rule:select({ "spatk", "atk", "spatk", "unknown", "speed" }), { "spatk", "atk" })
    local selected = rule:select()
    selected[1] = "def"
    equal(rule:select(), { "atk", "spatk" })
    local names = StatStages.getNames()
    names[1] = "hp"
    assert(StatPattern:new():match("atk"))
end)

test("element rules distinguish any from all without imposing exact combinations", function()
    local fire = ElementPattern:new { Element.Fire }
    assert(fire:matchAny { Element.Fire, Element.Fighting })
    assert(not fire:matchAll { Element.Fire, Element.Fighting })
    local rule = ElementPattern:new { Element.Fire, Element.Water, Element.Grass }
    assert(rule:matchAll { Element.Water, Element.Grass })
    assert(not rule:matchAny { Element.Ice })
    assert(not rule:matchAll {} and not rule:matchAny {})
    -- 属性技能的空元素数组不会被误认为满足全部条件。
    assert(not ElementPattern:new():matchAll {})
    assert(not rule:matchAll { "unknown" })
    assert(ElementPattern:new(nil, { Element.Fire }):match(Element.Water))
    assert(not ElementPattern:new(nil, { Element.Fire }):match(Element.Fire))
    local all, count = ElementPattern:new():select(), 0
    for _ in pairs(Element.chart) do count = count + 1 end
    assert(#all == count)
    for index = 2, #all do assert(all[index - 1] < all[index]) end
end)

test("malformed rule and candidate arrays fail instead of silently truncating", function()
    for _, bad in ipairs({ false, "atk", { stat = "atk" }, { [2] = "atk" },
        { "atk", [3] = "speed" }, { 1 }, { [0] = "atk" } }) do
        rejects(function() StatPattern:new(bad) end)
        rejects(function() StatPattern:new(nil, bad) end)
        rejects(function() StatPattern:new():select(bad) end)
        rejects(function() StatPattern:new():matchAny(bad) end)
        rejects(function() StatPattern:new():matchAll(bad) end)
    end
end)

test("selecting positive stages leaves negative and unselected stages intact", function()
    local stages = StatStages:new()
    stages:changeMany { atk = 2, spatk = -1, speed = 3 }
    local changes = {}
    for _, name in ipairs(StatPattern:new({ "atk", "spatk" }):select()) do
        local stage = stages:get(name)
        if stage > 0 then
            changes[name] = -stage
        end
    end
    stages:changeMany(changes)
    assert(stages:get("atk") == 0 and stages:get("spatk") == -1 and stages:get("speed") == 3)
end)

print(string.format("%d pattern tests passed", passed))
