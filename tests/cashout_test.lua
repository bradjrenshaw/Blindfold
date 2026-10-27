-- Harness: the cash-out breakdown — every row recorded and spoken in vanilla;
-- under Steamodded's compact cash-out (only 7 rows drawn, counted in the
-- global total_cashout_rows) the undrawn rows are skipped and the game's
-- "...and N more" line is spoken and kept instead.
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
_G.localize = function(a)
    if type(a) == "table" and a.key == "cashout_hidden" then
        return "...and " .. a.vars[1] .. " more"
    end
    return "ERROR"
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
_G.G = {}

local Cashout = ba_require("events.cashout")
local spoken = {}
Cashout.say = function(s) spoken[#spoken + 1] = s end

local failures = 0
local function check(cond, label, got)
    if cond then print("ok   " .. label)
    else failures = failures + 1; print("FAIL " .. label .. " (got: " .. tostring(got) .. ")") end
end

-- The game's add_round_eval_row as Steamodded patches it: our wrap (on_row)
-- runs first, then the original counts every non-bottom row.
local function round(n_jokers, compact)
    spoken = {}
    if compact then _G.total_cashout_rows = 0 else _G.total_cashout_rows = nil end
    local function add(config)
        Cashout.on_row(config)
        if compact and config.name ~= "bottom" then
            _G.total_cashout_rows = _G.total_cashout_rows + 1
        end
    end
    add({ name = "blind1", dollars = 4 })
    for i = 1, n_jokers do add({ name = "joker" .. i, dollars = 1 }) end
    add({ name = "bottom", dollars = 4 + n_jokers })
end

round(9, false)
check(#Cashout.rows == 10 and #spoken == 10 and not Cashout.hidden_text,
    "vanilla: every row recorded and spoken", #Cashout.rows)

round(9, true)
check(#Cashout.rows == 7, "compact: only the 7 drawn rows recorded", #Cashout.rows)
check(spoken[#spoken] == "...and 3 more" and #spoken == 8,
    "compact: the hidden-count line spoken last", spoken[#spoken])
check(Cashout.hidden_text == "...and 3 more", "compact: hidden line kept for the buffer", Cashout.hidden_text)

round(3, true)
check(#Cashout.rows == 4 and not Cashout.hidden_text, "compact, few rows: nothing hidden", Cashout.hidden_text)

_G.total_cashout_rows = nil
print(failures == 0 and "ALL PASS" or (failures .. " FAILURES"))
os.exit(failures == 0 and 0 or 1)
