-- check_loc.lua — every locale must mirror loc/en.lua's key tree exactly,
-- and every string must carry the same {placeholders} as its English source.
local ROOT = arg[1] or "."
local LANGS = { "de", "fr", "es_es", "es_419", "it", "pt_br", "nl", "pl", "ru", "ja", "ko", "zh_cn", "zh_tw", "id" }

local function load_loc(name)
    local f = assert(io.open(ROOT .. "/src/loc/" .. name .. ".lua", "rb"))
    local code = f:read("*a"); f:close()
    local chunk = assert(load(code, "@" .. name, "t"))
    return chunk(function() end)
end

local function placeholders(s)
    local list = {}
    for p in s:gmatch("{%w+}") do list[#list + 1] = p end
    table.sort(list)
    return table.concat(list, " ")
end

local function walk(prefix, node, out)
    for k, v in pairs(node) do
        local path = prefix == "" and tostring(k) or (prefix .. "." .. tostring(k))
        if type(v) == "table" then walk(path, v, out)
        elseif type(v) == "string" then out[path] = v end
    end
end

local en = {}
walk("", load_loc("en"), en)

local failures = 0
for _, lang in ipairs(LANGS) do
    local ok, loaded = pcall(load_loc, lang)
    if not ok then
        failures = failures + 1
        print("FAIL " .. lang .. " (load: " .. tostring(loaded) .. ")")
    else
        local t = {}
        walk("", loaded, t)
        local probs = {}
        for k, v in pairs(en) do
            if t[k] == nil then probs[#probs + 1] = "missing " .. k
            elseif placeholders(v) ~= placeholders(t[k]) then probs[#probs + 1] = "placeholders " .. k end
        end
        for k in pairs(t) do
            if en[k] == nil then probs[#probs + 1] = "extra " .. k end
        end
        if #probs == 0 then print("ok   " .. lang)
        else
            failures = failures + 1
            table.sort(probs)
            print("FAIL " .. lang .. ": " .. table.concat(probs, "; "))
        end
    end
end

print(failures == 0 and "ALL PASS" or (failures .. " FAILURES"))
os.exit(failures == 0 and 0 or 1)
