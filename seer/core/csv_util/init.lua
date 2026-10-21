-- SPDX-License-Identifier: LGPL-2.1-or-later
-- 普通函数模块：只处理 CSV 文本，不创建游戏对象，也不执行单元格中的 Lua。
local Csv = {}

function Csv.parse(text, source)
    source = source or "CSV"
    text = text:gsub("^\239\187\191", "")
    local records, record, field = {}, {}, {}
    local quoted, closed, line, startLine = false, false, 1, 1
    local function fail(message) error(source .. ":" .. line .. ": " .. message, 0) end
    local function finishField()
        record[#record + 1] = table.concat(field)
        field, closed = {}, false
    end
    local function finishRecord()
        finishField()
        if #record > 1 or record[1] ~= "" then
            records[#records + 1] = { values = record, line = startLine }
        end
        record, startLine = {}, line + 1
    end
    local index = 1
    while index <= #text do
        local char = text:sub(index, index)
        if quoted then
            if char == '"' then
                if text:sub(index + 1, index + 1) == '"' then
                    field[#field + 1] = '"'
                    index = index + 1
                else
                    quoted, closed = false, true
                end
            else
                field[#field + 1] = char
                if char == "\n" then line = line + 1 end
            end
        elseif char == "," then
            finishField()
        elseif char == "\r" or char == "\n" then
            finishRecord()
            if char == "\r" and text:sub(index + 1, index + 1) == "\n" then index = index + 1 end
            line = line + 1
        elseif closed then
            fail("unexpected character after closing quote")
        elseif char == '"' then
            if #field > 0 then fail("quote inside unquoted field") end
            quoted = true
        else
            field[#field + 1] = char
        end
        index = index + 1
    end
    if quoted then fail("unterminated quoted field") end
    if #field > 0 or #record > 0 or closed then finishRecord() end
    assert(#records > 0, source .. ": missing header")
    local headers, seen = records[1].values, {}
    for _, header in ipairs(headers) do
        assert(header ~= "" and not seen[header], source .. ": empty or duplicate header: " .. header)
        seen[header] = true
    end
    local rows = {}
    for number = 2, #records do
        local entry = records[number]
        assert(#entry.values == #headers, source .. ":" .. entry.line .. ": column count mismatch")
        local row = {}
        for column, header in ipairs(headers) do row[header] = entry.values[column] end
        rows[#rows + 1] = { data = row, line = entry.line }
    end
    return rows, headers
end

-- 与 Lua 模块使用同一个根目录，允许从其他工作目录启动终端测试。
function Csv.read(path)
    local candidates, seen = {}, {}
    for template in package.path:gmatch("[^;]+") do
        local prefix = template:match("^(.-)%?%.lua$")
        if prefix then candidates[#candidates + 1] = prefix .. path end
    end
    candidates[#candidates + 1] = path
    for _, candidate in ipairs(candidates) do
        if not seen[candidate] then
            seen[candidate] = true
            local file = io.open(candidate, "rb")
            if file then
                local text = file:read("a")
                file:close()
                return Csv.parse(text, candidate)
            end
        end
    end
    error("cannot read CSV: " .. path)
end

return Csv
