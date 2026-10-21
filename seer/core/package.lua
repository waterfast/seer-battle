-- SPDX-License-Identifier: LGPL-2.1-or-later
-- 参考新月杀 ltk/core/package.lua 的集合结构和 install 接口，按本项目独立实现。
local class = kt.class
local EffectSkeleton = require "seer.core.effect_skeleton"
local Config = require "seer.core.csv_util.config"

--- Package 用来描述一个赛尔号扩展包，即效果、Buff、技能和道具的集合。
--- 内容使用显式固定编号；技能与 Buff 是 CSV 普通配置表。
---@class SeerPackage: Object
---@field id integer @扩展包编号，标准包为 100
---@field name string @扩展包名称
---@field extensionName string @扩展包资源目录名称
---@field effects EffectSkeleton[]
---@field buffs table[]
---@field skills table[]
---@field items table[] @预留的道具表，暂不安装或分配道具编号
---@field translations table<string, table<string, string>> @按语言保存的翻译表
local Package = class("SeerPackage")

--- 扩展包的构造函数。
---@param name string @包名称
---@param id integer @包编号
function Package:initialize(name, id)
    assert(type(name) == "string" and name ~= "", "package name must be a non-empty string")
    assert(math.type(id) == "integer" and id > 0, "package id must be a positive integer")
    self.id = id
    self.name = name
    self.extensionName = name
    self.effects, self.buffs, self.skills, self.items = {}, {}, {}, {}
    self.translations = {}
end

--- 向扩展包中添加一个效果定义。
---@param effect EffectSkeleton
function Package:addEffect(effect)
    assert(type(effect) == "table" and effect.isInstanceOf and effect:isInstanceOf(EffectSkeleton),
        "package effects must be skeletons")
    table.insert(self.effects, effect)
end

--- 向扩展包中添加一个 Buff 定义。
---@param buff table
function Package:addBuff(buff)
    table.insert(self.buffs, buff)
end

--- 向扩展包中添加一个技能定义。
---@param skill table
function Package:addSkill(skill)
    table.insert(self.skills, skill)
end

--- 将文件返回的单个效果或效果列表加入扩展包。
---@param effects EffectSkeleton|EffectSkeleton[]
function Package:loadEffects(effects)
    assert(type(effects) == "table", "effect module must return an EffectSkeleton or a skeleton list")
    if effects.isInstanceOf then
        self:addEffect(effects)
        return
    end
    for _, effect in ipairs(effects) do
        assert(effect.isInstanceOf and effect:isInstanceOf(EffectSkeleton), "invalid effect in module")
        self:addEffect(effect)
    end
end

--- 获得目录中的文件名。宿主使用 FileIO；独立终端演示使用系统目录列表。
--- 后者仅接受普通路径字符，避免将路径内容作为命令执行。
local function listFiles(path)
    if FileIO and FileIO.ls then return FileIO.ls(path) end
    assert(path:match("^[%w_./\\:%- ]+$"), "unsupported directory path")
    local windows = package.config:sub(1, 1) == "\\"
    -- 跟随 package.path 的根目录，终端脚本从其他工作目录启动时也能找到包。
    for template in package.path:gmatch("[^;]+") do
        local prefix = template:match("^(.-)%?%.lua$")
        if prefix then
            local directory = prefix .. path
            assert(directory:match("^[%w_./\\:%- ]+$"), "unsupported directory path")
            local command = windows and ('dir /b /a-d "' .. directory:gsub("/", "\\") .. '" 2>nul')
                or ("ls -1 '" .. directory .. "' 2>/dev/null")
            local stream = assert(io.popen(command, "r"))
            local files = {}
            for filename in stream:lines() do files[#files + 1] = filename end
            local ok = stream:close()
            if ok then return files end
        end
    end
    error("cannot list package directory: " .. path)
end

--- 加载目录内的效果 Lua 文件；排序仅保证加载顺序一致，不参与编号。
--- 不递归子目录，忽略 init.lua；模块加载失败直接报告，不静默跳过内容。
local function loadByPath(self, path, accept)
    path = path:gsub("\\", "/"):gsub("/+$", "")
    local modulePath = path:gsub("^%./", ""):gsub("/", ".")
    local files = listFiles(path)
    table.sort(files)
    for _, filename in ipairs(files) do
        if filename:sub(-4) == ".lua" and filename ~= "init.lua" then
            accept(self, require(modulePath .. "." .. filename:sub(1, -5)))
        end
    end
end

--- 一次导入目录内所有效果文件，每个文件可以返回 EffectSkeleton 或 EffectSkeleton[]。
---@param path string @项目相对路径，例如 packages/standard/effects
function Package:loadEffectsByPath(path)
    loadByPath(self, path, self.loadEffects)
end

--- CSV 行转换为普通配置表，不构造 Buff 或 Skill 实例。
function Package:loadBuffsFromCsv(path)
    for _, definition in ipairs(Config.load(path, "buff")) do self:addBuff(definition) end
end

function Package:loadSkillsFromCsv(path)
    for _, definition in ipairs(Config.load(path, "skill")) do self:addSkill(definition) end
end

--- 安装前统一校验编号及效果引用，失败时不修改引擎与定义。
---@param engine SeerEngine
function Package:install(engine)
    assert(not engine.packages[self.id], "duplicate package id: " .. self.id)
    for _, extension in pairs(engine.packages) do
        assert(extension.name ~= self.name, "duplicate package name: " .. self.name)
    end

    local pending, seen = {}, {}
    local groups = {
        { self.effects, engine.effects },
        { self.buffs, engine.buffs },
        { self.skills, engine.skills },
    }
    for _, group in ipairs(groups) do
        for _, definition in ipairs(group[1]) do
            assert(type(definition) == "table" and not seen[definition], "duplicate or invalid definition")
            local id = definition.id
            assert(math.type(id) == "integer" and id > 0, "content must have an explicit positive integer id")
            assert(not engine.effects[id] and not engine.buffs[id] and not engine.skills[id],
                "duplicate content id: " .. id)
            assert(not pending[id], "duplicate content id: " .. id)
            assert(not definition.package or definition.package == self, "definition belongs to another package")
            seen[definition] = true
            pending[id] = { definition = definition, registry = group[2] }
        end
    end
    -- 配置保存骨架编号及两组参数表；安装时校验，运行时才创建实际 Effect。
    local availableEffects = {}
    for id, skeleton in pairs(engine.effects) do availableEffects[id] = skeleton end
    for _, skeleton in ipairs(self.effects) do availableEffects[skeleton.id] = skeleton end
    for _, definitions in ipairs({ self.buffs, self.skills }) do
        for _, definition in ipairs(definitions) do
            engine:validateEffects(definition.effects, availableEffects)
        end
    end
    for id, entry in pairs(pending) do
        entry.definition.package = self
        entry.registry[id] = entry.definition
    end
    -- 骨架可在自己的 Lua 文件里维护名称和描述，避免与逻辑分散在不同目录。
    for _, effect in ipairs(self.effects) do
        for language, translations in pairs(effect.translations or {}) do
            engine:loadTranslationTable(translations, language)
        end
    end
    for language, translations in pairs(self.translations) do
        engine:loadTranslationTable(translations, language)
    end
    engine.packages[self.id] = self
end

return Package
