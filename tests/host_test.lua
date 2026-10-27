-- Harness: the hot-reload host — hook() wraps a function once with a
-- trampoline, later generations re-point it instead of stacking wraps, a
-- generation that stops hooking falls through to the original, and wraps
-- added on top by other mods survive a reload.
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

local failures = 0
local function check(cond, label, got)
    if cond then print("ok   " .. label)
    else failures = failures + 1; print("FAIL " .. label .. " (got: " .. tostring(got) .. ")") end
end

local H = ba_require("host")
local calls = {}
local Game = { add = function(a, b) calls[#calls + 1] = "orig"; return a + b end }

-- Generation 1.
H.begin_generation()
H.hook(Game, "add", function(orig) return function(a, b)
    calls[#calls + 1] = "gen1"
    return orig(a, b)
end end)
local trampoline = Game.add
check(Game.add(1, 2) == 3 and table.concat(calls, ",") == "gen1,orig", "gen 1 wraps", table.concat(calls, ","))

-- Another mod wraps on top of ours afterwards (Steamodded mods load later).
local below = Game.add
Game.add = function(a, b) calls[#calls + 1] = "othermod"; return below(a, b) end

-- Generation 2 re-points the trampoline: no stacking, other mod kept.
calls = {}
H.begin_generation()
H.hook(Game, "add", function(orig) return function(a, b)
    calls[#calls + 1] = "gen2"
    return orig(a, b)
end end)
check(Game.add(2, 2) == 4 and table.concat(calls, ",") == "othermod,gen2,orig",
    "gen 2 replaces gen 1, other mod's wrap survives", table.concat(calls, ","))
check(H.gen == 2, "generation counter", H.gen)

-- Generation 3 doesn't hook it: straight to the original.
calls = {}
H.begin_generation()
check(below == trampoline, "the trampoline itself is never replaced", tostring(below))
Game.add(1, 1)
check(table.concat(calls, ",") == "othermod,orig", "unhooked generation falls through", table.concat(calls, ","))

-- Hooking something that isn't a function is a no-op.
H.hook(Game, "missing", function(orig) return function() end end)
check(Game.missing == nil, "missing target left alone", Game.missing)

-- The host persists on _G across loads of host.lua.
loaded["host"] = nil
local H2 = ba_require("host")
check(H2 == H and H2.gen == 3, "host state survives re-loading host.lua", H2.gen)

print(failures == 0 and "ALL PASS" or (failures .. " FAILURES"))
os.exit(failures == 0 and 0 or 1)
