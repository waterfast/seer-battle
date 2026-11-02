-- Run with Lua 5.5 from the project root: lua55 tests/battle_flow.lua
-- Host transport is replaced; the real Context, Logic, async scheduler and GameEvents run.
local scriptDirectory = arg[0]:match("^(.*[/\\])") or "./"
local root = scriptDirectory .. "../"
package.path = root .. "?.lua;" .. root .. "?/init.lua;"
  .. root .. "basescripts/?.lua;" .. root .. "basescripts/?/init.lua;" .. package.path
kt = { class = require "lib.middleclass", tablib = require "corelib.tablib", json = require "lib.json" }
require "seer.init"
local notifications, hostEvents = {}, {}
kt.log = { info = function() end, critical = function(msg) error(msg) end }
kt.rand = function()
  return { random = function(_, m, n)
    if not m then return 0.5 end
    if m == 217 and n == 255 then return 255 end
    return n and m or 1
  end }
end
kt.gamethread = { id = 1, bindCoroutineToContext = function() end, removeContext = function() end }
kt.c = {
  luaEvent = function(name) hostEvents[#hostEvents + 1] = name end,
  notifySocket = function(_, command, data)
    notifications[#notifications + 1] = { command = command, data = kt.json.decode(data) }
  end,
  requestSocket = function(_, _, _, _, _, cb)
    cb(nil, kt.json.encode({ skillId = -99, targetId = -1 }))
  end,
}
local async = require "corelib.async"
local GameEvent = require "gamethread.gameevent"
local BaseLogic = require "gamethread.gamelogic"
local Logic = require "seer.gamethread.gamelogic"
local Context = require "seer.gamethread.game-context"
local Player = require "gamethread.player"
local Effect = require "seer.core.effect_type.trigger"
require "seer.core.events"
local E = sr
local Flow = require "seer.gamethread.events.gameflow"
local passed = 0

local function run(fn)
  local completed, ok, err
  async.newscope():spawn(function()
    ok, err = xpcall(fn, debug.traceback)
    completed = true
  end)
  assert(completed, "test unexpectedly suspended")
  assert(ok, err)
end
local function test(name, fn)
  run(fn)
  passed = passed + 1
  print("PASS " .. name)
end
local function spec(id)
  return { id = id, pet_id = 100 + id, name = "Pet" .. id, level = 50,
    atk = 100, def = 100, spatk = 80, spdef = 100, speed = 50,
    hp = 100, maxHp = 100, skills = { 1, 2 } }
end
local function makeContext(options)
  options = options or {}
  local boardgame = { id = "seer", logicClass = Logic, skills = {
    [1] = { name = "Attack", power = options.power or 50, pp = 20 },
    [2] = { name = "Status", power = 0, category = "status", pp = 20 },
  } }
  sr.skills = boardgame.skills
  local data = { id = 1, seed = options.seed, battleData = { players = { [11] = {pets={spec(1)}}, [22] = {pets={spec(2)}} }, maxRounds = 3 } }
  local ctx = Context:new(boardgame, data)
  for _, id in ipairs({11, 22}) do
    local user = { id = id, username = "User", state = "robot", notify = function() end,
      request = function() return options.reply end }
    local player = Player:new(user)
    player.ctx = ctx
    ctx.players[#ctx.players + 1] = player
  end
  ctx.logic = Logic:new(ctx)
  return ctx
end
local function prepared(options)
  local ctx = makeContext(options)
  ctx.logic:prepareRoom()
  ctx.logic:loadRoleData()
  return ctx, ctx.logic, ctx.pets[1], ctx.pets[2]
end
local function effect(event, priority, use)
  local skeleton = sr.createEffectSkeleton { id = 1, name = "test", event = event }
  local item = Effect:new(skeleton)
  item.priority = priority or 1
  function item:triggerable() return true end
  item.use = use or function() end
  return item
end

test("abnormal application nests buff addition with ordered timing and isolated instances", function()
  local ctx, logic, a, b = prepared()
  local definition = sr:getBuff(10021)
  local BuffEvents = require "seer.gamethread.events.buff"
  local order = {}
  for _, timing in ipairs({ sr.PreAbnormal, sr.AbnormalCaused, sr.AbnormalInflicted,
      sr.BeforeBuffAdded, sr.BuffAdded, sr.BuffAddFinished, sr.AbnormalApplied, sr.AbnormalFinished }) do
    logic:addEffect(effect(timing, 1, function(self, event, target, owner, data)
      order[#order + 1] = event.class.name
      assert(data.who == b and data.from == a and data.skill == a.skills[1])
      assert(target == (timing == sr.AbnormalCaused and a or b))
      if timing == sr.BeforeBuffAdded then
        assert(logic:getCurrentEvent():findParent(BuffEvents.ApplyAbnormal))
        data.buff.turn = 2
      end
    end))
  end
  -- addBuff 的异常分派与显式 applyAbnormal 一样，不能绕过异常检查。
  assert(ctx:addBuff { from = a, who = b, buff = definition.id, skill = a.skills[1] })
  assert(table.concat(order, ",") == "sr.PreAbnormal,sr.AbnormalCaused,sr.AbnormalInflicted,sr.BeforeBuffAdded,sr.BuffAdded,sr.BuffAddFinished,sr.AbnormalApplied,sr.AbnormalFinished")
  local buff = ctx:getBuff(b, definition.id)
  assert(buff and buff.owner == b and buff.turn == 2 and definition.turn == nil)
  assert(not ctx:applyAbnormal { from = a, who = b, buff = definition.id, skill = a.skills[1] })
  assert(#b.buffs == 1 and ctx:getBuff(b, definition.id) == buff)
  assert(#logic.gameEventStack == 0 and #logic.triggerStack == 0)
end)

test("abnormal immunity and general buff prevention retain finished timings", function()
  local ctx, logic, a, b = prepared()
  local poison = sr:getBuff(10021)
  local guard = sr:getBuff(10022)
  local applied, finished, added = 0, 0, 0
  logic:addEffect(effect(sr.AbnormalInflicted, 1, function(self, event, target, owner, data)
    assert(target == b)
    data:preventBuff()
  end))
  logic:addEffect(effect(sr.AbnormalApplied, 1, function() applied = applied + 1 end))
  logic:addEffect(effect(sr.AbnormalFinished, 1, function(self, event, target, owner, data)
    assert(data.prevented and not data.added)
    finished = finished + 1
  end))
  logic:addEffect(effect(sr.BeforeBuffAdded, 1, function() added = added + 1; return true end))
  assert(not ctx:applyAbnormal { from = a, who = b, buff = poison.id })
  assert(applied == 0 and finished == 1 and added == 0 and #b.buffs == 0)
  local buffFinished = 0
  logic:addEffect(effect(sr.BuffAddFinished, 1, function(self, event, target, owner, data)
    assert(data.prevented and not data.added)
    buffFinished = buffFinished + 1
  end))
  assert(not ctx:addBuff { from = a, who = b, buff = guard.id })
  assert(added == 1 and buffFinished == 1 and #b.buffs == 0)
end)

test("buff removal respects prevention, instance identity, ownership and expiry", function()
  local ctx, logic, a, b = prepared()
  local guard = sr:getBuff(10022)
  assert(ctx:addBuff { who = a, buff = guard.id })
  local buff = ctx:getBuff(a, guard.id)
  assert(not ctx:addBuff { who = b, buff = buff })
  assert(not pcall(function() ctx:addBuff { who = a, buff = guard } end))
  local prevention = logic:addEffect(effect(sr.BeforeBuffRemoved, 1, function(self, event, target, owner, data)
    assert(data.reason == "test")
    return true
  end))
  assert(not ctx:removeBuff { who = a, buff = buff, reason = "test" })
  assert(ctx:getBuff(a, guard.id) == buff and buff.owner == a)
  logic:removeEffect(prevention)
  buff.count = 0
  assert(not ctx:getBuff(a, guard.id) and ctx:getBuff(a, guard.id, true) == buff)
  local entries = logic:collectEffects()
  for _, entry in ipairs(entries) do assert(entry.effect ~= buff.effects[1]) end
  assert(ctx:removeBuff { who = a, buff = buff, reason = "expired" })
  assert(buff.owner == nil and #a.buffs == 0 and not ctx:removeBuff { who = a, buff = guard.id })
end)

test("nested buff additions cannot create duplicate ids and finished games reject mutation", function()
  local ctx, logic, a = prepared()
  local guard = sr:getBuff(10022)
  local nested = false
  logic:addEffect(effect(sr.BeforeBuffAdded, 1, function()
    if not nested then
      nested = true
      assert(ctx:addBuff { who = a, buff = guard.id })
    end
  end))
  assert(not ctx:addBuff { who = a, buff = guard.id })
  assert(#a.buffs == 1)
  ctx.gameFinished = true
  assert(not ctx:removeBuff { who = a, buff = a.buffs[1] })
  assert(#a.buffs == 1)
  local _, _, _, other = prepared()
  assert(not pcall(function() ctx:addBuff { who = other, buff = guard.id } end))
end)

test("strengthen and weaken wrappers use the same basic stage event", function()
  local ctx, logic, a = prepared()
  local order = {}
  a.statStages:set("atk", 5)
  for _, timing in ipairs({ sr.BeforeStageChange, sr.StagesChanged, sr.StageChangeFinished }) do
    logic:addEffect(effect(timing, 1, function(self, event, target, owner, data)
      assert(target == a and data.reason == sr.ReasonStrengthen)
      order[#order + 1] = event.class.name
      if timing == sr.StagesChanged then
        assert(data.oldStages.atk == 5 and data.newStages.atk == 6 and data.actualChanges.atk == 1)
      end
    end))
  end
  local spec = { from = a, who = a, skill = a.skills[1], changes = { atk = 3, speed = 1 } }
  local actual = ctx:strengthen(spec)
  assert(actual.atk == 1 and actual.speed == 1 and spec.changes.atk == 3 and spec.reason == nil)
  assert(table.concat(order, ",") == "sr.BeforeStageChange,sr.StagesChanged,sr.StageChangeFinished")
  -- 新上下文只监听弱化，不混入上面的强化断言。
  local ctx2, logic2, b = prepared()
  local weakened = 0
  logic2:addEffect(effect(sr.BeforeStageChange, 1, function(self, event, target, owner, data)
    assert(data.reason == sr.ReasonWeaken and data.changes.def == -2)
  end))
  logic2:addEffect(effect(sr.StagesChanged, 1, function() weakened = weakened + 1 end))
  assert(ctx2:weaken { who = b, changes = { def = 2 } }.def == -2)
  assert(b.statStages.def == -2 and weakened == 1)
end)

test("stage immunity, partial changes, capping and explicit reasons share one commit path", function()
  local ctx, logic, a = prepared()
  local changed, finished = 0, 0
  logic:addEffect(effect(sr.StagesChanged, 1, function() changed = changed + 1 end))
  logic:addEffect(effect(sr.StageChangeFinished, 1, function() finished = finished + 1 end))
  local immunity = logic:addEffect(effect(sr.BeforeStageChange, 1, function(self, event, target, owner, data)
    data:preventStageChange()
  end))
  assert(next(ctx:strengthen { who = a, changes = { atk = 2 } }) == nil)
  assert(a.statStages.atk == 0 and changed == 0 and finished == 1)
  logic:removeEffect(immunity)
  local partial = logic:addEffect(effect(sr.BeforeStageChange, 1, function(self, event, target, owner, data)
    assert(data.reason == sr.ReasonStageChange)
    data.changes.atk = 0
  end))
  local actual = ctx:changeStages { who = a, reason = sr.ReasonStageChange, changes = { atk = 2, accuracy = -8 } }
  assert(actual.atk == 0 and actual.accuracy == -6 and a.statStages.accuracy == -6)
  assert(changed == 1 and finished == 2)
  logic:removeEffect(partial)
  assert(ctx:weaken { who = a, changes = { accuracy = 1 } }.accuracy == 0)
  assert(changed == 1 and finished == 3)
  assert(not pcall(function() ctx:weaken { who = a, changes = { atk = -1 } } end))
  assert(not pcall(function() ctx:changeStages { who = a, changes = { hp = 1 } } end))
  assert(not pcall(function() ctx:changeStages { who = a, reason = 99, changes = { atk = 1 } } end))
end)

test("clear boosts normalizes positive stages and uses common prevention timings", function()
  local ctx, logic, a = prepared()
  a.statStages:changeMany { atk = 3, def = -2, speed = 2, accuracy = 1 }
  local cleared, finished = 0, 0
  local block = logic:addEffect(effect(sr.BeforeStageChange, 1, function(self, event, target, owner, data)
    if data.reason == sr.ReasonClearBoosts then return true end
  end))
  logic:addEffect(effect(sr.StageChangeFinished, 1, function() finished = finished + 1 end))
  assert(next(ctx:clearBoosts { who = a }) == nil and a.statStages.atk == 3)
  logic:removeEffect(block)
  logic:addEffect(effect(sr.StagesChanged, 1, function(self, event, target, owner, data)
    assert(data.reason == sr.ReasonClearBoosts)
    cleared = cleared + 1
  end))
  local actual = ctx:clearBoosts { who = a, stats = { "atk", "def" } }
  assert(actual.atk == -3 and actual.def == nil and a.statStages.def == -2 and a.statStages.speed == 2)
  actual = ctx:clearBoosts { who = a }
  assert(actual.speed == -2 and actual.accuracy == -1 and a.statStages.def == -2)
  assert(cleared == 2 and finished == 3)
  ctx:clearBoosts { who = a }
  assert(cleared == 2 and finished == 4)
  local StageEvents = require "seer.gamethread.events.stage"
  local recorded = logic.eventRecorder[StageEvents.ChangeStages]
  assert(#recorded == 4 and recorded[2].data.operation == "clearBoosts" and recorded[2].data.stats[1] == "atk")
  assert(recorded[2].data.changes.atk == -3)
  assert(#logic.gameEventStack == 0 and #logic.triggerStack == 0)
end)

test("nested removal keeps replacement instances and invalid stage batches stay atomic", function()
  local ctx, logic, a = prepared()
  local guard = sr:getBuff(10022)
  assert(ctx:addBuff { who = a, buff = guard.id })
  local old = ctx:getBuff(a, guard.id)
  local replacement, nested = nil, false
  logic:addEffect(effect(sr.BeforeBuffRemoved, 1, function()
    if not nested then
      nested = true
      assert(ctx:removeBuff { who = a, buff = old })
      assert(ctx:addBuff { who = a, buff = guard.id })
      replacement = ctx:getBuff(a, guard.id)
    end
  end))
  assert(not ctx:removeBuff { who = a, buff = old })
  assert(replacement and replacement ~= old and ctx:getBuff(a, guard.id) == replacement)
  local invalid = logic:addEffect(effect(sr.BeforeStageChange, 1, function(self, event, target, owner, data)
    data.changes.def = "invalid"
  end))
  assert(not pcall(function() ctx:strengthen { who = a, changes = { atk = 2 } } end))
  assert(a.statStages.atk == 0 and a.statStages.def == 0)
  assert(#logic.gameEventStack == 0 and #logic.triggerStack == 0)
  logic:removeEffect(invalid)
  ctx.gameFinished = true
  assert(next(ctx:changeStages { who = a, changes = { atk = 2 } }) == nil)
  assert(a.statStages.atk == 0)
end)

test("CSV handles BOM quotes line endings and reports malformed input", function()
  local Csv = require "seer.core.csv_util"
  local rows, headers = Csv.parse('\239\187\191id,name,note\r\n1,"a,b","say ""hi"""\r\n2,test,"line1\nline2"', "sample")
  assert(#rows == 2 and headers[2] == "name" and rows[1].data.name == "a,b")
  assert(rows[1].data.note == 'say "hi"' and rows[2].data.note == "line1\nline2")
  for _, bad in ipairs({ 'id,id\n1,2', 'id,name\n1', 'id\n"open', 'id\n"ok"bad', 'id\na"b' }) do
    assert(not pcall(Csv.parse, bad, "bad.csv"))
  end
end)

local function csvEffects(references)
  return '"' .. kt.json.encode(references):gsub('"', '""') .. '"'
end

test("CSV config rejects bad data and keeps state out of buff definitions", function()
  local Csv = require "seer.core.csv_util"
  local Config = require "seer.core.csv_util.config"
  local function parse(text, kind)
    local rows, headers = Csv.parse(text, "inline.csv")
    return Config.convert(rows, headers, kind, "inline.csv")
  end
  local rows = parse('id,name,type,maxPp,element,effects\n8,测试,status,0,Fire|Water,' .. csvEffects({
    { id = 10011, on_usevalue = { stat = "atk", stages = 1 } }, { id = 10013, on_usevalue = { amount = 50 } },
  }), "skill")
  assert(rows[1].maxPp == 0 and #rows[1].element == 2 and #rows[1].effects == 2)
  assert(getmetatable(rows[1]) == nil)
  local engine = require("seer.core.engine"):new()
  engine.effects = sr.effects
  engine:registerSkill(rows[1])
  local instance = engine:createSkill(8)
  assert(instance.pp == 0 and instance.maxPp == 0 and instance.element[2] == "Water")
  assert(instance.effects[1].skeleton == sr:getEffect(10011) and rows[1].effects[1].id == 10011)
  local bad = {
    { "skill", 'id,name,type,maxPp\n1,a,status,5\n1,b,status,5' },
    { "skill", 'id,name,type,maxPp\n1,a,invalid,5' },
    { "skill", 'id,name,type,maxPp,accuracy\n1,a,status,5,101' },
    { "skill", 'id,name,type,maxPp,element\n1,a,status,5,Unknown' },
    { "skill", 'id,name,type,maxPp,effects\n1,a,status,5,1||2' },
    { "skill", 'id,name,type,maxPp\n1,a,status,' },
    { "buff", 'id,name,type,turn\n1,a,5,3' },
    { "buff", 'id,name,type\n1,a,6' },
    { "buff", 'id,name,type,dispellable\n1,a,5,yes' },
  }
  for _, case in ipairs(bad) do assert(not pcall(parse, case[2], case[1])) end
  local config = sr:getBuff(10021)
  assert(getmetatable(config) == nil and config.turn == nil and config.count == nil and config.value == nil)
  local plain = sr:createBuff(10021)
  assert(plain.turn == nil and not plain:isExpired())
  assert(not pcall(function() sr:createBuff(10021, { type = 8 }) end))
  local _, _, a, b = prepared()
  assert(a.ctx:addBuff { who = a, buff = 10021, state = { turn = 2 } })
  assert(a.ctx:addBuff { who = b, buff = 10021, state = { turn = 5 } })
  assert(a.buffs[1].turn == 2 and b.buffs[1].turn == 5 and config.turn == nil)
  assert(not pcall(function() a.ctx:addBuff { who = a, buff = plain, state = { turn = 3 } } end))
end)

test("trigger skeletons isolate condition and execution tables and forward the correct group", function()
  local Engine = require "seer.core.engine"
  local Skeleton = require "seer.core.effect_skeleton"
  local RuntimeEffect = require "seer.core.effect"
  local engine, calls = Engine:new(), {}
  local skeleton = Engine.createEffectSkeleton {
    id = 91001, name = "parameter test", event = sr.SkillHit,
    can_trigger = function(self, event, target, owner, data, parameters)
      assert(parameters == self.can_triggervalue and parameters ~= self.on_usevalue)
      calls[#calls + 1] = "condition"
      return parameters.enabled
    end,
    on_cost = function(self, event, target, owner, data, parameters)
      assert(parameters == self.on_usevalue)
      calls[#calls + 1] = "cost"
      return parameters.allowed
    end,
    on_use = function(self, event, target, owner, data, parameters)
      assert(parameters == self.on_usevalue)
      calls[#calls + 1] = "use"
      parameters.nested.amount = parameters.nested.amount + 1
      return true
    end,
  }
  engine:registerEffect(skeleton)
  local condition = { enabled = true, nested = { amount = 1 } }
  local execution = { allowed = false, nested = { amount = 5 } }
  local first = engine:createEffect(91001, condition, execution)
  local second = engine:createEffect(91001, condition, execution)
  assert(skeleton:isInstanceOf(Skeleton) and not skeleton:isInstanceOf(RuntimeEffect))
  assert(first:isInstanceOf(RuntimeEffect) and first.skeleton == engine:getEffect(91001))
  assert(first ~= second and first.on_usevalue ~= second.on_usevalue)
  assert(first:triggerable() and not first:cost())
  first.on_usevalue.allowed = true
  assert(first:cost() and first:use() == true)
  assert(table.concat(calls, ",") == "condition,cost,cost,use")
  assert(first.on_usevalue.nested.amount == 6 and second.on_usevalue.nested.amount == 5)
  assert(execution.nested.amount == 5 and first.can_triggervalue.nested.amount == 1)
  first.can_triggervalue.nested.amount = 9
  assert(condition.nested.amount == 1 and second.can_triggervalue.nested.amount == 1)
  local sameInput = engine:createEffect(91001, execution, execution)
  assert(sameInput.can_triggervalue.nested ~= sameInput.on_usevalue.nested)
  local empty = engine:createEffect(91001)
  assert(next(empty.can_triggervalue) == nil and next(empty.on_usevalue) == nil)
  assert(empty.can_triggervalue ~= empty.on_usevalue)
  assert(skeleton.can_triggervalue == nil and skeleton.on_usevalue == nil and first.value == nil)
  local extension = require("seer.core.package"):new("runtime_rejected", 911)
  assert(not pcall(function() extension:loadEffects(first) end))
  assert(not pcall(function() engine:registerEffect(first) end))
  assert(#extension.effects == 0 and engine:getEffect(91001) == skeleton)
end)

test("effect configuration validates both parameter groups before installation", function()
  local References = require "seer.core.csv_util.effects"
  for _, bad in ipairs({ '[10013]', '[null]', '{}', '[{"id":0}]', '[{"id":10013,"typo":5}]',
    '[{"id":10013,"value":50}]', '[{"id":10013,"on_usevalue":50}]',
    '[{"id":10013,"can_triggervalue":false}]' }) do
    assert(not pcall(References.parse, bad))
  end
  local badParameters = {
    { 10013, { amount = -1 } }, { 10013, { amount = "50" } }, { 10013, {} },
    { 10011, { stat = "hp", stages = 1 } }, { 10011, { stat = "atk", stages = -1 } },
    { 10011, { stat = "atk", stages = 1.5 } }, { 10014, { turns = 0 } }, { 10015, { ratio = 2 } },
  }
  for _, entry in ipairs(badParameters) do
    assert(not pcall(function() sr:createEffect(entry[1], {}, entry[2]) end))
  end
  for _, condition in ipairs({ false, 1, { hpBelow = 0 }, { hpBelow = 2 }, { hpBelow = false } }) do
    assert(not pcall(function() sr:createEffect(10013, condition, { amount = 50 }) end))
  end
  local cycle = {}; cycle.self = cycle
  assert(not pcall(function() sr:createEffect(10013, cycle, { amount = 50 }) end))
  assert(not pcall(function() sr:createEffect(10013, {}, cycle) end))
  local Package = require "seer.core.package"
  for index, reference in ipairs({
    { id = 10013, can_triggervalue = { hpBelow = -1 }, on_usevalue = { amount = 50 } },
    { id = 10013, can_triggervalue = {}, on_usevalue = { amount = -1 } },
  }) do
    local extension = Package:new("invalid_parameters" .. index, 910 + index)
    local definition = { id = 91030 + index, name = "bad heal", effects = { reference } }
    extension:addSkill(definition)
    local ok, message = pcall(function() extension:install(sr) end)
    assert(not ok and tostring(message):find(index == 1 and "can_triggervalue" or "on_usevalue", 1, true))
    assert(sr:getSkill(definition.id) == nil and sr:getPackage(extension.id) == nil and definition.package == nil)
  end
end)

test("one heal skeleton drives skills with different recovery values", function()
  local _, logic, a, b = prepared()
  sr:registerSkill { id = 92031, name = "heal 20", type = "status", maxPp = 5,
    effects = { { id = 10013, on_usevalue = { amount = 20 } } } }
  sr:registerSkill { id = 92032, name = "heal 60", type = "status", maxPp = 5,
    effects = { { id = 10013, on_usevalue = { amount = 60 } } } }
  a.skills = logic:createSkills { 92031, 92032 }
  logic:loseHp { who = a, num = 80 }
  assert(logic:useSkill { from = a, to = b, skill = a.skills[1] })
  assert(a:getHp() == 40)
  assert(logic:useSkill { from = a, to = b, skill = a.skills[2] })
  assert(a:getHp() == 100)
  local first, second = a.skills[1].effects[1], a.skills[2].effects[1]
  assert(first.skeleton == second.skeleton and first ~= second and first.on_usevalue.amount == 20 and second.on_usevalue.amount == 60)
  assert(first.source == a.skills[1] and first.owner == a)
  assert(sr:getEffect(10013).value == nil and sr:getSkill(92031).effects[1].on_usevalue.amount == 20)
end)

test("heal condition thresholds vary independently from recovery amounts", function()
  local _, logic, a, b = prepared()
  sr:registerSkill { id = 92531, name = "below half", type = "status", maxPp = 5,
    effects = { { id = 10013, can_triggervalue = { hpBelow = 0.5 }, on_usevalue = { amount = 20 } } } }
  sr:registerSkill { id = 92532, name = "below eighty percent", type = "status", maxPp = 5,
    effects = { { id = 10013, can_triggervalue = { hpBelow = 0.8 }, on_usevalue = { amount = 20 } } } }
  a.skills = logic:createSkills { 92531, 92532 }
  logic:loseHp { who = a, num = 50 }
  assert(logic:useSkill { from = a, to = b, skill = a.skills[1] } and a:getHp() == 50)
  logic:loseHp { who = a, num = 1 }
  assert(logic:useSkill { from = a, to = b, skill = a.skills[1] } and a:getHp() == 69)
  assert(logic:useSkill { from = a, to = b, skill = a.skills[2] } and a:getHp() == 89)
  assert(sr:getSkill(92531).effects[1].can_triggervalue.hpBelow == 0.5)
  assert(a.skills[1].effects[1].on_usevalue.amount == a.skills[2].effects[1].on_usevalue.amount)
end)

test("parameterized strengthening reuses stage manager immunity reasons and caps", function()
  local _, logic, a, b = prepared()
  sr:registerSkill { id = 93031, name = "atk and speed", type = "status", maxPp = 5,
    effects = { { id = 10011, on_usevalue = { stat = "atk", stages = 2 } },
      { id = 10011, on_usevalue = { stat = "speed", stages = 3 } } } }
  a.skills = logic:createSkills { 93031 }
  local changes = 0
  local blocker = logic:addEffect(effect(sr.BeforeStageChange, 1, function(_, _, _, _, data)
    assert(data.from == a and data.who == a and data.skill == a.skills[1])
    assert(data.reason == sr.ReasonStrengthen)
    if data.changes.speed then data:preventStageChange() end
  end))
  logic:addEffect(effect(sr.StagesChanged, 1, function() changes = changes + 1 end))
  assert(logic:useSkill { from = a, to = b, skill = a.skills[1] })
  assert(a.statStages.atk == 2 and a.statStages.speed == 0 and changes == 1)
  logic:removeEffect(blocker)
  a.statStages:set("atk", 5)
  assert(logic:useSkill { from = a, to = b, skill = a.skills[1] })
  assert(a.statStages.atk == 6 and a.statStages.speed == 3 and changes == 3)
  local first, second = a.skills[1].effects[1], a.skills[1].effects[2]
  assert(first ~= second and first.skeleton == second.skeleton)
  assert(first.on_usevalue.stat == "atk" and second.on_usevalue.stat == "speed")
  assert(#logic.gameEventStack == 0 and #logic.triggerStack == 0)
end)

test("buff effects use their own values while counters stay on their source buffs", function()
  local ctx, logic, a, b = prepared()
  sr:registerBuff { id = 94021, name = "guard 3", type = 8, effects = { { id = 10012, on_usevalue = { amount = 3 } } } }
  sr:registerBuff { id = 94022, name = "guard 7", type = 8, effects = { { id = 10012, on_usevalue = { amount = 7 } } } }
  assert(ctx:addBuff { who = a, buff = 94021, state = { count = 1 } })
  assert(ctx:addBuff { who = b, buff = 94022, state = { count = 1 } })
  local first, second = a.buffs[1].effects[1], b.buffs[1].effects[1]
  assert(first.source == a.buffs[1] and second.source == b.buffs[1])
  assert(first.skeleton == second.skeleton and first.on_usevalue.amount == 3 and second.on_usevalue.amount == 7)
  assert(logic:damage { from = a, to = b, damage = 20 } == 13)
  assert(logic:damage { from = b, to = a, damage = 20 } == 17)
  assert(#a.buffs == 0 and #b.buffs == 0)
  assert(sr:getBuff(94021).effects[1].on_usevalue.amount == 3 and sr:getBuff(94021).count == nil)
end)

test("effect folder imports single objects and lists in sorted file order", function()
  local Package = require "seer.core.package"
  local extension = Package:new("loader_test", 105)
  local first = sr.createEffectSkeleton { id = 10511, name = "single", event = sr.SkillHit }
  local second = sr.createEffectSkeleton { id = 10512, name = "list_a", event = sr.SkillHit }
  local third = sr.createEffectSkeleton { id = 10513, name = "list_b", event = sr.SkillHit }
  package.preload["test.effect_folder.a_single"] = function() return first end
  package.preload["test.effect_folder.b_list"] = function() return { second, third } end
  local previous = FileIO
  FileIO = { ls = function(path)
    assert(path == "test/effect_folder")
    return { "b_list.lua", "init.lua", "readme.md", "a_single.lua" }
  end }
  extension:loadEffectsByPath("test/effect_folder")
  FileIO = previous
  assert(#extension.effects == 3 and extension.effects[1] == first)
  assert(extension.effects[2] == second and extension.effects[3] == third)
  assert(first.id == 10511 and second.id == 10512)
  local Engine = require "seer.core.engine"
  extension:install(Engine:new())
  assert(first.id == 10511 and second.id == 10512 and third.id == 10513)
end)

test("translation keys support language selection and readable fallbacks", function()
  assert(sr:translate("standard.skill.spark") == "火花")
  assert(sr:translate("standard.skill.spark", "en_US") == "Ember")
  assert(sr:translate("standard.skill.spark", "fr_FR") == "火花")
  assert(sr:translate("missing.key", "en_US") == "missing.key")
  assert(require("packages.standard").skills[1].name == "standard.skill.spark")
  local Engine = require "seer.core.engine"
  assert(getmetatable(require("packages.standard").skills[1]) == nil)
end)

test("effect modules install local descriptions and defer translation until display", function()
  local engine = require("seer.core.engine"):new()
  local extension = require "packages.standard"
  extension:install(engine)
  local skeleton = engine:getEffect(10013)
  local runtime = engine:createEffect(10013, {}, { amount = 50 })
  assert(skeleton.description == "10013.description")
  assert(runtime.description == skeleton.description)
  assert(engine:translate(runtime.description) == skeleton.translations.zh_CN[skeleton.description])
  assert(engine:translate(runtime.description, "en_US") == skeleton.translations.en_US[skeleton.description])
  assert(engine:translate(runtime.description, "fr_FR") == engine:translate(runtime.description))
  assert(runtime.description == "10013.description")
end)

test("explicit ids survive package ordering and installation failures are atomic", function()
  local Engine = require "seer.core.engine"
  local Package = require "seer.core.package"
  local engine = Engine:new()
  local extension = Package:new("example", 101)
  local hit = engine.createEffectSkeleton { id = 10111, name = "hit", event = sr.SkillHit,
    can_trigger = function() return true end }
  local skill = { id = 10131, name = "example", maxPp = 5, effects = { hit.id } }
  local buff = { id = 10121, name = "example", effects = { hit.id } }
  assert(hit.id == 10111 and hit:createEffect():triggerable())
  assert(next(engine.effects) == nil and getmetatable(skill) == nil and getmetatable(buff) == nil)
  extension:addEffect(hit)
  extension:addSkill({ id = 10132, name = "inserted first" })
  extension:addSkill(skill)
  extension:addBuff(buff)
  extension:install(engine)
  assert(engine:getEffect(10111) == hit and engine:getBuff(10121) == buff)
  assert(engine:getSkill(10131) == skill and skill.package == extension)
  assert(not pcall(function() extension:install(engine) end))
  assert(not pcall(function() Package:new("other", 101):install(engine) end))
  assert(not pcall(function() Package:new("example", 102):install(engine) end))
  local conflict = Package:new("conflict", 103)
  local first = { id = 10331, name = "first" }
  conflict:addSkill(first)
  conflict:addBuff({ id = 10321, name = "bad reference", effects = { 99999 } })
  assert(not pcall(function() conflict:install(engine) end))
  assert(first.package == nil and engine:getSkill(10331) == nil and engine:getPackage(103) == nil)
  engine:registerSkill { id = 10331 }
  assert(not pcall(function() conflict:install(engine) end))
  assert(not pcall(function() engine.createEffectSkeleton { event = sr.SkillHit } end))
  assert(not pcall(function() engine.createEffectSkeleton { id = 1, type = -1 } end))
end)

test("standard buff instances resolve effects and isolate counters from configuration", function()
  local Engine = require "seer.core.engine"
  local extension = require "packages.standard"
  local standard = require "packages.standard"
  local ids = {
    skills = { strike = standard.skills[1].id, recover = standard.skills[2].id,
      focus = standard.skills[3].id, poison = standard.skills[4].id },
    buffs = { poison = 10021, guard = 10022 },
    effects = { recover = require("packages.standard.effects.heal").id,
      poisonTick = require("packages.standard.effects.poison_tick").id },
  }
  local engine = Engine:new()
  extension:install(engine)
  assert(sr:getPackage(100) == extension)
  assert(extension.skills[1].id == 10031 and extension.skills[1].name == "standard.skill.spark")
  assert(engine:getEffect(10011) and extension.buffs[1].id == 10021)
  local a, b = engine:createBuff(ids.buffs.poison, { turn = 3 }), engine:createBuff(ids.buffs.poison, { turn = 5 })
  assert(a ~= b and a.effects ~= b.effects and a.effects[1].skeleton == engine:getEffect(ids.effects.poisonTick) and a.effects[1] ~= b.effects[1])
  a:advanceRound()
  assert(a.turn == 2 and b.turn == 5 and engine:getBuff(ids.buffs.poison).turn == nil)
  assert(engine:getBuff(ids.buffs.poison).effects[1].id == ids.effects.poisonTick)
  assert(not pcall(function() engine:cloneBuff(-99) end))
end)

test("standard skills and buffs execute through the real battle pipeline", function()
  local _, logic, a, b = prepared()
  local standard = require "packages.standard"
  local ids = {
    skills = { strike = standard.skills[1].id, recover = standard.skills[2].id,
      focus = standard.skills[3].id, poison = standard.skills[4].id },
    buffs = { poison = 10021, guard = 10022 },
    effects = { recover = require("packages.standard.effects.heal").id,
      poisonTick = require("packages.standard.effects.poison_tick").id },
  }
  for _, definition in ipairs(require("packages.standard").skills) do sr:registerSkill(definition) end
  a.skills = logic:createSkills { ids.skills.recover, ids.skills.focus, ids.skills.poison, ids.skills.strike }
  local another = logic:createSkills { ids.skills.recover }
  assert(a.skills[1].effects[1].skeleton == sr:getEffect(ids.effects.recover))
  logic:loseHp { who = a, num = 60 }
  assert(logic:useSkill { from = a, to = b, skill = a.skills[1] })
  assert(a:getHp() == 90 and a.skills[1].pp == 4 and another[1].pp == 5)
  assert(sr:getSkill(ids.skills.recover).maxPp == 5 and sr:getSkill(ids.skills.recover).pp == nil)
  assert(logic:useSkill { from = a, to = b, skill = a.skills[2] })
  assert(a.statStages.atk == 1 and a:getAtk() == 150)
  assert(logic:useSkill { from = a, to = b, skill = a.skills[3] })
  assert(#b.buffs == 1 and b.buffs[1].turn == 3)
  assert(logic:useSkill { from = a, to = b, skill = a.skills[3] })
  assert(#b.buffs == 1) -- The example poison does not stack or refresh.
  for number = 1, 3 do
    logic.roundNumber = number
    logic:executeEvent(Flow.Turn, TurnData:new(a.player, { who = a.player, from = a, type = "pass" }))
    logic:finishRound(RoundData:new { number = number })
  end
  assert(b:getHp() == 64 and #b.buffs == 0)
  assert(sr:getBuff(ids.buffs.poison).turn == nil)
  local guard = sr:createBuff(ids.buffs.guard, { count = 2, value = 10 })
  assert(a.ctx:addBuff { who = b, buff = guard })
  assert(logic:damage { from = a, to = b, damage = 20 } == 10)
  assert(guard.count == 1)
  assert(logic:damage { from = a, to = b, damage = 20 } == 10)
  assert(#b.buffs == 0 and sr:getBuff(ids.buffs.guard).count == nil)
  assert(logic:damage { from = a, to = b, damage = 20 } == 20)
end)

test("generic abnormal buffs share the effect pipeline and isolate state", function()
  local Buff = require "seer.core.buff"
  local BuffType = require "seer.core.buff.type"
  local _, logic, a, b = prepared()
  local calls = 0
  local effects = { effect(sr.BeforeSkillUse, 1, function(self, event, target, owner)
    assert(owner == a)
    calls = calls + 1
  end) }
  local options = { type = BuffType.Abnormal, turn = 2, effects = effects }
  local abnormal = Buff:new(2001, "test abnormal", options)
  local other = Buff:new(2001, "test abnormal", options)
  assert(abnormal:isInstanceOf(Buff) and abnormal.type == BuffType.Abnormal)
  assert(abnormal.effects ~= effects and abnormal.effects ~= other.effects)
  a.buffs[#a.buffs + 1] = abnormal
  assert(logic:useSkill { from = a, to = b, skill = a.skills[1] })
  assert(calls == 1 and abnormal.turn == 2)
  assert(not abnormal:advanceRound())
  assert(abnormal:advanceRound() and abnormal:advanceRound())
  assert(abnormal.turn == 0 and other.turn == 2 and options.turn == 2)
  -- 该用例直接测试容器方法；局内寿命由 finishRound 统一推进。
  table.remove(a.buffs)
  assert(logic:useSkill { from = a, to = b, skill = a.skills[1] })
  assert(calls == 1)
end)

test("buff category is independent of optional and combined lifetime limits", function()
  local Buff = require "seer.core.buff"
  local BuffType = require "seer.core.buff.type"
  local persistent = Buff:new(1, "passive", { type = BuffType.Feature })
  assert(persistent.turn == nil and persistent.count == nil and persistent.stacks == nil)
  assert(not persistent:advanceRound() and persistent.turn == nil)
  assert(not persistent:consume() and not persistent:isExpired())
  local timed = Buff:new(2, "limited passive", { type = BuffType.Feature, turn = 3, count = 2 })
  assert(timed.type == persistent.type and not timed:advanceRound())
  assert(not timed:consume(3) and timed.count == 2)
  assert(timed:consume() and timed:consume() and timed:isExpired())
  assert(timed.turn == 2 and not timed:consume())
  local elapsed = Buff:new(3, "timed", { turn = 1, count = 5 })
  assert(elapsed:advanceRound() and not elapsed:consume() and elapsed.count == 5)
  local mark = Buff:new(4, "mark", { type = BuffType.Mark, stacks = 1, maxStacks = 3 })
  assert(mark:addStacks(9) == 2 and not mark:consumeStacks(4))
  assert(mark:consumeStacks(3) and mark:isExpired() and mark.turn == nil)
  local shield = Buff:new(5, "shield", { type = BuffType.Shield, value = 100, dispellable = false })
  assert(shield.value == 100 and not shield.dispellable and shield.turn == nil)
  shield.value = 0
  assert(not shield:isExpired()) -- Custom values do not imply a generic lifetime rule.
end)

test("buff options reject invalid counters and preserve explicit zero", function()
  local Buff = require "seer.core.buff"
  for _, key in ipairs({ "turn", "count", "stacks" }) do
    assert(Buff:new(1, nil, { [key] = 0 }):isExpired())
    for _, value in ipairs({ -1, 1.5, "2", false }) do
      assert(not pcall(function() Buff:new(1, nil, { [key] = value }) end))
    end
  end
  for _, options in ipairs({ { type = "Round" }, { type = "Abnormal" }, { type = -1 },
      { type = 6 }, { type = 7 }, { type = 99 }, { type = 1.5 }, { maxStacks = 2 },
      { stacks = 1, maxStacks = 0 }, { value = math.huge }, { dispellable = 1 } }) do
    assert(not pcall(function() Buff:new(1, nil, options) end))
  end
  local BuffType = require "seer.core.buff.type"
  assert(BuffType.None == 0 and BuffType.Abnormal == 5 and BuffType.Shield == 8)
  for _, kind in pairs(BuffType) do
    assert(math.type(kind) == "integer" and Buff:new(1, nil, { type = kind }).type == kind)
  end
  local buff = Buff:new(1)
  assert(not pcall(function() buff:consume(0) end))
  assert(not pcall(function() buff:addStacks() end))
  assert(buff.stacks == nil and buff.type == 0 and buff.dispellable)
end)

test("stat stages clamp, batch validate, reset and isolate pets", function()
  local _, _, a, b = prepared()
  assert(a.stat ~= b.stat and a.statStages ~= b.statStages)
  assert(a.statStages:set("atk", 99) == 6)
  assert(a.statStages:change("atk", 1) == 0)
  assert(a.statStages:change("atk", -99) == -12)
  assert(a.statStages:getMultiplier("atk") == 0.25)
  local changes = a.statStages:changeMany { atk = 7, speed = 2, accuracy = -1 }
  assert(changes.atk == 7 and a:getAtk() == 150 and a:getSpeed() == 100)
  assert(a.statStages:getMultiplier("accuracy") == 0.85)
  assert(not pcall(function() a.statStages:changeMany { atk = 1, evasion = 1 } end))
  assert(a.statStages.atk == 1 and b.statStages.atk == 0)
  assert(not pcall(function() a.statStages:set("speed", 1.5) end))
  a.statStages:reset()
  assert(a:getAtk() == 100 and a.statStages.accuracy == 0)
  local snapshot = a.stat:toTable()
  snapshot.atk = 999
  assert(a.stat.atk == 100)
  assert(not pcall(function() a.stat:setMany { atk = 200, hp = -1 } end))
  assert(a.stat.atk == 100)
end)

test("stages affect damage, turn order and accuracy", function()
  local ctx, logic, a, b = prepared()
  local normal = logic:calculateDamage(a, a.skills[1], b)
  a.statStages:change("atk", 2)
  assert(logic:calculateDamage(a, a.skills[1], b) > normal)
  b.statStages:change("def", 2)
  assert(logic:calculateDamage(a, a.skills[1], b) == normal)
  b.statStages:change("speed", 1)
  local actions = {
    { who = a.player, from = a, skill = a.skills[1] },
    { who = b.player, from = b, skill = b.skills[1] },
  }
  logic:sortActions(actions)
  assert(actions[1].from == b)
  a.statStages:set("accuracy", -6)
  ctx.random = function() return 26 end
  assert(logic:useSkill { from = a, to = b, skill = a.skills[1] })
  assert(b.stat.hp == 100 and a.skills[1].pp == 19)
  ctx.random = function(_, low) return low == 217 and 255 or 25 end
  assert(logic:useSkill { from = a, to = b, skill = a.skills[1] })
  assert(b.stat.hp < 100)
end)

test("sr engine initializes events and registers skill definitions", function()
  local Engine = require "core.engine"
  local SeerEngine = require "seer.core.engine"
  assert(sr:isInstanceOf(SeerEngine) and sr:isInstanceOf(Engine))
  assert(sr.RoundStart and sr.DamageFinished)
  assert(require "seer.init" == sr)
  local engine = SeerEngine:new()
  local skill = { id = 1001, name = "Attack", power = 50 }
  engine:registerSkill(skill)
  assert(engine:getSkill(1001) == skill and engine:getSkill(-1) == nil)
end)

test("battle skills import new fields and isolate PP and mutable containers", function()
  local ctx = makeContext()
  local sharedEffect = sr.createEffectSkeleton { id = 90001, name = "shared skeleton", event = E.SkillUsing }
  sr:registerEffect(sharedEffect)
  local definition = { name = "Special", power = 50, type = "special", category = "physical",
    element = { "Fire" }, hits = 3, critChance = 0.25, pp = 7, effects = { { id = sharedEffect.id, on_usevalue = { nested = { amount = 7 } } } } }
  sr.skills[1] = definition
  ctx.logic:prepareRoom()
  ctx.logic:loadRoleData()
  local first, second = ctx.pets[1].skills[1], ctx.pets[2].skills[1]
  local otherBattle = makeContext()
  sr.skills[1] = definition
  otherBattle.logic:prepareRoom()
  otherBattle.logic:loadRoleData()
  local third = otherBattle.pets[1].skills[1]
  assert(first.type == "special" and first.hits == 3 and first.critChance == 0.25)
  assert(first.element[1] == "Fire" and first.maxPp == 7)
  assert(first.effects[1].skeleton == sharedEffect and second.effects[1].skeleton == sharedEffect)
  assert(first.effects[1] ~= second.effects[1] and first.effects[1].source == first)
  first.effects[1].on_usevalue.nested.amount = 99
  assert(second.effects[1].on_usevalue.nested.amount == 7 and definition.effects[1].on_usevalue.nested.amount == 7)
  first.pp = first.pp - 1
  first.element[1] = "Water"
  table.remove(first.effects, 1)
  for _, skill in ipairs({second, third}) do
    assert(skill.pp == 7 and skill.element[1] == "Fire" and #skill.effects == 1)
  end
  assert(definition.pp == 7 and definition.element[1] == "Fire" and #definition.effects == 1)
end)

test("six pets per bag load through an independent data source", function()
  local ctx = makeContext()
  local source = {}
  for _, player in ipairs(ctx.players) do
    local data = { pets = {}, items = { [9001] = 3 } }
    for index = 1, 6 do
      local petData = spec(player.id * 10 + index)
      if index == 1 then petData.hp = 0 end
      data.pets[#data.pets + 1] = petData
    end
    source[player.id] = data
  end
  source[11].activePetId = 113
  ctx.battleData.players = nil
  function ctx:getPlayerBattleData(player)
    return source[player.id]
  end
  ctx.logic:prepareRoom()
  ctx.logic:loadRoleData()
  assert(#ctx.pets == 12)
  local first, second = ctx.players[1], ctx.players[2]
  assert(first.pet.id == 113 and second.pet.id == 222)
  assert(first.bag:getOwner() == first and #first.bag:getPets() == 6)
  assert(not first.bag:getPet(111).alive and #first.bag:getAlivePets() == 5)
  assert(first.bag:getPet(113) == first.pet and first.bag:getPet(-1) == nil)
  assert(first.bag:hasItem(9001, 3) and first.bag:getItemCount(-1) == 0)
  local items = first.bag:getItems()
  items[9001] = 0
  assert(first.bag:getItemCount(9001) == 3 and source[11].items[9001] == 3)
  local choices, targets = ctx.logic:getSkillChoices(first.pet)
  assert(#choices == 2 and #targets == 1 and targets[1] == second.pet.id)
  local reserve = second.bag:getPet(223)
  assert(not ctx.logic:canUseSkill(first.pet, first.pet.skills[1], reserve))
  reserve.effects = { effect(E.TurnStart, 1, function() error("reserve effect ran") end) }
  ctx.logic:trigger(E.TurnStart, first.pet, {})
end)

test("alive follows hp and a surviving reserve prevents premature defeat", function()
  local ctx, logic, a, b = prepared()
  local backup = logic:createPet(a.player, spec(3))
  a.player.bag.pets[#a.player.bag.pets + 1] = backup
  ctx.pets[#ctx.pets + 1] = backup
  local fainted = false
  logic:addEffect(effect(E.PetFainted, 1, function(_, _, target)
    if target == a then
      fainted = true
      assert(target.stat.hp == 0 and not target.alive)
    end
  end))
  assert(a.alive and backup.alive)
  logic:damage {from=b,to=a,damage=1000}
  assert(fainted and not a.alive and not logic:canAct(a.player))
  assert(not logic:checkGameOver() and not ctx.gameFinished)
  assert(logic:recover {who=a,num=100} == 0 and not a.alive)
  logic:loseHp {who=backup,num=1000}
  assert(#a.player.bag:getAlivePets() == 0)
  assert(logic:checkGameOver() and ctx.gameFinished)
end)

test("new skill type controls special damage and status skips base damage", function()
  local ctx = makeContext()
  sr.skills[1] = { name = "Special", type = "special", power = 50 }
  -- 正威力也不能让属性技能走普通伤害分支。
  sr.skills[2] = { name = "Status", type = "status", power = 100 }
  ctx.logic:prepareRoom()
  ctx.logic:loadRoleData()
  local a, b = ctx.pets[1], ctx.pets[2]
  a.stat.atk, a.stat.spatk, b.stat.def, b.stat.spdef = 1, 200, 100, 100
  assert(ctx.logic:calculateDamage(a, a.skills[1], b) == 46)
  ctx.logic:useSkill {from=a,to=b,skill=a.skills[1]}
  assert(b.stat.hp == 54 and a.skills[1].pp == 19)
  ctx.logic:useSkill {from=a,to=b,skill=a.skills[2]}
  assert(b.stat.hp == 54 and a.skills[2].pp == 19)
end)

test("passive skills cannot be selected or used as active moves", function()
  local ctx = makeContext()
  sr.skills[1] = { name = "Passive", type = "passive", power = 50 }
  ctx.logic:prepareRoom()
  ctx.logic:loadRoleData()
  local a, b = ctx.pets[1], ctx.pets[2]
  local choices = ctx.logic:getSkillChoices(a)
  assert(#choices == 1 and choices[1].id == 2)
  assert(not ctx.logic:getSelectedSkill(a.player, {type="skill",skillId=1,targetId=b.id}))
  assert(not ctx.logic:useSkill {from=a,to=b,skill=a.skills[1]})
  assert(a.skills[1].pp == 20 and b.stat.hp == 100)
end)

test("priority, stable ties, cost rejection, interruption and cost data isolation", function()
  local ctx, logic, a, b = prepared()
  local order = {}
  local first = effect(E.TurnStart, 3, function(self, ev, target, owner)
    assert(target == a and owner == b)
    assert(ev:getCostData(self, owner).paid)
    order[#order + 1] = "first"
  end)
  function first:cost(ev, target, owner)
    ev:setCostData(self, { paid = true }, owner)
    return true
  end
  logic:addEffect(first, b)
  local denied = effect(E.TurnStart, 2, function() error("cost rejected") end)
  function denied:cost() return false end
  logic:addEffect(denied, a)
  logic:addEffect(effect(E.TurnStart, 1, function() order[#order+1] = "tie1" end))
  logic:addEffect(effect(E.TurnStart, 1, function() order[#order+1] = "tie2"; return true end))
  logic:addEffect(effect(E.TurnStart, 0, function() error("must stop") end))
  local broken, ev = logic:trigger(E.TurnStart, a, {})
  assert(broken and ev.broken and table.concat(order, ",") == "first,tie1,tie2")
  assert(#logic.triggerStack == 0)
end)

test("nested trigger snapshot and effect removal", function()
  local _, logic, a = prepared()
  local calls = {}
  local added = false
  logic:addEffect(effect(E.TurnStart, 1, function()
    calls[#calls+1] = "outer"
    if not added then
      added = true
      logic:addEffect(effect(E.TurnStart, 0, function() calls[#calls+1] = "new" end))
      logic:trigger(E.TurnEnd, a, {})
    end
  end))
  local entry = logic:addEffect(effect(E.TurnEnd, 1, function() calls[#calls+1] = "inner" end))
  logic:trigger(E.TurnStart, a, {})
  assert(table.concat(calls, ",") == "outer,inner")
  logic:removeEffect(entry)
  logic:trigger(E.TurnStart, a, {})
  assert(table.concat(calls, ",") == "outer,inner,outer,new")
end)

test("damage stages, hp clamping, recovery and loss bypass damage hooks", function()
  local _, logic, a, b = prepared()
  local stages = {}
  for _, timing in ipairs({E.PreDamage, E.DamageCaused, E.DetermineDamageCaused,
      E.DamageInflicted, E.DetermineDamageInflicted, E.BeforeHpChanged,
      E.HpChanged, E.PetFainted, E.Damage, E.Damaged, E.DamageFinished}) do
    logic:addEffect(effect(timing, 1, function() stages[#stages+1] = timing.name end))
  end
  assert(logic:damage {from=a,to=b,damage=150} == 100 and b.stat.hp == 0)
  assert(#stages == 11 and stages[8] == E.PetFainted.name and stages[11] == E.DamageFinished.name)
  assert(logic:recover {who=b,num=50} == 0 and b.stat.hp == 0)
  assert(logic:loseHp {who=a,num=20} == 20 and a.stat.hp == 80)
  assert(logic:recover {who=a,num=100} == 20 and a.stat.hp == 100)
end)

test("prevent damage still finishes, before hp change can cancel", function()
  local _, logic, a, b = prepared()
  local finished = 0
  local blocker = logic:addEffect(effect(E.DamageInflicted, 1, function(_, _, _, _, data) data:preventDamage() end))
  logic:addEffect(effect(E.DamageFinished, 1, function() finished = finished + 1 end))
  assert(logic:damage {from=a,to=b,damage=20} == 0 and b.stat.hp == 100 and finished == 1)
  logic:removeEffect(blocker)
  logic:addEffect(effect(E.BeforeHpChanged, 1, function() return true end))
  assert(logic:damage {from=a,to=b,damage=20} == 0 and b.stat.hp == 100 and finished == 2)
end)

test("generic damage returns its settlement data without requiring an attack", function()
  local ctx, logic, _, b = prepared()
  local observed
  logic:addEffect(effect(E.HpChanged, 1, function(_, _, _, _, data)
    observed = data.damageEvent
  end))
  local actual, damage = ctx:damage { to = b, damage = 150, damageType = E.FixedDamage }
  assert(actual == 100 and damage.actualDamage == 100 and damage.damage == 150)
  assert(observed == damage and damage.from == nil and damage.skillUse == nil)
  assert(damage.damageType == E.FixedDamage and b.stat.hp == 0)

  b.stat.hp, b.alive = 100, true
  logic:addEffect(effect(E.PreDamage, 1, function(_, _, _, _, data) data:preventDamage() end))
  actual, damage = ctx:damage { to = b, damage = 20 }
  assert(actual == 0 and damage.actualDamage == 0 and damage.prevented and b.stat.hp == 100)
end)

test("skill damage links its source flow without passing it to additional fixed damage", function()
  local _, logic, a, b = prepared()
  local mainDamage, extraDamage, skillUse
  a.skills[1].effects = { sr:createEffect(10017, {}, { amount = 50 }) }
  logic:addEffect(effect(E.PreDamage, 1, function(_, _, _, _, data)
    if data.damageType == E.NormalDamage then
      mainDamage = data
      skillUse = data.skillUse
      assert(skillUse and skillUse.skill == a.skills[1])
      assert(data.calculation == skillUse.calculation and data.calculation.baseDamage == 24)
    else
      extraDamage = data
      assert(data.damageType == E.FixedDamage and data.skillUse == nil)
    end
  end))
  logic:addEffect(effect(E.AfterSkillDamage, 1, function(_, _, _, _, data)
    assert(data == skillUse and data.damageEvent == mainDamage)
    assert(data.actualDamage == mainDamage.actualDamage and data.actualDamage == 24)
  end))
  assert(logic:useSkill { from = a, to = b, skill = a.skills[1] })
  assert(mainDamage and extraDamage and extraDamage.actualDamage == 50 and b.stat.hp == 26)
end)

test("server rejects invalid skill, target, foreign pet and exhausted PP", function()
  local ctx, logic, a, b = prepared()
  assert(not logic:getSelectedSkill(ctx.players[1], {type="skill",skillId=99,targetId=b.id}))
  assert(not logic:getSelectedSkill(ctx.players[1], {type="skill",skillId=1,targetId=a.id}))
  assert(not logic:canUseSkill(a, b.skills[1], b))
  a.skills[1].pp = 0
  assert(not logic:getSelectedSkill(ctx.players[1], {type="skill",skillId=1,targetId=b.id}))
  local actions = logic:chooseActions()
  assert(actions[1].skill == a.skills[2] and actions[1].to == b)
end)

test("skill effects are scoped, status and miss skip damage, PP consumed", function()
  local _, logic, a, b = prepared()
  local hits = 0
  a.skills[1].effects = { effect(E.SkillUsing, 1, function() hits=hits+1 end) }
  logic:trigger(E.SkillUsing, a, {})
  assert(hits == 0)
  a.skills[1].accuracy = 0
  assert(logic:useSkill {from=a,to=b,skill=a.skills[1]})
  assert(hits == 1 and b.stat.hp == 100 and a.skills[1].pp == 19 and #logic.skillUseStack == 0)
  assert(logic:useSkill {from=a,to=b,skill=a.skills[2]})
  assert(b.stat.hp == 100 and a.skills[2].pp == 19)
  logic:trigger(E.SkillUsing, a, {})
  assert(hits == 1)
end)

test("round contains seat ordered turns and skip works", function()
  local ctx, logic, a = prepared()
  local turns = {}
  logic:addEffect(effect(E.TurnStart, 1, function(_, _, player) turns[#turns+1] = player.player.id end))
  logic:addEffect(effect(E.EventTurnChanging, 1, function(_, _, player, _, data)
    if player.player == ctx.players[2] then data.skipped=true end
  end))
  logic:executeEvent(Flow.Round, RoundData:new {number=1,turn_table={table.unpack(ctx.players)}})
  assert(#turns==1 and turns[1]==11 and ctx.current==nil and #logic.gameEventStack==0)
end)

test("failing effect restores trigger, skill scope and game event stacks", function()
  local _, logic, a, b = prepared()
  a.skills[1].effects = {
    effect(E.SkillUsing, 1, function() error("expected effect failure") end),
  }
  local ok, err = pcall(logic.useSkill, logic, {from=a,to=b,skill=a.skills[1]})
  assert(not ok and tostring(err):find("expected effect failure", 1, true))
  assert(#logic.triggerStack == 0)
  assert(#logic.skillUseStack == 0)
  assert(#logic.gameEventStack == 0)
end)

test("both actions are collected before faster pet attacks and knocks out opponent", function()
  local ctx, logic, a, b = prepared {power=500}
  local order = {}
  for _, player in ipairs(ctx.players) do
    player.user.request = function()
      order[#order + 1] = "choose" .. player.id
      return {type="skill",skillId=1,targetId=player == ctx.players[1] and b.id or a.id}
    end
  end
  b.stat.speed = a.stat.speed + 1
  local useSkill = logic.useSkill
  function logic:useSkill(data)
    order[#order + 1] = "use" .. data.from.player.id
    return useSkill(self, data)
  end
  logic:executeEvent(Flow.Round, RoundData:new {number=1})
  assert(table.concat(order, ",") == "choose11,choose22,use22")
  assert(a.stat.hp == 0 and b.stat.hp == b.stat.maxHp)
end)

test("action priority precedes speed", function()
  local _, logic, a, b = prepared()
  b.stat.speed = a.stat.speed + 100
  a.skills[1].priority = 1
  local actions = {
    ActionData:new {who=b.player,from=b,type="skill",skill=b.skills[1]},
    ActionData:new {who=a.player,from=a,type="skill",skill=a.skills[1]},
  }
  logic:sortActions(actions)
  assert(actions[1].from == a)
end)

test("complete run ends on knockout; trusted data is mandatory", function()
  local ctx = makeContext {power=500}
  local winner
  ctx.gameOver = function(self, result) self.gameFinished=true; winner=result.winners[1] end
  ctx.logic:run()
  assert(ctx.gameFinished and winner==11 and ctx.logic.roundNumber==1)
  assert(#ctx.logic.gameEventStack==0 and #ctx.logic.skillUseStack==0)
  local bad = makeContext()
  bad.battleData.players=nil
  assert(not pcall(bad.logic.loadRoleData, bad.logic))
end)

test("round limit ends a zero damage battle", function()
  local ctx = makeContext {power=0}
  local result
  ctx.gameOver = function(self, value) self.gameFinished=true; result=value end
  ctx.logic:run()
  assert(ctx.gameFinished and ctx.logic.roundNumber==3 and result==nil)
end)

test("timeout fallback samples legal skills using the room random source", function()
  local ctx, logic, a, b = prepared()
  local rolls = 0
  function ctx:random(low, high) rolls = rolls + 1; return high end
  local actions = logic:chooseActions()
  assert(actions[1].skill == a.skills[2] and actions[2].skill == b.skills[2])
  assert(rolls == 4)
  a.skills[2].pp = 0
  b.skills[2].type = "passive"
  actions = logic:chooseActions()
  assert(actions[1].skill == a.skills[1] and actions[2].skill == b.skills[1])
  for _, player in ipairs(ctx.players) do player.user.request = function() return {type="pass"} end end
  local before = rolls
  actions = logic:chooseActions()
  assert(actions[1].type == "pass" and actions[2].type == "pass" and rolls == before)
end)

test("prevented and exhausted actors do not receive requests", function()
  local ctx, logic, a, b = prepared()
  for _, player in ipairs(ctx.players) do player.user.request = function() error("must not ask") end end
  logic:addEffect(effect(E.BeforeActionChoice, 1, function(_, _, target) return target == a end))
  for _, skill in ipairs(b.skills) do skill.pp = 0 end
  local actions = logic:chooseActions()
  assert(actions[1].prevented and actions[2].type == "pass")
end)

test("skill damage and effect completion hooks run in order and report actual damage", function()
  local _, logic, a, b = prepared()
  local order = {}
  for _, timing in ipairs({E.BeforeSkillUse, E.SkillUsing, E.BeforeSkillHit, E.SkillHit,
      E.BeforeSkillDamage, E.AfterSkillDamage, E.SkillEffectFinished, E.SkillUseFinished}) do
    logic:addEffect(effect(timing, 1, function(_, _, _, _, data)
      order[#order + 1] = timing
      if timing == E.AfterSkillDamage then assert(data.actualDamage == 24) end
    end))
  end
  assert(logic:useSkill {from=a,to=b,skill=a.skills[1]})
  assert(#order == 8 and order[6] == E.AfterSkillDamage and order[8] == E.SkillUseFinished)
  order = {}
  assert(logic:useSkill {from=a,to=b,skill=a.skills[2]})
  assert(#order == 6 and order[5] == E.SkillEffectFinished)
  order = {}
  a.skills[1].accuracy = 0
  assert(logic:useSkill {from=a,to=b,skill=a.skills[1]})
  assert(#order == 4 and order[4] == E.SkillUseFinished)
end)

test("room seeds reproduce fallback choices and hit checks with independent RNGs", function()
  local previous = kt.rand
  kt.rand = require "lib.xoshiro256starstar"
  local first, second = makeContext {seed=20261021}, makeContext {seed=20261021}
  assert(first.secret.seed == 20261021 and second.secret.seed == 20261021)
  kt.rand = previous
  for _, ctx in ipairs({first, second}) do ctx.logic:prepareRoom(); ctx.logic:loadRoleData() end
  for _ = 1, 10 do
    local left, right = first.logic:chooseActions(), second.logic:chooseActions()
    for i = 1, 2 do assert(left[i].skill.id == right[i].skill.id) end
    assert(first.logic.battleController:checkHit(first.pets[1], first.pets[1].skills[1])
      == second.logic.battleController:checkHit(second.pets[1], second.pets[1].skills[1]))
  end
  assert(first.secret.rng ~= second.secret.rng)
end)

test("cancelled skill stages keep PP and completion hooks consistent", function()
  local _, logic, a, b = prepared()
  local effectsFinished, usesFinished, afterDamage = 0, 0, nil
  logic:addEffect(effect(E.SkillEffectFinished, 1, function() effectsFinished = effectsFinished + 1 end))
  logic:addEffect(effect(E.SkillUseFinished, 1, function() usesFinished = usesFinished + 1 end))
  logic:addEffect(effect(E.AfterSkillDamage, 1, function(_, _, _, _, data) afterDamage = data.actualDamage end))
  local blocker = logic:addEffect(effect(E.BeforeSkillUse, 1, function() return true end))
  assert(not logic:useSkill {from=a,to=b,skill=a.skills[1]})
  assert(a.skills[1].pp == 20 and usesFinished == 0)
  logic:removeEffect(blocker)
  blocker = logic:addEffect(effect(E.BeforeSkillHit, 1, function() return true end))
  assert(logic:useSkill {from=a,to=b,skill=a.skills[1],hit=true})
  assert(a.skills[1].pp == 19 and usesFinished == 1 and effectsFinished == 0)
  logic:removeEffect(blocker)
  logic:addEffect(effect(E.DamageInflicted, 1, function(_, _, _, _, data) data:preventDamage() end))
  assert(logic:useSkill {from=a,to=b,skill=a.skills[1]})
  assert(afterDamage == 0 and effectsFinished == 1 and usesFinished == 2 and b.stat.hp == 100)
end)

test("turn start cancellation stops the action and still clears the turn", function()
  local ctx, logic, a, b = prepared()
  local ended = 0
  logic:addEffect(effect(E.BeforeTurnStart, 1, function() return true end))
  logic:addEffect(effect(E.TurnEnd, 1, function() ended = ended + 1 end))
  logic:executeEvent(Flow.Turn, TurnData:new(a.player,
    ActionData:new {who=a.player,from=a,to=b,skill=a.skills[1],type="skill"}))
  assert(a.skills[1].pp == 20 and b.stat.hp == 100 and ended == 1 and ctx.current == nil)
end)

-- 延后驱动回调：真实验证等待期间已发出双方请求，而非仅使用同步替身。
local function deferredRequests(reverse)
  local ctx, logic, a, b = prepared()
  local pending, finished, failure = {}, false, nil
  for _, player in ipairs(ctx.players) do
    player.user.request = function(_, command, payload, timeout)
      assert(command == "Seer.ChooseAction" and timeout == 30 and payload.petId == player.pet.id)
      local ok, reply = async.await(async.wrap(function(callback)
        pending[player.id] = callback
      end)())
      assert(ok)
      return reply
    end
  end
  async.newscope():spawn(function()
    local ok, err = xpcall(function()
      local actions = logic:chooseActions()
      assert(actions[1].skill == a.skills[1] and actions[2].skill == b.skills[1])
    end, debug.traceback)
    finished, failure = true, not ok and err or nil
  end)
  assert(not finished and pending[11] and pending[22], "both requests must start before any reply")
  local first, second = reverse and 22 or 11, reverse and 11 or 22
  pending[first](nil, {type="skill",skillId=1,targetId=first == 11 and b.id or a.id})
  assert(not finished, "must wait for both replies")
  pending[second](nil, {type="skill",skillId=1,targetId=second == 11 and b.id or a.id})
  assert(finished and not failure, failure)
  passed = passed + 1
  print("PASS deferred parallel replies " .. (reverse and "reverse" or "forward"))
end
deferredRequests(false)
deferredRequests(true)

local function deferredHostTimeout()
  local User = require "server.user"
  local ctx, logic = prepared()
  local previous = kt.c.requestSocket
  local pending, finished, failure = {}, false, nil
  for _, player in ipairs(ctx.players) do
    player.user = User:new(player.id)
    player.user.state = "online"
  end
  kt.c.requestSocket = function(id, _, _, timeout, _, callback)
    assert(timeout == 30)
    pending[id] = callback
  end
  async.newscope():spawn(function()
    local ok, err = xpcall(function()
      local actions = logic:chooseActions()
      assert(actions[1].skill and actions[2].skill)
    end, debug.traceback)
    finished, failure = true, not ok and err or nil
  end)
  assert(pending[11] and pending[22] and not finished)
  pending[22](nil, "invalid json")
  assert(not finished)
  pending[11]("timeout")
  kt.c.requestSocket = previous
  assert(finished and not failure, failure)
  passed = passed + 1
  print("PASS host timeout and malformed JSON fall back after parallel requests")
end
deferredHostTimeout()

test("awaitall handles empty groups, mixed callbacks, nil results and task errors", function()
  assert(#async.awaitall().finished == 0)
  local group = async.awaitall(
    async.async(function() return nil, "tail" end)(),
    async.wrap(function(callback) callback(nil, 42) end)(),
    async.async(function() error("expected grouped failure") end)())
  local head, tail = group:getResult(1)
  assert(head == nil and tail == "tail" and group:getResult(2) == 42)
  assert(#group.finished == 3 and group.errmsg:find("expected grouped failure", 1, true))
end)

local function cancelPendingRound()
  local ctx, logic = prepared()
  local pending, finished, failure, cancellations = {}, false, nil, 0
  for _, player in ipairs(ctx.players) do
    player.user.request = function()
      return async.await(async.wrap(function(callback)
        pending[#pending + 1] = callback
        return function() cancellations = cancellations + 1 end
      end)())
    end
  end
  async.newscope():spawn(function()
    local ok, err = xpcall(function()
      logic:executeEvent(Flow.Round, RoundData:new {number=1})
    end, debug.traceback)
    finished, failure = true, not ok and err or nil
  end)
  assert(#pending == 2 and not finished)
  local round = logic.gameEventStack[1]
  round:shutdown()
  assert(finished and failure and failure:find(async.CANCELLED, 1, true) and round.interrupted, failure)
  assert(cancellations == 2 and #logic.gameEventStack == 0 and #logic.skillUseStack == 0)
  for _, callback in ipairs(pending) do callback(nil, {type="pass"}) end
  assert(#logic.gameEventStack == 0)
  passed = passed + 1
  print("PASS cancel pending round cleans events and ignores late replies")
end
cancelPendingRound()

local function testHostRun()
  notifications, hostEvents = {}, {}
  local boardgame = { id="seer", logicClass=Logic, skills={ [1]={name="Attack",power=500} } }
  sr.skills = boardgame.skills
  local left,right = spec(1),spec(2)
  left.skills,right.skills={1},{1}
  local ctx = Context:new(boardgame, {id=99, users={
    {id=11,connId=101,username="A",state="online"},
    {id=22,connId=102,username="B",state="online"},
  }, battleData={players={[11]={pets={left}},[22]={pets={right}}}}})
  ctx:run()
  assert(ctx.gameFinished and #ctx.logic.gameEventStack==0 and #ctx.logic.skillUseStack==0)
  local result
  for _, n in ipairs(notifications) do if n.command=="Room::GameOver" then result=n.data end end
  assert(result and result.winners[1]==11)
  assert(hostEvents[1]=="gameStart" and hostEvents[#hostEvents]=="gameOver")
end
testHostRun()
passed = passed + 1
print("PASS real Context.run/start with host request and notification adapters")

local function demoBattle()
  local ctx, logic, a, b = prepared()
  for _, definition in ipairs(require("test.seer_data").skills) do sr:registerSkill(definition) end
  a.skills = logic:createSkills { 101, 102, 301, 104 }
  a.stat.hp, a.stat.maxHp = 200, 400
  b.stat.hp, b.stat.maxHp = 1000, 1000
  return ctx, logic, a, b
end

test("demo strengthens all stages except special attack and respects cap", function()
  local ctx, logic, a, b = demoBattle()
  a.statStages:set("spatk", -2)
  ctx:useSkill { from = a, to = b, skill = a.skills[1] }
  for _, name in ipairs(require("seer.core.stat-stages").getNames()) do
    assert(a.statStages:get(name) == (name == "spatk" and -2 or 3))
  end
  for _ = 1, 2 do ctx:useSkill { from = a, to = b, skill = a.skills[1] } end
  for _, name in ipairs(require("seer.core.stat-stages").getNames()) do
    assert(a.statStages:get(name) == (name == "spatk" and -2 or 6))
  end
  assert(b.stat.hp == 1000 and a.skills[1].pp == 7)
  assert(#logic.gameEventStack == 0 and #logic.skillUseStack == 0)
end)

test("demo random weaken totals three and redistributes near lower cap", function()
  local ctx, logic, a, b = demoBattle()
  ctx:useSkill { from = a, to = b, skill = a.skills[2] }
  local sum = 0
  for _, stage in pairs(b.statStages:toTable()) do sum = sum + stage end
  assert(sum == -3 and a.statStages:get("atk") == 0)
  local names = require("seer.core.stat-stages").getNames()
  for _, name in ipairs(names) do b.statStages:set(name, -6) end
  b.statStages:set("accuracy", -5)
  ctx:useSkill { from = a, to = b, skill = a.skills[2] }
  assert(b.statStages:get("accuracy") == -6)
  -- 全部已到底时不再抽取，也不会卡死或越界。
  ctx:useSkill { from = a, to = b, skill = a.skills[2] }
  for _, name in ipairs(names) do assert(b.statStages:get(name) == -6) end
  assert(#logic.gameEventStack == 0 and #logic.triggerStack == 0)
end)

test("demo heals self by 100 capped at maximum", function()
  local ctx, logic, a, b = demoBattle()
  ctx:useSkill { from = a, to = b, skill = a.skills[3] }
  assert(a.stat.hp == 300 and b.stat.hp == 1000)
  a.stat.hp = 370
  ctx:useSkill { from = a, to = b, skill = a.skills[3] }
  assert(a.stat.hp == 400)
  assert(#logic.gameEventStack == 0)
end)

test("demo power 100 then separate fixed damage; no extra on miss or defeated target", function()
  local ctx, logic, a, b = demoBattle()
  local damages = {}
  logic:addEffect(effect(sr.DamageFinished, 1, function(self, event, target, owner, data)
    damages[#damages + 1] = { kind = data.damageType, amount = data.damage, actual = data.actualDamage }
  end))
  local expected = logic:calculateDamage(a, a.skills[4], b)
  ctx:useSkill { from = a, to = b, skill = a.skills[4] }
  assert(#damages == 2 and damages[1].kind == sr.NormalDamage and damages[1].amount == expected)
  assert(damages[2].kind == sr.FixedDamage and damages[2].amount == 50 and damages[2].actual == 50)
  assert(b.stat.hp == 1000 - expected - 50)
  ctx:useSkill { from = a, to = b, skill = a.skills[4], hit = false }
  assert(#damages == 2)
  b.stat.hp = 1
  ctx:useSkill { from = a, to = b, skill = a.skills[4] }
  assert(#damages == 3 and damages[3].actual == 1 and b.stat.hp == 0)
  assert(#logic.gameEventStack == 0 and #logic.skillUseStack == 0 and #logic.triggerStack == 0)
end)

test("standard stage change supports configured targets subsets and random strengthening", function()
  local ctx, logic, a, b = demoBattle()
  sr:registerSkill { id = 97031, name = "configured weaken", type = "status", effects = {
    { id = 10016, on_usevalue = { target = "target", stats = { "atk", "speed" }, stages = -2 } },
  } }
  sr:registerSkill { id = 97032, name = "configured random strengthen", type = "status", effects = {
    { id = 10016, on_usevalue = { target = "self", stats = { "def" }, mode = "random_total", stages = 3 } },
  } }
  a.skills = logic:createSkills { 97031, 97032 }
  ctx:useSkill { from = a, to = b, skill = a.skills[1] }
  assert(b.statStages:get("atk") == -2 and b.statStages:get("speed") == -2)
  assert(b.statStages:get("def") == 0 and a.statStages:get("atk") == 0)
  a.statStages:set("def", 5)
  ctx:useSkill { from = a, to = b, skill = a.skills[2] }
  assert(a.statStages:get("def") == 6 and b.statStages:get("def") == 0)
  assert(#logic.gameEventStack == 0)
end)

test("standard fixed damage uses each skill instance amount and shared skeleton", function()
  local ctx, logic, a, b = demoBattle()
  sr:registerSkill { id = 97033, name = "fixed 17", type = "physical", power = 1, effects = {
    { id = 10017, on_usevalue = { amount = 17 } },
  } }
  local first, second = sr:createSkill(97033), sr:createSkill(97033)
  assert(first.effects[1] ~= second.effects[1] and first.effects[1].skeleton == sr:getEffect(10017))
  first.effects[1].on_usevalue.amount = 23
  assert(second.effects[1].on_usevalue.amount == 17 and sr:getSkill(97033).effects[1].on_usevalue.amount == 17)
  a.skills = { first, second }
  local amounts = {}
  logic:addEffect(effect(sr.DamageFinished, 1, function(self, event, target, owner, data)
    if data.damageType == sr.FixedDamage then amounts[#amounts + 1] = data.actualDamage end
  end))
  for _, skill in ipairs(a.skills) do ctx:useSkill { from = a, to = b, skill = skill } end
  assert(#amounts == 2 and amounts[1] == 23 and amounts[2] == 17)
end)

test("standard stage and fixed damage reject invalid instance parameters", function()
  local stage = { target = "self", stats = { "atk" }, stages = 2 }
  local instance = sr:createEffect(10016, {}, stage)
  stage.stats[1] = "speed"
  assert(instance.on_usevalue.stats[1] == "atk" and instance.skeleton == sr:getEffect(10016))
  for _, parameters in ipairs({
    { target = "other", stages = 1 }, { target = "self", stages = 0 },
    { target = "self", stages = 1.5 }, { target = "self", stages = 1, mode = "unknown" },
    { target = "self", stages = 1, stats = { "hp" } },
    { target = "self", stages = 1, exclude = { "unknown" } },
  }) do assert(not pcall(sr.createEffect, sr, 10016, {}, parameters)) end
  for _, parameters in ipairs({ {}, { amount = 0 }, { amount = -1 }, { amount = 1.5 } }) do
    assert(not pcall(sr.createEffect, sr, 10017, {}, parameters))
  end
end)

test("special actions validate ownership and consume items once", function()
  local ctx, logic, a, b = prepared()
  a.player.bag.items[1] = 2
  a.stat.hp = 20
  assert(not logic:useItem { from = a, to = b, itemId = 1 })
  assert(logic:useItem { from = a, to = a, itemId = 1 })
  assert(a.stat.hp == 70 and a.player.bag.items[1] == 1)
  assert(logic:useItem { from = a, to = a, itemId = 1 })
  assert(a.stat.hp == 100 and a.player.bag.items[1] == 0)
end)

test("item cancellation preserves inventory and PP recovery clamps", function()
  local ctx, logic, a = prepared()
  a.player.bag.items[2] = 2
  a.skills[1].pp = a.skills[1].maxPp - 1
  assert(logic:useItem { from = a, to = a, itemId = 2 })
  assert(a.skills[1].pp == a.skills[1].maxPp)
  a.skills[1].pp = 0
  logic:addEffect(effect(sr.BeforeItemUse, 1, function(self, event, target, owner, data)
    data.prevented = true
  end))
  assert(not logic:useItem { from = a, to = a, itemId = 2 })
  assert(a.player.bag.items[2] == 1 and a.skills[1].pp == 0)
end)

test("switch cancellation, forced replacement and skill retargeting", function()
  local ctx, logic, a, b = prepared()
  local bench = logic:createPet(a.player, spec(3))
  table.insert(a.player.bag.pets, bench)
  table.insert(ctx.pets, bench)
  assert(not logic:switchPet { from = a, to = b })
  local blocker = effect(sr.BeforePetSwitch, 1, function(self, event, target, owner, data)
    data.prevented = true
  end)
  logic:addEffect(blocker)
  assert(not logic:switchPet { from = a, to = bench })
  a.alive, a.stat.hp = false, 0
  logic:replaceFaintedPets()
  assert(a.player.pet == bench)
  local pp = b.skills[1].pp
  logic:playTurn(TurnData:new(b.player, ActionData:new {
    who = b.player, from = b, to = a, type = "skill", skill = b.skills[1],
  }))
  assert(b.skills[1].pp == pp - 1 and bench.stat.hp < 100)
end)

test("request accepts item intent and standard ratio damage uses the damage pipeline", function()
  local ctx, logic, a, b = prepared { reply = { type = "item", itemId = 1, targetId = 1 } }
  a.player.bag.items[1] = 1
  a.stat.hp = 10
  local actions = logic:chooseActions()
  assert(actions[1].type == "item" and actions[1].to == a)
  logic:playTurn(TurnData:new(a.player, actions[1]))
  assert(a.stat.hp == 60)
  local ratio = sr:createEffect(10018, {}, { ratio = 0.25 })
  ratio.owner = a
  local skeleton = sr:getEffect(10018)
  skeleton.on_use(ratio, { ctx = ctx }, b, a, { from = a, to = b }, { ratio = 0.25 })
  assert(b.stat.hp == 75)
end)

test("clear boosts resolves selected stats after nested changes independently of reason", function()
  local ctx, logic, a = prepared()
  a.statStages:changeMany { atk = 3, def = 2 }
  local nested = false
  local hook = logic:addEffect(effect(sr.BeforeStageChange, 1, function(_, _, _, _, data)
    if data.operation == "clearBoosts" and not nested then
      nested = true
      ctx:changeStages { who = a, changes = { atk = -2 } }
    end
  end))
  local actual = ctx:clearBoosts { who = a, stats = { "atk" }, reason = sr.ReasonStageChange }
  assert(actual.atk == -1 and a.statStages.atk == 0 and a.statStages.def == 2)
  logic:removeEffect(hook)
  a.statStages:set("atk", 3)
  logic:addEffect(effect(sr.BeforeStageChange, 1, function(_, _, _, _, data)
    if data.operation == "clearBoosts" then a.statStages:set("atk", -1) end
  end))
  assert(next(ctx:clearBoosts { who = a, stats = { "atk" } }) == nil and a.statStages.atk == -1)
  assert(not pcall(function() ctx:clearBoosts { who = a, stats = { "hp" } } end))
end)

test("expired buffs are cleared before reapplication despite removal prevention", function()
  local ctx, logic, a = prepared()
  assert(ctx:addBuff { who = a, buff = 10022, state = { turn = 1 } })
  local old = ctx:getBuff(a, 10022)
  old.turn = 0
  logic:addEffect(effect(sr.BeforeBuffRemoved, 1, function(_, _, _, _, data)
    assert(data.forced and data.reason == "expired")
    data:preventBuff()
    return true
  end))
  assert(ctx:addBuff { who = a, buff = 10022, state = { turn = 3 } })
  assert(old.owner == nil and #a.buffs == 1 and a.buffs[1] ~= old and a.buffs[1].turn == 3)
end)

test("complete round advances buff lifetimes even when both actions pass", function()
  local ctx, logic, a = prepared { reply = { type = "pass" } }
  assert(ctx:addBuff { who = a, buff = 10022, state = { turn = 1 } })
  local buff = a.buffs[1]
  logic:executeEvent(Flow.Round, RoundData:new { number = 1 })
  assert(buff.owner == nil and buff.turn == 0 and #a.buffs == 0)
  assert(#logic.gameEventStack == 0 and logic.roundEndNumber == nil)
end)

test("opponent-start effects precede centralized expiry and count-only buffs do not tick", function()
  local ctx, logic, a, b = prepared()
  assert(ctx:applyAbnormal { from = a, who = b, buff = 10021, state = { turn = 1 } })
  assert(ctx:addBuff { who = a, buff = 10022, state = { count = 2 } })
  local poison, guard = b.buffs[1], a.buffs[1]
  logic.roundNumber = 1
  logic:executeEvent(Flow.Turn, TurnData:new(a.player, { who = a.player, from = a, type = "pass" }))
  logic:finishRound(RoundData:new { number = 1 })
  assert(b.stat.hp == 88 and poison.turn == 0 and poison.owner == nil and #b.buffs == 0)
  assert(guard.count == 2 and guard.turn == nil and guard.owner == a)
  logic:finishRound(RoundData:new { number = 1 })
  assert(b.stat.hp == 88 and guard.count == 2)
  assert(logic.roundEndNumber == nil and #logic.gameEventStack == 0)
end)

test("buffs added or replaced during round end keep their first duration", function()
  local ctx, logic, a = prepared()
  assert(ctx:addBuff { who = a, buff = 10022, state = { turn = 2 } })
  local old, replacement = a.buffs[1]
  logic:addEffect(effect(sr.RoundEnd, 1, function()
    if not replacement then
      assert(ctx:removeBuff { who = a, buff = old })
      assert(ctx:addBuff { who = a, buff = 10022, state = { turn = 1 } })
      replacement = a.buffs[1]
    end
  end))
  logic:finishRound(RoundData:new { number = 1 })
  assert(old.owner == nil and replacement.turn == 1 and replacement.firstTickRound == 2)
  logic:finishRound(RoundData:new { number = 2 })
  assert(replacement.owner == nil and #a.buffs == 0)
end)

test("switch clears default buffs but keeps explicit pet state and side marks", function()
  local ctx, logic, a = prepared()
  local bench = logic:createPet(a.player, spec(3))
  table.insert(a.player.bag.pets, bench)
  table.insert(ctx.pets, bench)
  sr:registerBuff { id = 95021, name = "retained", type = 3, keepOnSwitch = true }
  sr:registerBuff { id = 95022, name = "side mark", type = 3, scope = "side" }
  assert(ctx:applyAbnormal { who = a, buff = 10021, state = { turn = 3 } })
  assert(ctx:addBuff { who = a, buff = 95021, state = { turn = 1 } })
  assert(ctx:addBuff { who = a.player, buff = 95022, state = { turn = 2 } })
  local poison, retained, side = a.buffs[1], a.buffs[2], a.player.buffs[1]
  assert(not pcall(function() ctx:addBuff { who = a, buff = 95022 } end))
  assert(not pcall(function() ctx:addBuff { who = a.player, buff = 10022 } end))
  local left, entered, sideCalls = 0, 0, 0
  a.effects = { effect(sr.AfterPetLeave, 1, function() left = left + 1 end) }
  bench.effects = { effect(sr.AfterPetLeave, 1, function() error("new pet entered too early") end),
    effect(sr.BeforePetEnter, 1, function() entered = entered + 1 end) }
  local skeleton = sr.createEffectSkeleton { id = 95011, event = sr.TurnStart,
    can_trigger = function(_, _, _, owner) return owner == a.player end,
    on_use = function() sideCalls = sideCalls + 1 end }
  side.effects = { skeleton:createEffect({}, {}, side) }
  logic:addEffect(effect(sr.BeforeBuffRemoved, 1, function(_, _, _, _, data)
    if data.reason == "switch" then return true end
  end))
  a.statStages:set("atk", 2)
  assert(ctx:switchPet { from = a, to = bench })
  assert(left == 1 and entered == 1 and a.player.pet == bench and a.statStages.atk == 0)
  assert(poison.owner == nil and #a.buffs == 1 and retained.owner == a)
  assert(side.owner == a.player and a.player.buffs[1] == side)
  logic:trigger(sr.TurnStart, bench, {})
  assert(sideCalls == 1)
  logic:finishRound(RoundData:new { number = 1 })
  assert(retained.owner == nil and #a.buffs == 0 and side.turn == 1)
end)

test("buff effect consumption syncs counters and expires without script removal", function()
  local ctx, logic, a, b = prepared()
  sr:registerBuff { id = 95024, name = "undispellable guard", type = 8, dispellable = false,
    effects = { { id = 10012, on_usevalue = { amount = 10 } } } }
  assert(ctx:addBuff { who = a, buff = 95024, state = { count = 2 } })
  local buff, updates = a.buffs[1], {}
  assert(not ctx:removeBuff { who = a, buff = buff, reason = "dispel" })
  local broadcast = ctx.broadcast
  ctx.broadcast = function(self, command, data)
    if command == "Seer.BuffUpdated" then updates[#updates + 1] = data end
    return broadcast(self, command, data)
  end
  assert(ctx:damage { from = b, to = a, damage = 20 } == 10)
  assert(buff.count == 1 and updates[1].count == 1 and updates[1].scope == "pet")
  assert(ctx:damage { from = b, to = a, damage = 20 } == 10)
  assert(buff.owner == nil and #a.buffs == 0)
end)

test("round-end errors restore lifecycle scope and switch cleanup rejects new temporary buffs", function()
  local ctx, logic, a = prepared()
  local blocker = logic:addEffect(effect(sr.RoundEnd, 1, function() error("round-end failure") end))
  assert(not pcall(function() logic:finishRound(RoundData:new { number = 1 }) end))
  assert(logic.roundEndNumber == nil and #logic.gameEventStack == 0 and #logic.triggerStack == 0)
  logic:removeEffect(blocker)
  local bench = logic:createPet(a.player, spec(3))
  table.insert(a.player.bag.pets, bench)
  table.insert(ctx.pets, bench)
  assert(ctx:addBuff { who = a, buff = 10022 })
  logic:addEffect(effect(sr.BeforeBuffRemoved, 1, function(_, _, _, _, data)
    if data.reason == "switch" then
      assert(not ctx:applyAbnormal { who = a, buff = 10021, state = { turn = 2 } })
    end
  end))
  assert(ctx:switchPet { from = a, to = bench })
  assert(#a.buffs == 0 and not logic.leavingPets[a])
end)

test("removed buff candidates cannot run later in the same trigger snapshot", function()
  local ctx, logic, a = prepared()
  assert(ctx:addBuff { who = a, buff = 10022, state = { turn = 2 } })
  local buff, calls = a.buffs[1], 0
  local skeleton = sr.createEffectSkeleton { id = 95012, event = sr.TurnStart,
    can_trigger = function() return true end,
    on_use = function() calls = calls + 1 end }
  buff.effects = { skeleton:createEffect({}, {}, buff) }
  logic:addEffect(effect(sr.TurnStart, 10, function() ctx:removeBuff { who = a, buff = buff } end))
  logic:trigger(sr.TurnStart, a, {})
  assert(calls == 0 and buff.owner == nil)
end)

test("buff lifetime options load from CSV and cannot be overridden by state", function()
  local Config = require "seer.core.csv_util.config"
  local rows = { { line = 2, data = { id = "95023", name = "side", type = "3",
    scope = "side", keepOnSwitch = "true" } } }
  local defs = Config.convert(rows, { "id", "name", "type", "scope", "keepOnSwitch" }, "buff", "test")
  sr:registerBuff(defs[1])
  local buff = sr:createBuff(95023)
  assert(buff.scope == "side" and buff.keepOnSwitch)
  assert(not pcall(function() sr:createBuff(95023, { keepOnSwitch = false }) end))
  assert(not pcall(function() require("seer.core.buff"):new(1, nil, { scope = "wrong" }) end))
end)

test("passive elemental damage calculates independently of skill use and settles once", function()
  local ctx, logic, a, b = prepared()
  b.stat.maxHp, b.stat.hp = 1000, 1000
  b.element = { "Water" }
  local pp, depth = a.skills[1].pp, logic:getCurrentEventDepth()
  local amount, calculation = ctx:calculateDamage { to = b, baseDamage = 100, element = { "Electric" } }
  assert(amount == 200 and calculation.baseDamage == 100 and calculation.effectivenessMultiplier == 2)
  assert(a.skills[1].pp == pp and logic:getCurrentEventDepth() == depth and #logic.skillUseStack == 0)
  local actual, damage = ctx:damage { from = a, to = b, damage = amount, calculation = calculation }
  assert(actual == 200 and b.stat.hp == 800 and damage.calculation == calculation and damage.skillUse == nil)
  b.element = { "Ground" }
  assert(ctx:calculateDamage { to = b, baseDamage = 100, element = { "Electric" } } == 0)
  assert(ctx:damage { to = b, damage = 100, damageType = sr.FixedDamage } == 100)
  assert(not pcall(function() ctx:calculateDamage { to = b, baseDamage = -1 } end))
  b.element = { "Water" }
  a.skills[1].element = { "Electric" }
  local before = b.stat.hp
  assert(logic:calculateDamage(a, a.skills[1], b) == 48)
  assert(ctx:useSkill { from = a, to = b, skill = a.skills[1] })
  assert(b.stat.hp == before - 48 and a.skills[1].pp == pp - 1)
end)

test("critical skill damage exposes its calculation and breaks defense after settlement", function()
  local ctx, logic, a, b = prepared()
  b.statStages:changeMany { def = 2, spdef = 3 }
  local order = {}
  a.skills[1].effects = { sr:createEffect(10017, {}, { amount = 50 }) }
  logic:addEffect(effect(sr.PreDamage, 1, function(_, _, _, _, data)
    if data.damageType == sr.NormalDamage then
      assert(data.calculation.isCritical and data.skillUse.isCritical and data.damage == 26)
      assert(b.statStages.def == 2)
    else
      assert(data.damageType == sr.FixedDamage and data.calculation == nil and data.skillUse == nil)
    end
  end))
  logic:addEffect(effect(sr.DamageFinished, 1, function(_, _, _, _, data)
    if data.damageType == sr.NormalDamage then order[#order + 1] = "damage" end
  end))
  logic:addEffect(effect(sr.StagesChanged, 1, function(_, _, _, _, data)
    assert(data.reason == sr.ReasonCriticalBreak and data.actualChanges.def == -2)
    order[#order + 1] = "break"
  end))
  logic:addEffect(effect(sr.AfterSkillDamage, 1, function(_, _, _, _, data)
    assert(data.damageEvent.calculation == data.calculation and data.actualDamage == 26)
    order[#order + 1] = "after"
  end))
  assert(ctx:useSkill { from = a, to = b, skill = a.skills[1], isCritical = true, randomRoll = 255 })
  assert(table.concat(order, ",") == "damage,break,after")
  assert(b.statStages.def == 0 and b.statStages.spdef == 3 and b.stat.hp == 24)
end)

test("critical special damage resets only special defense and miss or prevention does not break", function()
  local ctx, logic, a, b = prepared()
  a.skills[1].type = "special"
  b.stat.hp, b.stat.maxHp = 1000, 1000
  b.statStages:changeMany { def = 3, spdef = -2 }
  logic:addEffect(effect(sr.SkillHit, 1, function(_, _, _, _, data)
    if data.skill == a.skills[1] then data.isCritical = true; data.randomRoll = 255 end
  end))
  assert(ctx:useSkill { from = a, to = b, skill = a.skills[1] })
  assert(b.stat.hp == 926 and b.statStages.spdef == 0 and b.statStages.def == 3)
  b.statStages:set("spdef", 2)
  local blocker = logic:addEffect(effect(sr.PreDamage, 1, function(_, _, _, _, data)
    assert(data.calculation.isCritical)
    data:preventDamage()
  end))
  assert(ctx:useSkill { from = a, to = b, skill = a.skills[1] })
  assert(b.stat.hp == 926 and b.statStages.spdef == 2)
  logic:removeEffect(blocker)
  a.skills[1].accuracy = 0
  local hitDraws = 0
  ctx.random = function(_, low, high)
    assert(low == 1 and high == 100, "miss must not draw critical or variance")
    hitDraws = hitDraws + 1
    return 100
  end
  assert(ctx:useSkill { from = a, to = b, skill = a.skills[1] })
  assert(hitDraws == 1 and b.stat.hp == 926 and b.statStages.spdef == 2)
  assert(#logic.gameEventStack == 0 and #logic.skillUseStack == 0)
end)




test("official dot statuses tick at opponent action start once per round", function()
  for _, id in ipairs({10021, 10023, 10024}) do
    local ctx, logic, a, b = prepared()
    logic.roundNumber = 1
    assert(ctx:applyAbnormal { from = a, who = b, buff = id, state = { turn = 2 } })
    logic:executeEvent(Flow.Turn, TurnData:new(b.player, { who = b.player, from = b, type = "pass" }))
    assert(b:getHp() == 100) -- 自己行动不扣血
    logic:executeEvent(Flow.Turn, TurnData:new(a.player, { who = a.player, from = a, type = "pass" }))
    assert(b:getHp() == 88)
    logic:executeEvent(Flow.Turn, TurnData:new(a.player, { who = a.player, from = a, type = "pass" }))
    assert(b:getHp() == 88) -- 同轮嵌套/重入不重复
    logic:finishRound(RoundData:new { number = 1 })
    assert(b:getHp() == 88 and ctx:getBuff(b, id).turn == 1)
    logic.roundNumber = 2
    logic:executeEvent(Flow.Turn, TurnData:new(a.player, { who = a.player, from = a, type = "pass" }))
    assert(b:getHp() == 76)
    logic:finishRound(RoundData:new { number = 2 })
    assert(not ctx:getBuff(b, id))
  end
end)

test("dot applied after opponent starts retains its first full duration", function()
  local ctx, logic, a, b = prepared()
  logic.roundNumber = 1
  for _, definition in ipairs(require("packages.standard").skills) do sr:registerSkill(definition) end
  a.skills = logic:createSkills {10034}
  logic:executeEvent(Flow.Turn, TurnData:new(a.player,
    { who = a.player, from = a, to = b, type = "skill", skill = a.skills[1] }))
  local buff = ctx:getBuff(b, 10021)
  assert(buff and buff.turn == 3 and b:getHp() == 100)
  logic:finishRound(RoundData:new { number = 1 })
  assert(buff.turn == 3)
  for number = 2, 4 do
    logic.roundNumber = number
    logic:executeEvent(Flow.Turn, TurnData:new(a.player, { who = a.player, from = a, type = "pass" }))
    logic:finishRound(RoundData:new { number = number })
  end
  assert(b:getHp() == 64 and buff.owner == nil)
end)

test("burn halves per-use physical and special power without modifying fixed damage", function()
  for _, kind in ipairs({"physical", "special"}) do
    local ctx, logic, a, b = prepared()
    a.skills[1].type = kind
    a.skills[1].critChance = 0
    local power, expected = a.skills[1].power
    expected = ctx:calculateDamage { from = a, to = b, skill = a.skills[1], power = power / 2,
      isCritical = false, randomRoll = 255 }
    assert(ctx:applyAbnormal { who = a, buff = 10023, state = { turn = 3 } })
    local data = SkillUseData:new { from = a, to = b, skill = a.skills[1], isCritical = false, randomRoll = 255 }
    assert(logic:useSkill(data))
    assert(data.power == power / 2 and data.calculation.power == power / 2
      and data.damage == expected and a.skills[1].power == power)
    local direct = ctx:calculateDamage { from = a, to = b, baseDamage = 10 }
    assert(direct == 10 and ctx:damage { from = a, to = b, damage = direct } == 10)
    assert(logic:useSkill { from = a, to = b, skill = a.skills[2] })
    assert(a.skills[2].pp == 19) -- 属性技能照常释放
  end
end)

test("fatigue blocks both skill categories without PP cost and expires centrally", function()
  local ctx, logic, a, b = prepared()
  logic.roundNumber = 1
  assert(ctx:applyAbnormal { who = a, buff = 10025, state = { turn = 1 } })
  for _, skill in ipairs(a.skills) do
    local pp = skill.pp
    local data = SkillUseData:new { from = a, to = b, skill = skill }
    assert(not logic:useSkill(data) and data.prevented and data.preventReason == "fatigue")
    assert(skill.pp == pp and b:getHp() == 100)
  end
  logic:finishRound(RoundData:new { number = 1 })
  assert(not ctx:getBuff(a, 10025))
  assert(logic:useSkill { from = a, to = b, skill = a.skills[2] })
  assert(a.skills[2].pp == 19)
end)

test("fatigue does not prevent switching and switch removes classic statuses", function()
  local ctx, logic, a = prepared()
  local bench = logic:createPet(a.player, spec(3))
  table.insert(a.player.bag.pets, bench)
  table.insert(ctx.pets, bench)
  for _, id in ipairs({10021, 10023, 10024, 10025}) do
    assert(ctx:applyAbnormal { who = a, buff = id, state = { turn = 3 } })
  end
  assert(ctx:switchPet { from = a, to = bench })
  assert(#a.buffs == 0 and a.player.pet == bench)
end)

test("classic status skills use common hit probability and abnormal immunity pipeline", function()
  for _, pair in ipairs({{10035,10023},{10036,10024},{10037,10025}}) do
    local ctx, logic, a, b = prepared()
    for _, definition in ipairs(require("packages.standard").skills) do sr:registerSkill(definition) end
    a.skills = logic:createSkills {pair[1]}
    assert(logic:useSkill { from = a, to = b, skill = a.skills[1], hit = false })
    assert(#b.buffs == 0)
    local block = logic:addEffect(effect(sr.AbnormalInflicted, 100, function(_, _, _, _, data)
      data:preventBuff()
    end))
    assert(logic:useSkill { from = a, to = b, skill = a.skills[1] })
    assert(#b.buffs == 0)
    logic:removeEffect(block)
    assert(logic:useSkill { from = a, to = b, skill = a.skills[1] })
    assert(ctx:getBuff(b, pair[2]).turn == 3)
  end
end)




test("typed content registers abnormal identity and keeps named effect parameters isolated", function()
  local Engine = require "seer.core.engine"
  local Abnormal = require "seer.core.abnormal"
  local engine = Engine:new()
  require("packages.standard"):install(engine)
  assert(engine:getAbnormal(10061).abnormalKind == "paralysis")
  assert(engine:getAbnormal(10071) == nil and engine:getBuff(10071).type == 4)
  local one, two = engine:createBuff(10061, {turn = 2}), engine:createBuff(10061, {turn = 3})
  assert(one:isInstanceOf(Abnormal) and one.abnormalCategory == "control")
  assert(one.abnormalKind == "paralysis" and one.turn == 2 and two.turn == 3)
  one.effects[1].on_usevalue.changed = true
  assert(not two.effects[1].on_usevalue.changed)
  assert(not pcall(function() engine:createBuff(10061, {abnormalKind = "poison"}) end))
  local ctx, _, a = prepared()
  assert(ctx:applyAbnormal {who = a, buff = 10061, state = {turn = 2}})
  assert(ctx:applyAbnormal {who = a, buff = 10023, state = {turn = 2}})
  assert(#ctx:getAbnormals(a) == 2 and #ctx:getAbnormals(a, "control") == 1)
  assert(ctx:hasAbnormal(a, "paralysis") and not ctx:hasAbnormal(a, "sleep"))
  assert(ctx:getAbnormal(a, "paralysis") == ctx:getBuff(a, 10061))
  sr:registerBuff {id=99065, name="paralysis variant", type=5,
    abnormalKind="paralysis", abnormalCategory="control"}
  assert(not ctx:applyAbnormal {who=a, buff=99065, state={turn=2}}) -- 按身份去重
  local bad = spec(9)
  bad.soulMark = 10061
  assert(not pcall(function() ctx.logic:createPet(a.player, bad) end))
  ctx:getBuff(a, 10061).turn = 0
  assert(not ctx:hasAbnormal(a, "paralysis"))
end)

test("typed CSV rejects invalid categories mixed effect sources and missing named effects", function()
  local Config = require "seer.core.csv_util.config"
  local function load(row, headers, kind)
    return Config.convert({{line = 2, data = row}}, headers, kind, "test.csv")
  end
  local headers = {"id", "name", "abnormalKind", "abnormalCategory"}
  local row = {id = "99061", name = "test", abnormalKind = "test", abnormalCategory = "control"}
  assert(load(row, headers, "abnormal")[1].type == 5)
  row.abnormalCategory = "invalid"
  assert(not pcall(load, row, headers, "abnormal"))
  assert(not pcall(load, {id="99062",name="bad",type="4"}, {"id","name","type"}, "mark"))
  assert(not pcall(load, {id="99063",name="bad",type="8",effects='[{"id":10012}]',effectSet="guard"},
    {"id","name","type","effects","effectSet"}, "buff"))
  local Package = require "seer.core.package"
  local extension = Package:new("missing_effect_set", 990)
  local original = Config.load
  Config.load = function() return {{id=99064, name="bad", type=3, effectSet="missing"}} end
  local ok = pcall(function() extension:loadMarksFromCsv("unused") end)
  Config.load = original
  assert(not ok and #extension.buffs == 0)
end)

test("new control statuses block skills and sleep wakes on attack hit even if damage is shielded", function()
  for _, id in ipairs({10061, 10062, 10063}) do
    local ctx, logic, a, b = prepared()
    logic.roundNumber = 1
    assert(ctx:applyAbnormal {who = b, buff = id, state = {turn = 2}})
    for _, skill in ipairs(b.skills) do
      local pp = skill.pp
      assert(not logic:useSkill {from=b, to=a, skill=skill})
      assert(skill.pp == pp)
    end
    if id == 10063 then
      assert(logic:useSkill {from=a, to=b, skill=a.skills[1], hit=false})
      assert(ctx:hasAbnormal(b, "sleep"))
      assert(logic:useSkill {from=a, to=b, skill=a.skills[2]})
      assert(ctx:hasAbnormal(b, "sleep"))
      logic:addEffect(effect(sr.PreDamage, 100, function(_, _, _, _, data) data:preventDamage() end))
      assert(logic:useSkill {from=a, to=b, skill=a.skills[1], hit=true})
      assert(not ctx:hasAbnormal(b, "sleep") and b:getHp() == 100)
      assert(logic:useSkill {from=b, to=a, skill=b.skills[2]})
    end
  end
end)

local function equippedThunderGod()
  local ctx = makeContext()
  ctx.battleData.players[11].pets[1].soulMark = 10071
  ctx.logic:prepareRoom()
  ctx.logic:loadRoleData()
  return ctx, ctx.logic, ctx.pets[1], ctx.pets[2]
end

test("soul marks equip from snapshots and attack priority changes actual round order without accumulating", function()
  local ctx, logic, a, b = equippedThunderGod()
  assert(ctx:getBuff(a, 10071).keepOnSwitch and not ctx:getBuff(a, 10071).dispellable)
  local ready
  local broadcast = ctx.broadcast
  ctx.broadcast = function(self, command, data)
    if command == "Seer.BattleReady" then ready = data end
    return broadcast(self, command, data)
  end
  logic:prepareForStart()
  assert(ready.pets[1].buffs[1].buffId == 10071)
  a.stat.speed, b.stat.speed = 1, 100
  local function actions(skill)
    return {
      ActionData:new {who=b.player, from=b, to=a, type="skill", skill=b.skills[1]},
      ActionData:new {who=a.player, from=a, to=b, type="skill", skill=skill},
    }
  end
  local list = actions(a.skills[1])
  logic:sortActions(list)
  assert(list[1].from == a and list[1].priority == 1 and a.skills[1].priority == 0)
  logic:sortActions(list)
  assert(list[1].priority == 1)
  list = actions(a.skills[2])
  logic:sortActions(list)
  assert(list[1].from == b) -- 属性技能没有先制加成
  -- 实际 Round 走排序和控制管道，满血必定麻痹，慢速持有者先出手。
  logic.roundNumber = 1
  logic.chooseActions = function() return actions(a.skills[1]) end
  local pp = b.skills[1].pp
  logic:executeEvent(Flow.Round, RoundData:new {number=1})
  assert(a:getHp() == 100 and b:getHp() < 100 and b.skills[1].pp == pp)
  assert(a.skills[1].pp == 19)
end)

test("thunder god reads current HP probability exact threshold and uses abnormal immunity", function()
  for _, case in ipairs({{hp=100, roll=.99, expected=true}, {hp=50, roll=.49, expected=true},
      {hp=50, roll=.5, expected=false}, {hp=25, roll=.3, expected=false}}) do
    local ctx, logic, a, b = equippedThunderGod()
    a.stat.hp = case.hp
    local draws, durationDraws = 0, 0
    ctx.random = function(_, low, high)
      if low ~= nil then
        assert(low == 2 and high == 3)
        durationDraws = durationDraws + 1
        return 3
      end
      draws = draws + 1
      return case.roll
    end
    -- 指定 miss 排除命中/伤害随机数，并验证“使用”触发并不依赖命中。
    assert(logic:useSkill {from=a,to=b,skill=a.skills[1],hit=false})
    assert(ctx:hasAbnormal(b, "paralysis") == case.expected)
    assert(draws == (case.hp == 100 and 0 or 1))
    assert(durationDraws == (case.expected and 1 or 0))
    if case.expected then assert(ctx:getAbnormal(b, "paralysis").turn == 3) end
  end
  local ctx, logic, a, b = equippedThunderGod()
  assert(logic:useSkill {from=a,to=b,skill=a.skills[2]})
  assert(not ctx:hasAbnormal(b, "paralysis"))
  logic:addEffect(effect(sr.AbnormalInflicted, 100, function(_, _, _, _, data) data:preventBuff() end))
  assert(logic:useSkill {from=a,to=b,skill=a.skills[1],hit=false})
  assert(not ctx:hasAbnormal(b, "paralysis"))
end)

test("soul mark retains its instance on bench and does not affect another active pet", function()
  local ctx, logic, a, b = equippedThunderGod()
  local soul = ctx:getBuff(a, 10071)
  local bench = logic:createPet(a.player, spec(3))
  table.insert(a.player.bag.pets, bench)
  table.insert(ctx.pets, bench)
  assert(ctx:switchPet {from=a,to=bench})
  assert(ctx:getBuff(a, 10071) == soul and soul.owner == a and not ctx:getBuff(bench,10071))
  local list = {ActionData:new {who=a.player,from=bench,to=b,type="skill",skill=bench.skills[1]}}
  logic:sortActions(list)
  assert(list[1].priority == 0)
  assert(logic:useSkill {from=bench,to=b,skill=bench.skills[1],hit=false})
  assert(not ctx:hasAbnormal(b,"paralysis"))
  assert(ctx:switchPet {from=bench,to=a})
  assert(ctx:getBuff(a,10071) == soul)
  assert(logic:useSkill {from=a,to=b,skill=a.skills[1],hit=false})
  assert(ctx:hasAbnormal(b,"paralysis"))
end)




test("context abnormal helper defaults to two or three turns and preserves application timings", function()
  for _, duration in ipairs({2, 3}) do
    local ctx, logic, a, b = prepared()
    local draws, order = 0, {}
    ctx.random = function(_, low, high)
      assert(low == 2 and high == 3)
      draws = draws + 1
      return duration
    end
    for _, timing in ipairs({sr.PreAbnormal, sr.AbnormalCaused, sr.AbnormalInflicted, sr.AbnormalApplied}) do
      logic:addEffect(effect(timing, 1, function(_, event, _, _, data)
        order[#order + 1] = event.class.name
        assert(data.from == a and data.who == b and data.skill == a.skills[1])
      end))
    end
    assert(ctx:inflictAbnormal {from=a,who=b,kind="fear",skill=a.skills[1]})
    assert(ctx:getAbnormal(b,"fear").turn == duration and draws == 1)
    assert(table.concat(order,",") == "sr.PreAbnormal,sr.AbnormalCaused,sr.AbnormalInflicted,sr.AbnormalApplied")
  end
end)

test("context abnormal helper supports fixed duration range chance immunity and duplicate rejection", function()
  local ctx, logic, a, b = prepared()
  ctx.random = function() error("unexpected random draw") end
  assert(not ctx:inflictAbnormal {who=b,buff=10061,chance=0})
  assert(ctx:inflictAbnormal {who=b,buff=10061,turns=4})
  assert(ctx:getAbnormal(b,"paralysis").turn == 4)
  assert(not ctx:inflictAbnormal {who=b,buff=10061,turns=2})
  assert(ctx:getAbnormal(b,"paralysis").turn == 4)
  assert(ctx:inflictAbnormal {who=b,kind="burn",minTurns=5,maxTurns=5})
  assert(ctx:getAbnormal(b,"burn").turn == 5)
  ctx.random = function(_, low, high)
    if low then assert(low == 4 and high == 6); return 6 end
    return 0.49
  end
  assert(ctx:inflictAbnormal {who=b,buff=10024,chance=.5,minTurns=4,maxTurns=6})
  assert(ctx:getAbnormal(b,"frostbite").turn == 6)
  ctx.random = function(_, low) assert(low == nil); return .5 end
  assert(not ctx:inflictAbnormal {who=b,buff=10063,chance=.5})
  logic:addEffect(effect(sr.AbnormalInflicted, 100, function(_, _, _, _, data) data:preventBuff() end))
  assert(not ctx:inflictAbnormal {from=a,who=b,buff=10063,turns=2})
  assert(not ctx:hasAbnormal(b,"sleep"))
end)

test("context abnormal helper validates requests before random draws", function()
  local ctx, _, a = prepared()
  ctx.random = function() error("validation consumed randomness") end
  local bad = {
    {buff=10022}, {kind="unknown"}, {buff=10061,kind="paralysis"}, {},
    {buff=10061,turns=0}, {buff=10061,minTurns=3,maxTurns=2},
    {buff=10061,minTurns=2}, {buff=10061,turns=2,minTurns=2,maxTurns=3},
    {buff=10061,chance=1.1}, {buff=10061,state={turn=3}},
  }
  for _, spec in ipairs(bad) do
    spec.who = a
    local ok, message = pcall(function() ctx:inflictAbnormal(spec) end)
    assert(not ok and not tostring(message):find("validation consumed randomness",1,true))
    assert(#a.buffs == 0)
  end
  sr:registerBuff {id=99066,name="fear variant",type=5,abnormalKind="fear",abnormalCategory="control"}
  local ok, message = pcall(function() ctx:inflictAbnormal {who=a,kind="fear"} end)
  assert(not ok and tostring(message):find("ambiguous abnormal kind",1,true))
  assert(ctx:inflictAbnormal {who=a,buff=10062,turns=2})
  sr.abnormals[99066], sr.buffs[99066] = nil, nil
end)

print(string.format("%d battle flow tests passed", passed))
