-- Harness: the packs overlay's lifecycle gates — the close-animation window
-- (pack on screen, state already flipped back) must cede the screen and
-- refuse picks (a use_card fired there crashes the game at
-- button_callbacks.lua:2298; user crash report).
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

local Packs = ba_require("overlays.packs")

local failures = 0
local function check(cond, label, got)
    if cond then print("ok   " .. label)
    else failures = failures + 1; print("FAIL " .. label .. " (got: " .. tostring(got) .. ")") end
end

local tarot = { ability = { set = "Tarot" } }
_G.G = {
    STAGES = { RUN = 2 }, STAGE = 2,
    STATES = { SELECTING_HAND = 1, SHOP = 5, BLIND_SELECT = 7, TAROT_PACK = 9,
        PLANET_PACK = 10, SPECTRAL_PACK = 15, STANDARD_PACK = 17, BUFFOON_PACK = 18 },
    STATE = 9,
    GAME = { pack_choices = 1 },
    pack_cards = { cards = { tarot } },
}

-- Deal-in: pending until the card count holds still, then active.
local v
for _ = 1, 20 do v = Packs:handler() end
check(v == "active", "open pack settles to active", v)
check(Packs.pick_allowed() == true, "pick allowed while the pack is live", Packs.pick_allowed())

-- The close window: state flipped back to blind select (tag pack), pack area
-- still on screen. Cede AND refuse picks.
G.STATE = G.STATES.BLIND_SELECT
v = Packs:handler()
check(v == "inactive", "close-to-blinds cedes the screen", v)
check(Packs.pick_allowed() == false, "no picks into the teardown", Packs.pick_allowed())

-- Same once the area is torn down, whatever the state says.
G.STATE = G.STATES.TAROT_PACK
G.pack_cards.REMOVED = true
check(Packs.pick_allowed() == false, "no picks on a removed area", Packs.pick_allowed())
G.pack_cards.REMOVED = nil

-- The reload bounce (state stuck at SHOP with the pack up) is still claimed
-- and repaired: the handler puts the state back to what the contents imply.
G.STATE = G.STATES.SHOP
for _ = 1, 20 do v = Packs:handler() end
check(v == "active", "SHOP bounce is still claimed", v)
check(G.STATE == G.STATES.TAROT_PACK, "and the state is repaired from contents", G.STATE)
check(G.GAME.PACK_INTERRUPT == G.STATES.SHOP, "PACK_INTERRUPT restored for the close path", G.GAME.PACK_INTERRUPT)

print(failures == 0 and "ALL PASS" or (failures .. " FAILURES"))
os.exit(failures == 0 and 0 or 1)
