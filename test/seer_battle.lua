-- SPDX-License-Identifier: LGPL-2.1-or-later
-- Lua 5.5：lua55 test/seer_battle.lua [--auto | --pvp]
local scriptDirectory = arg[0]:match("^(.*[/\\])") or "./"
local root = scriptDirectory .. "../"
package.path = root .. "?.lua;" .. root .. "?/init.lua;"
    .. root .. "basescripts/?.lua;" .. root .. "basescripts/?/init.lua;" .. package.path

kt = {
    class = require "lib.middleclass",
    tablib = require "corelib.tablib",
    json = require "lib.json",
    rand = require "lib.xoshiro256starstar",
}
require "seer.init"

local Data = require "test.seer_data"
local Boardgame = require "core.boardgame"
local Engine = require "core.engine"
local GameThread = require "gamethread.gamethread"

local auto = arg[1] == "--auto"
local pvp = arg[1] == "--pvp"
local context
local outcome
local hostFinished = false
local cancelled = false
local failures = {}
local requestsThisRound = {}
local StatStages = require "seer.core.stat-stages"
local statLabels = { atk = "攻击", def = "防御", spatk = "特攻", spdef = "特防", speed = "速度", accuracy = "命中" }

local function describeStages(stages)
    local parts = {}
    for _, name in ipairs(StatStages.getNames()) do
        if stages[name] ~= nil then
            parts[#parts + 1] = string.format("%s%+d", statLabels[name], stages[name])
        end
    end
    return table.concat(parts, "，")
end

-- 观察真实 HP 事件以展示伤害类别，不修改共享广播协议或战斗规则。
local function installObservers()
    local hp = sr.createEffectSkeleton {
        id = 90901, name = "demo.hp_log", event = sr.HpChanged,
        can_trigger = function() return true end,
        on_use = function(self, event, target, owner, data)
            local damage = data.damageEvent
            local label = damage and (damage.damageType == sr.FixedDamage and "固定伤害" or "普通伤害")
                or (data.reason == "recover" and "回复" or "体力变化")
            print(string.format("  %s：%s %d 点（实际），HP %d/%d", data.who.name,
                label, math.abs(data.num), data.who.stat.hp, data.who.stat.maxHp))
        end,
    }
    local miss = sr.createEffectSkeleton {
        id = 90902, name = "demo.miss_log", event = sr.SkillMissed,
        can_trigger = function() return true end,
        on_use = function() print("  技能未命中。") end,
    }
    context.logic:addEffect(hp:createEffect())
    context.logic:addEffect(miss:createEffect())
end

local function petName(id)
    local pet = context and context:getPet(id)
    return pet and pet.name or tostring(id)
end

local function showStatus()
    for _, pet in ipairs(context.pets) do
        print(string.format("  %s：HP %d/%d", pet.name, pet.stat.hp, pet.stat.maxHp))
        print("    能力等级：" .. describeStages(pet.statStages:toTable()))
    end
end

local function chooseComputerAction(request)
    local selected
    for _, choice in ipairs(request.skills) do
        local skill = sr:getSkill(choice.id)
        if not selected or (skill.power or 0) > (sr:getSkill(selected.id).power or 0) then
            selected = choice
        end
    end
    if not selected or not request.targets[1] then return { type = "pass" } end
    return { type = "skill", skillId = selected.id, targetId = request.targets[1] }
end

local function chooseHumanAction(request)
    print("\n请选择 " .. petName(request.petId) .. " 的行动：")
    for index, choice in ipairs(request.skills) do
        local skill = sr:getSkill(choice.id)
        print(string.format("  %d. %s  威力 %d  PP %d  先制 %+d", index,
            sr:translate(choice.name), skill.power or 0, choice.pp, skill.priority or 0))
        if skill.description then print("     " .. skill.description) end
    end
    print("  0. 跳过本轮行动")

    while true do
        io.write("输入序号（直接回车选第一项，q 退出）：")
        io.flush()
        for index, action in ipairs(request.actions) do
            print(string.format("a%d: %s → %s%s", index,
                action.type == "switch" and "换宠" or "道具", petName(action.targetId),
                action.itemId and ("（道具 " .. action.itemId .. "）") or ""))
        end
        local line = io.read("*l")
        if line == nil or line == "q" then return nil end
        if line == "0" then return { type = "pass" } end
        local special = line:match("^a(%d+)$")
        if special and request.actions[tonumber(special)] then return request.actions[tonumber(special)] end
        local index = line == "" and 1 or tonumber(line)
        local choice = index and request.skills[index]
        if choice then
            return { type = "skill", skillId = choice.id, targetId = request.targets[1] }
        end
        print("没有这个选项，请重新输入。")
    end
end

-- 这里只替换 C++ 宿主的输入输出；玩家、上下文、Logic、技能和体力结算都使用项目代码。
kt.c = {}

function kt.c.getPluginRoot()
    return root .. "seer"
end

function kt.c.luaEvent(name)
    if name == "gameOver" then hostFinished = true end
end

function kt.c.notifySocket(connectionId, command, payload)
    -- broadcast 会给双方各发一次；终端共用一块屏幕，只显示第一份。
    if connectionId ~= Data.users[1].connId then return end
    local data = kt.json.decode(payload)
    if command == "Seer.BattleReady" then
        installObservers()
        print("\n双方精灵已入场：")
        showStatus()
    elseif command == "Seer.RoundStart" then
        requestsThisRound = {}
        print(string.format("\n========== 第 %d 轮 ==========", data.number))
        showStatus()
    elseif command == "Seer.SkillUsing" then
        -- 自动和手动测试都确认：没有收齐双方行动时不能开始攻击。
        assert(requestsThisRound[1011] and requestsThisRound[1022], "技能执行早于双方行动提交")
        local skill = sr:getSkill(data.skillId)
        local target = skill.type == "status" and "" or " → " .. petName(data.to)
        print(string.format("%s 使用 %s%s（剩余 PP %d）", petName(data.from),
            sr:translate(skill.name), target, data.pp))
    elseif command == "Seer.StagesChanged" then
        print(string.format("  %s 能力变化：%s", petName(data.id), describeStages(data.changes)))
    elseif command == "Room::GameOver" then
        outcome = data
        local winner = data.winners and data.winners[1]
        if winner then
            print("\n战斗结束，胜者：" .. context:getPlayer(winner).pet.name)
        else
            print("\n战斗结束：平局或退出。")
        end
    end
end

function kt.c.requestSocket(connectionId, command, payload, timeout, timestamp, callback)
    assert(command == "Seer.ChooseAction", "未知测试请求：" .. command)
    local request = kt.json.decode(payload)
    local computer = auto or (not pvp and connectionId == Data.users[2].connId)
    local reply
    if computer then
        reply = chooseComputerAction(request)
        print(petName(request.petId) .. " 已选择行动。")
    else
        reply = chooseHumanAction(request)
    end
    requestsThisRound[connectionId] = true
    if not reply then
        cancelled = true
        -- 用一次明确的跳过回复结束当前询问；gameFinished 会阻止继续执行技能。
        context:gameOver()
        reply = { type = "pass" }
    end
    callback(nil, kt.json.encode(reply))
end

kt.log = {
    info = function() end,
    warn = function(message) print("提示：" .. tostring(message)) end,
    critical = function(message)
        failures[#failures + 1] = tostring(message)
        io.stderr:write(tostring(message), "\n")
    end,
}

kt.engine = Engine:new()
kt.gamethread = GameThread:new()
kt.gamethread:setId(1)

for _, skill in ipairs(Data.skills) do sr:registerSkill(skill) end

local game = Boardgame:new { id = "seer", name = "雷伊 VS 盖亚" }
game.logicClass = require "seer.gamethread.gamelogic"
game.contextClass = require "seer.gamethread.game-context"
kt.engine:registerGame(game)

context = kt.gamethread:registerContext(game, {
    id = 1,
    users = Data.users,
    battleData = { players = Data.players, maxRounds = 30 },
})

print("雷伊 VS 盖亚 · 命令行战斗测试")
print(auto and "模式：双方自动" or (pvp and "模式：双方手动" or "模式：手动雷伊，对战电脑盖亚"))
print("以下为测试面板；技能参数、性格编号不是正式配置。")
for _, user in ipairs(Data.users) do
    local pet = Data.players[user.id].pets[1]
    print(string.format("%s：等级 %d，性格 %s，个体 %d，速度 %d", pet.name,
        pet.level, Data.natures[pet.nature], pet.iv, pet.speed))
end

context:run()

assert(context.gameFinished and outcome and hostFinished, "战斗没有正常结束")
if not cancelled then
    assert((outcome.winners and outcome.winners[1]) or context.logic.roundNumber == 30,
        "战斗提前结束，请检查上方错误信息")
end
assert(#failures == 0, table.concat(failures, "\n"))
assert(#context.logic.gameEventStack == 0, "战斗事件栈未清理")
assert(#context.logic.skillUseStack == 0, "当前技能效果未清理")
assert(#context.logic.triggerStack == 0, "触发时机栈未清理")
print(string.format("测试通过：共 %d 轮，事件栈已清理。", context.logic.roundNumber))
