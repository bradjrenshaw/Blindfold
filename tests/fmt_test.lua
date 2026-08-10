-- Harness: the scoring format engine — verbosity styles, joker-popup
-- normalization against the live loc templates, and HUD-parity number
-- rendering (scientific / naneinf) in the hand-panel lines.
local ROOT = arg[1] or "."
local loaded = {}
local function ba_require(name)
    if loaded[name] then return loaded[name] end
    local f = assert(io.open(ROOT .. "/src/" .. name:gsub("%.", "/") .. ".lua", "rb"))
    local code = f:read("*a"); f:close()
    local chunk = assert(load(code, "@" .. name, "t"))
    loaded[name] = true
    loaded[name] = chunk(ba_require) or true
    return loaded[name]
end

_G.love = { filesystem = { write = function() end, read = function() return nil end,
    append = function() end } }
_G.localize = function(v) return tostring(v) end
-- Stub of the game's number_format (inf branch hardcoded to LuaJIT's in-game
-- "naneinf"; the 5.4 harness can't reproduce it through the original code).
_G.number_format = function(num)
    if type(num) ~= "number" then return num or "" end
    if num == math.huge then return "naneinf" end
    if num >= 1e11 then
        local fac = math.floor(math.log(num, 10))
        return string.format("%.3f", num / (10 ^ fac)) .. "e" .. fac
    end
    return (string.format("%.0f", num):reverse():gsub("(%d%d%d)", "%1,")
        :gsub(",$", "")):reverse()
end

local Message = ba_require("ui.message")
local en = ba_require("loc.en")
Message.set_resolver(function(key)
    local node = en
    for part in tostring(key):gmatch("[^.]+") do
        if type(node) ~= "table" then return nil end
        node = node[part]
    end
    return type(node) == "string" and node or nil
end)
local function L(key, vars) return Message.localized(key, vars):resolve() end

_G.G = {
    SETTINGS = { language = "en" },
    localization = { misc = { v_dictionary = {
        a_chips = "+#1#", a_chips_minus = "-#1#",
        a_mult = "+#1# Mult", a_mult_minus = "-#1# Mult",
        a_xmult = "X#1# Mult", a_xmult_minus = "-X#1# Mult",
    } } },
}

local Scoring = ba_require("events.scoring")
local vals = {}
Scoring.settings = { value = function(k) return vals[k] end }
local spoken = {}
Scoring.say = function(s) spoken[#spoken + 1] = s end

local failures = 0
local function check(cond, label, got)
    if cond then print("ok   " .. label)
    else failures = failures + 1; print("FAIL " .. label .. " (got: " .. tostring(got) .. ")") end
end

-- --- Verbosity styles ---------------------------------------------------------
check(Scoring.format_effect("chips", 10) == L("SCORING.CHIPS", { amt = "+10" }),
    "chips default: signed word", Scoring.format_effect("chips", 10))
vals["scoring.fmt.chips_gain"] = "signed"
check(Scoring.format_effect("chips", 10) == "+10", "chips signed", Scoring.format_effect("chips", 10))
vals["scoring.fmt.chips_gain"] = "bare"
check(Scoring.format_effect("chips", 10) == "10", "chips bare", Scoring.format_effect("chips", 10))
vals["scoring.fmt.chips_gain"] = "abbr"
check(Scoring.format_effect("chips", 10) == "10" .. L("SCORING.ABBR_CHIPS"),
    "chips abbr", Scoring.format_effect("chips", 10))
vals["scoring.fmt.chips_gain"] = nil

-- Mult never renders bare: sanitized back to the signed word.
vals["scoring.fmt.mult_gain"] = "bare"
check(Scoring.format_effect("mult", 10) == L("SCORING.MULT", { amt = "+10" }),
    "mult bare is sanitized to signed word", Scoring.format_effect("mult", 10))
vals["scoring.fmt.mult_gain"] = nil

check(Scoring.format_effect("xmult", 3) == L("SCORING.XMULT", { amt = 3 }),
    "xmult default: word", Scoring.format_effect("xmult", 3))
vals["scoring.fmt.xmult"] = "x"
check(Scoring.format_effect("xmult", 3) == "3x", "xmult x style", Scoring.format_effect("xmult", 3))
vals["scoring.fmt.xmult"] = nil

-- --- Popup normalization --------------------------------------------------------
check(Scoring.normalize_message("+3 Mult") == L("SCORING.MULT", { amt = "+3" }),
    "numeric mult popup normalizes", Scoring.normalize_message("+3 Mult"))
check(Scoring.normalize_message("+1,000 Mult") == L("SCORING.MULT", { amt = "+1000" }),
    "comma-grouped popup normalizes", Scoring.normalize_message("+1,000 Mult"))
check(Scoring.normalize_message("X4 Mult") == L("SCORING.XMULT", { amt = 4 }),
    "xmult popup normalizes", Scoring.normalize_message("X4 Mult"))
check(Scoring.normalize_message("Again!") == nil,
    "non-numeric popup stays verbatim", Scoring.normalize_message("Again!"))
check(Scoring.normalize_message("+1.234e13 Mult") == nil,
    "scientific popup stays verbatim (its render)", Scoring.normalize_message("+1.234e13 Mult"))

-- --- Hand-panel totals: HUD number parity ----------------------------------------
-- No G.E_MANAGER: on_hand_text speaks directly.
Scoring.on_hand_text(nil, { chips = 100, mult = 5 })       -- tracks the running pair
spoken = {}
Scoring.on_hand_text(nil, { chip_total = 1e15 })
check(spoken[1] == L("SCORING.TOTAL", { chips = "100", mult = "5", score = "1.000e15" }),
    "total speaks scientific like the HUD", spoken[1])

Scoring.on_hand_text(nil, { chips = 200, mult = 7 })
spoken = {}
Scoring.on_hand_text(nil, { chip_total = math.huge })
check(spoken[1] == L("SCORING.TOTAL", { chips = "200", mult = "7", score = "naneinf" }),
    "infinite total speaks naneinf", spoken[1])

Scoring.on_hand_text(nil, { chips = 1500, mult = 3 })
spoken = {}
Scoring.on_hand_text(nil, { chip_total = 4500 })
check(spoken[1] == L("SCORING.TOTAL", { chips = "1,500", mult = "3", score = "4,500" }),
    "ordinary totals get HUD comma grouping", spoken[1])

print(failures == 0 and "ALL PASS" or (failures .. " FAILURES"))
os.exit(failures == 0 and 0 or 1)
