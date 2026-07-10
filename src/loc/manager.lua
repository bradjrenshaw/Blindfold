-- loc/manager.lua — localization manager (port of SayTheSpire2's
-- LocalizationManager). Holds the English source plus the active locale (if any
-- beyond English), resolves dotted keys with current-locale → English fallback,
-- and re-detects the active locale when the game language changes.
local require = ...

local L = {
    lang = "en",
    en = {},        -- full English source (loc/en.lua)
    current = nil,  -- active sparse locale table, or nil when language is English
}

-- Locales we actually ship a table for. Add an entry when loc/<code>.lua
-- exists. All non-English tables are machine translated (README) —
-- correction submissions welcome.
local AVAILABLE = {
    en = true,
    de = true, fr = true, it = true, nl = true, pl = true, ru = true,
    es_es = true, es_419 = true, pt_br = true,
    ja = true, ko = true, id = true,
    zh_cn = true, zh_tw = true,
}

-- Map a Balatro language code (e.g. 'en-us', 'fr', 'pt_BR') to our locale file
-- name. Unknown / untranslated languages resolve to English.
local function map_lang(code)
    code = tostring(code or ""):lower()
    if code == "" or code:sub(1, 2) == "en" then return "en" end
    return AVAILABLE[code] and code or "en"
end

local function load_locale(name)
    local ok, tbl = pcall(require, "loc." .. name)
    if ok and type(tbl) == "table" then return tbl end
    return nil
end

-- Dotted lookup, e.g. "TYPES.SLIDER".
local function lookup(tbl, key)
    if type(tbl) ~= "table" then return nil end
    local node = tbl
    for part in tostring(key):gmatch("[^.]+") do
        if type(node) ~= "table" then return nil end
        node = node[part]
    end
    return type(node) == "string" and node or nil
end

function L.init(game_lang)
    L.en = load_locale("en") or {}
    L.set_language(game_lang)
end

function L.set_language(game_lang)
    local name = map_lang(game_lang)
    L.lang = name
    L.current = (name ~= "en") and load_locale(name) or nil
end

-- Resolve a key: active locale first, then English fallback. Returns nil if
-- neither has it (Message then renders the raw key so misses are visible).
function L.get(key)
    return (L.current and lookup(L.current, key)) or lookup(L.en, key)
end

return L
